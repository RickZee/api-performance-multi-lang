"""Configuration management for test suite."""

# Prefer AWSConfig over TerraformConfig - no terraform dependency
from test_suite.config.aws_config import AWSConfig

# Keep TerraformConfig for backward compatibility
try:
    from test_suite.config.terraform import TerraformConfig
except ImportError:
    TerraformConfig = None

