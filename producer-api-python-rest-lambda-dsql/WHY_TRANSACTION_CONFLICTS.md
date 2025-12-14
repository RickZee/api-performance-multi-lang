# Why DSQL Transaction Conflicts Occur

## Overview

Transaction conflicts (OC000 errors) in Aurora DSQL occur due to the combination of:
1. **Optimistic Concurrency Control (OCC)** - DSQL's conflict detection mechanism
2. **Concurrent write patterns** - Multiple transactions writing simultaneously
3. **Distributed architecture** - DSQL's distributed nature amplifies conflict potential

## Root Causes

### 1. DSQL's Optimistic Concurrency Control (OCC)

**How OCC Works:**
- Transactions proceed **without locking** resources during execution
- All reads and writes happen normally
- Conflicts are detected **only at commit time**
- If another transaction modified overlapping data, the commit fails with OC000

**Why This Causes Conflicts:**
```
Transaction A:                    Transaction B:
├─ INSERT business_events          ├─ INSERT business_events
├─ INSERT event_headers           ├─ INSERT event_headers  
├─ INSERT car_entities            ├─ INSERT loan_entities
└─ COMMIT (checks for conflicts)   └─ COMMIT (checks for conflicts)
                                   
If both touch same partition/table → OC000 conflict!
```

### 2. Concurrent Lambda Invocations

**Test Scenario:**
- **4 Virtual Users (VUs)** running concurrently
- Each VU sends events **simultaneously**
- Each event triggers a **separate Lambda invocation**
- Each Lambda creates a **separate database transaction**

**Timeline of Conflicts:**
```
Time 0ms:  VU1 → Lambda1 → Transaction1 starts
Time 5ms:  VU2 → Lambda2 → Transaction2 starts  
Time 10ms: VU3 → Lambda3 → Transaction3 starts
Time 15ms: VU4 → Lambda4 → Transaction4 starts

Time 50ms: Transaction1 commits → SUCCESS
Time 55ms: Transaction2 commits → OC000 (conflict with Transaction1)
Time 60ms: Transaction3 commits → OC000 (conflict with Transaction1/2)
Time 65ms: Transaction4 commits → OC000 (conflict with previous)
```

### 3. Multiple Table Writes Per Transaction

**Each transaction writes to 3+ tables:**
```python
async with conn.transaction():
    # 1. Write to business_events table
    INSERT INTO business_events (id, event_name, ...)
    
    # 2. Write to event_headers table  
    INSERT INTO event_headers (id, event_name, ...)
    
    # 3. Write to entity tables (car_entities, loan_entities, etc.)
    INSERT INTO car_entities (entity_id, ...)
    # OR
    INSERT INTO loan_entities (entity_id, ...)
    # OR
    INSERT INTO loan_payment_entities (entity_id, ...)
    # OR
    INSERT INTO service_record_entities (entity_id, ...)
```

**Why This Increases Conflict Risk:**
- More tables = more opportunities for conflicts
- Each INSERT updates indexes (potential conflict points)
- Foreign key checks may read from other tables (overlapping reads)
- DSQL's distributed nature means even different rows can conflict if in same partition

### 4. DSQL's Distributed Architecture

**Partitioning Behavior:**
- DSQL distributes data across multiple partitions
- Even with unique primary keys, multiple transactions can:
  - Hit the same partition
  - Update the same indexes
  - Modify the same metadata structures

**Conflict Detection:**
- DSQL tracks which partitions/keys were modified
- At commit, it checks if any overlapping modifications occurred
- If yes → OC000 error

### 5. Index Updates

**Every INSERT triggers index updates:**
```sql
-- Primary key index
CREATE UNIQUE INDEX business_events_pkey ON business_events(id);

-- Foreign key indexes  
CREATE INDEX event_headers_id_idx ON event_headers(id);
CREATE INDEX car_entities_event_id_idx ON car_entities(event_id);
```

**Why Indexes Cause Conflicts:**
- Multiple transactions updating the same index structure
- Even if inserting different rows, index pages may overlap
- DSQL detects index-level conflicts at commit time

### 6. Foreign Key Validation

**Foreign key checks read from other tables:**
```sql
-- event_headers.id references business_events.id
-- entities.event_id references event_headers.id
```

**Potential Conflict Scenario:**
```
Transaction A:                    Transaction B:
├─ INSERT business_events(id=1)   ├─ INSERT business_events(id=2)
├─ INSERT event_headers(id=1)     ├─ INSERT event_headers(id=2)
│  └─ FK check reads              │  └─ FK check reads
│     business_events             │     business_events
└─ COMMIT                         └─ COMMIT
                                   
Both read business_events table → potential conflict!
```

## Why Some Events Failed More Than Others

### Car Created: 14/5 (Some Success)
- **First events** to be processed
- Less contention initially (fewer concurrent transactions)
- Some retries from k6 eventually succeeded

### Loan Created: 3/5 (Many Failures)
- **Higher contention** - depends on Car entities
- More concurrent transactions by this point
- Foreign key relationships increase conflict surface

### Payment/Service: 0/5 (All Failed)
- **Cascading failures:**
  1. Prerequisite entities (Car, Loan) may not exist due to previous conflicts
  2. Foreign key checks fail
  3. Higher contention on related tables
  4. No transaction-level retry (before fix)

## Factors That Increase Conflict Likelihood

### 1. **Concurrency Level**
- More concurrent transactions = higher conflict probability
- 4 VUs = 4 concurrent transactions = significant conflict risk

### 2. **Transaction Duration**
- Longer transactions = more time for conflicts
- Our transactions are relatively short (good), but still vulnerable

### 3. **Write Patterns**
- Writing to multiple tables increases conflict surface
- Our pattern: 3+ tables per transaction = higher risk

### 4. **Data Distribution**
- If data clusters in same partitions → more conflicts
- Random UUIDs help (we use them), but not perfect

### 5. **Index Density**
- More indexes = more conflict points
- We have primary keys + foreign keys + entity lookups

## Why Regular PostgreSQL Doesn't Have This Issue

**Regular PostgreSQL (Aurora PG):**
- Uses **pessimistic locking** (row-level locks)
- Locks acquired during transaction
- Conflicts detected immediately (blocking)
- No OC000 errors - transactions wait for locks

**Aurora DSQL:**
- Uses **optimistic concurrency control**
- No locks during transaction
- Conflicts detected at commit
- OC000 errors require retry

## Mitigation Strategies

### 1. **Transaction-Level Retry** ✅ (Implemented)
- Retry entire transaction on OC000
- Exponential backoff to reduce contention
- New connection for each retry

### 2. **Reduce Transaction Duration**
- Keep transactions as short as possible
- Minimize operations per transaction
- Already optimized (single event per transaction)

### 3. **Optimize Write Patterns**
- Batch related operations when possible
- Reduce number of tables written per transaction
- Consider denormalization for hot paths

### 4. **Connection Pooling** (Not Used)
- We use direct connections (DSQL compatibility)
- Pooling might help, but DSQL has limitations

### 5. **Partitioning Strategy**
- Use random/unique primary keys (already done)
- Distribute writes across partitions
- Avoid hot keys/partitions

### 6. **Index Optimization**
- Minimize number of indexes
- Use partial indexes where possible
- Consider index-only operations

## Expected Behavior After Fix

With transaction-level retry implemented:
- **First attempt**: May still get OC000
- **Retry 1**: Most conflicts resolved (100ms delay)
- **Retry 2**: Remaining conflicts resolved (200ms delay)
- **Retry 3**: Final attempt (400ms delay)

**Expected success rate:** 95-100% (up from 85%)

## Monitoring

Watch for:
- **OC000 error rate**: Should decrease (errors are retried, not returned)
- **Retry count**: CloudWatch logs show retry attempts
- **Transaction duration**: May increase slightly due to retries
- **Success rate**: Should approach 100%

## Conclusion

Transaction conflicts are **inherent to DSQL's OCC design** and **expected under concurrent load**. The fix implements proper retry logic to handle these conflicts gracefully, turning transient failures into successful operations.

The conflicts occur because:
1. DSQL uses OCC (no locks during transaction)
2. Multiple concurrent transactions write to same tables
3. Conflicts detected at commit time (not during execution)
4. Distributed architecture amplifies conflict potential

This is **normal behavior** for DSQL and requires application-level retry logic (which we've now implemented).
