# DSQL Transaction Conflict (OC000) Root Cause Analysis

## Problem Summary

During k6 batch testing with 5 events per type (20 total events, 4 VUs), we observed:
- **Car Created**: 14/5 (some retries succeeded)
- **Loan Created**: 3/5 (many failures)
- **Loan Payment Submitted**: 0/5 (all failed)
- **Car Service Done**: 0/5 (all failed)

Error message: `"Error processing event: change conflicts with another transaction, please retry: (OC000)"`

## Root Cause

### 1. OC000 Error Code
**OC000** is Aurora DSQL's Optimistic Concurrency Control (OCC) error code. DSQL uses OCC instead of pessimistic locking:

- Transactions proceed without locking resources during execution
- Conflicts are detected **at commit time**
- When multiple transactions modify the same data concurrently:
  - First transaction to commit succeeds
  - Subsequent transactions detect conflict and receive OC000 error
  - Failed transactions must be retried

### 2. Missing Retry Logic for Transaction Conflicts

**Current Implementation Issues:**

1. **`_is_retryable_error()` only checks connection/timeout errors:**
   ```python
   retryable_errors = [
       'connection',
       'timeout',
       'network',
       # ... no 'conflict' or 'OC000'
   ]
   ```

2. **OC000 errors are NOT recognized as retryable:**
   - Error message contains "conflicts with another transaction" and "(OC000)"
   - But `_is_retryable_error()` doesn't check for these patterns
   - Result: OC000 errors are returned as 500 errors without retry

3. **Retry logic exists but doesn't apply:**
   - `_retry_with_backoff()` method exists in repositories
   - But it only retries if `_is_retryable_error()` returns True
   - Since OC000 is not recognized, no retry happens

4. **Transaction-level retry missing:**
   - Current retry is at repository method level
   - But OC000 happens at transaction commit time
   - Need transaction-level retry in `EventProcessingService.process_event()`

### 3. Why Some Events Failed More Than Others

**Car Created (14/5):**
- First events to be sent
- Some conflicts occurred, but retries (from k6) eventually succeeded
- Less contention initially

**Loan Created (3/5):**
- Higher contention (depends on Car entities)
- More conflicts due to concurrent access
- Fewer successful retries

**Payment/Service (0/5):**
- All failed because:
  1. They depend on Loan/Car entities that may not exist yet (due to previous conflicts)
  2. Higher contention on related tables
  3. No transaction-level retry means single attempt fails

## Impact

1. **Data Loss**: Events are lost when OC000 occurs and no retry happens
2. **Poor User Experience**: 500 errors returned to clients
3. **Incomplete Test Results**: Only 17/20 events succeeded (85% success rate)
4. **Cascading Failures**: Dependent events (Payment, Service) fail because prerequisite entities don't exist

## Solution

### 1. Detect OC000 Errors
Update `_is_retryable_error()` to recognize transaction conflicts:

```python
def _is_retryable_error(self, error: Exception) -> bool:
    """Check if error is retryable (connection/timeout/transaction conflicts)."""
    error_str = str(error).lower()
    retryable_errors = [
        'connection',
        'timeout',
        'network',
        'unable to connect',
        'connection refused',
        'connection reset',
        'connection timed out',
        'server closed the connection',
        'could not connect',
        'network is unreachable',
        'no route to host',
        # DSQL transaction conflicts
        'conflicts with another transaction',
        'oc000',
        'mutation conflicts',
        'transaction conflict',
    ]
    return any(err in error_str for err in retryable_errors)
```

### 2. Add Transaction-Level Retry
Implement retry logic in `EventProcessingService.process_event()`:

```python
async def process_event(self, event: Event) -> None:
    """Process a single event with transaction-level retry for OC000 errors."""
    MAX_TRANSACTION_RETRIES = 3
    INITIAL_RETRY_DELAY = 0.1
    
    for attempt in range(MAX_TRANSACTION_RETRIES):
        try:
            # ... existing transaction code ...
            return  # Success, exit retry loop
        except Exception as e:
            error_str = str(e).lower()
            is_oc000 = 'oc000' in error_str or 'conflicts with another transaction' in error_str
            
            if not is_oc000 or attempt == MAX_TRANSACTION_RETRIES - 1:
                raise  # Not retryable or last attempt
            
            # Exponential backoff with jitter
            delay = INITIAL_RETRY_DELAY * (2 ** attempt)
            await asyncio.sleep(delay)
            logger.warning(f"Transaction conflict (OC000), retrying ({attempt + 1}/{MAX_TRANSACTION_RETRIES})...")
```

### 3. Optimize Transaction Design
- **Minimize contention**: Use randomized UUIDs (already done)
- **Reduce transaction duration**: Keep transactions short
- **Consider batching**: Group related operations when possible

## Testing

After implementing the fix:
1. Run k6 test again: `k6 run --env DB_TYPE=dsql --env EVENTS_PER_TYPE=5 ...`
2. Verify all 20 events succeed
3. Check CloudWatch logs for retry attempts
4. Monitor OC000 error rate (should decrease with retries)

## References

- [AWS Aurora DSQL Concurrency Control](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-concurrency-control.html)
- Error Code: OC000 = "mutation conflicts with another transaction, retry as needed"
