"""
Load infrastructure configuration from AWS using boto3.
Replaces terraform.py dependency with direct AWS queries.
Falls back to terraform.py if AWS lookup fails.
"""

import os
import boto3
from typing import Optional, Dict
from botocore.exceptions import ClientError, BotoCoreError


class AWSConfig:
    """Load infrastructure configuration from AWS."""
    
    def __init__(self, region: Optional[str] = None):
        self.region = region or os.getenv('AWS_REGION', 'us-east-1')
        self.ec2 = boto3.client('ec2', region_name=self.region)
        self.rds = boto3.client('rds', region_name=self.region)
        self.s3 = boto3.client('s3', region_name=self.region)
    
    def find_instance_by_tag(self, tag_key: str, tag_value: str) -> Optional[str]:
        """Find EC2 instance ID by tag."""
        try:
            response = self.ec2.describe_instances(
                Filters=[
                    {'Name': f'tag:{tag_key}', 'Values': [tag_value]},
                    {'Name': 'instance-state-name', 'Values': ['running', 'stopped', 'stopping']}
                ]
            )
            
            for reservation in response['Reservations']:
                for instance in reservation['Instances']:
                    return instance['InstanceId']
            
            return None
        except (ClientError, BotoCoreError):
            return None
    
    def find_test_runner_instance(self) -> Optional[str]:
        """Find test runner EC2 instance."""
        # Try multiple tag patterns
        patterns = [
            ('Name', '*test-runner*'),
            ('Name', '*test*runner*'),
            ('Name', '*dsql*test*runner*'),
        ]
        
        for tag_key, tag_value in patterns:
            instance_id = self.find_instance_by_tag(tag_key, tag_value)
            if instance_id:
                return instance_id
        
        return None
    
    def find_bastion_instance(self) -> Optional[str]:
        """Find bastion host EC2 instance."""
        patterns = [
            ('Name', '*bastion*'),
            ('Name', '*bastion*host*'),
        ]
        
        for tag_key, tag_value in patterns:
            instance_id = self.find_instance_by_tag(tag_key, tag_value)
            if instance_id:
                return instance_id
        
        return None
    
    def find_dsql_host(self) -> Optional[str]:
        """Find DSQL (Aurora Data API) endpoint."""
        # First try environment variable
        dsql_host = os.getenv('DSQL_HOST') or os.getenv('AURORA_DSQL_HOST')
        if dsql_host:
            return dsql_host
        
        try:
            # Try to find Aurora cluster
            response = self.rds.describe_db_clusters()
            
            for cluster in response.get('DBClusters', []):
                cluster_id = cluster.get('DBClusterIdentifier', '')
                endpoint = cluster.get('Endpoint', '')
                
                # DSQL endpoints typically have .dsql- in the hostname
                if endpoint and ('.dsql-' in endpoint or 'dsql' in cluster_id.lower()):
                    return endpoint
                
                # Also check reader endpoint
                reader_endpoint = cluster.get('ReaderEndpoint', '')
                if reader_endpoint and ('.dsql-' in reader_endpoint or 'dsql' in cluster_id.lower()):
                    return reader_endpoint
            
        except (ClientError, BotoCoreError) as e:
            # Silently fail - will use environment variable or return None
            pass
        
        return None
    
    def find_s3_bucket(self) -> Optional[str]:
        """Find S3 bucket for test artifacts."""
        # Try environment variable first
        bucket = os.getenv('S3_BUCKET') or os.getenv('S3_BUCKET_NAME')
        if bucket:
            return bucket
        
        # Try Terraform output as fallback (more reliable)
        try:
            from test_suite.config.terraform import TerraformConfig
            terraform_config = TerraformConfig()
            bucket = terraform_config.get_output('s3_bucket_name')
            if bucket:
                return bucket
        except Exception:
            pass
        
        # Try to find bucket by name pattern (last resort)
        try:
            response = self.s3.list_buckets()
            patterns = [
                '*lambda*deploy*',
                '*test*',
                '*dsql*',
            ]
            
            for bucket_info in response.get('Buckets', []):
                bucket_name = bucket_info['Name']
                for pattern in patterns:
                    if self._match_pattern(bucket_name, pattern):
                        return bucket_name
        except (ClientError, BotoCoreError):
            pass
        
        return None
    
    def _match_pattern(self, text: str, pattern: str) -> bool:
        """Simple wildcard pattern matching."""
        import fnmatch
        return fnmatch.fnmatch(text.lower(), pattern.lower())
    
    def get_all_config(self, fallback_to_terraform: bool = True) -> Dict[str, Optional[str]]:
        """Get all required configuration from AWS.
        
        Args:
            fallback_to_terraform: If True, fall back to terraform.py for missing values
        """
        test_runner_id = self.find_test_runner_instance()
        bastion_id = self.find_bastion_instance()
        dsql_host = self.find_dsql_host()
        s3_bucket = self.find_s3_bucket()
        
        config = {
            'test_runner_instance_id': test_runner_id or bastion_id,
            'bastion_instance_id': bastion_id,
            'aws_region': self.region,
            'dsql_host': dsql_host,
            'iam_username': os.getenv('IAM_DATABASE_USERNAME', 'lambda_dsql_user'),
            's3_bucket': s3_bucket,
        }
        
        # Fallback to terraform if needed
        if fallback_to_terraform:
            try:
                from test_suite.config.terraform import TerraformConfig
                terraform_config = TerraformConfig()
                
                # Only use terraform for missing values
                if not config['test_runner_instance_id']:
                    config['test_runner_instance_id'] = terraform_config.get_output('dsql_test_runner_instance_id') or terraform_config.get_output('bastion_host_instance_id')
                
                if not config['dsql_host']:
                    config['dsql_host'] = terraform_config.get_output('aurora_dsql_host')
                
                if not config['s3_bucket']:
                    config['s3_bucket'] = terraform_config.get_output('s3_bucket_name')
                
                # Use terraform region if available
                terraform_region = terraform_config.get_output('aws_region')
                if terraform_region:
                    config['aws_region'] = terraform_region
                    
            except Exception:
                # Terraform not available, continue with AWS config
                pass
        
        return config
    
    def validate_config(self) -> tuple[bool, Optional[str]]:
        """Validate that required configuration is present."""
        config = self.get_all_config()
        
        if not config['test_runner_instance_id']:
            return False, "Test runner EC2 instance ID not found. Try setting AWS_REGION or check instance tags."
        
        if not config['dsql_host']:
            return False, "DSQL host not found. Try setting DSQL_HOST environment variable."
        
        return True, None

