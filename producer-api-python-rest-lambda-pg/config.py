"""Configuration management for Lambda environment."""

import os
import logging
from typing import Optional

logger = logging.getLogger(__name__)


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
    
    # Check if DATABASE_URL has newlines (indicates malformed password)
    # If so, fall back to component-based configuration
    if database_url and ('\n' in database_url or '\r' in database_url):
        # DATABASE_URL is malformed (has newlines), use component-based approach
        logger.warning("DATABASE_URL contains newlines, falling back to component-based configuration")
        database_url = None
    
    if not database_url:
        # Fall back to Aurora Serverless component-based configuration
        aurora_endpoint = os.getenv("AURORA_ENDPOINT", "").strip()
        database_name = os.getenv("DATABASE_NAME", "").strip()
        database_user = os.getenv("DATABASE_USER", "").strip()
        database_password = os.getenv("DATABASE_PASSWORD", "").strip()
        
        # Remove any newlines from password (password may be duplicated with newline)
        database_password_clean = database_password.replace('\n', '').replace('\r', '')
        
        # If password was duplicated, take only the first 32 characters (expected password length)
        # This handles the case where password is duplicated: "PASSWORD\nPASSWORD" -> "PASSWORD"
        if len(database_password_clean) > 32:
            # Password appears duplicated, take first occurrence
            database_password_clean = database_password_clean[:32]
            logger.warning(f"Password was longer than expected ({len(database_password_clean)} chars), using first 32 characters")
        
        if aurora_endpoint and database_name and database_user and database_password_clean:
            # Construct connection string for Aurora Serverless
            # Format: postgresql://user:password@host:port/database
            # Aurora Serverless typically uses port 5432
            # Don't URL-encode password - asyncpg handles it, and encoding can cause issues
            database_url = f"postgresql://{database_user}:{database_password_clean}@{aurora_endpoint}:5432/{database_name}"
            logger.info(f"Using component-based configuration: {database_user}@{aurora_endpoint}/{database_name} (password length: {len(database_password_clean)})")
        else:
            # Default for local development/testing
            database_url = "postgresql://postgres:password@localhost:5432/car_entities"
            logger.warning("Missing component-based config, using default local database URL")
    
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
