# CDC Streaming Architecture Documentation

## Summary

Change Data Capture (CDC) streaming architecture that enables real-time event processing from PostgreSQL databases to Kafka, with filtering and routing using Apache Flink.

### Key Capabilities

- **Real-time CDC**: Captures database changes (INSERT, UPDATE, DELETE) from PostgreSQL tables and streams them to Kafka
- **Intelligent Filtering**: Configurable YAML-based filter definitions that automatically generate Flink SQL for event filtering
- **Multi-topic Routing**: Routes filtered events to consumer-specific Kafka topics based on business rules
- **Schema Management**: Schema Registry available for schema validation (currently using JSON format, Avro schemas available for future use)
- **Scalable Processing**: Apache Flink for stateful stream processing with horizontal scaling
- **Code Generation**: Automated SQL generation from declarative filter configurations
- **CI/CD Integration**: Infrastructure-as-code ready with validation and testing capabilities
- **Cost Optimization**: Aurora auto-start/stop functionality for dev/staging environments (automatically stops database after inactivity, starts on API requests)

### Example Data Structures

This architecture uses specific example structures for validation and testing:

- **Car Entity**: [`data/entities/car/car-large.json`](../../data/entities/car/car-large.json) - Large car entity with all required fields
- **Loan Created Event**: [`data/schemas/event/samples/loan-created-event.json`](../../data/schemas/event/samples/loan-created-event.json) - Complete loan created event structure

These examples are used throughout the system for:

- Filter configuration (specifically targeting `LoanCreated` events)
- Test data generation
- Entity validation
- Schema documentation

## System Architecture Overview

### High-Level Data Flow

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                         PostgreSQL Database                             │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ business_events table                                           │   │
│  │ - id, event_name, event_type, created_date, saved_date         │   │
│  │ - event_data (JSONB) - full event structure                    │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ CDC Capture (Logical Replication)
                               │ Captures flat columns + event_data JSONB
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                 Kafka Connect (Source Connector)                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Confluent Managed PostgresCdcSource OR Debezium Connector        │  │
│  │ - Extracts flat columns (id, event_name, event_type, etc.)      │  │
│  │ - Includes event_data as JSON string                             │  │
│  │ - Adds CDC metadata (__op, __table, __ts_ms)                    │  │
│  │ - Uses ExtractNewRecordState transform                           │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ JSON Serialized Events
                               │ (Flat structure with event_data JSONB)
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        Schema Registry                                  │
│  Available for schema validation (currently JSON format)                │
│  Avro schemas available for future use                                  │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ JSON Events
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Kafka: raw-business-events                           │
│  Format: JSON                                                          │
│  Structure: id, event_name, event_type, created_date, saved_date,    │
│            event_data (JSON string), __op, __table, __ts_ms           │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ Stream Processing
                               ▼
┌────────────────────────────────────────────────────────────────────────┐
│                    Confluent Flink                                     │
│                                                                        │
│  Flink SQL Jobs:                                                       │
│  - Filter by event_type, __op (operation type)                        │
│  - Route to consumer-specific topics                                   │
│  - Preserves flat structure + event_data                               │
└──────────────────────────────┬─────────────────────────────────────────┘
                               │
                               │ Filtered & Routed Events (JSON)
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Consumer-Specific Kafka Topics                       │
│  ┌──────────────────────────┐  ┌──────────────────────────┐         │
│  │filtered-loan-created-     │  │filtered-service-events    │         │
│  │events                      │  └──────────────────────────┘         │
│  └──────────────────────────┘  ┌──────────────────────────┐            │
│  ┌──────────────────────────┐  │filtered-car-created-  │            │
│  │filtered-loan-payment-     │  │events                   │            │
│  │submitted-events           │  └──────────────────────────┘            │
│  └──────────────────────────┘                                          │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ Consume Events
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Consumer Applications                                │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐       │
│  │ Loan Consumer    │  │Loan Payment      │  │Service Consumer  │       │
│  │ - Topic:         │  │Consumer          │  │ - Topic:         │       │
│  │   filtered-loan- │  │ - Topic:         │  │   filtered-      │       │
│  │   created-events  │  │   filtered-loan-  │  │   service-events │       │
│  │ - Parses flat    │  │   payment-        │  │ - Parses flat    │       │
│  │   structure +    │  │   submitted-     │  │   structure +    │       │
│  │   event_data     │  │   events          │  │   event_data     │       │
│  │   JSON string    │  │ - Parses flat    │  │   JSON string    │       │
│  └──────────────────┘  │   structure +    │  └──────────────────┘       │
│  ┌──────────────────┐  │   event_data     │  ┌──────────────────┐       │
│  │ Car Consumer     │  │   JSON string    │  │ All consumers   │       │
│  │ - Topic:         │  └──────────────────┘  │ connect to       │       │
│  │   filtered-car-  │                       │ Confluent Cloud   │       │
│  │   created-events  │                       │ with SASL_SSL      │       │
│  │ - Parses flat    │                       │ authentication    │       │
│  │   structure +    │                       └──────────────────┘       │
│  │   event_data     │                                                      │
│  │   JSON string    │                                                      │
│  └──────────────────┘                                                      │
└─────────────────────────────────────────────────────────────────────────┘
```

### How Consumers Get Filtered Events

**Complete Flow**:

1. **PostgreSQL** → `business_events` table stores events with:
   - Flat columns: `id`, `event_name`, `event_type`, `created_date`, `saved_date`
   - JSONB column: `event_data` (contains full nested event structure)
2. **CDC Connector** → Captures changes and publishes to `raw-business-events` Kafka topic:
   - Extracts flat column values
   - Includes `event_data` as JSON string
   - Adds CDC metadata: `__op` (operation: 'c'=create, 'u'=update, 'd'=delete), `__table`, `__ts_ms`
   - Format: JSON (not Avro)
3. **Flink SQL Job** →
   - Consumes from `raw-business-events` (acts as Kafka consumer)
   - Filters events using flat columns (`event_type`, `__op`)
   - **Writes to filtered Kafka topics** (acts as Kafka producer):
     - `filtered-loan-created-events`
     - `filtered-loan-payment-submitted-events`
     - `filtered-service-events`
     - `filtered-car-created-events`
   - Preserves flat structure + `event_data` JSONB field
4. **Consumer Applications** →
   - Connect to Kafka brokers
   - Subscribe to filtered topics using Kafka consumer groups
   - Parse flat structure for filtering metadata
   - Extract and parse `event_data` JSONB field to access nested event structure
   - Process events independently of Flink

## Data Model Architecture

### Hybrid Data Model: Flat Columns + JSONB

The architecture uses a **hybrid data model** that combines the benefits of both flat relational structures and nested JSON:

**Database Layer (PostgreSQL)**:

```sql
CREATE TABLE business_events (
    -- Flat columns for efficient filtering and querying
    id VARCHAR(255) PRIMARY KEY,
    event_name VARCHAR(255) NOT NULL,
    event_type VARCHAR(255),
    created_date TIMESTAMP WITH TIME ZONE,
    saved_date TIMESTAMP WITH TIME ZONE,
    
    -- JSONB column for full event structure
    event_data JSONB NOT NULL  -- Contains: {eventHeader: {...}, eventBody: {...}}
);
```

**Benefits of This Approach**:

1. **Efficient Filtering**: Flat columns (`event_type`, `event_name`) enable fast filtering in Flink SQL without JSON parsing
2. **Full Data Preservation**: JSONB `event_data` column preserves complete nested event structure
3. **Index Support**: PostgreSQL can index flat columns for fast queries
4. **Flexibility**: Consumers can access both flat metadata and nested entity data
5. **CDC Compatibility**: CDC connectors can efficiently capture both column values and JSONB content

**Data Flow Through the System**:

1. **Producer APIs** → Insert events with:
   - Flat columns extracted from `eventHeader`
   - Full event JSON stored in `event_data` JSONB column

2. **CDC Connector** → Captures:
   - Flat column values as separate fields
   - `event_data` JSONB as JSON string
   - Adds CDC metadata (`__op`, `__table`, `__ts_ms`)

3. **Kafka Topics** → Store events as JSON with:
   - Flat structure: `id`, `event_name`, `event_type`, `created_date`, `saved_date`
   - `event_data`: JSON string containing full nested structure
   - CDC metadata: `__op`, `__table`, `__ts_ms`

4. **Flink SQL** → Filters using:
   - Flat columns (`event_type`, `__op`) for efficient filtering
   - Preserves `event_data` JSON string for consumers

5. **Consumers** → Process events by:
   - Using flat columns for routing/metadata
   - Parsing `event_data` JSON string to access nested structure

**Example Event Structure**:

**In Database (business_events table)**:

```sql
id: "event-123"
event_name: "LoanCreated"
event_type: "LoanCreated"
created_date: "2024-01-15T10:30:00Z"
saved_date: "2024-01-15T10:30:05Z"
event_data: {
  "eventHeader": {
    "uuid": "event-123",
    "eventName": "LoanCreated",
    "createdDate": 1705312200000,
    "savedDate": 1705312205000,
    "eventType": "LoanCreated"
  },
  "eventBody": {
    "entities": [{
      "entityType": "Loan",
      "entityId": "loan-456",
      "updatedAttributes": {
        "loan": {
          "loanAmount": 50000,
          "balance": 50000,
          "status": "active"
        }
      }
    }]
  }
}
```

**In Kafka (raw-business-events topic)**:

The event structure in Kafka depends on the connector configuration:

**With ExtractNewRecordState Transform** (Recommended connectors):

```json
{
  "id": "event-123",
  "event_name": "LoanCreated",
  "event_type": "LoanCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "event_data": "{\"eventHeader\":{...},\"eventBody\":{...}}",
  "__op": "c",
  "__table": "business_events",
  "__ts_ms": 1705312205000
}
```

**Without ExtractNewRecordState Transform** (Non-recommended connector):

```json
{
  "id": "event-123",
  "event_name": "LoanCreated",
  "event_type": "LoanCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "event_data": "{\"eventHeader\":{...},\"eventBody\":{...}}"
}
```

**Note**: When using the non-recommended connector, the `-no-op.sql` Flink SQL file adds `__op` and `__table` fields when writing to filtered topics, but the raw topic will not have these fields.

**Trade-offs**:

| Aspect | Flat Columns | JSONB Column |
|--------|--------------|--------------|
| **Filtering Performance** | Fast (indexed columns) | Requires JSON parsing |
| **Data Completeness** | Limited to extracted fields | Full nested structure |
| **Schema Evolution** | Requires DDL changes | Flexible (JSON) |
| **Query Complexity** | Simple SQL | JSON path queries |
| **Storage** | Normalized | Denormalized |

**Recommendation**: This hybrid approach provides the best of both worlds - efficient filtering for stream processing and complete data preservation for consumers.

## Component Deep Dive

### 1. PostgreSQL Database (Source)

**Purpose**: The source of truth for business events stored in the `business_events` table

**Database Schema**:

The `business_events` table uses a hybrid approach combining flat columns for efficient filtering and a JSONB column for full event data:

```sql
CREATE TABLE business_events (
    id VARCHAR(255) PRIMARY KEY,              -- From eventHeader.uuid
    event_name VARCHAR(255) NOT NULL,         -- From eventHeader.eventName
    event_type VARCHAR(255),                  -- From eventHeader.eventType
    created_date TIMESTAMP WITH TIME ZONE,    -- From eventHeader.createdDate
    saved_date TIMESTAMP WITH TIME ZONE,      -- From eventHeader.savedDate
    event_data JSONB NOT NULL                 -- Full event JSON (eventHeader + eventBody)
);

-- Indexes for efficient filtering
CREATE INDEX idx_business_events_event_type ON business_events(event_type);
CREATE INDEX idx_business_events_created_date ON business_events(created_date);
```

**Data Model**:

- **Flat Columns**: `id`, `event_name`, `event_type`, `created_date`, `saved_date` - extracted from `eventHeader` for efficient querying and filtering
- **JSONB Column**: `event_data` - stores the complete event structure including:
  - `eventHeader`: UUID, eventName, createdDate, savedDate, eventType
  - `eventBody`: entities array with entityType, entityId, updatedAttributes
  - Full nested structure preserved for consumers

**How It Works**:

- Producer APIs insert events into `business_events` table with both flat columns and full JSONB data
- PostgreSQL Write-Ahead Log (WAL) records all changes
- Logical replication slots enable CDC capture without impacting database performance
- CDC connector captures both flat column values and the `event_data` JSONB content
- Flat columns enable efficient filtering in Flink SQL
- JSONB column preserves full event structure for consumers

**Configuration**:

```sql
-- Enable logical replication
ALTER SYSTEM SET wal_level = logical;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET max_wal_senders = 10;

-- Create replication slot (done by connector)
SELECT pg_create_logical_replication_slot('business_events_cdc_slot', 'pgoutput');
```

**RDS Proxy for Connection Pooling**:

For high-throughput write operations from serverless Lambda functions, **RDS Proxy** is deployed to enable connection pooling and multiplexing:

- **Purpose**: Manages database connections efficiently for Lambda functions writing events to `business_events` table
- **Benefits**:
  - **Connection Multiplexing**: 1000+ concurrent Lambda instances share a pool of 50-100 actual database connections
  - **Reduced Connection Overhead**: Eliminates "too many clients already" errors by pooling connections
  - **Automatic Failover**: Handles connection health checks and automatic failover
  - **Improved Latency**: Reuses connections, avoiding connection setup overhead
- **Architecture**:
  - Lambda functions connect to RDS Proxy endpoint (not directly to Aurora)
  - RDS Proxy maintains a connection pool to Aurora PostgreSQL
  - Each Lambda uses 1-2 connections (reduced from 5), with RDS Proxy managing the pool
  - CDC connectors continue to connect directly to Aurora (not through proxy)
- **Configuration**: Managed via Terraform (`terraform/modules/rds-proxy/`)
  - Enabled by default when both Aurora and Python Lambda are enabled
  - Can be disabled via `enable_rds_proxy = false` variable
- **Capacity**: Enables 1000+ concurrent Lambda executions vs ~16 without proxy

**Detailed Explanation: How RDS Proxy Solves Connection Exhaustion**

#### The Problem Without RDS Proxy

**Connection Multiplication Effect:**

Without RDS Proxy, each Lambda instance maintains its own connection pool directly to Aurora:

```text
Without RDS Proxy:
- Each Lambda instance: 2 connections (reduced from 5)
- Aurora db.r5.large: 1,802 max_connections
- Maximum concurrent Lambdas: 1,802 / 2 = ~901 Lambdas (theoretical)
- At 1000+ concurrent Lambdas: 2000+ connections needed → "too many clients already" error
- Even with larger instances, connection exhaustion occurs at high concurrency
```

**What Happens:**
1. Each Lambda container maintains its own connection pool (2 connections)
2. With high concurrency, AWS spins up many Lambda containers simultaneously
3. Each container holds connections even when idle (Lambda containers are reused)
4. Aurora's connection limit is quickly exhausted
5. New Lambda invocations fail with "too many clients already" errors

#### How RDS Proxy Solves This

**Connection Multiplexing Architecture:**

RDS Proxy acts as an intermediary layer that multiplexes many Lambda connections into fewer Aurora connections:

```text
With RDS Proxy:
- Each Lambda instance: 1-2 connections to RDS Proxy
- RDS Proxy: Maintains pool of 1,442 actual connections to Aurora (80% of 1,802 max)
- RDS Proxy: Multiplexes many Lambda connections → fewer Aurora connections
- Maximum concurrent Lambdas: 2000+ (proxy handles pooling efficiently)
- Reserved connections: 360 (20% headroom for admin/emergency use)
```

**Key Mechanisms:**

1. **Connection Pooling at Proxy Layer**
   - Lambda functions connect to RDS Proxy endpoint (not directly to Aurora)
   - RDS Proxy maintains a smaller pool of actual connections to Aurora
   - Many Lambda connections share the same Aurora connections
   - Connections are borrowed from the pool when needed, returned when done

2. **Connection Reuse**
   - RDS Proxy reuses Aurora connections across multiple Lambda requests
   - Idle Lambda connections don't hold Aurora connections
   - Connections are borrowed from the pool when needed, returned when idle
   - Reduces connection setup/teardown overhead

3. **Connection Lifecycle Management**
   - **max_connections_percent = 80**: Uses up to 80% of Aurora's max connections (leaves 20% headroom for admin connections)
   - **max_idle_connections_percent = 50**: Keeps 50% idle for burst capacity
   - **connection_borrow_timeout = 120**: Waits up to 2 minutes for available connection
   - Automatic health checks and failover handling

4. **Reduced Per-Lambda Overhead**
   - Each Lambda uses 1-2 connections to proxy (reduced from 5 direct connections)
   - Proxy manages the actual Aurora connection pool
   - Lambda containers can scale without exhausting Aurora connections

#### Real-World Example

**Scenario: 500 Concurrent Lambda Executions**

**Without RDS Proxy:**

```text
500 Lambdas × 2 connections = 1,000 connections needed
Aurora db.r5.large limit = 1,802 connections
Result: ✅ Would succeed, but at 1000+ Lambdas: 2000+ connections needed → ❌ Connection exhaustion
```

**With RDS Proxy:**

```text
500 Lambdas × 2 connections to proxy = 1,000 proxy connections
RDS Proxy maintains pool of ~1,442 connections to Aurora (80% of 1,802 max)
RDS Proxy multiplexes: 1,000 Lambda connections → 1,442 Aurora connections available
Result: ✅ All 500 Lambdas succeed with significant headroom
```

#### Performance Benefits

1. **Reduced Connection Setup Time**
   - Proxy reuses connections, avoiding per-request setup overhead
   - Typical savings: 10-50ms per request

2. **Better Resource Utilization**
   - Aurora connections are used more efficiently
   - Less time spent on connection setup/teardown
   - More CPU cycles available for actual queries

3. **Automatic Failover**
   - Proxy handles connection health checks
   - Automatic retry on connection failures
   - Better resilience to transient network issues

4. **No Lambda Throttling from DB Connections**
   - Lambda can scale to account limits (1000+ concurrent)
   - Database connection limits no longer block Lambda scaling
   - Enables true serverless scaling

#### Do You Need to Increase RDS Size?

**Short Answer: Probably Not, But It Depends on Your Workload**

**Current Configuration:**
- **Aurora Instance**: `db.r5.large` (1,802 max_connections)
- **RDS Proxy Config**: `max_connections_percent = 80` (uses 80% of available connections, reserves 20% for admin)
- **RDS Proxy Config**: `max_idle_connections_percent = 50` (keeps 50% idle for bursts)
- **Effective RDS Proxy Connections**: 1,442 (80% of 1,802)
- **Reserved for Admin**: 360 connections (20% headroom)

**Capacity with RDS Proxy:**

```text
Aurora max connections: 1,802 (db.r5.large)
RDS Proxy available connections: 1,442 (80% of max)
Reserved for admin/emergency: 360 connections (20% headroom)
With connection multiplexing: Supports 2000+ concurrent Lambdas
Each Lambda uses 1-2 connections to proxy
Proxy efficiently manages the 1,442 Aurora connections
```

**When You Might Need to Upgrade:**

1. **High Connection Wait Times**
   - Monitor: `ConnectionBorrowedCount` and `ConnectionBorrowedWaitTime` CloudWatch metrics
   - If wait times are consistently high (>1 second), proxy pool may be saturated

2. **Aurora CPU/Memory Pressure**
   - More connections can increase CPU/memory usage
   - Monitor: `CPUUtilization`, `DatabaseConnections`, `FreeableMemory`
   - If CPU consistently > 80%, consider upgrade

3. **Need for More Connections Beyond Multiplexing**
   - If you need >1000 concurrent Lambdas with heavy DB usage
   - If CDC connectors or other services also need connections
   - If you have multiple applications sharing the database

4. **Performance Requirements**
   - Larger instances provide more CPU/memory for query processing
   - Better for complex queries or high write throughput
   - Consider if query performance is a bottleneck

**Upgrade Options (if needed):**

**Current Production Configuration:**
- **Aurora Instance**: `db.r5.large` (1,802 max_connections)
- **RDS Proxy**: 1,442 available connections (80% of max)
- **Capacity**: Supports 2000+ concurrent Lambda executions

**Further Upgrade Options (if needed):**

```text
db.r5.large → db.r5.xlarge
- Max connections: 1,802 → 3,604
- Cost: ~2x
- Benefit: 2x connection capacity, more CPU/memory
```

```text
db.r5.large → db.r5.2xlarge
- Max connections: 1,802 → 5,000 (max limit)
- Cost: ~4x
- Benefit: Maximum connection capacity, significantly more CPU/memory
```

**Option 2: Monitor Current Configuration**

```text
Current production setup:
1. Aurora db.r5.large with RDS Proxy (1,442 available connections)
2. Monitor CloudWatch metrics:
   - DatabaseConnections (should stay < 1,802)
   - ConnectionBorrowedCount (proxy metrics)
   - ConnectionBorrowedWaitTime (should be < 100ms)
   - CPUUtilization (should stay < 80%)
3. Upgrade only if metrics indicate saturation
```

**Current Production Configuration:**

**Aurora `db.r5.large` + RDS Proxy (80% max connections):**

1. **High Connection Capacity**
   - 1,802 max connections (4x increase from db.t3.medium)
   - 1,442 connections available via RDS Proxy (80% of max)
   - 360 connections reserved for admin/emergency use (20% headroom)
   - Supports 2000+ concurrent Lambda executions with headroom

2. **Optimized Connection Pooling**
   - RDS Proxy uses 80% of max connections (not 100%)
   - Leaves 20% headroom for admin connections, CDC connectors, and emergency use
   - Prevents connection exhaustion during spikes
   - Better stability under high load

3. **Performance Benefits**
   - More CPU and memory (16 GB RAM vs 4 GB)
   - Better query performance for high write throughput
   - Handles complex queries more efficiently
   - Reduced connection wait times

4. **When to Consider Further Upgrade**
   - Connection wait times consistently > 1 second
   - Aurora CPU consistently > 80%
   - Need > 3000 concurrent Lambdas with heavy DB usage
   - DatabaseConnections consistently > 1,600 (approaching 1,802 limit)

**Monitoring Strategy:**

Key metrics to watch:

```bash
# RDS Proxy Metrics
- DatabaseConnections: Should stay < Aurora max_connections
- ConnectionBorrowedCount: Number of connections borrowed
- ConnectionBorrowedWaitTime: Should be < 100ms typically

# Aurora Metrics  
- DatabaseConnections: Should stay < max_connections
- CPUUtilization: Should stay < 80%
- FreeableMemory: Should have sufficient headroom

# Lambda Metrics
- ConcurrentExecutions: Track peak concurrency
- Throttles: Should decrease significantly
- Duration: Should improve with connection reuse
```

**Conclusion:** The current production configuration (`db.r5.large` with RDS Proxy at 80% max connections) provides significant capacity for high Lambda concurrency. With 1,442 available connections and 360 reserved for admin use, the system can handle 2000+ concurrent Lambda executions with substantial headroom. Monitor CloudWatch metrics regularly and consider further upgrades only if metrics indicate saturation (connection wait times > 1s, CPU > 80%, or approaching connection limits).

**Aurora Auto-Start/Stop for Cost Optimization**:

For dev/staging environments, **Aurora Auto-Start/Stop** functionality is deployed to automatically manage database lifecycle and reduce costs during periods of inactivity:

- **Purpose**: Automatically stops Aurora cluster when inactive and starts it when API requests arrive
- **Cost Savings**: Reduces compute costs by stopping the database during off-hours or low-activity periods
- **User Experience**: Provides seamless experience with automatic startup on first request
- **Environment**: Only enabled for non-production environments (dev/staging)

#### Auto-Stop Lambda

**Purpose**: Monitors API Gateway invocations and automatically stops Aurora cluster after a period of inactivity.

**How It Works**:

1. **Scheduled Execution**: Runs every hour via EventBridge (rate: 1 hour)
2. **Activity Monitoring**: Checks CloudWatch metrics for API Gateway invocations in the last N hours (default: 3 hours)
3. **Decision Logic**:
   - If API invocations detected → Keeps cluster running
   - If no invocations for 3+ hours → Stops Aurora cluster
4. **Fail-Safe**: If metrics cannot be checked, keeps cluster running (prevents accidental shutdowns)

**Configuration**:

- **Trigger**: EventBridge schedule (every 1 hour)
- **Inactivity Threshold**: 3 hours (configurable via `inactivity_hours` variable)
- **Monitoring**: API Gateway `Count` metric from CloudWatch
- **Actions**: `rds:DescribeDBClusters`, `rds:StopDBCluster`, `rds:StartDBCluster`
- **Terraform Module**: `terraform/modules/aurora-auto-stop/`

**Example Flow**:

```text
Hour 0: API receives requests → Cluster running
Hour 1: No requests → Auto-stop Lambda checks → Activity detected → Keeps running
Hour 2: No requests → Auto-stop Lambda checks → Activity detected → Keeps running
Hour 3: No requests → Auto-stop Lambda checks → No activity for 3 hours → Stops cluster
Hour 4: Cluster stopped (saving compute costs)
```

#### Auto-Start Lambda

**Purpose**: Automatically starts Aurora cluster when API requests arrive and database is stopped.

**How It Works**:

1. **Trigger**: Invoked by API Lambda when database connection fails
2. **Status Check**: Checks Aurora cluster status via RDS API
3. **Start Logic**:
   - If cluster is `stopped` → Starts cluster immediately
   - If cluster is `available` or `starting` → Returns current status
   - If cluster is in transition → Returns status without action
4. **Response**: Returns status information for API Lambda to provide user feedback

**Integration with API Lambda**:

The Python REST Lambda handler includes automatic database startup logic:

1. **Connection Error Detection**: Catches database connection errors during API requests
2. **Auto-Start Invocation**: Invokes auto-start Lambda to check/start database
3. **User-Friendly Response**: Returns HTTP 503 with retry guidance:
   ```json
   {
     "error": "Service Temporarily Unavailable",
     "message": "The database is currently starting. Please retry your request in 1-2 minutes.",
     "status": 503,
     "retry_after": 120
   }
   ```
4. **Retry Header**: Includes `Retry-After: 120` header for client guidance

**Example Flow**:

```text
1. User submits event to API
2. API Lambda attempts database connection → Fails (database stopped)
3. API Lambda detects connection error
4. API Lambda invokes auto-start Lambda
5. Auto-start Lambda checks status → Cluster is stopped
6. Auto-start Lambda starts cluster
7. API Lambda returns 503: "Database is starting, please retry in 1-2 minutes"
8. User retries after 1-2 minutes → Database is available → Request succeeds
```

**Configuration**:

- **Trigger**: Invoked by API Lambda on connection failure
- **Actions**: `rds:DescribeDBClusters`, `rds:StartDBCluster`
- **Terraform Module**: `terraform/modules/aurora-auto-start/`
- **IAM Permissions**: API Lambda has permission to invoke auto-start Lambda
- **Environment Variable**: `AURORA_AUTO_START_FUNCTION_NAME` set in API Lambda

#### Cost Optimization Benefits

**Cost Savings**:

- **Compute Costs**: Aurora compute charges only apply when cluster is running
- **Storage Costs**: Storage charges continue (minimal compared to compute)
- **Typical Savings**: 50-70% cost reduction for dev/staging environments with intermittent usage
- **Example**: If database is stopped 12 hours/day → ~50% cost savings

**When Auto-Start/Stop is Enabled**:

- **Environments**: Only dev/staging (not production)
- **Conditions**: 
  - `enable_aurora = true`
  - `enable_python_lambda = true`
  - `environment != "prod"`
- **Terraform**: Automatically deployed when conditions are met

**Monitoring**:

Key CloudWatch metrics to monitor:

```bash
# Auto-Stop Lambda Metrics
- Invocations: Should be ~24/day (once per hour)
- Duration: Should be < 5 seconds typically
- Errors: Should be 0 (fail-safe keeps cluster running on errors)

# Auto-Start Lambda Metrics
- Invocations: Varies based on API usage patterns
- Duration: Should be < 5 seconds typically
- Errors: Monitor for RDS API errors

# Aurora Metrics
- DBClusterStatus: Monitor transitions (available → stopped → starting → available)
- DatabaseConnections: Should be 0 when stopped

# API Lambda Metrics
- 503 Responses: Track when database is starting
- Connection Errors: Should decrease after auto-start implementation
```

**Best Practices**:

1. **Production Environments**: Auto-start/stop is disabled for production to ensure availability
2. **CDC Connectors**: CDC connectors connect directly to Aurora (not through RDS Proxy)
   - **Note**: If database is stopped, CDC connectors will fail until database restarts
   - **Recommendation**: For production CDC pipelines, keep database running or use separate production database
3. **Startup Time**: Aurora typically takes 1-2 minutes to start from stopped state
   - API returns 503 with retry guidance during this period
   - Clients should implement exponential backoff retry logic
4. **Monitoring**: Set up CloudWatch alarms for:
   - Auto-start Lambda errors
   - Excessive 503 responses from API
   - Database startup failures

**Configuration Files**:

- **Auto-Stop Module**: `terraform/modules/aurora-auto-stop/`
  - `main.tf`: Lambda function and EventBridge schedule
  - `variables.tf`: Configuration variables
  - `outputs.tf`: Function name and ARN
- **Auto-Start Module**: `terraform/modules/aurora-auto-start/`
  - `main.tf`: Lambda function code
  - `variables.tf`: Configuration variables
  - `outputs.tf`: Function name and ARN
- **API Lambda Handler**: `producer-api-python-rest-lambda/lambda_handler.py`
  - Includes connection error detection
  - Invokes auto-start Lambda on connection failure
  - Returns user-friendly 503 responses

**Disabling Auto-Start/Stop**:

To disable auto-start/stop functionality:

1. **Via Terraform Variables**: Set `environment = "prod"` (auto-start/stop only enabled for non-production)
2. **Manual Override**: Comment out auto-start/stop modules in `terraform/main.tf`
3. **Keep Database Running**: Manually start database and disable auto-stop Lambda schedule

### 2. CDC Source Connector

**Purpose**: Captures database changes from `business_events` table and streams them to Kafka

**Connector Options**:

The system supports four connector implementations with different capabilities:

#### Recommended Connectors (Include ExtractNewRecordState Transform)

1. **PostgresCdcSourceV2 (Debezium)** ⭐ **Most Recommended**
   - **Connector Class**: `PostgresCdcSourceV2`
   - **Configuration**: `connectors/postgres-cdc-source-v2-debezium-business-events-confluent-cloud.json`
   - **Features**:
     - Fully managed connector service with V2 architecture
     - Full CDC metadata support (`__op`, `__table`, `__ts_ms`, `__deleted`)
     - Proper ExtractNewRecordState transform support
     - Best for production deployments
   - **Flink SQL**: Use `business-events-routing-confluent-cloud.sql`

2. **Debezium PostgreSQL Connector** ⭐ **Currently Used in Setup Scripts**
   - **Connector Class**: `io.debezium.connector.postgresql.PostgresConnector`
   - **Configuration**: `connectors/postgres-debezium-business-events-confluent-cloud.json`
   - **Features**:
     - Open-source Debezium connector
     - Full ExtractNewRecordState transform support
     - More configuration flexibility
     - Used by `setup-business-events-pipeline.sh` script
   - **Flink SQL**: Use `business-events-routing-confluent-cloud.sql`

3. **Confluent Managed PostgresCdcSource (Fixed)** ✅ **Recommended**
   - **Connector Class**: `PostgresCdcSource`
   - **Configuration**: `connectors/postgres-cdc-source-business-events-confluent-cloud-fixed.json`
   - **Features**:
     - Fully managed connector service
     - Includes ExtractNewRecordState transform (fixed version)
     - Automatic scaling and monitoring
     - Adds CDC metadata: `__op`, `__table`, `__ts_ms`
   - **Flink SQL**: Use `business-events-routing-confluent-cloud.sql`

#### Non-Recommended Connector (Missing ExtractNewRecordState)

4. **Confluent Managed PostgresCdcSource (Basic)** ⚠️ **NOT RECOMMENDED**
   - **Connector Class**: `PostgresCdcSource`
   - **Configuration**: `connectors/postgres-cdc-source-business-events-confluent-cloud.json`
   - **Limitations**:
     - Missing ExtractNewRecordState transform
     - Does not add `__op`, `__table`, `__ts_ms` fields
     - Requires workaround in Flink SQL
   - **Flink SQL**: Use `business-events-routing-confluent-cloud-no-op.sql` (adds metadata in Flink)
   - **Note**: This configuration is deprecated. Use the `-fixed.json` version instead.

**How It Works**:

- Connects to PostgreSQL replication slot (created automatically)
- Reads WAL changes via logical replication
- Captures flat column values (`id`, `event_name`, `event_type`, `created_date`, `saved_date`)
- Captures `event_data` JSONB column as JSON string
- **Recommended connectors** apply **ExtractNewRecordState** transform to unwrap Debezium envelope:
  - Extracts actual record data (not before/after structure)
  - Adds CDC metadata: `__op` (operation: 'c'=create, 'u'=update, 'd'=delete), `__table`, `__ts_ms`
- Applies **RegexRouter** transform to route to `raw-business-events` topic
- Publishes events to Kafka in **JSON format** (not Avro)
- Maintains offset tracking for exactly-once semantics

**Event Structure Output**:

The connector output structure depends on whether ExtractNewRecordState transform is configured:

**With ExtractNewRecordState Transform** (Recommended connectors):

```json
{
  "id": "event-uuid-123",
  "event_name": "LoanCreated",
  "event_type": "LoanCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "event_data": "{\"eventHeader\":{...},\"eventBody\":{...}}",
  "__op": "c",
  "__table": "business_events",
  "__ts_ms": 1705312205000
}
```

**Without ExtractNewRecordState Transform** (Non-recommended connector):

```json
{
  "id": "event-uuid-123",
  "event_name": "LoanCreated",
  "event_type": "LoanCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "event_data": "{\"eventHeader\":{...},\"eventBody\":{...}}"
}
```

**Note**: When using the non-recommended connector, the `-no-op.sql` Flink SQL file adds `__op` and `__table` fields in the SELECT statement, but this is less efficient than having the connector add them.

**Key Configuration**:

- **Format**: JSON (using `JsonConverter` with `schemas.enable=false`)
- **Transform**: `ExtractNewRecordState` to unwrap Debezium envelope (required for recommended connectors)
- **Transform**: `RegexRouter` or `TopicRegexRouter` to route to `raw-business-events` topic
- **Table**: `public.business_events`
- **Replication Slot**: Created automatically by connector

**Configuration Files**:

- `connectors/postgres-cdc-source-v2-debezium-business-events-confluent-cloud.json` - ⭐ Most recommended (V2 Debezium)
- `connectors/postgres-debezium-business-events-confluent-cloud.json` - ⭐ Currently used in setup scripts
- `connectors/postgres-cdc-source-business-events-confluent-cloud-fixed.json` - ✅ Recommended (Fixed PostgresCdcSource)
- `connectors/postgres-cdc-source-business-events-confluent-cloud.json` - ⚠️ NOT RECOMMENDED (Missing transform)

**Connector-Flink SQL Compatibility Matrix**:

| Connector Configuration | ExtractNewRecordState | CDC Metadata Fields | Flink SQL File | Recommendation |
|------------------------|----------------------|---------------------|---------------|----------------|
| `postgres-cdc-source-v2-debezium-*.json` | ✅ Yes | `__op`, `__table`, `__ts_ms`, `__deleted` | `business-events-routing-confluent-cloud.sql` | ⭐ Most Recommended |
| `postgres-debezium-*.json` | ✅ Yes | `__op`, `__table`, `__ts_ms` | `business-events-routing-confluent-cloud.sql` | ⭐ Currently Used |
| `postgres-cdc-source-*-fixed.json` | ✅ Yes | `__op`, `__table`, `__ts_ms` | `business-events-routing-confluent-cloud.sql` | ✅ Recommended |
| `postgres-cdc-source-*.json` (basic) | ❌ No | None (added in Flink) | `business-events-routing-confluent-cloud-no-op.sql` | ⚠️ NOT RECOMMENDED |

**Migration Path**:

If you're currently using the non-recommended connector (`postgres-cdc-source-business-events-confluent-cloud.json`):

1. **Option 1 (Recommended)**: Migrate to `postgres-cdc-source-v2-debezium-business-events-confluent-cloud.json`
   - Update connector configuration
   - Switch Flink SQL to `business-events-routing-confluent-cloud.sql`
   - Restart connector

2. **Option 2**: Migrate to `postgres-cdc-source-business-events-confluent-cloud-fixed.json`
   - Update connector configuration
   - Switch Flink SQL to `business-events-routing-confluent-cloud.sql`
   - Restart connector

3. **Option 3**: Continue using Debezium connector (`postgres-debezium-business-events-confluent-cloud.json`)
   - Already includes ExtractNewRecordState
   - Already uses `business-events-routing-confluent-cloud.sql`
   - No changes needed

### 3. Kafka Broker

**Key Topics**:

- `raw-business-events`: All CDC events from PostgreSQL (3 partitions)
  - Format: JSON
  - Structure: Flat columns + `event_data` JSONB + CDC metadata
- `filtered-loan-created-events`: Loan created events (auto-created by Flink)
- `filtered-loan-payment-submitted-events`: Loan payment events (auto-created by Flink)
- `filtered-service-events`: Service-related events (auto-created by Flink)
- `filtered-car-created-events`: Car created events (auto-created by Flink)

**Topic Format**: All topics use JSON format (not Avro). Schema Registry is available for future Avro migration.

### 4. Schema Registry

**Purpose**: Centralized schema management and validation (available for future use)

**Current Implementation**:

- **Format**: Currently using JSON format for Kafka messages (no schema validation)
- **Avro Schemas**: Avro schema files exist in `schemas/` directory:
  - `schemas/raw-event.avsc` - Raw event Avro schema
  - `schemas/filtered-event.avsc` - Filtered event Avro schema
- **Future Use**: Avro schemas are available for migration when schema validation is needed

**How It Works** (when using Avro):

- Stores Avro schemas for Kafka topics
- Validates producer messages against registered schemas
- Enforces schema evolution policies (BACKWARD, FORWARD, FULL)
- Provides schema versioning and compatibility checking

**When to Use Avro vs JSON**:

- **JSON (Current)**: Simpler setup, no schema enforcement, easier debugging
- **Avro (Future)**: Schema validation, better performance, type safety, schema evolution

### 5. Flink Cluster

**Purpose**: Stateful stream processing engine for filtering and routing events

#### Confluent Cloud for Apache Flink (Managed Service)

**Confluent Cloud for Apache Flink** is a fully managed, cloud-native Flink service that provides:

- **Compute Pools**: Resource allocation units measured in CFUs (Confluent Flink Units)
- **SQL Statements**: Deploy Flink jobs as SQL statements (no JAR files required)
- **Auto-Scaling**: Automatically adjusts resources based on workload demands
- **Managed Infrastructure**: No need to manage JobManager or TaskManager instances
- **Built-in Integration**: Seamless integration with Schema Registry, RBAC, and private networking
- **High Availability**: Automatic failover and data replication

**Compute Pools**:

- **Purpose**: Isolated compute resources for Flink SQL statements
- **Sizing**: Configured with maximum CFUs (e.g., 4 CFU, 8 CFU)
- **Auto-Scaling**: Automatically scales up/down based on input topic rates
- **Multi-Region**: Deploy separate compute pools per region for active-active setup

**SQL Statements**:

- **Deployment Model**: Flink jobs are deployed as SQL statements, not JAR files
- **Management**: Create, update, and delete statements via Console, CLI, or REST API
- **Versioning**: SQL statements are versioned and can be updated without downtime
- **Monitoring**: Built-in monitoring and metrics for each statement

**How It Works**:

- **Consumes from Kafka**: Reads events from `raw-business-events` topic (acts as Kafka consumer)
- **Applies Filtering**: Applies filtering logic defined in Flink SQL statements using flat columns (`event_type`, `__op`)
- **Writes to Kafka**: Writes filtered events to consumer-specific Kafka topics (acts as Kafka producer)
  - `filtered-loan-created-events`
  - `filtered-loan-payment-submitted-events`
  - `filtered-service-events`
  - `filtered-car-created-events`
- **Preserves Structure**: Maintains flat structure + `event_data` JSONB field for consumers
- **Maintains State**: Maintains exactly-once semantics via automatic checkpoints
- **Auto-Scales**: Automatically adjusts compute resources based on throughput

**Deployment Example** (Confluent Cloud):

```bash
# Create compute pool
confluent flink compute-pool create prod-flink-east \
  --cloud aws \
  --region us-east-1 \
  --max-cfu 4

# Deploy SQL statement (Recommended)
confluent flink statement create \
  --compute-pool cp-east-123 \
  --statement-name event-routing-job \
  --statement-file flink-jobs/business-events-routing-confluent-cloud.sql
```

### 6. Flink SQL Jobs

**Purpose**: Declarative stream processing queries for filtering and routing events

#### Confluent Cloud Flink SQL Statements

In **Confluent Cloud**, Flink jobs are deployed as **SQL statements** rather than JAR files:

- **Statement-Based Deployment**: Deploy SQL directly without compiling to JARs
- **Version Control**: SQL statements are versioned and can be updated in place
- **Built-in Monitoring**: Each statement has built-in metrics and monitoring
- **Auto-Scaling**: Statements automatically scale based on input topic rates

**How It Works**:

- **Source Tables**: Defines source tables that read from Kafka topics (e.g., `raw-business-events`)
- **Sink Tables**: Defines sink tables that write to filtered Kafka topics (e.g., `filtered-loan-events`)
  - **Auto-Topic Creation (anti-pattern?)**: Filtered topics are automatically created by Flink when it writes to them for the first time
- **Filtering**: Uses SQL WHERE clauses to filter events based on business rules
- **Routing**: Routes matching events to different Kafka topics based on filter conditions
- **Fault Tolerance**: Automatic checkpoints ensure exactly-once semantics (managed by Confluent Cloud)

**Flink SQL File Variants**:

The system provides two Flink SQL files to support different connector configurations:

1. **`business-events-routing-confluent-cloud.sql`** ⭐ **Recommended**
   - **Use With**: Connectors that include ExtractNewRecordState transform
   - **Source Table**: Expects `__op`, `__table`, `__ts_ms` fields from connector
   - **Filtering**: Can filter by `__op` field (e.g., `WHERE event_type = 'LoanCreated' AND __op = 'c'`)
   - **Compatible Connectors**:
     - `postgres-cdc-source-v2-debezium-business-events-confluent-cloud.json`
     - `postgres-debezium-business-events-confluent-cloud.json`
     - `postgres-cdc-source-business-events-confluent-cloud-fixed.json`

2. **`business-events-routing-confluent-cloud-no-op.sql`** ⚠️ **Workaround for Non-Recommended Connector**
   - **Use With**: Connectors that do NOT include ExtractNewRecordState transform
   - **Source Table**: Does NOT expect `__op`, `__table`, `__ts_ms` fields
   - **Filtering**: Cannot filter by `__op` (assumes all events are inserts)
   - **Workaround**: Adds `__op` and `__table` fields in SELECT statement (less efficient)
   - **Compatible Connectors**:
     - `postgres-cdc-source-business-events-confluent-cloud.json` (non-recommended)

**Recommendation**: Always use `business-events-routing-confluent-cloud.sql` with a recommended connector that includes ExtractNewRecordState transform. The `-no-op.sql` variant is a workaround and should only be used if you cannot migrate to a recommended connector.

**Example Flink SQL Statement** (from `flink-jobs/business-events-routing-confluent-cloud.sql` - Recommended):

```sql
-- ============================================================================
-- Step 1: Create Source Table
-- ============================================================================
-- Source Table: Raw Business Events from Kafka (CDC connector output)
-- Structure matches the flat output from CDC connector
CREATE TABLE `raw-business-events` (
    `id` STRING,                    -- Event UUID
    `event_name` STRING,            -- Event name (e.g., "LoanCreated")
    `event_type` STRING,           -- Event type (e.g., "LoanCreated")
    `created_date` STRING,          -- Created timestamp
    `saved_date` STRING,           -- Saved timestamp
    `event_data` STRING,            -- Full event JSON as string (from JSONB column)
    `__op` STRING,                  -- CDC operation: 'c'=create, 'u'=update, 'd'=delete
    `__table` STRING,               -- Source table name: "business_events"
    `__ts_ms` BIGINT                -- CDC capture timestamp
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry',
    'scan.startup.mode' = 'earliest-offset'
);

-- ============================================================================
-- Step 2: Create Sink Table
-- ============================================================================
-- Sink Table: Filtered Loan Created Events
CREATE TABLE `filtered-loan-created-events` (
    `id` STRING,
    `event_name` STRING,
    `event_type` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `event_data` STRING,            -- Preserves full event JSON
    `__op` STRING,
    `__table` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry'
);

-- ============================================================================
-- Step 3: INSERT Statement - Filter and Route
-- ============================================================================
-- Filter LoanCreated events and route to filtered topic
INSERT INTO `filtered-loan-created-events`
SELECT 
    `id`,
    `event_name`,
    `event_type`,
    `created_date`,
    `saved_date`,
    `event_data`,                   -- Full event JSON preserved
    `__op`,
    `__table`
FROM `raw-business-events`
WHERE `event_type` = 'LoanCreated' AND `__op` = 'c';  -- Filter by event_type and operation

-- Additional filters for other event types:
-- Loan Payment Submitted Events
INSERT INTO `filtered-loan-payment-submitted-events`
SELECT * FROM `raw-business-events`
WHERE `event_type` = 'LoanPaymentSubmitted' AND `__op` = 'c';

-- Car Created Events
INSERT INTO `filtered-car-created-events`
SELECT * FROM `raw-business-events`
WHERE `event_type` = 'CarCreated' AND `__op` = 'c';

-- Service Events (filtered by event_name)
INSERT INTO `filtered-service-events`
SELECT * FROM `raw-business-events`
WHERE `event_name` = 'CarServiceDone' AND `__op` = 'c';
```

**Example Flink SQL Statement** (from `flink-jobs/business-events-routing-confluent-cloud-no-op.sql` - Workaround):

This variant is used when the connector does NOT provide `__op`, `__table`, `__ts_ms` fields. The SQL adds these fields in the SELECT statement:

```sql
-- ============================================================================
-- Step 1: Create Source Table (No CDC Metadata Fields)
-- ============================================================================
-- Source Table: Raw Business Events from Kafka (PostgresCdcSource output)
-- Note: PostgresCdcSource outputs flat structure without __op, __table, __ts_ms
CREATE TABLE `raw-business-events` (
    `id` STRING,
    `event_name` STRING,
    `event_type` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `event_data` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry',
    'scan.startup.mode' = 'earliest-offset'
);

-- ============================================================================
-- Step 2: Create Sink Table (With CDC Metadata Fields)
-- ============================================================================
-- Sink Table: Filtered Loan Created Events
CREATE TABLE `filtered-loan-created-events` (
    `id` STRING,
    `event_name` STRING,
    `event_type` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `event_data` STRING,
    `__op` STRING,
    `__table` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry'
);

-- ============================================================================
-- Step 3: INSERT Statement - Filter and Route (Adds Metadata in Flink)
-- ============================================================================
-- Filter LoanCreated events and route to filtered topic
-- Note: Adds __op and __table fields in SELECT (workaround)
INSERT INTO `filtered-loan-created-events`
SELECT 
    `id`,
    `event_name`,
    `event_type`,
    `created_date`,
    `saved_date`,
    `event_data`,
    'c' AS `__op`,                    -- Add __op = 'c' in Flink (assumes all are inserts)
    'business_events' AS `__table`    -- Add __table in Flink
FROM `raw-business-events`
WHERE `event_type` = 'LoanCreated';   -- No __op filter (assumes all are inserts)
```

**Key Differences Between SQL Variants**:

| Aspect | `business-events-routing-confluent-cloud.sql` | `business-events-routing-confluent-cloud-no-op.sql` |
|--------|----------------------------------------------|---------------------------------------------------|
| **Source Table Fields** | Includes `__op`, `__table`, `__ts_ms` | Does NOT include CDC metadata fields |
| **CDC Metadata Source** | From connector (ExtractNewRecordState) | Added in Flink SELECT (workaround) |
| **Filtering by Operation** | Can filter by `__op` (e.g., `WHERE __op = 'c'`) | Cannot filter by `__op` (assumes all inserts) |
| **Performance** | More efficient (metadata from connector) | Less efficient (metadata added in Flink) |
| **Recommended** | ✅ Yes (with recommended connectors) | ⚠️ No (workaround only) |

**Key Differences from Nested Structure**:

- **Flat Structure**: Uses flat columns (`id`, `event_name`, `event_type`, etc.) instead of nested `eventHeader`/`eventBody`
- **JSON Format**: Uses `json-registry` format (not Avro)
- **CDC Metadata**: Includes `__op`, `__table`, `__ts_ms` from CDC connector
- **Event Data**: `event_data` is a STRING containing the full JSON event (consumers parse this)
- **Filtering**: Filters on flat columns (`event_type`, `__op`) for efficiency

**Deployment** (Confluent Cloud):

```bash
# Deploy SQL statement to compute pool (Recommended)
confluent flink statement create \
  --compute-pool cp-east-123 \
  --statement-name event-routing-job \
  --statement-file flink-jobs/business-events-routing-confluent-cloud.sql

# Update existing statement
confluent flink statement update \
  --compute-pool cp-east-123 \
  --statement-id ss-456789 \
  --statement-file flink-jobs/business-events-routing-confluent-cloud.sql

# List statements
confluent flink statement list --compute-pool cp-east-123

# Get statement status
confluent flink statement describe ss-456789 --compute-pool cp-east-123
```

**Note**: The deployment example above uses `business-events-routing-confluent-cloud.sql` which is the recommended SQL file for connectors with ExtractNewRecordState transform. If you must use the non-recommended connector, replace with `business-events-routing-confluent-cloud-no-op.sql`.

**Topic Creation**: Filtered topics (`filtered-loan-created-events`, `filtered-service-events`, etc.) are automatically created by Flink when it writes to them for the first time. No manual topic creation is required for filtered topics. Only the `raw-business-events` topic needs to be created manually before deploying the CDC connector.

**Filter Types Supported**:

- **Event Type Filtering**: Filter by `event_type` column (e.g., `'LoanCreated'`, `'CarCreated'`)
- **Event Name Filtering**: Filter by `event_name` column (e.g., `'CarServiceDone'`)
- **Operation Type Filtering**: Filter by `__op` to capture only creates (`'c'`), updates (`'u'`), or deletes (`'d'`)
- **Multi-Condition Filtering**: Combine conditions with AND/OR logic (e.g., `event_type = 'LoanCreated' AND __op = 'c'`)
- **Value-Based Filtering**: Can filter on flat column values (dates, IDs, etc.)
- **JSON Data Filtering**: For nested filtering, parse `event_data` JSON string using JSON functions (advanced)

**Note**: The current implementation filters on flat columns for efficiency. To filter on nested data within `event_data`, you would need to parse the JSON string using Flink's JSON functions.

### 7. Consumer Applications

**Purpose**: Process filtered events from consumer-specific Kafka topics

**Available Consumers**:

The system includes 4 dockerized consumers, one for each filtered topic:

1. **Loan Consumer** (`consumers/loan-consumer/`)
   - Topic: `filtered-loan-created-events`
   - Consumer Group: `loan-consumer-group`
   - Processes `LoanCreated` events

2. **Loan Payment Consumer** (`consumers/loan-payment-consumer/`)
   - Topic: `filtered-loan-payment-submitted-events`
   - Consumer Group: `loan-payment-consumer-group`
   - Processes `LoanPaymentSubmitted` events

3. **Service Consumer** (`consumers/service-consumer/`)
   - Topic: `filtered-service-events`
   - Consumer Group: `service-consumer-group`
   - Processes `CarServiceDone` events

4. **Car Consumer** (`consumers/car-consumer/`)
   - Topic: `filtered-car-created-events`
   - Consumer Group: `car-consumer-group`
   - Processes `CarCreated` events

**How Consumers Get Filtered Events**:

Consumers **do NOT connect to Flink**. Instead, they connect directly to **Kafka** (local or Confluent Cloud) and subscribe to the filtered topics that Flink writes to. Here's the complete flow:

1. **Flink SQL Jobs Write to Kafka Topics**:
   - Flink SQL jobs consume from `raw-business-events` topic
   - After filtering and transformation, Flink writes filtered events to consumer-specific Kafka topics:
     - `filtered-loan-created-events`
     - `filtered-loan-payment-submitted-events`
     - `filtered-service-events`
     - `filtered-car-created-events`
   - These topics are **created in Kafka** automatically by Flink when it first writes to them
   - Flink acts as a **producer** to these filtered topics
   - Events maintain the flat structure: `id`, `event_name`, `event_type`, `created_date`, `saved_date`, `event_data` (JSON string), `__op`, `__table`

2. **Consumers Connect to Kafka**:
   - Consumer applications connect to Kafka brokers using `bootstrap.servers`
   - They subscribe to the filtered topics using Kafka consumer groups
   - Consumers are standard Kafka consumers - they have no direct connection to Flink
   - Consumers receive JSON messages with flat structure

**Confluent Cloud Connection**:

All consumers support connecting to both local Kafka (for development) and Confluent Cloud (for production). Configuration is done via environment variables:

**Local Kafka (Development)**:

```yaml
environment:
  KAFKA_BOOTSTRAP_SERVERS: kafka:29092
  KAFKA_TOPIC: filtered-loan-created-events
  CONSUMER_GROUP_ID: loan-consumer-group
```

**Confluent Cloud (Production)**:

```yaml
environment:
  KAFKA_BOOTSTRAP_SERVERS: pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
  KAFKA_TOPIC: filtered-loan-created-events
  KAFKA_API_KEY: <your-api-key>
  KAFKA_API_SECRET: <your-api-secret>
  CONSUMER_GROUP_ID: loan-consumer-group
```

When `KAFKA_API_KEY` and `KAFKA_API_SECRET` are provided, consumers automatically use SASL_SSL authentication:

```python
consumer_config = {
    'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
    'security.protocol': 'SASL_SSL',
    'sasl.mechanism': 'PLAIN',
    'sasl.username': KAFKA_API_KEY,
    'sasl.password': KAFKA_API_SECRET,
    'group.id': CONSUMER_GROUP_ID,
    'auto.offset.reset': 'earliest',
    'enable.auto.commit': True,
}
```

**Docker Compose Configuration**:

All consumers are defined in `docker-compose.yml` and can be started together:

```bash
# Start all consumers
docker-compose up -d loan-consumer loan-payment-consumer service-consumer car-consumer

# View logs
docker-compose logs -f loan-consumer
docker-compose logs -f loan-payment-consumer
docker-compose logs -f service-consumer
docker-compose logs -f car-consumer
```

To connect to Confluent Cloud, set environment variables before starting:

```bash
export KAFKA_BOOTSTRAP_SERVERS="pkc-xxxxx.us-east-1.aws.confluent.cloud:9092"
export KAFKA_API_KEY="<your-api-key>"
export KAFKA_API_SECRET="<your-api-secret>"
docker-compose up -d
```

**Event Processing in Consumers**:

Consumers receive events in the following flat structure:

```json
{
  "id": "event-uuid-123",
  "event_name": "LoanCreated",
  "event_type": "LoanCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "event_data": "{\"eventHeader\":{\"uuid\":\"...\",\"eventName\":\"LoanCreated\",...},\"eventBody\":{\"entities\":[...]}}",
  "__op": "c",
  "__table": "business_events"
}
```

**Consumer Implementation Pattern**:

1. **Parse Flat Structure**: Extract filtering metadata from flat columns (`event_type`, `event_name`, `__op`)
2. **Parse Event Data**: Extract and parse the `event_data` JSON string to access nested event structure:

   ```python
   import json
   
   # Parse flat structure
   event_type = message['event_type']
   event_name = message['event_name']
   
   # Parse nested structure from event_data
   event_data = json.loads(message['event_data'])
   event_header = event_data['eventHeader']
   event_body = event_data['eventBody']
   entities = event_body['entities']
   ```

3. **Process Entities**: Access nested entity data from the parsed `event_data`

**Example Consumer Implementation** (from `consumers/loan-consumer/consumer.py`):

All consumers follow the same pattern for parsing flat structure events:

```python
def process_event(event_value):
    """Process a loan event"""
    # Extract flat structure fields
    event_id = event_value.get('id', 'Unknown')
    event_name = event_value.get('event_name', 'Unknown')
    event_type = event_value.get('event_type', 'Unknown')
    created_date = event_value.get('created_date', 'Unknown')
    saved_date = event_value.get('saved_date', 'Unknown')
    cdc_op = event_value.get('__op', 'Unknown')
    cdc_table = event_value.get('__table', 'Unknown')
    
    # Parse event_data JSON string to access nested structure
    event_data_str = event_value.get('event_data', '{}')
    try:
        event_data = json.loads(event_data_str) if isinstance(event_data_str, str) else event_data_str
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse event_data JSON: {e}")
        event_data = {}
    
    # Extract nested structure
    event_header = event_data.get('eventHeader', {})
    event_body = event_data.get('eventBody', {})
    entities = event_body.get('entities', [])
    
    # Process entities with nested structure
    for entity in entities:
        entity_type = entity.get('entityType', 'Unknown')
        entity_id = entity.get('entityId', 'Unknown')
        updated_attrs = entity.get('updatedAttributes', {})
        
        # Access nested attributes based on entity type
        if entity_type == 'Loan':
            loan_data = updated_attrs.get('loan', {})
            loan_amount = loan_data.get('loanAmount')
            balance = loan_data.get('balance')
            status = loan_data.get('status')
```

**Key Points**:

- All consumers parse the **flat structure** first (id, event_name, event_type, etc.)
- The `event_data` field is a **JSON string** that must be parsed with `json.loads()`
- After parsing `event_data`, consumers can access the nested structure (eventHeader, eventBody, entities)
- Each consumer processes entity-specific attributes based on the entity type

**Topic Creation**:

- Filtered topics are automatically created by Flink when it first writes to them
- No manual topic creation is required for filtered topics
- Only the `raw-business-events` topic needs to be created manually before deploying the CDC connector

**Consumer Deployment**:

All 4 consumers are dockerized and can be deployed via Docker Compose:

```bash
# Build and start all consumers
cd cdc-streaming
docker-compose up -d loan-consumer loan-payment-consumer service-consumer car-consumer

# Check consumer status
docker-compose ps

# View consumer logs
docker-compose logs -f loan-consumer
```

For Confluent Cloud deployment, ensure environment variables are set:

```bash
export KAFKA_BOOTSTRAP_SERVERS="pkc-xxxxx.us-east-1.aws.confluent.cloud:9092"
export KAFKA_API_KEY="<your-api-key>"
export KAFKA_API_SECRET="<your-api-secret>"
docker-compose up -d
```

Each consumer prints events to stdout with detailed information including:

- Flat structure fields (id, event_name, event_type, created_date, saved_date)
- CDC metadata (`__op`, `__table`)
- Parsed nested structure from event_data (eventHeader, eventBody, entities)
- Entity-specific attributes based on entity type

## Fundamentals Section

### Change Data Capture (CDC)

**Concept**: Capture and track changes to data in a database in real-time

**How It Works**:

1. **Logical Replication**: PostgreSQL WAL contains all changes
2. **Replication Slot**: Connector creates a slot to read WAL changes
3. **Change Events**: Each INSERT/UPDATE/DELETE becomes an event
4. **Event Structure**: Contains before/after state and metadata
5. **Streaming**: Events are immediately published to Kafka

## Configuration and Code Generation

### YAML Filter Configuration System

**Purpose**: Declarative filter definitions that generate Flink SQL automatically

**Structure**: See `flink-jobs/filters.yaml` for examples

**Supported Operators**:

- `equals`: Exact match
- `in`: Match any value in list
- `notIn`: Exclude values in list
- `greaterThan`, `lessThan`, `greaterThanOrEqual`, `lessThanOrEqual`: Numeric comparisons
- `between`: Range check
- `matches`: Regex pattern matching
- `isNull`, `isNotNull`: Null checks

For detailed information, see [CODE_GENERATION.md](CODE_GENERATION.md).

---

## Production Deployment Considerations

### Disaster Recovery

For comprehensive disaster recovery procedures, backup strategies, failover mechanisms, and testing methodologies, see [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md).

**Summary**:

- **Backup Strategy**: Multi-level backup approach with replication, snapshots, and savepoints
- **Recovery Procedures**: Component-specific recovery steps for Kafka, Flink, connectors, and consumers
- **RTO/RPO Targets**: < 1 hour RTO, < 5 minutes RPO
- **Multi-Region**: Active-active setup with automatic failover
- **Testing**: Regular disaster recovery drills and automated testing

### Performance Tuning

For comprehensive performance tuning strategies, optimization techniques, and troubleshooting guides, see [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md).

**Summary**:

- **Kafka Tuning**: Broker configuration, topic settings, producer/consumer optimization
- **Flink Tuning**: Parallelism, state backend, checkpoint configuration, operator optimization
- **Connector Tuning**: Batch settings, parallel processing, PostgreSQL optimization
- **Consumer Tuning**: Batch processing, parallel processing, consumer group scaling
- **Infrastructure Tuning**: Network, disk I/O, CPU, memory optimization
- **Monitoring**: Key metrics, performance testing, troubleshooting procedures

## Related Documentation

- **[DISASTER_RECOVERY.md](DISASTER_RECOVERY.md)**: Comprehensive disaster recovery procedures and failover mechanisms
- **[PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md)**: Performance optimization strategies and tuning guides
- **[CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md)**: Complete Confluent Cloud setup guide

## References

- [Confluent Platform Documentation](https://docs.confluent.io/)
- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Apache Flink Documentation](https://nightlies.apache.org/flink/flink-docs-stable/)
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)
- [Schema Registry Documentation](https://docs.confluent.io/platform/current/schema-registry/index.html)
