"""Business event repository for database operations."""

import asyncpg
import json
import logging
import asyncio
from typing import Optional
from datetime import datetime
from repository.connection_pool import invalidate_connection_pool

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
    
    def __init__(self, pool: asyncpg.Pool):
        """Initialize repository with connection pool."""
        self.pool = pool
    
    def _is_retryable_error(self, error: Exception) -> bool:
        """Check if error is retryable (connection/timeout errors)."""
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
        ]
        return any(err in error_str for err in retryable_errors)
    
    def _is_pool_invalidation_error(self, error: Exception) -> bool:
        """Check if error indicates connection pool should be invalidated (wrong database/connection)."""
        error_str = str(error).lower()
        # Check for errors that suggest wrong database connection
        invalid_pool_errors = [
            '127.0.0.1',  # Connecting to localhost instead of RDS
            'localhost',
            'cannot assign requested address',  # Connection to wrong endpoint
        ]
        return any(err in error_str for err in invalid_pool_errors)
    
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
                
                # If this is a pool invalidation error, invalidate the pool before retrying
                if self._is_pool_invalidation_error(e) and attempt == 0:
                    logger.warning(f"Pool invalidation error detected: {e}. Invalidating connection pool...")
                    await invalidate_connection_pool()
                
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
                     event_data: dict) -> None:
        """Create a new business event with retry logic.
        
        Raises:
            DuplicateEventError: If an event with the same ID already exists (409 Conflict)
        """
        async def _do_create():
            async with self.pool.acquire() as conn:
                try:
                    # Diagnostic: Check current database and schema
                    current_db = await conn.fetchval('SELECT current_database();')
                    current_schema = await conn.fetchval('SELECT current_schema();')
                    table_exists = await conn.fetchval("""
                        SELECT EXISTS (
                            SELECT FROM information_schema.tables 
                            WHERE table_schema = $1
                            AND table_name = 'business_events'
                        );
                    """, current_schema)
                    
                    logger.info(f"Database context - DB: {current_db}, Schema: {current_schema}, business_events exists: {table_exists}")
                    
                    if not table_exists:
                        # List available tables for debugging
                        tables = await conn.fetch("""
                            SELECT tablename 
                            FROM pg_tables 
                            WHERE schemaname = $1
                            ORDER BY tablename;
                        """, current_schema)
                        table_list = [t['tablename'] for t in tables]
                        logger.warning(f"business_events table not found in schema '{current_schema}'. Available tables: {table_list}")
                    
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
                except asyncpg.UniqueViolationError as e:
                    # Raise custom exception for duplicate key violations
                    logger.warning(f"Duplicate event ID detected: {event_id}")
                    raise DuplicateEventError(event_id, f"Event with ID '{event_id}' already exists") from e
        
        await self._retry_with_backoff(_do_create)
