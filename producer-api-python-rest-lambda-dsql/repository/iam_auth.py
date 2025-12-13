"""IAM authentication helper for Aurora DSQL."""

import boto3
import logging
from datetime import datetime, timedelta
from typing import Optional

logger = logging.getLogger(__name__)

# Token cache with expiration
_token_cache: Optional[dict] = None


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
                logger.debug("Using cached IAM auth token")
                return cached_token
            else:
                logger.info("IAM auth token expired or expiring soon, regenerating")
    
    # Generate new token
    try:
        rds_client = boto3.client('rds', region_name=region)
        token = rds_client.generate_db_auth_token(
            DBHostname=endpoint,
            Port=port,
            DBUsername=iam_username,
            Region=region
        )
        
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


def clear_token_cache():
    """Clear the token cache (useful for testing or forced refresh)."""
    global _token_cache
    _token_cache = None
    logger.debug("IAM auth token cache cleared")

