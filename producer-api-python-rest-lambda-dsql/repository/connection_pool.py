"""Direct connection management for Lambda and FastAPI (no pooling)."""

import asyncpg
import logging
from typing import Union

from .iam_auth import generate_iam_auth_token
from config import LambdaConfig

logger = logging.getLogger(__name__)


async def get_connection(database_url_or_config: Union[str, LambdaConfig]) -> asyncpg.Connection:
    """
    Get a direct database connection (no pooling) with detailed logging.
    
    For Lambda workloads with single-event-per-invocation patterns, direct connections
    are simpler and avoid DSQL compatibility issues (e.g., pg_advisory_unlock_all).
    
    IAM tokens are cached for 14 minutes to minimize overhead.
    
    Args:
        database_url_or_config: Either a database URL string (legacy) or LambdaConfig object
        
    Returns:
        asyncpg.Connection: Direct database connection
    """
    import time
    connection_start = time.time()
    
    logger.debug("Creating database connection...")
    config = database_url_or_config if isinstance(database_url_or_config, LambdaConfig) else None
    
    if config and config.use_iam_auth:
        # Determine the endpoint to use for token generation and connection
        # Use dsql_host (format: <cluster-id>.<service-suffix>.<region>.on.aws) for proper SNI
        if config.dsql_host:
            dsql_endpoint = config.dsql_host
            logger.info(f"Using DSQL host for connection: {dsql_endpoint}")
        else:
            # Fallback to VPC endpoint (may fail with SNI error)
            dsql_endpoint = config.aurora_dsql_endpoint
            logger.warning(f"DSQL_HOST not set, using VPC endpoint (may fail with SNI error): {dsql_endpoint}")
        
        # Generate IAM token (uses cache, valid for 14 minutes)
        try:
            import time
            connection_start = time.time()
            
            token_start = time.time()
            iam_token = generate_iam_auth_token(
                endpoint=dsql_endpoint,
                port=config.aurora_dsql_port,
                iam_username=config.iam_username,
                region=config.aws_region
            )
            token_duration = int((time.time() - token_start) * 1000)
            
            logger.debug(
                f"IAM token generated",
                extra={
                    'token_duration_ms': token_duration,
                    'token_length': len(iam_token),
                    'endpoint': dsql_endpoint,
                }
            )
            
            # Use dsql_host for connection - ensures correct SNI and private DNS resolution
            dsql_host = config.dsql_host or config.aurora_dsql_endpoint
            if not dsql_host:
                raise ValueError("DSQL_HOST or AURORA_DSQL_ENDPOINT must be set for DSQL connections")
            
            logger.info(
                f"Creating direct DSQL connection",
                extra={
                    'host': dsql_host,
                    'user': config.iam_username,
                    'database': config.database_name,
                    'port': config.aurora_dsql_port,
                }
            )
            
            # Create direct connection (no pooling)
            print(f"[DSQL] About to call asyncpg.connect - host={dsql_host}, port={config.aurora_dsql_port}")
            connect_start = time.time()
            print(f"[DSQL] Calling asyncpg.connect now...")
            conn = await asyncpg.connect(
                host=dsql_host,  # Use direct endpoint - asyncpg will use this for SNI
                port=config.aurora_dsql_port,
                user=config.iam_username,
                password=iam_token,  # Presigned URL query string (pass directly, no encoding/decoding)
                database=config.database_name,
                ssl='require',  # DSQL requires SSL
                command_timeout=30,
                server_settings={
                    'search_path': 'car_entities_schema'
                }
            )
            print(f"[DSQL] asyncpg.connect returned successfully")
            connect_duration = int((time.time() - connect_start) * 1000)
            total_duration = int((time.time() - connection_start) * 1000)
            
            print(f"[DSQL] Connection created - duration: {connect_duration}ms")
            logger.info(
                f"Direct DSQL connection created successfully",
                extra={
                    'connection_id': id(conn),
                    'connect_duration_ms': connect_duration,
                    'total_duration_ms': total_duration,
                    'host': dsql_host,
                    'search_path': 'car_entities_schema',
                }
            )
            return conn
            
        except Exception as e:
            total_duration = int((time.time() - connection_start) * 1000) if 'connection_start' in locals() else 0
            logger.error(
                f"Failed to create DSQL connection",
                extra={
                    'error': str(e),
                    'error_type': type(e).__name__,
                    'duration_ms': total_duration,
                    'host': dsql_host if 'dsql_host' in locals() else 'unknown',
                },
                exc_info=True
            )
            raise
    else:
        # Legacy password-based authentication
        if config:
            database_url = config.database_url
            if not database_url:
                raise ValueError("Database URL is required when not using IAM authentication")
        else:
            # Legacy: database_url string passed directly
            database_url = database_url_or_config
        
        logger.info(f"Creating direct connection (legacy mode): {database_url.split('@')[-1] if '@' in database_url else 'unknown'}")
        conn = await asyncpg.connect(
            database_url,
            command_timeout=30
        )
        return conn
