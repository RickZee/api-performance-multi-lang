"""Retry utilities for transaction-level retry with error classification."""

import asyncpg
import logging
from typing import Optional, Callable, Any
from functools import wraps
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential_jitter,
    retry_if_exception,
    before_sleep_log,
    after_log,
    RetryCallState,
)

logger = logging.getLogger(__name__)

# Custom exception for OC000 transaction conflicts
class OC000TransactionConflictError(Exception):
    """Exception raised for DSQL OC000 transaction conflicts (retryable)."""
    def __init__(self, message: str, sqlstate: Optional[str] = None, original_error: Optional[Exception] = None):
        self.message = message
        self.sqlstate = sqlstate or 'OC000'
        self.original_error = original_error
        super().__init__(self.message)


def is_oc000_error(exception: Exception) -> bool:
    """Check if exception is an OC000 transaction conflict error.
    
    Args:
        exception: The exception to check
        
    Returns:
        True if this is an OC000 error, False otherwise
    """
    # Check for SerializationError (asyncpg's exception type for OC000)
    if isinstance(exception, asyncpg.SerializationError):
        error_msg = str(exception).lower()
        if 'oc000' in error_msg or 'conflicts with another transaction' in error_msg:
            return True
    
    # Check for PostgresError with sqlstate OC000
    if isinstance(exception, asyncpg.PostgresError):
        if hasattr(exception, 'sqlstate') and exception.sqlstate == 'OC000':
            return True
        # Also check error message for OC000 patterns
        error_msg = str(exception).lower()
        if 'oc000' in error_msg or 'conflicts with another transaction' in error_msg:
            return True
    
    # Check error message for OC000 patterns (fallback)
    error_str = str(exception).lower()
    oc000_patterns = [
        'oc000',
        'conflicts with another transaction',
        'mutation conflicts',
        'transaction conflict',
        'change conflicts',
        'serializationerror',  # asyncpg exception type
    ]
    return any(pattern in error_str for pattern in oc000_patterns)


def classify_dsql_error(exception: Exception) -> tuple[bool, str, Optional[str]]:
    """Classify DSQL error and extract context.
    
    Args:
        exception: The exception to classify
        
    Returns:
        Tuple of (is_retryable, error_type, sqlstate)
        - is_retryable: True if error should be retried
        - error_type: Classification of error (OC000, DuplicateEventError, etc.)
        - sqlstate: PostgreSQL error code if available
    """
    # Check for SerializationError (asyncpg's exception for OC000)
    # SerializationError can have sqlstate '40001' (serialization failure) or 'OC000' (DSQL-specific)
    if isinstance(exception, asyncpg.SerializationError):
        error_msg = str(exception).lower()
        # Check for OC000 in message or sqlstate
        sqlstate = None
        if hasattr(exception, 'sqlstate'):
            sqlstate = exception.sqlstate
        
        # DSQL OC000 conflicts or PostgreSQL serialization failures (40001)
        if ('oc000' in error_msg or 
            'conflicts with another transaction' in error_msg or
            sqlstate == 'OC000' or 
            sqlstate == '40001'):  # PostgreSQL serialization failure
            return True, 'OC000_TRANSACTION_CONFLICT', sqlstate or 'OC000'
    
    # Check for OC000 transaction conflicts (PostgresError)
    if is_oc000_error(exception):
        sqlstate = None
        if isinstance(exception, asyncpg.PostgresError) and hasattr(exception, 'sqlstate'):
            sqlstate = exception.sqlstate
        return True, 'OC000_TRANSACTION_CONFLICT', sqlstate or 'OC000'
    
    # Check for duplicate event errors (not retryable)
    from repository.business_event_repo import DuplicateEventError
    if isinstance(exception, DuplicateEventError):
        return False, 'DUPLICATE_EVENT', None
    
    # Check for unique violation (duplicate key)
    if isinstance(exception, asyncpg.UniqueViolationError):
        sqlstate = None
        if hasattr(exception, 'sqlstate'):
            sqlstate = exception.sqlstate
        return False, 'UNIQUE_VIOLATION', sqlstate
    
    # Check for connection/timeout errors (retryable)
    error_str = str(exception).lower()
    connection_errors = [
        'connection',
        'timeout',
        'network',
        'unable to connect',
        'connection refused',
        'connection reset',
        'connection timed out',
        'server closed the connection',
    ]
    if any(err in error_str for err in connection_errors):
        sqlstate = None
        if isinstance(exception, asyncpg.PostgresError) and hasattr(exception, 'sqlstate'):
            sqlstate = exception.sqlstate
        return True, 'CONNECTION_ERROR', sqlstate
    
    # Default: not retryable
    sqlstate = None
    if isinstance(exception, asyncpg.PostgresError) and hasattr(exception, 'sqlstate'):
        sqlstate = exception.sqlstate
    return False, 'UNKNOWN_ERROR', sqlstate


def log_retry_attempt(call_state: RetryCallState, event_id: Optional[str] = None, 
                     event_type: Optional[str] = None, attempt_number: Optional[int] = None):
    """Log retry attempt with structured context.
    
    Args:
        call_state: Tenacity retry call state
        event_id: Event ID for context
        event_type: Event type for context
        attempt_number: Attempt number (if not in call_state)
    """
    attempt = attempt_number or call_state.attempt_number
    exception = call_state.outcome.exception() if call_state.outcome else None
    
    is_retryable, error_type, sqlstate = classify_dsql_error(exception) if exception else (False, 'UNKNOWN', None)
    
    log_context = {
        'event_id': event_id,
        'event_type': event_type,
        'attempt': attempt,
        'error_type': error_type,
        'sqlstate': sqlstate,
        'is_retryable': is_retryable,
        'exception': str(exception) if exception else None,
    }
    
    if error_type == 'OC000_TRANSACTION_CONFLICT':
        logger.warning(
            f"OC000 transaction conflict detected - retrying",
            extra=log_context
        )
    else:
        logger.warning(
            f"Retryable error detected - retrying",
            extra=log_context
        )


def retry_on_oc000(stop_after: int = 5, min_wait: float = 0.1, max_wait: float = 2.0):
    """Create a retry decorator for OC000 transaction conflicts.
    
    Args:
        stop_after: Maximum number of retry attempts (default: 5)
        min_wait: Minimum wait time in seconds (default: 0.1)
        max_wait: Maximum wait time in seconds (default: 2.0)
        
    Returns:
        Retry decorator configured for OC000 errors
    """
    def retry_condition(exception: Exception) -> bool:
        """Check if exception should be retried."""
        is_retryable, error_type, sqlstate = classify_dsql_error(exception)
        
        logger.info(
            f"Retry condition check: exception={type(exception).__name__}, "
            f"is_retryable={is_retryable}, error_type={error_type}, sqlstate={sqlstate}",
            extra={
                'exception_type': type(exception).__name__,
                'is_retryable': is_retryable,
                'error_type': error_type,
                'sqlstate': sqlstate,
                'exception_str': str(exception)[:200],
            }
        )
        
        # Only retry OC000 conflicts and connection errors
        # Do NOT retry duplicate events or other permanent errors
        should_retry = is_retryable and error_type in ('OC000_TRANSACTION_CONFLICT', 'CONNECTION_ERROR')
        
        if should_retry:
            logger.warning(f"Exception is retryable: {error_type}")
        else:
            logger.warning(f"Exception is NOT retryable: {error_type} (is_retryable={is_retryable})")
        
        return should_retry
    
    def before_sleep_handler(retry_state: RetryCallState):
        """Log before sleep with context."""
        exception = retry_state.outcome.exception() if retry_state.outcome else None
        if exception:
            is_retryable, error_type, sqlstate = classify_dsql_error(exception)
            wait_time = retry_state.next_action.sleep if retry_state.next_action else 0
            
            logger.warning(
                f"Retrying after {wait_time:.3f}s (attempt {retry_state.attempt_number}/{stop_after})",
                extra={
                    'error_type': error_type,
                    'sqlstate': sqlstate,
                    'attempt': retry_state.attempt_number,
                    'wait_time': wait_time,
                }
            )
    
    def after_retry_handler(retry_state: RetryCallState):
        """Log after retry completes."""
        if retry_state.outcome and retry_state.outcome.failed:
            exception = retry_state.outcome.exception()
            is_retryable, error_type, sqlstate = classify_dsql_error(exception)
            
            logger.error(
                f"All retry attempts exhausted ({retry_state.attempt_number}/{stop_after})",
                extra={
                    'error_type': error_type,
                    'sqlstate': sqlstate,
                    'final_attempt': retry_state.attempt_number,
                    'exception': str(exception),
                },
                exc_info=exception
            )
        else:
            if retry_state.attempt_number > 1:
                logger.info(
                    f"Successfully completed after {retry_state.attempt_number} attempts",
                    extra={
                        'total_attempts': retry_state.attempt_number,
                    }
                )
    
    # Use tenacity's built-in wait_exponential_jitter to avoid thundering herd
    # Formula: min(initial * 2^n + random.uniform(0, jitter), maximum)
    # This provides exponential backoff with jitter to spread retry attempts
    wait_strategy = wait_exponential_jitter(
        initial=min_wait,  # Starting wait time (100ms)
        max=max_wait,      # Maximum wait time (2s)
        jitter=0.1         # Jitter range (0-100ms) to avoid thundering herd
    )
    
    return retry(
        stop=stop_after_attempt(stop_after),
        wait=wait_strategy,
        retry=retry_if_exception(retry_condition),
        before_sleep=before_sleep_handler,
        after=after_retry_handler,
        reraise=True,  # Re-raise the exception after all retries exhausted
    )


def with_retry_context(event_id: Optional[str] = None, event_type: Optional[str] = None):
    """Decorator to add retry context to function calls.
    
    Args:
        event_id: Event ID for logging context
        event_type: Event type for logging context
        
    Returns:
        Decorator that adds context to retry attempts
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # Store context in function attributes for retry handlers
            func._retry_context = {
                'event_id': event_id,
                'event_type': event_type,
            }
            return await func(*args, **kwargs)
        return wrapper
    return decorator
