"""Connection pool management for Lambda (singleton pattern)."""

import asyncpg
import logging
from typing import Optional

logger = logging.getLogger(__name__)

# Global connection pool (reused across Lambda invocations)
_pool: Optional[asyncpg.Pool] = None


async def get_connection_pool(database_url: str) -> asyncpg.Pool:
    """
    Get or create the connection pool (singleton pattern).
    The pool is reused across Lambda invocations for better performance.
    """
    global _pool
    
    if _pool is None:
        logger.info("Creating new connection pool")
        try:
            # Parse connection string and create pool
            # asyncpg expects postgresql:// format
            _pool = await asyncpg.create_pool(
                database_url,
                min_size=1,
                max_size=2,  # Reduced - RDS Proxy handles connection pooling
                command_timeout=30,
            )
            logger.info("Connection pool created successfully")
        except Exception as e:
            logger.error(f"Failed to create connection pool: {e}")
            raise
    
    return _pool


async def close_connection_pool():
    """Close the connection pool (useful for testing)."""
    global _pool
    
    if _pool is not None:
        logger.info("Closing connection pool")
        await _pool.close()
        _pool = None
