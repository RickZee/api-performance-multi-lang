"""
Manage EC2 instance lifecycle.
"""

import time
import boto3
from typing import Dict, Optional
from botocore.exceptions import ClientError, BotoCoreError


class EC2Manager:
    """Manage EC2 instance lifecycle."""
    
    def __init__(self, instance_id: str, region: str):
        self.instance_id = instance_id
        self.region = region
        self.ec2 = boto3.client('ec2', region_name=region)
        self.ssm = boto3.client('ssm', region_name=region)
    
    def get_status(self) -> Dict[str, str]:
        """Get instance status and metadata."""
        try:
            response = self.ec2.describe_instances(
                InstanceIds=[self.instance_id]
            )
            
            if not response['Reservations']:
                return {'state': 'not-found', 'type': 'unknown'}
            
            instance = response['Reservations'][0]['Instances'][0]
            return {
                'state': instance['State']['Name'],
                'type': instance.get('InstanceType', 'unknown'),
                'instance_id': self.instance_id
            }
        except (ClientError, BotoCoreError) as e:
            return {'state': 'error', 'error': str(e)}
    
    def ensure_running(self, timeout: int = 300) -> bool:
        """Start instance if stopped, wait for ready."""
        status = self.get_status()
        state = status.get('state')
        
        if state == 'running':
            return True
        
        if state in ['stopped', 'stopping']:
            print(f"Starting instance {self.instance_id}...")
            try:
                self.ec2.start_instances(InstanceIds=[self.instance_id])
                
                # Wait for running state
                waiter = self.ec2.get_waiter('instance_running')
                waiter.wait(
                    InstanceIds=[self.instance_id],
                    WaiterConfig={'Delay': 5, 'MaxAttempts': 60}
                )
                print("Instance is running")
            except (ClientError, BotoCoreError) as e:
                print(f"Error starting instance: {e}")
                return False
        
        # Wait for SSM agent
        return self.wait_for_ssm_agent(timeout=120)
    
    def wait_for_ssm_agent(self, timeout: int = 120) -> bool:
        """Wait for SSM agent to be online."""
        print("Waiting for SSM agent...")
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                response = self.ssm.describe_instance_information(
                    Filters=[
                        {'Key': 'InstanceIds', 'Values': [self.instance_id]}
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

