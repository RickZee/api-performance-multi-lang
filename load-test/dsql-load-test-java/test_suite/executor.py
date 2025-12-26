"""
Remote executor for AWS operations (SSM, S3, EC2).
"""

import time
import boto3
import json
from pathlib import Path
from typing import Optional, Tuple
from botocore.config import Config as BotoConfig
from botocore.exceptions import ClientError, BotoCoreError

from test_suite.config import Config


class RemoteExecutor:
    """Execute commands and manage files on remote EC2 instance."""
    
    def __init__(self, config: Config):
        self.config = config
        
        # Configure boto3 with reasonable timeouts
        boto_config = BotoConfig(
            read_timeout=60,
            connect_timeout=10,
            retries={'max_attempts': 3, 'mode': 'adaptive'}
        )
        
        self.ssm = boto3.client('ssm', region_name=config.region, config=boto_config)
        self.s3 = boto3.client('s3', region_name=config.region, config=boto_config)
        self.ec2 = boto3.client('ec2', region_name=config.region, config=boto_config)
    
    def ensure_instance_ready(self) -> bool:
        """Start instance if needed, wait for SSM agent to be ready."""
        status = self._get_instance_status()
        state = status.get('state')
        
        if state == 'running':
            print("Instance is running")
        elif state in ['stopped', 'stopping']:
            print(f"Starting instance {self.config.instance_id}...")
            try:
                self.ec2.start_instances(InstanceIds=[self.config.instance_id])
                
                # Wait for running state
                waiter = self.ec2.get_waiter('instance_running')
                waiter.wait(
                    InstanceIds=[self.config.instance_id],
                    WaiterConfig={'Delay': 5, 'MaxAttempts': 60}
                )
                print("Instance is running")
            except (ClientError, BotoCoreError) as e:
                print(f"Error starting instance: {e}")
                return False
        else:
            print(f"Instance state is {state}, cannot proceed")
            return False
        
        # Wait for SSM agent
        return self._wait_for_ssm_agent()
    
    def _get_instance_status(self) -> dict:
        """Get instance status."""
        try:
            response = self.ec2.describe_instances(InstanceIds=[self.config.instance_id])
            if not response['Reservations']:
                return {'state': 'not-found'}
            
            instance = response['Reservations'][0]['Instances'][0]
            return {'state': instance['State']['Name']}
        except (ClientError, BotoCoreError) as e:
            return {'state': 'error', 'error': str(e)}
    
    def _wait_for_ssm_agent(self, timeout: int = 120) -> bool:
        """Wait for SSM agent to be online."""
        print("Waiting for SSM agent...")
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                response = self.ssm.describe_instance_information(
                    Filters=[
                        {'Key': 'InstanceIds', 'Values': [self.config.instance_id]}
                    ]
                )
                
                if response['InstanceInformationList']:
                    status = response['InstanceInformationList'][0].get('PingStatus', 'Offline')
                    if status == 'Online':
                        print("SSM agent is online")
                        return True
                
                time.sleep(2)
            except (ClientError, BotoCoreError):
                time.sleep(2)
        
        print(f"Warning: SSM agent not online after {timeout} seconds")
        return False
    
    def stop_instance(self) -> bool:
        """Stop EC2 instance if it's running."""
        status = self._get_instance_status()
        state = status.get('state')
        
        if state == 'running':
            print(f"Stopping instance {self.config.instance_id}...")
            try:
                self.ec2.stop_instances(InstanceIds=[self.config.instance_id])
                
                # Wait for stopped state
                waiter = self.ec2.get_waiter('instance_stopped')
                waiter.wait(
                    InstanceIds=[self.config.instance_id],
                    WaiterConfig={'Delay': 5, 'MaxAttempts': 60}
                )
                print("Instance stopped")
                return True
            except (ClientError, BotoCoreError) as e:
                print(f"Error stopping instance: {e}")
                return False
        elif state in ['stopped', 'stopping']:
            print(f"Instance is already stopped or stopping (state: {state})")
            return True
        else:
            print(f"Instance state is {state}, cannot stop")
            return False
    
    def run_command(self, commands: list[str], timeout: int = 120) -> Tuple[bool, str, str]:
        """
        Run command via SSM, return (success, stdout, stderr).
        
        Args:
            commands: List of shell commands to execute
            timeout: Maximum time to wait for command completion (seconds)
        
        Returns:
            Tuple of (success: bool, stdout: str, stderr: str)
        """
        try:
            response = self.ssm.send_command(
                InstanceIds=[self.config.instance_id],
                DocumentName="AWS-RunShellScript",
                Parameters={'commands': commands},
                TimeoutSeconds=timeout
            )
            
            command_id = response['Command']['CommandId']
            
            # Wait for completion
            start_time = time.time()
            while time.time() - start_time < timeout:
                try:
                    invocation = self.ssm.get_command_invocation(
                        CommandId=command_id,
                        InstanceId=self.config.instance_id
                    )
                    
                    status = invocation['Status']
                    
                    if status in ['Success', 'Failed', 'Cancelled', 'TimedOut']:
                        stdout = invocation.get('StandardOutputContent', '')
                        stderr = invocation.get('StandardErrorContent', '')
                        success = status == 'Success'
                        return (success, stdout, stderr)
                    
                    time.sleep(2)
                except self.ssm.exceptions.InvocationDoesNotExist:
                    time.sleep(1)
                except (ClientError, BotoCoreError) as e:
                    return (False, '', str(e))
            
            # Timeout
            return (False, '', f"Command timed out after {timeout} seconds")
            
        except (ClientError, BotoCoreError) as e:
            return (False, '', str(e))
    
    def upload_file(self, local_path: str, s3_key: str) -> bool:
        """Upload a file to S3."""
        try:
            self.s3.upload_file(local_path, self.config.s3_bucket, s3_key)
            return True
        except (ClientError, BotoCoreError) as e:
            print(f"Error uploading to S3: {e}")
            return False
    
    def download_file(self, s3_key: str, local_path: str) -> bool:
        """Download a file from S3."""
        try:
            Path(local_path).parent.mkdir(parents=True, exist_ok=True)
            self.s3.download_file(self.config.s3_bucket, s3_key, local_path)
            return True
        except (ClientError, BotoCoreError) as e:
            print(f"Error downloading from S3: {e}")
            return False
    
    def file_exists(self, s3_key: str) -> bool:
        """Check if a file exists in S3."""
        try:
            self.s3.head_object(Bucket=self.config.s3_bucket, Key=s3_key)
            return True
        except ClientError:
            return False
    
    def download_result(self, test_id: str, dest_path: Path) -> bool:
        """
        Download test result JSON from S3.
        
        Always uses S3 (no SSM fallback) for reliability.
        """
        s3_key = f"test-results/{test_id}.json"
        
        # Try to download from S3
        if self.download_file(s3_key, str(dest_path)):
            # Validate JSON
            try:
                with open(dest_path, 'r') as f:
                    data = json.load(f)
                    if data and 'test_id' in data:
                        return True
            except (json.JSONDecodeError, Exception):
                pass
        
        # If download failed or invalid, create empty result
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        with open(dest_path, 'w') as f:
            json.dump({}, f)
        return False
    
    def list_test_results(self, prefix: str = "test-results/") -> list[str]:
        """
        List all test result files in S3.
        
        Args:
            prefix: S3 prefix for test results (default: "test-results/")
        
        Returns:
            List of test IDs (e.g., ["test-001-...", "test-002-..."])
        """
        test_ids = []
        
        try:
            # Use paginator to handle large result sets
            paginator = self.s3.get_paginator('list_objects_v2')
            pages = paginator.paginate(Bucket=self.config.s3_bucket, Prefix=prefix)
            
            for page in pages:
                if 'Contents' not in page:
                    continue
                
                for obj in page['Contents']:
                    key = obj['Key']
                    # Extract test ID from key: test-results/test-001-... -> test-001-...
                    if key.endswith('.json'):
                        # Remove prefix and .json extension
                        test_id = key[len(prefix):].replace('.json', '')
                        if test_id.startswith('test-'):
                            test_ids.append(test_id)
        
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', '')
            if error_code == 'NoSuchBucket':
                print(f"Error: S3 bucket not found: {self.config.s3_bucket}")
            elif error_code == 'AccessDenied':
                print(f"Error: Access denied to S3 bucket: {self.config.s3_bucket}")
            else:
                print(f"Error listing S3 objects: {e}")
        except BotoCoreError as e:
            print(f"Error connecting to S3: {e}")
        except Exception as e:
            print(f"Unexpected error listing test results: {e}")
        
        return test_ids

