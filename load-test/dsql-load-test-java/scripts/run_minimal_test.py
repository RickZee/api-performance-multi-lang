#!/usr/bin/env python3
"""
Run minimal test to verify the test suite works.
Uses minimal parameters: 2 threads, 2 iterations, 2 count, both scenarios.
"""

import sys
import json
from pathlib import Path
from datetime import datetime

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from test_suite.config.loader import TestDefinition
from test_suite.config.aws_config import AWSConfig as ConfigLoader
from test_suite.infrastructure.ec2_manager import EC2Manager
from test_suite.infrastructure.ssm_executor import SSMExecutor
from test_suite.infrastructure.s3_manager import S3Manager
from test_suite.archive.manager import ArchiveManager
from test_suite.orchestration.test_executor import TestExecutor
from test_suite.orchestration.result_collector import ResultCollector


def main():
    print("=" * 80)
    print("Minimal Test - Verification Run")
    print("=" * 80)
    print()
    
    # Get infrastructure config
    config_loader = ConfigLoader()
    infra_config = config_loader.get_all_config()
    is_valid, error = config_loader.validate_config()
    if not is_valid:
        print(f"Error: {error}")
        sys.exit(1)
    
    print(f"Test Runner Instance: {infra_config['test_runner_instance_id']}")
    print(f"DSQL Host: {infra_config['dsql_host']}")
    print(f"S3 Bucket: {infra_config['s3_bucket'] or 'Not configured'}")
    print()
    
    # Initialize managers
    ec2_manager = EC2Manager(
        infra_config['test_runner_instance_id'],
        infra_config['aws_region']
    )
    ssm_executor = SSMExecutor(
        infra_config['test_runner_instance_id'],
        infra_config['aws_region']
    )
    s3_manager = S3Manager(
        infra_config['s3_bucket'],
        infra_config['aws_region']
    )
    
    # Ensure EC2 is running
    print("=== Checking EC2 Instance ===")
    if not ec2_manager.ensure_running():
        print("Error: Failed to start EC2 instance or SSM agent not ready")
        sys.exit(1)
    print()
    
    # Create test definitions for minimal test (both scenarios)
    test_defs = [
        TestDefinition(
            test_id="minimal-test-scenario1",
            scenario=1,
            threads=2,
            iterations=2,
            count=2,
            batch_size=None,
            payload_size='default',
            event_type='CarCreated'
        ),
        TestDefinition(
            test_id="minimal-test-scenario2",
            scenario=2,
            threads=2,
            iterations=2,
            count=2,
            batch_size=2,
            payload_size='default',
            event_type='CarCreated'
        )
    ]
    
    # Initialize test executor
    script_dir = Path(__file__).parent.parent
    test_executor = TestExecutor(
        ssm_executor,
        s3_manager,
        str(script_dir),
        infra_config['dsql_host'],
        infra_config['iam_username'],
        infra_config['aws_region'],
        max_pool_size=10,  # Small pool for minimal test
        connection_rate_limit=100
    )
    
    # Prepare archive
    print("=== Creating deployment package ===")
    try:
        archive_path = test_executor.prepare_archive()
        print(f"✅ Archive created: {archive_path}")
    except Exception as e:
        print(f"❌ Failed to create archive: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    print()
    
    # Run tests
    results_dir = script_dir / 'results' / datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
    results_dir.mkdir(parents=True, exist_ok=True)
    result_collector = ResultCollector(ssm_executor, s3_manager)
    
    all_success = True
    for test_def in test_defs:
        print("=== Running Minimal Test ===")
        print(f"Test ID: {test_def.test_id}")
        print(f"Scenario: {test_def.scenario}, Threads: {test_def.threads}, "
              f"Iterations: {test_def.iterations}, Count: {test_def.count}")
        print()
        
        try:
            success = test_executor.execute_test(test_def)
            
            if success:
                print("✅ Test execution completed")
            else:
                print("❌ Test execution failed")
                all_success = False
                continue
        except Exception as e:
            print(f"❌ Error during test execution: {e}")
            import traceback
            traceback.print_exc()
            all_success = False
            continue
        
        print()
        
        # Collect result
        print("=== Collecting Results ===")
        result_collected = result_collector.collect_result(test_def.test_id, results_dir)
        
        if result_collected:
            print(f"✅ Result collected: {results_dir / f'{test_def.test_id}.json'}")
            
            # Display result summary
            result_file = results_dir / f"{test_def.test_id}.json"
            if result_file.exists():
                with open(result_file, 'r') as f:
                    result_data = json.load(f)
                print(f"  Success: {result_data.get('results', {}).get(f'scenario_{test_def.scenario}', {}).get('total_success', 0)}")
                print(f"  Errors: {result_data.get('results', {}).get(f'scenario_{test_def.scenario}', {}).get('total_errors', 0)}")
        else:
            print("⚠️  Result collection failed or result file is empty")
            all_success = False
        
        print()
    
    if not all_success:
        print("⚠️  Some tests failed")
        sys.exit(1)
    
    print()
    print("=" * 80)
    print("Minimal Test Complete")
    print("=" * 80)
    print(f"Results: {results_dir}")


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

