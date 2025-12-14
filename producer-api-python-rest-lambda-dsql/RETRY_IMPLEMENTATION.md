# Transaction-Level Retry Implementation

## Overview

Implemented transaction-level retry logic using the `tenacity` library with exponential backoff and jitter to handle DSQL OC000 transaction conflicts and avoid thundering herd problems.

## Implementation Details

### 1. Tenacity Library Integration

**Added to `requirements.txt`:**
```python
tenacity>=8.2.0  # Retry library with exponential backoff and jitter
```

### 2. Retry Utilities (`service/retry_utils.py`)

**Key Components:**

#### Error Classification
```python
def classify_dsql_error(exception: Exception) -> tuple[bool, str, Optional[str]]:
    """Classify DSQL error and extract context.
    
    Returns:
        Tuple of (is_retryable, error_type, sqlstate)
    """
```

**Error Types:**
- `OC000_TRANSACTION_CONFLICT`: DSQL optimistic concurrency control conflict (retryable)
- `DUPLICATE_EVENT`: Duplicate event ID (not retryable)
- `UNIQUE_VIOLATION`: Database unique constraint violation (not retryable)
- `CONNECTION_ERROR`: Connection/timeout errors (retryable)
- `UNKNOWN_ERROR`: Other errors (not retryable)

#### OC000 Detection
```python
def is_oc000_error(exception: Exception) -> bool:
    """Check if exception is an OC000 transaction conflict error."""
    # Checks:
    # 1. PostgresError with sqlstate == 'OC000'
    # 2. Error message patterns: 'oc000', 'conflicts with another transaction', etc.
```

#### Retry Decorator
```python
@retry_on_oc000(stop_after=5, min_wait=0.1, max_wait=2.0)
async def _execute_transaction(...):
    """Execute transaction with automatic retry on OC000 errors."""
```

**Configuration:**
- **Max Retries**: 5 attempts
- **Wait Strategy**: Exponential backoff (100ms - 2s) + jitter (0-100ms)
- **Retry Condition**: Only OC000 conflicts and connection errors
- **No Retry**: Duplicate events, unique violations, other permanent errors

### 3. Event Processing Service Updates

**Transaction Execution:**
```python
@retry_on_oc000(stop_after=5, min_wait=0.1, max_wait=2.0)
async def _execute_transaction(self, event: Event, event_id: str, transaction_id: str) -> None:
    """Execute transaction with retry logic (wrapped by tenacity decorator)."""
    conn = await get_connection(self.config)
    try:
        async with conn.transaction():
            # All database operations
            ...
    finally:
        await conn.close()  # Always close connection
```

**Key Features:**
- New connection for each retry attempt (avoids stale connections)
- Transaction ID for tracking across retries
- Structured logging with full context

### 4. Structured Logging

**Log Context Includes:**
```python
{
    'event_id': event_id,
    'event_type': event_type,
    'event_name': event_name,
    'transaction_id': transaction_id,  # Unique per transaction attempt
    'error_type': error_type,  # OC000_TRANSACTION_CONFLICT, etc.
    'sqlstate': sqlstate,  # 'OC000', etc.
    'is_retryable': is_retryable,
    'attempt': attempt_number,
    'wait_time': wait_time,
}
```

**Log Levels:**
- **INFO**: Successful processing, retry success after multiple attempts
- **WARNING**: OC000 conflict detected, retrying
- **ERROR**: All retries exhausted, non-retryable errors

## Retry Behavior

### Exponential Backoff with Jitter

**Wait Time Calculation:**
```
Attempt 1: 100ms + jitter(0-100ms) = 100-200ms
Attempt 2: 200ms + jitter(0-100ms) = 200-300ms
Attempt 3: 400ms + jitter(0-100ms) = 400-500ms
Attempt 4: 800ms + jitter(0-100ms) = 800-900ms
Attempt 5: 1600ms + jitter(0-100ms) = 1600-1700ms (capped at 2000ms)
```

**Jitter Purpose:**
- Prevents thundering herd (all retries at same time)
- Spreads retry attempts across time window
- Reduces contention on database

### Retry Flow

```
1. First Attempt:
   ├─ Create connection
   ├─ Start transaction
   ├─ Execute operations
   └─ Commit → SUCCESS ✅

2. If OC000 Error:
   ├─ Classify error (OC000_TRANSACTION_CONFLICT)
   ├─ Log with context
   ├─ Wait (exponential backoff + jitter)
   └─ Retry with new connection

3. After Max Retries:
   ├─ Log error with full context
   └─ Raise exception (returns 500)
```

## Error Classification

### OC000 Detection Methods

1. **SQLState Check** (Primary):
   ```python
   if isinstance(exception, asyncpg.PostgresError):
       if exception.sqlstate == 'OC000':
           return True
   ```

2. **Error Message Patterns** (Fallback):
   ```python
   patterns = [
       'oc000',
       'conflicts with another transaction',
       'mutation conflicts',
       'transaction conflict',
       'change conflicts',
   ]
   ```

### Non-Retryable Errors

- **DuplicateEventError**: Event ID already exists (409 Conflict)
- **UniqueViolationError**: Database constraint violation
- **Other permanent errors**: Schema errors, validation errors, etc.

## Testing

### Test Command
```bash
k6 run --env DB_TYPE=dsql \
  --env EVENTS_PER_TYPE=5 \
  --env LAMBDA_DSQL_API_URL=https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com \
  load-test/k6/send-batch-events.js
```

### Expected Results

**Before Fix:**
- Success Rate: ~85% (17/20 events)
- OC000 errors returned as 500
- No retry attempts

**After Fix:**
- Success Rate: 95-100% (19-20/20 events)
- OC000 errors retried automatically
- Structured logs in CloudWatch

### Monitoring

**CloudWatch Logs to Monitor:**
1. **Retry Attempts:**
   ```
   "OC000 transaction conflict detected - retrying"
   "Retrying after 0.234s (attempt 2/5)"
   ```

2. **Success After Retry:**
   ```
   "Successfully completed after 2 attempts"
   ```

3. **Retry Exhausted:**
   ```
   "All retry attempts exhausted (5/5)"
   ```

4. **Error Classification:**
   ```
   "error_type": "OC000_TRANSACTION_CONFLICT"
   "sqlstate": "OC000"
   "attempt": 3
   ```

## Benefits

1. **Automatic Retry**: OC000 errors handled transparently
2. **Thundering Herd Prevention**: Jitter spreads retry attempts
3. **Structured Logging**: Full context for debugging and monitoring
4. **Error Classification**: Distinguishes retryable vs permanent errors
5. **Connection Management**: New connection per retry (avoids stale connections)

## Configuration

**Retry Parameters** (in `event_processing.py`):
```python
@retry_on_oc000(stop_after=5, min_wait=0.1, max_wait=2.0)
```

**Adjustable:**
- `stop_after`: Maximum retry attempts (default: 5)
- `min_wait`: Minimum wait time (default: 0.1s)
- `max_wait`: Maximum wait time (default: 2.0s)
- Jitter: Fixed at 0-100ms (hardcoded in retry_utils.py)

## Comparison with Previous Implementation

| Feature | Previous | New (Tenacity) |
|---------|----------|----------------|
| Retry Logic | Manual loop | Decorator-based |
| Backoff | Exponential | Exponential + jitter |
| Max Retries | 3 | 5 |
| Error Detection | String matching | SQLState + patterns |
| Logging | Basic | Structured with context |
| Connection | New per retry | New per retry ✅ |
| Code Complexity | Higher | Lower (decorator) |

## Next Steps

1. **Deploy Lambda**: Build and deploy updated code
2. **Run k6 Test**: Verify 100% success rate
3. **Monitor Logs**: Check CloudWatch for retry metrics
4. **Tune Parameters**: Adjust retry count/backoff if needed
