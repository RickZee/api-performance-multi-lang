#!/usr/bin/env python3
"""
Verify if tests are actually running by checking:
1. S3 for test result files
2. EC2 instance for running processes
3. Recent test activity
"""

import sys
import os
import json
import boto3
from pathlib import Path
from datetime import datetime, timedelta
from botocore.exceptions import ClientError, BotoCoreError


def load_env_from_terraform():
    """Load environment variables from Terraform outputs."""
    script_dir = Path(__file__).parent.parent
    terraform_dir = script_dir.parent / 'terraform'
    
    env_vars = {}
    
    if terraform_dir.exists():
        terraform_outputs = {
            'S3_BUCKET': 's3_bucket_name',
            'TEST_RUNNER_INSTANCE_ID': 'dsql_test_runner_instance_id',
            'AWS_REGION': 'aws_region',
        }
        
        for env_var, tf_output in terraform_outputs.items():
            if not os.getenv(env_var):
                try:
                    import subprocess
                    result = subprocess.run(
                        ['terraform', 'output', '-raw', tf_output],
                        cwd=str(terraform_dir),
                        capture_output=True,
                        text=True,
                        timeout=10
                    )
                    if result.returncode == 0:
                        value = result.stdout.strip()
                        if value:
                            env_vars[env_var] = value
                            os.environ[env_var] = value
                except Exception:
                    pass
    
    return env_vars


def check_s3_results(s3_bucket: str, region: str) -> dict:
    """Check S3 for test result files."""
    print("=" * 80)
    print("Checking S3 for Test Results")
    print("=" * 80)
    
    try:
        s3 = boto3.client('s3', region_name=region)
        
        # List all test results
        paginator = s3.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=s3_bucket, Prefix='test-results/')
        
        all_files = []
        for page in pages:
            if 'Contents' in page:
                all_files.extend(page['Contents'])
        
        if not all_files:
            print("❌ No test result files found in S3")
            return {'found': False, 'count': 0}
        
        # Sort by last modified
        files = sorted(all_files, key=lambda x: x['LastModified'], reverse=True)
        latest = files[0]
        
        print(f"✅ Found {len(files)} test result file(s) in S3")
        print()
        print("Latest 5 results:")
        print()
        
        for obj in files[:5]:
            key = obj['Key']
            test_id = key.replace('test-results/', '').replace('.json', '')
            modified = obj['LastModified']
            size = obj['Size']
            age_seconds = (datetime.now(modified.tzinfo) - modified).total_seconds()
            
            if age_seconds < 60:
                age_str = f"{age_seconds:.0f}s ago"
            elif age_seconds < 3600:
                age_str = f"{age_seconds/60:.1f}m ago"
            else:
                age_str = f"{age_seconds/3600:.1f}h ago"
            
            print(f"  {test_id}")
            print(f"    Size: {size:,} bytes | Modified: {age_str}")
        
        # Check if any results are very recent (last 2 minutes)
        recent_count = sum(1 for f in files if (datetime.now(f['LastModified'].tzinfo) - f['LastModified']).total_seconds() < 120)
        
        return {
            'found': True,
            'count': len(files),
            'latest_age_seconds': (datetime.now(latest['LastModified'].tzinfo) - latest['LastModified']).total_seconds(),
            'recent_count': recent_count
        }
        
    except ClientError as e:
        print(f"❌ Error accessing S3: {e}")
        return {'found': False, 'error': str(e)}
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return {'found': False, 'error': str(e)}


def check_ec2_process(instance_id: str, region: str) -> dict:
    """Check EC2 instance for running test processes."""
    print()
    print("=" * 80)
    print("Checking EC2 Instance for Running Tests")
    print("=" * 80)
    
    try:
        ec2 = boto3.client('ec2', region_name=region)
        ssm = boto3.client('ssm', region_name=region)
        
        # Check instance status
        response = ec2.describe_instances(InstanceIds=[instance_id])
        if not response['Reservations']:
            print(f"❌ Instance {instance_id} not found")
            return {'running': False, 'error': 'Instance not found'}
        
        instance = response['Reservations'][0]['Instances'][0]
        state = instance['State']['Name']
        
        print(f"Instance ID: {instance_id}")
        print(f"State: {state}")
        
        if state != 'running':
            print(f"❌ Instance is not running (state: {state})")
            return {'running': False, 'state': state}
        
        print("✅ Instance is running")
        print()
        
        # Check for Java test process
        print("Checking for test processes...")
        try:
            result = ssm.send_command(
                InstanceIds=[instance_id],
                DocumentName='AWS-RunShellScript',
                Parameters={
                    'commands': [
                        'ps aux | grep -E "(dsql-load-test|java.*dsql)" | grep -v grep || echo "No test process found"',
                        'ls -lth /tmp/results/*.json 2>/dev/null | head -3 || echo "No result files in /tmp/results"'
                    ]
                },
                TimeoutSeconds=30
            )
            command_id = result['Command']['CommandId']
            print(f"Command sent (ID: {command_id})")
            print("Waiting for command output...")
            
            import time
            time.sleep(3)  # Wait a bit for command to execute
            
            # Get command output
            output = ssm.get_command_invocation(
                CommandId=command_id,
                InstanceId=instance_id
            )
            
            if output['Status'] == 'Success':
                stdout = output.get('StandardOutputContent', '')
                stderr = output.get('StandardErrorContent', '')
                
                print()
                if stdout:
                    print("Process Check:")
                    print(stdout)
                if stderr and 'No test process found' not in stderr:
                    print("Errors:")
                    print(stderr)
                
                has_process = 'dsql-load-test' in stdout or 'java' in stdout
                has_results = 'No result files' not in stdout
                
                return {
                    'running': True,
                    'has_process': has_process,
                    'has_results': has_results,
                    'output': stdout
                }
            else:
                print(f"Command status: {output['Status']}")
                return {'running': True, 'command_status': output['Status']}
                
        except Exception as e:
            print(f"⚠️  Could not check processes: {e}")
            return {'running': True, 'error': str(e)}
        
    except ClientError as e:
        print(f"❌ Error accessing EC2/SSM: {e}")
        return {'running': False, 'error': str(e)}
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return {'running': False, 'error': str(e)}


def main():
    """Main verification function."""
    print("=" * 80)
    print("Test Execution Verification")
    print("=" * 80)
    print()
    
    # Load environment variables
    env_vars = load_env_from_terraform()
    
    s3_bucket = os.getenv('S3_BUCKET')
    instance_id = os.getenv('TEST_RUNNER_INSTANCE_ID')
    region = os.getenv('AWS_REGION', 'us-east-1')
    
    if not s3_bucket:
        print("❌ S3_BUCKET not configured")
        print("   Set: export S3_BUCKET=your-bucket-name")
        print("   Or ensure Terraform outputs are available")
        sys.exit(1)
    
    # Check S3
    s3_status = check_s3_results(s3_bucket, region)
    
    # Check EC2 if instance ID is available
    ec2_status = {}
    if instance_id:
        ec2_status = check_ec2_process(instance_id, region)
    else:
        print()
        print("⚠️  TEST_RUNNER_INSTANCE_ID not configured, skipping EC2 check")
    
    # Summary
    print()
    print("=" * 80)
    print("Summary")
    print("=" * 80)
    
    if s3_status.get('found'):
        print(f"✅ S3: {s3_status['count']} test result file(s) found")
        if s3_status.get('latest_age_seconds', 999999) < 300:  # Less than 5 minutes
            print(f"   Latest result is {s3_status['latest_age_seconds']:.0f} seconds old - tests likely running!")
        elif s3_status.get('recent_count', 0) > 0:
            print(f"   {s3_status['recent_count']} recent result(s) - tests may be running")
        else:
            print(f"   Latest result is {s3_status['latest_age_seconds']/60:.1f} minutes old - tests may have completed")
    else:
        print("❌ S3: No test results found")
    
    if ec2_status:
        if ec2_status.get('running'):
            if ec2_status.get('has_process'):
                print("✅ EC2: Test process detected - tests are running!")
            elif ec2_status.get('has_results'):
                print("⚠️  EC2: No active process, but result files exist - tests may have completed")
            else:
                print("⚠️  EC2: Instance running but no test process or results detected")
        else:
            print(f"❌ EC2: Instance not running (state: {ec2_status.get('state', 'unknown')})")
    
    print()
    print("=" * 80)
    print("Recommendation:")
    if s3_status.get('found') and s3_status.get('latest_age_seconds', 999999) < 300:
        print("✅ Tests appear to be running (recent S3 activity detected)")
    elif s3_status.get('found'):
        print("⚠️  Tests may have completed. Check S3 for final results.")
    else:
        print("❌ No test activity detected. Check if test runner is started.")
    print("=" * 80)


if __name__ == '__main__':
    main()

