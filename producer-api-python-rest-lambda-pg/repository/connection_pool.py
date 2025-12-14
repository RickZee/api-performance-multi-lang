"""Connection pool management for Lambda and FastAPI (singleton pattern)."""

import asyncpg
import asyncio
import logging
import os
from typing import Optional

logger = logging.getLogger(__name__)

# Global connection pool for Lambda/FastAPI (single event loop)
_pool: Optional[asyncpg.Pool] = None
_pool_database_url: Optional[str] = None
_pool_loop_id: Optional[int] = None  # Track the loop ID that created the pool


def _is_flask_environment():
    """Check if running in Flask (multi-threaded) environment."""
    # FastAPI is async-native, so we don't need special handling
    # This function is kept for backward compatibility but should return False
    return False


async def get_connection(config) -> asyncpg.Connection:
    """Get a direct database connection (no pooling).
    
    RDS Proxy handles connection pooling at the infrastructure level,
    so we use direct connections per request.
    """
    try:
        database_url = config.database_url
        logger.info(f"Creating direct connection to: {database_url.split('@')[-1] if '@' in database_url else 'unknown'}")
        conn = await asyncpg.connect(database_url)
        logger.debug(f"Direct connection established: {id(conn)}")
        return conn
    except Exception as e:
        logger.error(f"Failed to create direct connection: {e}", exc_info=True)
        raise


async def get_connection_pool(database_url: str) -> asyncpg.Pool:
    """
    Get or create the connection pool.
    - Lambda: Uses global singleton pattern (single-threaded)
    - FastAPI: Uses global singleton pattern (single event loop)
    
    Invalidates and recreates the pool if:
    - The database URL changes
    - The current event loop differs from the loop that created the pool
    
    This ensures asyncpg pools are always used in the same loop context they were created in.
    """
    # FastAPI and Lambda both use a single event loop, so we can use global singleton
    global _pool, _pool_database_url, _pool_loop_id
    
    # Get current event loop ID - handle both running and non-running loops
    try:
        current_loop = asyncio.get_running_loop()
        current_loop_id = id(current_loop)
        logger.debug(f"get_connection_pool: using running loop: {current_loop_id}")
    except RuntimeError:
        # No running loop - get or create event loop (for Lambda handler context)
        try:
            current_loop = asyncio.get_event_loop()
            # Ensure loop is set for this thread
            if asyncio.get_event_loop() != current_loop:
                asyncio.set_event_loop(current_loop)
            current_loop_id = id(current_loop)
            logger.debug(f"get_connection_pool: using event loop (not running): {current_loop_id}")
        except RuntimeError:
            # No event loop exists - create a new one
            current_loop = asyncio.new_event_loop()
            asyncio.set_event_loop(current_loop)
            current_loop_id = id(current_loop)
            logger.warning(f"get_connection_pool: created new event loop: {current_loop_id}")
    
    logger.debug(f"get_connection_pool entry: loop_id={current_loop_id}, has_pool={_pool is not None}")
    
    # Invalidate pool if database URL changed OR if we're in a different event loop
    if _pool is not None:
        should_invalidate = False
        reason = None
        
        if _pool_database_url != database_url:
            should_invalidate = True
            reason = f"Database URL changed (Old: {_pool_database_url}, New: {database_url})"
        elif _pool_loop_id is not None and _pool_loop_id != current_loop_id:
            should_invalidate = True
            reason = f"Event loop changed (Pool loop: {_pool_loop_id}, Current loop: {current_loop_id})"
        
        if should_invalidate:
            logger.warning(f"Invalidating existing connection pool. Reason: {reason}")
            try:
                await _pool.close()
            except Exception as e:
                logger.warning(f"Error closing old connection pool: {e}")
            _pool = None
            _pool_database_url = None
            _pool_loop_id = None
    
    if _pool is None:
        # Get current event loop to ensure pool is bound to it
        # (current_loop already obtained above for invalidation check)
        loop_id = current_loop_id
        logger.info(f"Creating new connection pool for loop: {loop_id}, database: {database_url.split('@')[-1] if '@' in database_url else 'unknown'}")
        try:
            # Ensure we have a valid event loop before creating pool
            # asyncpg.create_pool() requires a running loop or properly set event loop
            try:
                # Try to get running loop first
                running_loop = asyncio.get_running_loop()
                logger.debug(f"Pool creation: using running loop: {id(running_loop)}")
            except RuntimeError:
                # No running loop - ensure event loop is set
                event_loop = asyncio.get_event_loop()
                if event_loop != current_loop:
                    asyncio.set_event_loop(current_loop)
                logger.debug(f"Pool creation: using event loop (not running): {id(current_loop)}")
            
            # Pool size configurable via environment variables
            min_size = int(os.getenv('DB_POOL_MIN_SIZE', '1'))
            max_size = int(os.getenv('DB_POOL_MAX_SIZE', '10'))
            command_timeout = int(os.getenv('DB_POOL_COMMAND_TIMEOUT', '30'))
            
            logger.info(f"Creating asyncpg pool: min_size={min_size}, max_size={max_size}, timeout={command_timeout}s")
            
            # Create pool - it will automatically bind to the current event loop
            # Note: The 'loop' parameter is deprecated in newer asyncpg versions
            # The pool will automatically use asyncio.get_running_loop() or asyncio.get_event_loop()
            _pool = await asyncpg.create_pool(
                database_url,
                min_size=min_size,
                max_size=max_size,
                command_timeout=command_timeout,
            )
            _pool_database_url = database_url
            _pool_loop_id = current_loop_id  # Track the loop that created this pool
            logger.info(f"Connection pool created successfully: pool_id={id(_pool)}, loop_id={loop_id}")
        except Exception as e:
            logger.error(f"Failed to create connection pool: {e}", exc_info=True)
            # Log additional context for debugging
            logger.error(f"Database URL (masked): ...@{database_url.split('@')[-1] if '@' in database_url else 'unknown'}")
            logger.error(f"Event loop ID: {current_loop_id}, loop closed: {current_loop.is_closed() if hasattr(current_loop, 'is_closed') else 'unknown'}")
            raise
    else:
        logger.debug(f"Returning existing connection pool: pool_id={id(_pool)}, loop_id={current_loop_id}")
    
    return _pool


async def invalidate_connection_pool():
    """Invalidate the connection pool, forcing recreation on next use."""
    global _pool, _pool_database_url, _pool_loop_id
    
    if _pool is not None:
        logger.warning("Invalidating connection pool due to error")
        try:
            await _pool.close()
        except Exception as e:
            logger.warning(f"Error closing connection pool during invalidation: {e}")
        _pool = None
        _pool_database_url = None
        _pool_loop_id = None


async def close_connection_pool():
    """Close the connection pool (useful for testing)."""
    global _pool, _pool_database_url, _pool_loop_id
    
    if _pool is not None:
        logger.info("Closing connection pool")
        try:
            await _pool.close()
        except Exception as e:
            logger.warning(f"Error closing connection pool: {e}")
        _pool = None
        _pool_database_url = None
        _pool_loop_id = None
