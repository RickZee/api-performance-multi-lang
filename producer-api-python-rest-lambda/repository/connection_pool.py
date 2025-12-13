"""Connection pool management for Lambda and FastAPI (singleton pattern)."""

import asyncpg
import asyncio
import logging
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
    
    # #region agent log - Hypothesis H
    import json
    try:
        current_loop = asyncio.get_running_loop()
        loop_id = id(current_loop)
        with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
            f.write(json.dumps({"sessionId":"debug-session","runId":"run2","hypothesisId":"H","location":"connection_pool.py:22","message":"get_connection_pool entry","data":{"loop_id":loop_id,"has_pool":_pool is not None,"pool_database_url":_pool_database_url},"timestamp":int(__import__('time').time()*1000)})+'\n')
    except Exception as e:
        try:
            with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
                f.write(json.dumps({"sessionId":"debug-session","runId":"run2","hypothesisId":"ERROR","location":"connection_pool.py:22","message":"Instrumentation error","data":{"error":str(e)},"timestamp":int(__import__('time').time()*1000)})+'\n')
        except: pass
    # #endregion
    
    # Get current event loop ID
    current_loop = asyncio.get_running_loop()
    current_loop_id = id(current_loop)
    
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
            # #region agent log - pool invalidation
            try:
                import json
                with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
                    f.write(json.dumps({"sessionId":"debug-session","runId":"run3","hypothesisId":"H","location":"connection_pool.py:invalidate","message":"Pool invalidated due to loop change","data":{"reason":reason,"old_loop_id":_pool_loop_id,"new_loop_id":current_loop_id},"timestamp":int(__import__('time').time()*1000)})+'\n')
            except: pass
            # #endregion
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
        # #region agent log - Hypothesis H
        try:
            with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
                f.write(json.dumps({"sessionId":"debug-session","runId":"run2","hypothesisId":"H","location":"connection_pool.py:48","message":"Creating pool - BEFORE create_pool","data":{"loop_id":loop_id,"database":database_url.split('@')[-1] if '@' in database_url else 'unknown'},"timestamp":int(__import__('time').time()*1000)})+'\n')
        except: pass
        # #endregion
        logger.info(f"Creating new connection pool for loop: {loop_id}, database: {database_url.split('@')[-1] if '@' in database_url else 'unknown'}")
        try:
            # Create pool - it will automatically bind to the current running event loop
            # Note: The 'loop' parameter is deprecated in newer asyncpg versions
            # The pool will automatically use asyncio.get_running_loop()
            _pool = await asyncpg.create_pool(
                database_url,
                min_size=1,
                max_size=10,  # Increased for FastAPI (better concurrency)
                command_timeout=30,
            )
            _pool_database_url = database_url
            _pool_loop_id = current_loop_id  # Track the loop that created this pool
            # #region agent log - Hypothesis H
            try:
                current_loop_after = asyncio.get_running_loop()
                loop_id_after = id(current_loop_after)
                pool_loop_id = id(_pool._loop) if hasattr(_pool, '_loop') else None
                with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
                    f.write(json.dumps({"sessionId":"debug-session","runId":"run2","hypothesisId":"H","location":"connection_pool.py:57","message":"Creating pool - AFTER create_pool","data":{"loop_id_before":loop_id,"loop_id_after":loop_id_after,"pool_id":id(_pool),"pool_loop_id":pool_loop_id},"timestamp":int(__import__('time').time()*1000)})+'\n')
            except: pass
            # #endregion
            logger.info(f"Connection pool created successfully for loop: {loop_id}")
        except Exception as e:
            logger.error(f"Failed to create connection pool: {e}", exc_info=True)
            raise
    else:
        # #region agent log - Hypothesis H
        try:
            current_loop = asyncio.get_running_loop()
            loop_id = id(current_loop)
            pool_loop_id = id(_pool._loop) if hasattr(_pool, '_loop') else None
            with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
                f.write(json.dumps({"sessionId":"debug-session","runId":"run2","hypothesisId":"H","location":"connection_pool.py:62","message":"Returning existing pool","data":{"loop_id":loop_id,"pool_id":id(_pool),"pool_loop_id":pool_loop_id},"timestamp":int(__import__('time').time()*1000)})+'\n')
        except: pass
        # #endregion
    
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
