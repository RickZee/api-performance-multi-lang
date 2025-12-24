#!/usr/bin/env python3
"""
Run minimal max throughput discovery test suite to verify all phases work.
This runs a reduced version of all test phases with minimal parameters.
"""

import sys
import os
from pathlib import Path
from datetime import datetime

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from test_suite.config import Config
from test_suite.executor import RemoteExecutor
from test_suite.runner import TestRunner

def main():
    print("=" * 80)
    print("DSQL Max Throughput Discovery - Minimal Test Run")
    print("=" * 80)
    print()
    print("This will run a minimal version of all test phases to verify everything works.")
    print("Expected duration: ~15-30 minutes")
    print()
    
    # Check environment variables
    try:
        config = Config.from_env()
    except ValueError as e:
        print(f"Error: {e}")
        print("\nPlease set required environment variables:")
        print("  export DSQL_HOST=your-host.dsql.us-east-1.on.aws")
        print("  export TEST_RUNNER_INSTANCE_ID=i-xxxxxxxxxxxxx")
        print("  export S3_BUCKET=your-bucket-name")
        print("\nOr load from Terraform:")
        print("  source scripts/load_env_from_terraform.sh")
        sys.exit(1)
    
    print(f"DSQL Host: {config.dsql_host}")
    print(f"Instance ID: {config.instance_id}")
    print(f"S3 Bucket: {config.s3_bucket}")
    print(f"Region: {config.region}")
    print()
    
    # Create results directory
    script_dir = Path(__file__).parent.parent
    timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
    results_dir = script_dir / 'results' / f'minimal-max-throughput-{timestamp}'
    results_dir.mkdir(parents=True, exist_ok=True)
    
    # Create symlink to latest
    latest_link = script_dir / 'results' / 'latest-minimal'
    if latest_link.exists():
        latest_link.unlink()
    latest_link.symlink_to(results_dir.name)
    
    print(f"Results directory: {results_dir}")
    print()
    
    # Use minimal config
    config_path = script_dir / 'test-config-max-throughput-minimal.json'
    if not config_path.exists():
        print(f"Error: Minimal config file not found: {config_path}")
        sys.exit(1)
    
    print(f"Using config: {config_path}")
    print()
    
    # Initialize components
    executor = RemoteExecutor(config)
    runner = TestRunner(
        config=config,
        executor=executor,
        config_path=str(config_path),
        results_dir=str(results_dir),
        max_pool_size=config.max_pool_size,
        connection_rate_limit=config.connection_rate_limit
    )
    
    # Load test config to get total test count
    from test_suite.runner import TestConfigLoader
    config_loader = TestConfigLoader(str(config_path))
    config_loader.load_config()
    all_tests = config_loader.generate_test_matrix()
    total_tests = len(all_tests)
    
    print(f"Total tests in minimal suite: {total_tests}")
    print("Test breakdown:")
    print("  Phase 1 (Thread optimization): 2 tests")
    print("  Phase 2 (Pool tuning): 1 test")
    print("  Phase 3 (High concurrency): 1 test")
    print("  Phase 4 (Payload impact - Scenario 2): 3 tests")
    print("  Phase 5 (Individual inserts - Scenario 1): 6 tests")
    print("  Phase 6 (Validation): 1 test")
    print()
    print("Starting test execution...")
    print("=" * 80)
    print()
    
    # Run test suite
    try:
        result = runner.run_suite()
        
        print()
        print("=" * 80)
        print("Test Suite Complete")
        print("=" * 80)
        print(f"Total tests: {result['total']}")
        print(f"Completed: {result['completed']}")
        print(f"Failed: {result['failed']}")
        print(f"Results directory: {result['results_dir']}")
        print()
        print("View results:")
        print(f"  ls -lh {results_dir}")
        print(f"  cat {results_dir}/comprehensive_report.txt")
        print()
        print("Monitor progress (if still running):")
        print(f"  python3 scripts/monitor_tests.py --config {config_path}")
        
    except KeyboardInterrupt:
        print("\n\nTest suite interrupted by user")
        print(f"Results saved to: {results_dir}")
        print("Resume with: python3 scripts/run_test_suite.py --config test-config-max-throughput-minimal.json --resume")
        sys.exit(1)
    except Exception as e:
        print(f"\n\nError running test suite: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()

