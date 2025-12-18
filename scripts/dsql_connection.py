"""Direct DSQL connection helper for validation scripts."""

import asyncpg
import asyncio
import boto3
import logging
from datetime import datetime, timedelta
from typing import Optional

logger = logging.getLogger(__name__)

# Token cache with expiration
_token_cache: Optional[dict] = None

# Connection timeout for DSQL connections
CONNECTION_TIMEOUT = 15  # seconds
COMMAND_TIMEOUT = 30  # seconds


def generate_iam_auth_token(
    endpoint: str, port: int, iam_username: str, region: str
) -> str:
    """
    Generate IAM authentication token for Aurora DSQL.
    
    Tokens are valid for 15 minutes. This function implements caching
    to avoid regenerating tokens on every call.
    
    Args:
        endpoint: Aurora DSQL cluster endpoint
        port: Database port (typically 5432 for PostgreSQL)
        iam_username: IAM database username
        region: AWS region for token generation
        
    Returns:
        IAM authentication token (valid for 15 minutes)
    """
    global _token_cache
    
    # Check if we have a valid cached token
    if _token_cache is not None:
        cached_token = _token_cache.get('token')
        expires_at = _token_cache.get('expires_at')
        cache_key = _token_cache.get('key')
        
        # Check if cached token is for the same endpoint/user and still valid
        expected_key = f"{endpoint}:{port}:{iam_username}"
        if cache_key == expected_key and expires_at:
            # Regenerate if expired or within 1 minute of expiration
            time_until_expiry = expires_at - datetime.utcnow()
            if time_until_expiry > timedelta(minutes=1):
                return cached_token
            else:
                logger.info("IAM auth token expired or expiring soon, regenerating")
    
    # Generate new token
    try:
        # For DSQL, we need to manually construct the presigned URL
        # DSQL uses a presigned URL format: endpoint/?Action=DbConnect&...signature...
        # We'll use botocore's signing capabilities to create this
        from botocore.auth import SigV4QueryAuth
        from botocore.awsrequest import AWSRequest
        from urllib.parse import urlencode, urlparse
        
        # Get AWS credentials from environment
        session = boto3.Session(region_name=region)
        credentials = session.get_credentials()
        
        if not credentials:
            raise Exception("No AWS credentials available")
        
        # Construct the DSQL endpoint URL
        # Format: https://<hostname>/?Action=DbConnect
        # Note: Username is NOT included in the presigned URL - it's specified in the connection string
        # The IAM policy condition (dsql:DbUser) determines which user the token allows
        query_params = {
            'Action': 'DbConnect'
        }
        dsql_url = f"https://{endpoint}/?{urlencode(query_params)}"
        
        # Create AWS request
        request = AWSRequest(method='GET', url=dsql_url)
        
        # Use SigV4QueryAuth for presigned URLs (adds signature to query string)
        # This is different from SigV4Auth which adds signature to headers
        expires_in = 900  # 15 minutes
        signer = SigV4QueryAuth(credentials, 'dsql', region, expires=expires_in)
        signer.add_auth(request)
        
        # After signing with SigV4QueryAuth, the URL should have signature in query string
        signed_url = request.url
        
        # Extract the presigned URL query string (includes all query parameters with signature)
        # The token is the query string part after the '?'
        parsed = urlparse(signed_url)
        signed_query = parsed.query
        
        if not signed_query:
            raise Exception(f"Failed to generate DSQL token from URL: {request.url}")
        
        # Token format to include host/port prefix
        # Format: {endpoint}:{port}/?{signed_query}
        token = f"{endpoint}:{port}/?{signed_query}"
        
        logger.info(f"Generated DSQL token with host/port prefix (length: {len(token)})")
        
        # Cache the token (valid for 15 minutes, but we'll expire it at 14 minutes)
        expires_at = datetime.utcnow() + timedelta(minutes=14)
        _token_cache = {
            'token': token,
            'expires_at': expires_at,
            'key': f"{endpoint}:{port}:{iam_username}"
        }
        
        logger.info("Generated new IAM auth token for Aurora DSQL")
        return token
    except Exception as e:
        logger.error(f"Failed to generate IAM auth token: {e}", exc_info=True)
        raise


async def get_dsql_connection(
    dsql_host: str,
    port: int,
    iam_username: str,
    region: str,
    database_name: str = "postgres"
) -> asyncpg.Connection:
    """
    Get a direct DSQL database connection with IAM authentication.
    
    Args:
        dsql_host: DSQL cluster hostname
        port: Database port (typically 5432)
        iam_username: IAM database username
        region: AWS region
        database_name: Database name (default: postgres)
        
    Returns:
        asyncpg.Connection: Direct database connection
        
    Raises:
        asyncio.TimeoutError: If connection establishment exceeds CONNECTION_TIMEOUT
        Exception: Other connection errors
    """
    try:
        # Generate IAM token (uses cache, valid for 14 minutes)
        iam_token = generate_iam_auth_token(
            endpoint=dsql_host,
            port=port,
            iam_username=iam_username,
            region=region
        )
        
        logger.info(
            f"Creating direct DSQL connection",
            extra={
                'host': dsql_host,
                'user': iam_username,
                'database': database_name,
                'port': port,
            }
        )
        
        # Create direct connection with timeout
        try:
            # Use asyncio.wait_for to enforce connection establishment timeout
            conn = await asyncio.wait_for(
                asyncpg.connect(
                    host=dsql_host,
                    port=port,
                    user=iam_username,
                    password=iam_token,
                    database=database_name,
                    ssl='require',  # DSQL requires SSL
                    command_timeout=COMMAND_TIMEOUT,
                    server_settings={
                        'search_path': 'car_entities_schema'
                    }
                ),
                timeout=CONNECTION_TIMEOUT
            )
            logger.info(f"Direct DSQL connection created successfully to {dsql_host}")
            return conn
        except asyncio.TimeoutError:
            logger.error(f"Connection timeout after {CONNECTION_TIMEOUT}s to {dsql_host}")
            raise ConnectionError(
                f"Connection timeout: Unable to connect to database within {CONNECTION_TIMEOUT} seconds"
            )
        
    except Exception as e:
        logger.error(
            f"Failed to create DSQL connection",
            extra={
                'error': str(e),
                'error_type': type(e).__name__,
                'host': dsql_host,
            },
            exc_info=True
        )
        raise


def clear_token_cache():
    """Clear the token cache (useful for testing or forced refresh)."""
    global _token_cache
    _token_cache = None
