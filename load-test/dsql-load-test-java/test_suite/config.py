"""
Simple configuration from environment variables.
"""

import os
from dataclasses import dataclass


@dataclass
class Config:
    """Test suite configuration from environment variables."""
    dsql_host: str
    instance_id: str
    s3_bucket: str
    region: str = "us-east-1"
    iam_username: str = "lambda_dsql_user"
    max_pool_size: int = 2000
    connection_rate_limit: int = 100
    
    @classmethod
    def from_env(cls) -> "Config":
        """Load config from environment - fail fast if missing."""
        missing = []
        
        dsql_host = os.getenv("DSQL_HOST")
        instance_id = os.getenv("TEST_RUNNER_INSTANCE_ID")
        s3_bucket = os.getenv("S3_BUCKET")
        region = os.getenv("AWS_REGION", "us-east-1")
        iam_username = os.getenv("IAM_DATABASE_USERNAME", "lambda_dsql_user")
        
        # Parse optional integers
        max_pool_size = 2000
        if os.getenv("MAX_POOL_SIZE"):
            try:
                max_pool_size = int(os.getenv("MAX_POOL_SIZE"))
            except ValueError:
                pass
        
        connection_rate_limit = 100
        if os.getenv("DSQL_CONNECTION_RATE_LIMIT"):
            try:
                connection_rate_limit = int(os.getenv("DSQL_CONNECTION_RATE_LIMIT"))
            except ValueError:
                pass
        
        if not dsql_host:
            missing.append("DSQL_HOST")
        if not instance_id:
            missing.append("TEST_RUNNER_INSTANCE_ID")
        if not s3_bucket:
            missing.append("S3_BUCKET")
        
        if missing:
            raise ValueError(
                f"Missing required environment variables: {', '.join(missing)}\n"
                f"Please set: export {' '.join(missing)}"
            )
        
        return cls(
            dsql_host=dsql_host,
            instance_id=instance_id,
            s3_bucket=s3_bucket,
            region=region,
            iam_username=iam_username,
            max_pool_size=max_pool_size,
            connection_rate_limit=connection_rate_limit
        )

