"""
Check test status on EC2 and in results directory.
"""

import json
import os
import sys
from pathlib import Path
from typing import Optional, Dict, List, Any
import boto3
from botocore.exceptions import ClientError


class StatusChecker:
    """Check test status from EC2 and local results."""
    
    def __init__(self, instance_id: str, region: str, results_dir: Path):
        self.instance_id = instance_id
        self.region = region
        self.results_dir = results_dir
        self.ssm = boto3.client('ssm', region_name=region)
    
    def get_active_command(self) -> Optional[Dict]:
        """Get currently active SSM command."""
        try:
            # Check all recent commands first (more reliable)
            response_all = self.ssm.list_commands(MaxResults=30)
            in_progress_commands = [cmd for cmd in response_all.get('Commands', []) if cmd['Status'] == 'InProgress']
            
            # Try each InProgress command to see if it's for our instance
            for cmd in in_progress_commands:
                try:
                    invocation = self.ssm.get_command_invocation(
                        CommandId=cmd['CommandId'],
                        InstanceId=self.instance_id
                    )
                    # If we can get the invocation, it's for our instance
                    return cmd
                except Exception:
                    # Not for our instance, continue to next
                    continue
            
            # Fallback: try instance-filtered list
            response = self.ssm.list_commands(
                InstanceId=self.instance_id,
                MaxResults=10
            )
            
            for cmd in response.get('Commands', []):
                if cmd['Status'] == 'InProgress':
                    return cmd
            
            return None
        except (ClientError, Exception) as e:
            # Debug: print error in development
            import os
            if os.getenv('DEBUG_MONITOR'):
                print(f"StatusChecker error: {e}", file=sys.stderr)
            return None
    
    def get_running_test_from_manifest(self) -> Optional[Dict[str, Any]]:
        """Get currently running test from manifest (most reliable source)."""
        manifest_file = self.results_dir / 'manifest.json'
        if not manifest_file.exists():
            return None
        
        try:
            with open(manifest_file, 'r') as f:
                manifest = json.load(f)
            
            # Find test with status="running"
            for test in manifest.get('tests', []):
                if test.get('status') == 'running':
                    return test
        except Exception:
            pass
        
        return None
    
    def get_current_test_id(self) -> Optional[str]:
        """Extract current test ID from active command output."""
        # First try the standard method
        cmd = self.get_active_command()
        if cmd:
            try:
                invocation = self.ssm.get_command_invocation(
                    CommandId=cmd['CommandId'],
                    InstanceId=self.instance_id
                )
                
                output = invocation.get('StandardOutputContent', '')
                
                # Try multiple patterns to extract test ID
                for line in output.split('\n'):
                    # Pattern 1: TEST_ID=test-xxx
                    if 'TEST_ID=' in line:
                        parts = line.split('TEST_ID=')
                        if len(parts) > 1:
                            test_id = parts[1].strip().split()[0]
                            if test_id.startswith('test-'):
                                return test_id
                    
                    # Pattern 2: Running test: test-xxx or Test ID: test-xxx
                    if 'Running test:' in line or 'Test ID:' in line or '[test-' in line:
                        import re
                        match = re.search(r'test-\d{3}-[^\s\)]+', line)
                        if match:
                            return match.group(0)
                    
                    # Pattern 3: Look for test-xxx pattern anywhere (improved regex to capture full ID)
                    import re
                    # Try to match full test ID format: test-001-scenario1-threads10-loops20-count1-payloaddefault
                    match = re.search(r'test-\d{3}-[a-z0-9_-]+(?:-threads\d+)?(?:-loops\d+)?(?:-count\d+)?(?:-batch\d+)?(?:-payload[a-z0-9]+)?', line)
                    if match:
                        test_id = match.group(0)
                        # Validate it looks like a real test ID (at least has test number and scenario)
                        parts = test_id.split('-')
                        if len(parts) >= 3:  # test-001-scenario1 at minimum
                            return test_id
                    
                    # Pattern 4: Look for just test-xxx number (fallback)
                    match = re.search(r'test-\d{3}', line)
                    if match:
                        return match.group(0)  # Return partial ID, will be resolved in get_current_test_info
                
            except (ClientError, Exception):
                pass
        
        # Fallback: check all InProgress commands and try to find one for our instance
        try:
            response = self.ssm.list_commands(MaxResults=20)
            for cmd in response.get('Commands', []):
                if cmd['Status'] == 'InProgress':
                    try:
                        invocation = self.ssm.get_command_invocation(
                            CommandId=cmd['CommandId'],
                            InstanceId=self.instance_id
                        )
                        output = invocation.get('StandardOutputContent', '')
                        
                        # Look for test ID patterns with regex
                        import re
                        # Try to find full test-xxx pattern
                        matches = re.findall(r'test-\d{3}-[a-z0-9_-]+(?:-threads\d+)?(?:-loops\d+)?(?:-count\d+)?(?:-batch\d+)?(?:-payload[a-z0-9]+)?', output)
                        if matches:
                            # Return the most complete match
                            for match in matches:
                                parts = match.split('-')
                                if len(parts) >= 4:
                                    return match
                        
                        # Fallback: look for just test number
                        matches = re.findall(r'test-\d{3}', output)
                        if matches:
                            return matches[0]  # Return partial, will be resolved in get_current_test_info
                    except Exception:
                        # Not for our instance, continue
                        continue
        except Exception:
            pass
        
        return None
    
    def get_current_test_info(self) -> Optional[Dict[str, str]]:
        """Get current test information including scenario details."""
        test_id = self.get_current_test_id()
        if not test_id:
            return None
        
        # First, try to get full test details from manifest if we have a partial test ID
        # (e.g., "test-002" instead of full "test-002-scenario1-threads10-...")
        manifest_file = self.results_dir / 'manifest.json'
        if manifest_file.exists() and len(test_id.split('-')) < 4:
            # Partial test ID - try to find full ID in manifest
            try:
                import json
                with open(manifest_file, 'r') as f:
                    manifest = json.load(f)
                
                # Extract test number from partial ID
                import re
                test_num_match = re.search(r'test-(\d{3})', test_id)
                if test_num_match:
                    test_num = test_num_match.group(1)
                    # Find test in manifest with this number
                    for test in manifest.get('tests', []):
                        full_test_id = test.get('test_id', '')
                        if full_test_id.startswith(f'test-{test_num}'):
                            # Found full test ID in manifest
                            return {
                                'test_id': full_test_id,
                                'scenario': str(test.get('scenario', '?')),
                                'threads': str(test.get('threads', '?')),
                                'iterations': str(test.get('iterations', '?')),
                                'count': str(test.get('count', '?'))
                            }
            except Exception:
                pass
        
        # Parse test ID to extract information
        # Format: test-001-scenario1-threads10-loops20-count1-payloaddefault
        import re
        parts = test_id.split('-')
        
        info = {'test_id': test_id}
        
        # Extract scenario
        scenario_match = re.search(r'scenario(\d+)', test_id)
        if scenario_match:
            info['scenario'] = scenario_match.group(1)
        else:
            info['scenario'] = '?'
        
        # Extract threads
        threads_match = re.search(r'threads(\d+)', test_id)
        if threads_match:
            info['threads'] = threads_match.group(1)
        else:
            info['threads'] = '?'
        
        # Extract iterations/loops
        loops_match = re.search(r'loops(\d+)', test_id)
        if loops_match:
            info['iterations'] = loops_match.group(1)
        else:
            info['iterations'] = '?'
        
        # Extract count
        count_match = re.search(r'count(\d+)', test_id)
        if count_match:
            info['count'] = count_match.group(1)
        else:
            info['count'] = '?'
        
        return info
    
    def get_completed_tests(self) -> List[str]:
        """Get list of completed test IDs from results directory."""
        completed = []
        
        if not self.results_dir.exists():
            return completed
        
        for json_file in self.results_dir.glob('test-*.json'):
            if self._is_test_complete(json_file):
                test_id = json_file.stem
                completed.append(test_id)
        
        return sorted(completed)
    
    def get_next_expected_test(self) -> Optional[Dict[str, str]]:
        """Infer next expected test from completed tests and manifest."""
        completed = self.get_completed_tests()
        if not completed:
            return None
        
        # Get the last completed test number
        import re
        last_match = re.search(r'test-(\d{3})', completed[-1])
        if not last_match:
            return None
        
        next_num = int(last_match.group(1)) + 1
        
        # Try to load manifest to get test details
        manifest_file = self.results_dir / 'manifest.json'
        if manifest_file.exists():
            try:
                import json
                with open(manifest_file, 'r') as f:
                    manifest = json.load(f)
                
                # Find test with this number in manifest
                for test in manifest.get('tests', []):
                    test_id = test.get('test_id', '')
                    if test_id.startswith(f'test-{next_num:03d}'):
                        return {
                            'test_id': test_id,
                            'scenario': str(test.get('scenario', '?')),
                            'threads': str(test.get('threads', '?')),
                            'iterations': str(test.get('iterations', '?')),
                            'count': str(test.get('count', '?'))
                        }
            except Exception:
                pass
        
        # Fallback: parse from last test pattern
        last_test = completed[-1]
        scenario_match = re.search(r'scenario(\d+)', last_test)
        scenario = scenario_match.group(1) if scenario_match else "?"
        
        return {
            'test_id': f'test-{next_num:03d}',
            'scenario': scenario,
            'threads': '?',
            'iterations': '?',
            'count': '?'
        }
    
    def _is_test_complete(self, json_file: Path) -> bool:
        """Check if test result file is complete."""
        if not json_file.exists():
            return False
        
        try:
            size = json_file.stat().st_size
            if size < 100:  # Less than just {}
                return False
            
            with open(json_file, 'r') as f:
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

