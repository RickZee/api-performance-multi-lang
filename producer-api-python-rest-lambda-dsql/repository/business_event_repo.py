"""Business event repository for database operations."""

import asyncpg
import json
import logging
import asyncio
from typing import Optional
from datetime import datetime

logger = logging.getLogger(__name__)

# Retry configuration
MAX_RETRIES = 3
INITIAL_RETRY_DELAY = 0.1  # 100ms
MAX_RETRY_DELAY = 2.0  # 2 seconds


class DuplicateEventError(Exception):
    """Exception raised when attempting to create an event with an existing ID."""
    def __init__(self, event_id: str, message: str = None):
        self.event_id = event_id
        self.message = message or f"Event with ID '{event_id}' already exists"
        super().__init__(self.message)


class BusinessEventRepository:
    """Repository for business event database operations."""
    
    def __init__(self, pool: Optional[asyncpg.Pool] = None):
        """Initialize repository (pool is optional, connections are passed directly)."""
        self.pool = pool  # Kept for backward compatibility, but not used
    
    def _is_retryable_error(self, error: Exception) -> bool:
        """Check if error is retryable (connection/timeout/transaction conflicts).
        
        Includes DSQL OC000 transaction conflict errors which require retry
        due to Optimistic Concurrency Control (OCC).
        """
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
            # DSQL transaction conflicts (OC000) - Optimistic Concurrency Control
            'conflicts with another transaction',
            'oc000',
            'mutation conflicts',
            'transaction conflict',
            'change conflicts',
        ]
        return any(err in error_str for err in retryable_errors)
    
    async def _retry_with_backoff(self, func, *args, **kwargs):
        """Retry function with exponential backoff."""
        delay = INITIAL_RETRY_DELAY
        last_error = None
        
        for attempt in range(MAX_RETRIES):
            try:
                return await func(*args, **kwargs)
            except DuplicateEventError:
                # Don't retry duplicate key errors - raise immediately
                raise
            except Exception as e:
                last_error = e
                
                # Check if error is retryable
                if not self._is_retryable_error(e) or attempt == MAX_RETRIES - 1:
                    raise
                
                # Exponential backoff
                logger.warning(
                    f"Retryable error on attempt {attempt + 1}/{MAX_RETRIES}: {e}. "
                    f"Retrying in {delay:.2f}s..."
                )
                await asyncio.sleep(delay)
                delay = min(delay * 2, MAX_RETRY_DELAY)
        
        # If we exhausted retries, raise the last error
        raise last_error
    
    async def create(self, event_id: str, event_name: str, event_type: Optional[str],
                     created_date: Optional[datetime], saved_date: Optional[datetime],
                     event_data: dict, conn: Optional[asyncpg.Connection] = None) -> None:
        """Create a new business event with retry logic.
        
        Args:
            event_id: Event ID
            event_name: Event name
            event_type: Event type
            created_date: Created date
            saved_date: Saved date
            event_data: Full event JSON as dict
            conn: Optional database connection (for transactions). If not provided, acquires from pool.
        
        Raises:
            DuplicateEventError: If an event with the same ID already exists (409 Conflict)
        """
        async def _do_create():
            if conn:
                # Use provided connection directly (transaction managed externally)
                # Skip diagnostics when in transaction for performance
                await self._insert_business_event(conn, event_id, event_name, event_type,
                                                 created_date, saved_date, event_data,
                                                 skip_diagnostics=True)
            else:
                # Connection should always be provided by service layer
                # This fallback should not be reached in normal operation
                raise ValueError("Connection must be provided (no pool available)")
        
        await self._retry_with_backoff(_do_create)
    
    async def _insert_business_event(self, conn: asyncpg.Connection, event_id: str, event_name: str,
                                    event_type: Optional[str], created_date: Optional[datetime],
                                    saved_date: Optional[datetime], event_data: dict,
                                    skip_diagnostics: bool = False) -> None:
        """Insert business event into database.
        
        Args:
            conn: Database connection
            event_id: Event ID
            event_name: Event name
            event_type: Event type
            created_date: Created date
            saved_date: Saved date
            event_data: Event data as dict
            skip_diagnostics: If True, skip diagnostic queries (useful when in transaction)
        """
        import time
        step_start = time.time()
        
        try:
            # Diagnostic: Check current database and schema (skip when in transaction for performance)
            if not skip_diagnostics:
                current_db = await conn.fetchval('SELECT current_database();')
                current_schema = await conn.fetchval('SELECT current_schema();')
                table_exists = await conn.fetchval("""
                    SELECT EXISTS (
                        SELECT FROM information_schema.tables 
                        WHERE table_schema = $1
                        AND table_name = 'business_events'
                    );
                """, current_schema)
                
                logger.debug(
                    f"Database context check",
                    extra={
                        'event_id': event_id,
                        'database': current_db,
                        'schema': current_schema,
                        'table_exists': table_exists,
                    }
                )
                
                if not table_exists:
                    # List available tables for debugging
                    tables = await conn.fetch("""
                        SELECT tablename 
                        FROM pg_tables 
                        WHERE schemaname = $1
                        ORDER BY tablename;
                    """, current_schema)
                    table_list = [t['tablename'] for t in tables]
                    logger.warning(
                        f"business_events table not found",
                        extra={
                            'event_id': event_id,
                            'schema': current_schema,
                            'available_tables': table_list,
                        }
                    )
            
            insert_start = time.time()
            await conn.execute(
                """
                INSERT INTO business_events (id, event_name, event_type, created_date, saved_date, event_data)
                VALUES ($1, $2, $3, $4, $5, $6)
                """,
                event_id,
                event_name,
                event_type,
                created_date,
                saved_date,
                json.dumps(event_data),
            )
            insert_duration = int((time.time() - insert_start) * 1000)
            total_duration = int((time.time() - step_start) * 1000)
            
            logger.debug(
                f"Business event inserted",
                extra={
                    'event_id': event_id,
                    'event_type': event_type,
                    'insert_duration_ms': insert_duration,
                    'total_duration_ms': total_duration,
                }
            )
        except asyncpg.UniqueViolationError as e:
            # Raise custom exception for duplicate key violations
            duration = int((time.time() - step_start) * 1000)
            logger.warning(
                f"Duplicate event ID detected: {event_id}",
                extra={
                    'event_id': event_id,
                    'error_type': 'UniqueViolationError',
                    'duration_ms': duration,
                }
            )
            raise DuplicateEventError(event_id, f"Event with ID '{event_id}' already exists") from e
        except asyncpg.SerializationError as e:
            # OC000 transaction conflict
            duration = int((time.time() - step_start) * 1000)
            sqlstate = getattr(e, 'sqlstate', None)
            logger.warning(
                f"OC000 transaction conflict during business_event insert",
                extra={
                    'event_id': event_id,
                    'error_type': 'SerializationError',
                    'sqlstate': sqlstate,
                    'duration_ms': duration,
                    'error': str(e)[:200],
                }
            )
            raise
        except Exception as e:
            duration = int((time.time() - step_start) * 1000)
            logger.error(
                f"Error inserting business event",
                extra={
                    'event_id': event_id,
                    'error_type': type(e).__name__,
                    'duration_ms': duration,
                    'error': str(e)[:200],
                },
                exc_info=True
            )
            raise
