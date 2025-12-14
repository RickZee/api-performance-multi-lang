"""Direct connection management for Lambda (no pooling).

RDS Proxy handles connection pooling at the infrastructure level,
so we use direct connections per request to avoid redundant pooling.
"""

import asyncpg
import logging
from config import LambdaConfig

logger = logging.getLogger(__name__)


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
    """
    database_url = config.database_url
    
    if not database_url:
        raise ValueError("Database URL is required")
    
    logger.debug(f"Creating direct connection: {database_url.split('@')[-1] if '@' in database_url else 'unknown'}")
    
    try:
        conn = await asyncpg.connect(
            database_url,
            command_timeout=30
        )
        logger.debug("Direct connection created successfully")
        return conn
    except Exception as e:
        logger.error(f"Failed to create direct connection: {e}", exc_info=True)
        raise

