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
        # For DSQL, we need to manually construct the presigned URL
        # DSQL uses a presigned URL format: endpoint/?Action=DbConnect&...signature...
        # We'll use botocore's signing capabilities to create this
        from botocore.auth import SigV4QueryAuth
        from botocore.awsrequest import AWSRequest
        from urllib.parse import urlencode, urlparse
        
        # Get AWS credentials from environment (Lambda provides these automatically)
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
        token = parsed.query
        
        if not token:
            raise Exception(f"Failed to generate DSQL token from URL: {request.url}")
        
        # DSQL expects the full presigned URL query string as the password
        # Format: Action=DbConnect&X-Amz-Algorithm=...&X-Amz-Signature=...
        logger.info(f"Generated DSQL token (length: {len(token)})")
        
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

