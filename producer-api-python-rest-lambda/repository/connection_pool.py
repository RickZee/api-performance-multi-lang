"""Connection pool management for Lambda (singleton pattern)."""

import asyncpg
import logging
from typing import Optional

logger = logging.getLogger(__name__)

# Global connection pool (reused across Lambda invocations)
_pool: Optional[asyncpg.Pool] = None
_pool_database_url: Optional[str] = None


async def get_connection_pool(database_url: str) -> asyncpg.Pool:
    """
    Get or create the connection pool (singleton pattern).
    The pool is reused across Lambda invocations for better performance.
    
    Invalidates and recreates the pool if the database URL changes,
    ensuring that configuration updates are picked up.
    """
    global _pool, _pool_database_url
    
    # Invalidate pool if database URL changed (e.g., after Lambda config update)
    if _pool is not None and _pool_database_url != database_url:
        logger.warning(f"Database URL changed. Invalidating existing connection pool. Old: {_pool_database_url}, New: {database_url}")
        try:
            await _pool.close()
        except Exception as e:
            logger.warning(f"Error closing old connection pool: {e}")
        _pool = None
        _pool_database_url = None
    
    if _pool is None:
        logger.info(f"Creating new connection pool for database: {database_url.split('@')[-1] if '@' in database_url else 'unknown'}")
        try:
            # Parse connection string and create pool
            # asyncpg expects postgresql:// format
            _pool = await asyncpg.create_pool(
                database_url,
                min_size=1,
                max_size=2,  # Reduced - RDS Proxy handles connection pooling
                command_timeout=30,
            )
            _pool_database_url = database_url
            logger.info("Connection pool created successfully")
        except Exception as e:
            logger.error(f"Failed to create connection pool: {e}")
            raise
    
    return _pool


async def invalidate_connection_pool():
    """Invalidate the connection pool, forcing recreation on next use."""
    global _pool, _pool_database_url
    
    if _pool is not None:
        logger.warning("Invalidating connection pool due to error")
        try:
            await _pool.close()
        except Exception as e:
            logger.warning(f"Error closing connection pool during invalidation: {e}")
        _pool = None
        _pool_database_url = None


async def close_connection_pool():
    """Close the connection pool (useful for testing)."""
    global _pool, _pool_database_url
    
    if _pool is not None:
        logger.info("Closing connection pool")
        try:
            await _pool.close()
        except Exception as e:
            logger.warning(f"Error closing connection pool: {e}")
        _pool = None
        _pool_database_url = None
