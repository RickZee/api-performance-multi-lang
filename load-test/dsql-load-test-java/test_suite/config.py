"""
Simple configuration from environment variables.
"""

import os
from dataclasses import dataclass
from typing import Optional


@dataclass
class Config:
    """Test suite configuration from environment variables."""
    database_type: str  # "dsql", "aurora", or "local"
    instance_id: Optional[str] = None  # Optional for local execution
    s3_bucket: Optional[str] = None  # Optional for local execution
    region: str = "us-east-1"
    max_pool_size: int = 2000
    connection_rate_limit: int = 100
    
    # DSQL-specific fields
    dsql_host: Optional[str] = None
    iam_username: Optional[str] = None
    
    # Aurora-specific fields
    aurora_host: Optional[str] = None
    aurora_port: Optional[int] = None
    aurora_username: Optional[str] = None
    aurora_password: Optional[str] = None
    database_name: Optional[str] = None
    
    # Local Docker-specific fields
    local_host: Optional[str] = None
    local_port: Optional[int] = None
    local_username: Optional[str] = None
    local_password: Optional[str] = None
    
    @classmethod
    def from_env(cls) -> "Config":
        """Load config from environment - fail fast if missing."""
        missing = []
        
        # Determine database type (default: dsql for backward compatibility)
        database_type = os.getenv("DATABASE_TYPE", "dsql").lower()
        if database_type not in ["dsql", "aurora", "local"]:
            raise ValueError(f"Invalid DATABASE_TYPE: {database_type}. Must be 'dsql', 'aurora', or 'local'")
        
        instance_id = os.getenv("TEST_RUNNER_INSTANCE_ID")
        s3_bucket = os.getenv("S3_BUCKET")
        region = os.getenv("AWS_REGION", "us-east-1")
        
        # Parse optional integers
        max_pool_size = 2000
        if os.getenv("MAX_POOL_SIZE"):
            try:
                max_pool_size = int(os.getenv("MAX_POOL_SIZE"))
            except ValueError:
                pass
        
        # Connection rate limit (more conservative for Aurora and local)
        default_rate_limit = 50 if database_type in ["aurora", "local"] else 100
        connection_rate_limit = default_rate_limit
        if os.getenv("DSQL_CONNECTION_RATE_LIMIT"):
            try:
                connection_rate_limit = int(os.getenv("DSQL_CONNECTION_RATE_LIMIT"))
            except ValueError:
                pass
        
        # Load database-specific configuration
        dsql_host = None
        iam_username = None
        aurora_host = None
        aurora_port = None
        aurora_username = None
        aurora_password = None
        database_name = None
        local_host = None
        local_port = None
        local_username = None
        local_password = None
        
        if database_type == "dsql":
            dsql_host = os.getenv("DSQL_HOST")
            iam_username = os.getenv("IAM_DATABASE_USERNAME", "lambda_dsql_user")
            if not dsql_host:
                missing.append("DSQL_HOST")
        elif database_type == "aurora":
            aurora_host = os.getenv("AURORA_HOST") or os.getenv("AURORA_ENDPOINT")
            aurora_port_str = os.getenv("AURORA_PORT", "5432")
            aurora_username = os.getenv("AURORA_USERNAME")
            aurora_password = os.getenv("AURORA_PASSWORD")
            database_name = os.getenv("DATABASE_NAME", "car_entities")
            
            if not aurora_host:
                missing.append("AURORA_HOST or AURORA_ENDPOINT")
            if not aurora_username:
                missing.append("AURORA_USERNAME")
            if not aurora_password:
                missing.append("AURORA_PASSWORD")
            
            try:
                aurora_port = int(aurora_port_str)
            except ValueError:
                raise ValueError(f"Invalid AURORA_PORT: {aurora_port_str}")
        else:  # local
            local_host = os.getenv("LOCAL_HOST", "localhost")
            local_port_str = os.getenv("LOCAL_PORT", "5433")
            local_username = os.getenv("LOCAL_USERNAME", "postgres")
            local_password = os.getenv("LOCAL_PASSWORD", "password")
            database_name = os.getenv("DATABASE_NAME", "car_entities")
            
            try:
                local_port = int(local_port_str)
            except ValueError:
                raise ValueError(f"Invalid LOCAL_PORT: {local_port_str}")
        
        # Common required fields (only for remote execution)
        if database_type != "local":
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
            database_type=database_type,
            instance_id=instance_id,
            s3_bucket=s3_bucket,
            region=region,
            max_pool_size=max_pool_size,
            connection_rate_limit=connection_rate_limit,
            dsql_host=dsql_host,
            iam_username=iam_username,
            aurora_host=aurora_host,
            aurora_port=aurora_port,
            aurora_username=aurora_username,
            aurora_password=aurora_password,
            database_name=database_name,
            local_host=local_host,
            local_port=local_port,
            local_username=local_username,
            local_password=local_password
        )

