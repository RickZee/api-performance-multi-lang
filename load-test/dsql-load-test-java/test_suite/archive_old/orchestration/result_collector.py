"""
Collect and validate test results.
"""

import json
import os
from pathlib import Path
from typing import Optional, Dict, Any
from test_suite.infrastructure.ssm_executor import SSMExecutor, SSMExecutionError
from test_suite.infrastructure.s3_manager import S3Manager


class ResultCollector:
    """Collect and validate test results from EC2."""
    
    def __init__(self, ssm_executor: SSMExecutor, s3_manager: Optional[S3Manager] = None):
        self.ssm_executor = ssm_executor
        self.s3_manager = s3_manager
    
    def collect_result(self, test_id: str, results_dir: Path) -> bool:
        """Collect result JSON from EC2 instance."""
        result_path = results_dir / f"{test_id}.json"
        
        # First try to get from S3 if available
        if self.s3_manager and self.s3_manager.bucket_name:
            s3_key = f"test-results/{test_id}.json"
            if self.s3_manager.file_exists(s3_key):
                if self.s3_manager.download_file(s3_key, str(result_path)):
                    if self._validate_result(result_path):
                        return True
        
        # Fallback: get via SSM
        # For large files (>24KB), SSM output is truncated, so we need to use S3 or split
        # Try to download from S3 first (even if not checked earlier, it might have been uploaded)
        if self.s3_manager and self.s3_manager.bucket_name:
            s3_key = f"test-results/{test_id}.json"
            # Try downloading even if file_exists check failed
            try:
                if self.s3_manager.download_file(s3_key, str(result_path)):
                    if self._validate_result(result_path):
                        print(f"  ✓ Downloaded from S3")
                        return True
            except Exception as e:
                print(f"  S3 download failed: {e}")
        
        # For SSM: try to get file size first, then use appropriate method
        size_check_commands = [
            f"if [ -f /tmp/results/{test_id}.json ]; then",
            f"  stat -f%z /tmp/results/{test_id}.json 2>/dev/null || stat -c%s /tmp/results/{test_id}.json 2>/dev/null || echo 0",
            "else",
            "  echo 0",
            "fi"
        ]
        
        try:
            size_result = self.ssm_executor.execute_command(size_check_commands, timeout=30)
            file_size = int(size_result.output.strip()) if size_result.output.strip().isdigit() else 0
            
            if file_size == 0:
                print(f"  Result file not found on EC2")
                result_path.parent.mkdir(parents=True, exist_ok=True)
                with open(result_path, 'w') as f:
                    f.write('{}')
                return False
            
            # SSM has ~24KB output limit, so for larger files we need S3
            if file_size > 20000:
                print(f"  Warning: Result file is large ({file_size} bytes), SSM output may be truncated")
                print(f"  Attempting to download from S3 or use alternative method...")
                
                # Try S3 one more time with explicit upload command
                if self.s3_manager and self.s3_manager.bucket_name:
                    upload_commands = [
                        f"(command -v aws >/dev/null 2>&1 && aws s3 cp /tmp/results/{test_id}.json s3://{self.s3_manager.bucket_name}/test-results/{test_id}.json 2>&1 || /usr/bin/aws s3 cp /tmp/results/{test_id}.json s3://{self.s3_manager.bucket_name}/test-results/{test_id}.json 2>&1) && echo 'Uploaded' || echo 'Upload failed'"
                    ]
                    upload_result = self.ssm_executor.execute_command(upload_commands, timeout=60)
                    if 'Uploaded' in upload_result.output:
                        # Now try to download
                        if self.s3_manager.download_file(f"test-results/{test_id}.json", str(result_path)):
                            if self._validate_result(result_path):
                                print(f"  ✓ Uploaded to S3 and downloaded")
                                return True
                
                # If S3 fails, try to get at least partial data via SSM (first 20KB)
                print(f"  Attempting partial download via SSM (first 20KB)...")
                commands = [
                    f"head -c 20000 /tmp/results/{test_id}.json 2>/dev/null || cat /tmp/results/{test_id}.json | head -c 20000"
                ]
            else:
                # Small file - can use SSM directly
                commands = [
                    f"cat /tmp/results/{test_id}.json"
                ]
            
            result = self.ssm_executor.execute_command(commands, timeout=120)
            
            if result.status == 'Success':
                result_json = result.output.strip()
                
                # Handle empty or invalid JSON
                if not result_json or result_json == '{}':
                    result_json = '{}'
                else:
                    # Validate JSON
                    try:
                        parsed = json.loads(result_json)
                        # If it's a partial file, mark it
                        if file_size > 20000 and len(result_json) < file_size:
                            print(f"  Warning: Only got {len(result_json)} bytes of {file_size} byte file")
                            # Try to make it valid JSON by closing any open structures
                            if not result_json.rstrip().endswith('}'):
                                # Try to close JSON
                                result_json = result_json.rstrip().rstrip(',') + '}'
                    except json.JSONDecodeError as e:
                        print(f"Warning: Invalid JSON for {test_id}: {e}")
                        result_json = '{}'
                
                # Save result
                result_path.parent.mkdir(parents=True, exist_ok=True)
                with open(result_path, 'w') as f:
                    f.write(result_json)
                
                return self._validate_result(result_path)
            else:
                print(f"Error collecting result for {test_id}: {result.error}")
                # Create empty result file
                result_path.parent.mkdir(parents=True, exist_ok=True)
                with open(result_path, 'w') as f:
                    f.write('{}')
                return False
                
        except SSMExecutionError as e:
            print(f"SSM error collecting result for {test_id}: {e}")
            # Create empty result file
            result_path.parent.mkdir(parents=True, exist_ok=True)
            with open(result_path, 'w') as f:
                f.write('{}')
            return False
    
    def _validate_result(self, result_path: Path) -> bool:
        """Validate that result file exists and contains valid JSON."""
        if not result_path.exists():
            return False
        
        try:
            with open(result_path, 'r') as f:
                data = json.load(f)
            
            # Check if it's not just an empty object
            if data == {}:
                return False
            
            # Check for required fields
            if 'test_id' not in data:
                return False
            
            return True
        except (json.JSONDecodeError, Exception):
            return False

