# DSQL Transaction Conflict (OC000) Fix

## Changes Made

### 1. Updated `_is_retryable_error()` in Repositories

**Files Modified:**
- `repository/business_event_repo.py`
- `repository/event_header_repo.py`

**Change:** Added detection for DSQL OC000 transaction conflict errors:

```python
# Added to retryable_errors list:
'conflicts with another transaction',
'oc000',
'mutation conflicts',
'transaction conflict',
'change conflicts',
```

**Impact:** Repository-level retry logic now recognizes OC000 errors as retryable.

### 2. Added Transaction-Level Retry in EventProcessingService

**File Modified:**
- `service/event_processing.py`

**Changes:**
1. Added `asyncio` import for sleep functionality
2. Implemented transaction-level retry loop with:
   - Maximum 3 retry attempts
   - Exponential backoff (100ms, 200ms, 400ms, capped at 2s)
   - New connection for each retry attempt
   - Specific OC000 error detection

**Key Features:**
- Detects OC000 errors at transaction commit time
- Retries entire transaction (not just individual operations)
- Creates fresh connection for each retry (avoids stale connection issues)
- Logs retry attempts for monitoring

### 3. Error Detection Logic

The fix detects OC000 errors by checking for these patterns in error messages:
- `'oc000'` (error code)
- `'conflicts with another transaction'` (error message)
- `'mutation conflicts'` (alternative message)
- `'transaction conflict'` (generic pattern)
- `'change conflicts'` (from our observed error)

## How It Works

1. **First Attempt:**
   - Create connection
   - Start transaction
   - Execute all operations (business_events, event_headers, entities)
   - Commit transaction

2. **If OC000 Error Occurs:**
   - Detect error pattern
   - Close connection
   - Wait with exponential backoff
   - Retry with new connection

3. **After Max Retries:**
   - If still failing, raise exception
   - Lambda returns 500 error (expected behavior for persistent failures)

## Expected Results

After this fix:
- **Success Rate:** Should improve from ~85% (17/20) to ~100% (20/20)
- **Retry Attempts:** CloudWatch logs will show retry warnings for OC000 conflicts
- **Performance:** Slight increase in latency for conflicted transactions (due to retries)
- **Reliability:** Events that previously failed will now succeed after retry

## Testing

To verify the fix:

1. **Run k6 test:**
   ```bash
   k6 run --env DB_TYPE=dsql --env EVENTS_PER_TYPE=5 \
     --env LAMBDA_DSQL_API_URL=https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com \
     load-test/k6/send-batch-events.js
   ```

2. **Expected Results:**
   - All 20 events should succeed (5 Car + 5 Loan + 5 Payment + 5 Service)
   - Check CloudWatch logs for retry messages (if conflicts occur)

3. **Monitor:**
   - CloudWatch Logs: Look for "Transaction conflict (OC000) detected" warnings
   - Success rate: Should be 100% or very close
   - Response times: May be slightly higher due to retries

## Deployment

1. **Build Lambda package:**
   ```bash
   cd producer-api-python-rest-lambda-dsql
   # Follow existing build process
   ```

2. **Deploy:**
   ```bash
   cd terraform
   terraform apply
   ```

3. **Verify:**
   - Check Lambda function code is updated
   - Run k6 test to validate fix

## Monitoring

After deployment, monitor:
- **OC000 Error Rate:** Should decrease (errors are retried, not returned)
- **Retry Count:** CloudWatch logs will show retry attempts
- **Success Rate:** Should be near 100%
- **Latency P95/P99:** May increase slightly due to retries

## Related Documentation

- See `DSQL_TRANSACTION_CONFLICT_ANALYSIS.md` for detailed root cause analysis
- [AWS Aurora DSQL Concurrency Control](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-concurrency-control.html)
