"""
Execute commands on EC2 via SSM.
"""

import time
import boto3
from botocore.config import Config
from typing import List, Optional, Callable, Dict, Any
from dataclasses import dataclass
from botocore.exceptions import ClientError, BotoCoreError, ReadTimeoutError, ConnectTimeoutError


@dataclass
class CommandResult:
    """Result of SSM command execution."""
    command_id: str
    status: str  # InProgress, Success, Failed, Cancelled, TimedOut
    exit_code: Optional[int] = None
    output: str = ""
    error: Optional[str] = None
    duration_seconds: float = 0.0


class SSMExecutionError(Exception):
    """SSM command execution errors."""
    pass


class SSMExecutor:
    """Execute commands on EC2 via SSM."""
    
    def __init__(self, instance_id: str, region: str):
        self.instance_id = instance_id
        self.region = region
        # Configure boto3 with timeouts to prevent indefinite blocking
        # read_timeout: max time to wait for response data
        # connect_timeout: max time to establish connection
        config = Config(
            read_timeout=30,  # 30 seconds max per API call
            connect_timeout=10,  # 10 seconds to connect
            retries={'max_attempts': 3, 'mode': 'adaptive'}
        )
        self.ssm = boto3.client('ssm', region_name=region, config=config)
    
    def execute_command(
        self,
        commands: List[str],
        timeout: int = 1800,
        working_directory: str = "/tmp"
    ) -> CommandResult:
        """Execute SSM command with proper error handling."""
        start_time = time.time()
        
        try:
            # Send command
            response = self.ssm.send_command(
                InstanceIds=[self.instance_id],
                DocumentName="AWS-RunShellScript",
                Parameters={
                    'commands': commands,
                    'workingDirectory': [working_directory]
                },
                TimeoutSeconds=timeout
            )
            
            command_id = response['Command']['CommandId']
            
            # Wait for completion
            result = self._wait_for_command(command_id, timeout)
            result.duration_seconds = time.time() - start_time
            
            return result
            
        except (ClientError, BotoCoreError) as e:
            raise SSMExecutionError(f"Failed to execute SSM command: {e}") from e
    
    def _wait_for_command(self, command_id: str, timeout: int) -> CommandResult:
        """Wait for command to complete and get result."""
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                response = self.ssm.get_command_invocation(
                    CommandId=command_id,
                    InstanceId=self.instance_id
                )
                
                status = response['Status']
                
                if status in ['Success', 'Failed', 'Cancelled', 'TimedOut']:
                    # Get output
                    output = response.get('StandardOutputContent', '')
                    error = response.get('StandardErrorContent', '')
                    exit_code = response.get('ResponseCode', -1)
                    
                    return CommandResult(
                        command_id=command_id,
                        status=status,
                        exit_code=exit_code,
                        output=output,
                        error=error
                    )
                
                time.sleep(2)
                
            except self.ssm.exceptions.InvocationDoesNotExist:
                # Command not found yet, wait a bit
                time.sleep(1)
            except (ReadTimeoutError, ConnectTimeoutError) as e:
                # Network timeout - retry after a short delay
                # Don't exit the loop, just retry
                time.sleep(2)
            except (ClientError, BotoCoreError) as e:
                return CommandResult(
                    command_id=command_id,
                    status='Error',
                    error=str(e)
                )
        
        # Timeout
        return CommandResult(
            command_id=command_id,
            status='TimedOut',
            error=f"Command timed out after {timeout} seconds"
        )
    
    def get_command_output(self, command_id: str, max_output_size: int = 24000) -> str:
        """Get command output, handles large outputs via S3."""
        try:
            response = self.ssm.get_command_invocation(
                CommandId=command_id,
                InstanceId=self.instance_id
            )
            
            output = response.get('StandardOutputContent', '')
            
            # If output is truncated or too large, might need S3 fallback
            if len(output) >= max_output_size:
                # Note: For very large outputs, we should use S3
                # This is handled in the result collector
                pass
            
            return output
            
        except (ClientError, BotoCoreError) as e:
            raise SSMExecutionError(f"Failed to get command output: {e}") from e
    
    def stream_output(self, command_id: str, callback: Optional[Callable[[str], None]] = None) -> None:
        """Stream command output in real-time."""
        # For now, just poll and call callback
        # Could be enhanced with CloudWatch Logs streaming
        last_output = ""
        
        while True:
            try:
                response = self.ssm.get_command_invocation(
                    CommandId=command_id,
                    InstanceId=self.instance_id
                )
                
                status = response['Status']
                output = response.get('StandardOutputContent', '')
                
                if output != last_output and callback:
                    new_output = output[len(last_output):]
                    callback(new_output)
                    last_output = output
                
                if status in ['Success', 'Failed', 'Cancelled', 'TimedOut']:
                    break
                
                time.sleep(1)
                
            except (ClientError, BotoCoreError):
                break

