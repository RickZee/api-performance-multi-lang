"""Configuration management for Lambda environment."""

import os
from typing import Optional


class LambdaConfig:
    """Lambda-specific configuration."""
    
    def __init__(
        self,
        database_url: str,
        log_level: str,
        aurora_endpoint: Optional[str] = None,
        database_name: Optional[str] = None,
        database_user: Optional[str] = None,
        database_password: Optional[str] = None,
        aurora_dsql_endpoint: Optional[str] = None,
        aurora_dsql_port: int = 5432,
        iam_username: Optional[str] = None,
        aws_region: Optional[str] = None,
        use_iam_auth: bool = False,
        aurora_dsql_cluster_resource_id: Optional[str] = None,
        dsql_host: Optional[str] = None,
    ):
        self.database_url = database_url
        self.log_level = log_level
        self.aurora_endpoint = aurora_endpoint
        self.database_name = database_name
        self.database_user = database_user
        self.database_password = database_password
        self.aurora_dsql_endpoint = aurora_dsql_endpoint
        self.aurora_dsql_port = aurora_dsql_port
        self.iam_username = iam_username
        self.aws_region = aws_region
        self.use_iam_auth = use_iam_auth
        self.aurora_dsql_cluster_resource_id = aurora_dsql_cluster_resource_id
        self.dsql_host = dsql_host


def load_lambda_config() -> LambdaConfig:
    """
    Load configuration for Lambda environment.
    Supports both direct DATABASE_URL, Aurora Serverless component-based configuration,
    and Aurora DSQL with IAM authentication.
    """
    # Check for Aurora DSQL configuration (IAM auth)
    aurora_dsql_endpoint = os.getenv("AURORA_DSQL_ENDPOINT", "")
    database_name = os.getenv("DATABASE_NAME", "")
    iam_username = os.getenv("IAM_USERNAME", "")
    aws_region = os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", ""))
    aurora_dsql_port = int(os.getenv("AURORA_DSQL_PORT", "5432"))
    aurora_dsql_cluster_resource_id = os.getenv("AURORA_DSQL_CLUSTER_RESOURCE_ID", "")
    dsql_host = os.getenv("DSQL_HOST", "")
    
    # Determine if we should use IAM authentication
    use_iam_auth = bool(aurora_dsql_endpoint and database_name and iam_username and aws_region)
    
    # Try to get DATABASE_URL first (standard approach)
    database_url = os.getenv("DATABASE_URL", "")
    
    if not database_url:
        if use_iam_auth:
            # For IAM auth, we'll construct the connection string dynamically in connection_pool
            # using the IAM token. For now, set a placeholder.
            database_url = ""  # Will be constructed with IAM token
        else:
            # Fall back to Aurora Serverless component-based configuration
            aurora_endpoint = os.getenv("AURORA_ENDPOINT", "")
            database_user = os.getenv("DATABASE_USER", "")
            database_password = os.getenv("DATABASE_PASSWORD", "")
            
            if aurora_endpoint and database_name and database_user and database_password:
                # Construct connection string for Aurora Serverless
                # Format: postgresql://user:password@host:port/database
                # Aurora Serverless typically uses port 5432
                database_url = f"postgresql://{database_user}:{database_password}@{aurora_endpoint}:5432/{database_name}"
            else:
                # Default for local development/testing
                database_url = "postgresql://postgres:password@localhost:5432/car_entities"
    
    # Log level
    log_level = os.getenv("LOG_LEVEL", "info")
    
    return LambdaConfig(
        database_url=database_url,
        log_level=log_level,
        aurora_endpoint=os.getenv("AURORA_ENDPOINT"),
        database_name=database_name or os.getenv("DATABASE_NAME", ""),
        database_user=os.getenv("DATABASE_USER"),
        database_password=os.getenv("DATABASE_PASSWORD"),
        aurora_dsql_endpoint=aurora_dsql_endpoint,
        aurora_dsql_port=aurora_dsql_port,
        iam_username=iam_username,
        aws_region=aws_region,
        use_iam_auth=use_iam_auth,
        aurora_dsql_cluster_resource_id=aurora_dsql_cluster_resource_id,
        dsql_host=dsql_host,
    )
