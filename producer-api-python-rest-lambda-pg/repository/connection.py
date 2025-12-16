"""Direct connection management for Lambda (no pooling).

RDS Proxy handles connection pooling at the infrastructure level,
so we use direct connections per request to avoid redundant pooling.
"""

import asyncpg
import asyncio
import logging
from config import LambdaConfig

logger = logging.getLogger(__name__)

# Connection timeout for VPC connections (can be slow on cold starts)
CONNECTION_TIMEOUT = 15  # seconds
COMMAND_TIMEOUT = 30  # seconds


async def get_connection(config: LambdaConfig) -> asyncpg.Connection:
    """
    Get a direct database connection (no pooling).
    
    RDS Proxy handles connection pooling at the infrastructure level,
    so we create direct connections per request. This simplifies the code
    and avoids cold start overhead from pool creation.
    
    Args:
        config: Lambda configuration object
        
    Returns:
        asyncpg.Connection: Direct database connection
        
    Raises:
        asyncio.TimeoutError: If connection establishment exceeds CONNECTION_TIMEOUT
        Exception: Other connection errors
    """
    database_url = config.database_url
    
    if not database_url:
        raise ValueError("Database URL is required")
    
    # Extract endpoint for logging (mask password)
    endpoint = database_url.split('@')[-1] if '@' in database_url else 'unknown'
    
    # Log event loop ID for debugging
    try:
        current_loop = asyncio.get_running_loop()
        loop_id = id(current_loop)
        logger.debug(f"Creating direct connection to {endpoint} in event loop: {loop_id}")
    except RuntimeError:
        loop_id = "unknown"
        logger.warning(f"Creating direct connection to {endpoint} (no running loop detected)")
    
    try:
        # Use asyncio.wait_for to enforce connection establishment timeout
        # This prevents hanging indefinitely on VPC connections
        conn = await asyncio.wait_for(
            asyncpg.connect(
                database_url,
                command_timeout=COMMAND_TIMEOUT  # Timeout for SQL commands/queries
            ),
            timeout=CONNECTION_TIMEOUT  # Timeout for connection establishment
        )
        logger.info(f"Direct connection created successfully to {endpoint} (loop_id={loop_id})")
        return conn
    except asyncio.TimeoutError:
        logger.error(f"Connection timeout after {CONNECTION_TIMEOUT}s to {endpoint} (loop_id={loop_id})")
        raise ConnectionError(f"Connection timeout: Unable to connect to database within {CONNECTION_TIMEOUT} seconds")
    except Exception as e:
        logger.error(f"Failed to create direct connection to {endpoint} (loop_id={loop_id}): {e}", exc_info=True)
        raise

