"""
Read Terraform outputs for infrastructure configuration.
"""

import subprocess
import os
from typing import Optional, Dict
from pathlib import Path


class TerraformConfig:
    """Read Terraform outputs for test infrastructure."""
    
    def __init__(self, terraform_dir: Optional[str] = None):
        if terraform_dir:
            self.terraform_dir = Path(terraform_dir)
        else:
            # Default: go up from test_suite/config/terraform.py to project root, then to terraform
            # test_suite/config/terraform.py -> test_suite/config/ -> test_suite/ -> load-test/dsql-load-test-java/ -> load-test/ -> root
            script_dir = Path(__file__).parent.parent.parent.parent.parent
            self.terraform_dir = script_dir / 'terraform'
    
    def get_output(self, output_name: str, default: Optional[str] = None) -> Optional[str]:
        """Get a Terraform output value."""
        try:
            result = subprocess.run(
                ['terraform', 'output', '-raw', output_name],
                cwd=self.terraform_dir,
                capture_output=True,
                text=True,
                check=False
            )
            
            if result.returncode == 0 and result.stdout.strip():
                value = result.stdout.strip()
                # Remove quotes if present
                if value.startswith('"') and value.endswith('"'):
                    value = value[1:-1]
                elif value.startswith("'") and value.endswith("'"):
                    value = value[1:-1]
                return value if value else default
            
            return default
        except Exception:
            return default
    
    def get_all_config(self) -> Dict[str, Optional[str]]:
        """Get all required configuration from Terraform outputs."""
        config = {
            'test_runner_instance_id': self.get_output('dsql_test_runner_instance_id'),
            'bastion_instance_id': self.get_output('bastion_host_instance_id'),
            'aws_region': self.get_output('aws_region', 'us-east-1'),
            'dsql_host': self.get_output('aurora_dsql_host'),
            'iam_username': self.get_output('iam_database_username', 'lambda_dsql_user'),
            's3_bucket': self.get_output('s3_bucket_name'),
        }
        
        # Fallback to bastion if test runner not available
        if not config['test_runner_instance_id']:
            config['test_runner_instance_id'] = config['bastion_instance_id']
        
        return config
    
    def validate_config(self) -> tuple[bool, Optional[str]]:
        """Validate that required configuration is present."""
        config = self.get_all_config()
        
        if not config['test_runner_instance_id']:
            return False, "Test runner EC2 instance ID not found"
        
        if not config['dsql_host']:
            return False, "DSQL host not found"
        
        return True, None

