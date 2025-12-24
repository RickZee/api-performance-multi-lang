#!/usr/bin/env python3
"""
Run full test suite with real-time progress monitoring and time estimates.
"""

import sys
import os
import time
import threading
from pathlib import Path
from datetime import datetime

sys.path.insert(0, str(Path(__file__).parent.parent))

from test_suite.config import Config
from test_suite.executor import RemoteExecutor
from test_suite.runner import TestRunner
from test_suite.monitor import monitor_progress


def run_tests_with_progress():
    """Run test suite with progress monitoring in background."""
    print("=" * 80)
    print("DSQL Performance Test Suite - Full Run")
    print("=" * 80)
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
        sys.exit(1)
    
    print(f"DSQL Host: {config.dsql_host}")
    print(f"Instance ID: {config.instance_id}")
    print(f"S3 Bucket: {config.s3_bucket}")
    print(f"Region: {config.region}")
    print()
    
    # Create results directory
    script_dir = Path(__file__).parent.parent
    timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
    results_dir = script_dir / 'results' / timestamp
    
    # Create symlink to latest
    latest_link = script_dir / 'results' / 'latest'
    latest_link.parent.mkdir(parents=True, exist_ok=True)
    if latest_link.exists() or latest_link.is_symlink():
        latest_link.unlink()
    latest_link.symlink_to(timestamp)
    
    print(f"Results directory: {results_dir}")
    print()
    
    # Initialize
    executor = RemoteExecutor(config)
    runner = TestRunner(
        config=config,
        executor=executor,
        config_path=str(script_dir / 'test-config.json'),
        results_dir=str(results_dir),
        max_pool_size=config.max_pool_size,
        connection_rate_limit=config.connection_rate_limit
    )
    
    # Load test config to get total test count
    from test_suite.runner import TestConfigLoader
    config_loader = TestConfigLoader(str(script_dir / 'test-config.json'))
    config_loader.load_config()
    all_tests = config_loader.generate_test_matrix()
    total_tests = len(all_tests)
    
    print(f"Total tests in suite: {total_tests}")
    print(f"Estimated duration: {total_tests * 2}-{total_tests * 5} minutes")
    print("  (2-5 minutes per test, depending on test size)")
    print()
    print("Starting test execution...")
    print("=" * 80)
    print()
    
    # Start progress monitor in background
    monitor_thread = threading.Thread(
        target=monitor_progress,
        args=(results_dir, total_tests, 10),
        daemon=True
    )
    monitor_thread.start()
    
    # Run test suite
    start_time = time.time()
    
    try:
        result = runner.run_suite()
        
        elapsed_time = time.time() - start_time
        
        print()
        print("=" * 80)
        print("Test Suite Execution Complete")
        print("=" * 80)
        print(f"Results directory: {results_dir}")
        print(f"Total tests: {result['total']}")
        print(f"Completed: {result['completed']}")
        print(f"Failed: {result['failed']}")
        print(f"Total duration: {elapsed_time/60:.1f} minutes ({elapsed_time/3600:.2f} hours)")
        print(f"Average per test: {elapsed_time/result['total']:.1f} seconds")
        print()
        
        if result['failed'] > 0:
            print("⚠️  Some tests failed. Check results for details.")
        else:
            print("✅ All tests completed successfully!")
        
        print()
        print("Next steps:")
        print(f"  1. Generate metrics: python3 scripts/generate_detailed_metrics.py {results_dir}")
        print(f"  2. View charts: open {results_dir}/charts/")
        print(f"  3. Review results: cat {results_dir}/metrics_summary.json")
        
        return result
        
    except KeyboardInterrupt:
        print("\n\n⚠️  Test suite interrupted by user")
        print(f"Progress saved to: {results_dir}")
        print("Resume with: python3 scripts/run_test_suite.py --resume")
        sys.exit(130)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    run_tests_with_progress()

