#!/usr/bin/env python3
"""
Quick check for test status on EC2 test runner.
"""

import sys
import os
from pathlib import Path
from datetime import datetime

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from test_suite.config.aws_config import AWSConfig as ConfigLoader
from test_suite.monitoring.status_checker import StatusChecker


def main():
    """Check if any tests are currently in progress."""
    print("=" * 80)
    print("EC2 Test Runner Status Check")
    print("=" * 80)
    print()
    
    # Get infrastructure config
    config_loader = ConfigLoader(region=os.getenv('AWS_REGION'))
    infra_config = config_loader.get_all_config()
    
    if not infra_config['test_runner_instance_id']:
        print("❌ Error: Test runner instance ID not found", file=sys.stderr)
        print("   Try setting AWS_REGION or check instance tags.", file=sys.stderr)
        sys.exit(1)
    
    instance_id = infra_config['test_runner_instance_id']
    region = infra_config['aws_region']
    
    print(f"Instance ID: {instance_id}")
    print(f"Region: {region}")
    print()
    
    # Determine results directory
    script_dir = Path(__file__).parent.parent
    latest_link = script_dir / 'results' / 'latest'
    if latest_link.exists() and latest_link.is_symlink():
        results_dir = latest_link.resolve()
    else:
        # Find most recent
        results_base = script_dir / 'results'
        if results_base.exists():
            dirs = sorted([d for d in results_base.iterdir() if d.is_dir()], reverse=True)
            if dirs:
                results_dir = dirs[0]
            else:
                results_dir = script_dir / 'results' / 'latest'
        else:
            results_dir = script_dir / 'results' / 'latest'
    
    # Create status checker
    status_checker = StatusChecker(instance_id, region, results_dir)
    
    # Check for active command
    print("Checking for active tests...")
    print("-" * 80)
    
    active_cmd = status_checker.get_active_command()
    
    if active_cmd:
        print("✅ Tests are IN PROGRESS")
        print()
        print(f"Command ID: {active_cmd.get('CommandId', 'N/A')}")
        print(f"Status: {active_cmd.get('Status', 'N/A')}")
        print(f"Requested At: {active_cmd.get('RequestedDateTime', 'N/A')}")
        print()
        
        # Get current test info
        current_test = status_checker.get_current_test_id()
        if current_test:
            print(f"Current Test: {current_test}")
            
            test_info = status_checker.get_current_test_info()
            if test_info:
                print(f"  Scenario: {test_info.get('scenario', '?')}")
                print(f"  Threads: {test_info.get('threads', '?')}")
                print(f"  Iterations: {test_info.get('iterations', '?')}")
                print(f"  Count: {test_info.get('count', '?')}")
        else:
            print("Current Test: (extracting from output...)")
        
        print()
        
        # Get completed tests count
        completed_tests = status_checker.get_completed_tests()
        print(f"Completed Tests: {len(completed_tests)}")
        if completed_tests:
            print(f"Last Completed: {completed_tests[-1]}")
    else:
        print("❌ No tests currently in progress")
        print()
        
        # Check completed tests
        completed_tests = status_checker.get_completed_tests()
        print(f"Completed Tests: {len(completed_tests)}")
        if completed_tests:
            print(f"Last Completed: {completed_tests[-1]}")
        else:
            print("No tests have been completed yet.")
    
    print()
    print("=" * 80)


if __name__ == '__main__':
    main()

