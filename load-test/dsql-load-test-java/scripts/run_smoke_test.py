#!/usr/bin/env python3
"""
Run smoke test to validate the testing pipeline works.
This runs 2 minimal tests (one for each scenario) to verify infrastructure.
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
    print("DSQL Performance Test Suite - Smoke Test")
    print("=" * 80)
    print()
    print("This will run 2 minimal tests (one per scenario) to validate the pipeline.")
    print("Expected duration: ~2-5 minutes")
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
    results_dir = script_dir / 'results' / f'smoke-test-{timestamp}'
    results_dir.mkdir(parents=True, exist_ok=True)
    
    # Create symlink to latest
    latest_link = script_dir / 'results' / 'latest-smoke'
    if latest_link.exists():
        latest_link.unlink()
    latest_link.symlink_to(results_dir.name)
    
    print(f"Results directory: {results_dir}")
    print()
    
    # Use smoke test config
    config_path = script_dir / 'test-config-smoke.json'
    if not config_path.exists():
        print(f"Error: Smoke test config file not found: {config_path}")
        sys.exit(1)
    
    print(f"Using config: {config_path}")
    print()
    
    # Record start time
    start_time = datetime.now()
    start_time_local = start_time.strftime('%Y-%m-%d %H:%M:%S %Z')
    start_time_iso = start_time.strftime('%Y-%m-%dT%H:%M:%S%z')
    start_time_utc = start_time.astimezone().strftime('%Y-%m-%dT%H:%M:%SZ')
    
    print(f"Start Time (Local): {start_time_local}")
    print(f"Start Time (UTC): {start_time_utc}")
    print(f"Estimated Duration: 2-5 minutes")
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
    
    print(f"Total tests in smoke test: {total_tests}")
    print("Test breakdown:")
    print("  Scenario 1 (Individual inserts): 1 test")
    print("    - 10 threads, 2 iterations, 5 inserts per iteration")
    print("    - Expected: ~100 total inserts")
    print("  Scenario 2 (Batch inserts): 1 test")
    print("    - 10 threads, 2 iterations, 10 rows per batch")
    print("    - Expected: ~200 total inserts")
    print()
    print("Starting smoke test execution...")
    print("=" * 80)
    print()
    
    # Run test suite
    try:
        result = runner.run_suite()
        
        # Calculate duration
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()
        duration_minutes = duration / 60
        
        print()
        print("=" * 80)
        print("Smoke Test Complete")
        print("=" * 80)
        print(f"Start Time (Local): {start_time_local}")
        print(f"End Time (Local): {end_time.strftime('%Y-%m-%d %H:%M:%S %Z')}")
        print(f"Total Duration: {duration:.1f} seconds ({duration_minutes:.2f} minutes)")
        print()
        print(f"Total tests: {result['total']}")
        print(f"Completed: {result['completed']}")
        print(f"Failed: {result['failed']}")
        print(f"Results directory: {result['results_dir']}")
        print()
        
        if result['failed'] == 0:
            print("✅ Smoke test PASSED - Pipeline is working correctly!")
            print()
            print("Next steps:")
            print("  1. Run minimal test suite:")
            print("     python3 scripts/run_minimal_max_throughput.py")
            print("  2. Run full max throughput discovery:")
            print("     python3 scripts/run_test_suite.py --config test-config-max-throughput.json")
        else:
            print("❌ Smoke test FAILED - Check errors above")
            sys.exit(1)
        
        print()
        print("View results:")
        print(f"  ls -lh {results_dir}")
        print(f"  cat {results_dir}/*.json | python3 -m json.tool | head -50")
        
    except KeyboardInterrupt:
        print("\n\nSmoke test interrupted by user")
        print(f"Results saved to: {results_dir}")
        sys.exit(1)
    except Exception as e:
        print(f"\n\nError running smoke test: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()

