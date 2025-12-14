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
    ):
        self.database_url = database_url
        self.log_level = log_level
        self.aurora_endpoint = aurora_endpoint
        self.database_name = database_name
        self.database_user = database_user
        self.database_password = database_password


def load_lambda_config() -> LambdaConfig:
    """
    Load configuration for Lambda environment.
    Supports both direct DATABASE_URL and Aurora Serverless component-based configuration.
    """
    # Try to get DATABASE_URL first (standard approach)
    database_url = os.getenv("DATABASE_URL", "").strip()
    
    if not database_url:
        # Fall back to Aurora Serverless component-based configuration
        aurora_endpoint = os.getenv("AURORA_ENDPOINT", "")
        database_name = os.getenv("DATABASE_NAME", "")
        database_user = os.getenv("DATABASE_USER", "")
        database_password = os.getenv("DATABASE_PASSWORD", "")
        
        if aurora_endpoint and database_name and database_user and database_password:
            # Construct connection string for Aurora Serverless
            # Format: postgresql://user:password@host:port/database
            # Aurora Serverless typically uses port 5432
            # Strip any newlines from password to prevent connection string issues
            database_password_clean = database_password.strip()
            database_url = f"postgresql://{database_user}:{database_password_clean}@{aurora_endpoint}:5432/{database_name}"
        else:
            # Default for local development/testing
            database_url = "postgresql://postgres:password@localhost:5432/car_entities"
    
    # Log level
    log_level = os.getenv("LOG_LEVEL", "info")
    
    return LambdaConfig(
        database_url=database_url,
        log_level=log_level,
        aurora_endpoint=os.getenv("AURORA_ENDPOINT"),
        database_name=os.getenv("DATABASE_NAME"),
        database_user=os.getenv("DATABASE_USER"),
        database_password=os.getenv("DATABASE_PASSWORD"),
    )
