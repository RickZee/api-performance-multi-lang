#!/usr/bin/env python3
"""
Main CLI entry point for running the test suite.
"""

import sys
import argparse
from pathlib import Path
from datetime import datetime

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from test_suite.config import Config
from test_suite.executor import RemoteExecutor
from test_suite.runner import TestRunner


def main():
    parser = argparse.ArgumentParser(
        description='Run DSQL performance test suite',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run full test suite
  python3 scripts/run_test_suite.py

  # Run specific test groups
  python3 scripts/run_test_suite.py --groups scenario1_thread_scaling scenario2_batch_impact

  # Resume from previous run
  python3 scripts/run_test_suite.py --resume

  # Custom results directory
  python3 scripts/run_test_suite.py --results-dir results/my-test-run
        """
    )
    
    parser.add_argument(
        '--config',
        default='test-config.json',
        help='Path to test configuration JSON file (default: test-config.json)'
    )
    
    parser.add_argument(
        '--results-dir',
        help='Results directory (default: results/TIMESTAMP)'
    )
    
    parser.add_argument(
        '--groups',
        nargs='+',
        help='Specific test groups to run (default: all groups)'
    )
    
    parser.add_argument(
        '--resume',
        action='store_true',
        help='Resume from previous run (skip completed tests)'
    )
    
    parser.add_argument(
        '--max-pool-size',
        type=int,
        default=2000,
        help='Maximum connection pool size (default: 2000)'
    )
    
    parser.add_argument(
        '--connection-rate-limit',
        type=int,
        default=100,
        help='DSQL connection rate limit per second (default: 100)'
    )
    
    parser.add_argument(
        '--tags',
        nargs='+',
        help='Filter tests by tags (e.g., --tags quick standard)'
    )
    
    args = parser.parse_args()
    
    # Determine results directory
    script_dir = Path(__file__).parent.parent
    if args.results_dir:
        results_dir = Path(args.results_dir)
    elif args.resume:
        # Use latest results directory
        latest_link = script_dir / 'results' / 'latest'
        if latest_link.exists() and latest_link.is_symlink():
            results_dir = latest_link.resolve()
        else:
            # Find most recent results directory
            results_base = script_dir / 'results'
            if results_base.exists():
                dirs = sorted([d for d in results_base.iterdir() if d.is_dir()], reverse=True)
                if dirs:
                    results_dir = dirs[0]
                else:
                    results_dir = results_base / datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
            else:
                results_dir = results_base / datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
    else:
        # Create new results directory
        timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
        results_dir = script_dir / 'results' / timestamp
        # Create symlink to latest
        latest_link = script_dir / 'results' / 'latest'
        latest_link.parent.mkdir(parents=True, exist_ok=True)
        if latest_link.exists() or latest_link.is_symlink():
            latest_link.unlink()
        latest_link.symlink_to(timestamp)
    
    # Validate config file
    config_path = script_dir / args.config
    if not config_path.exists():
        print(f"Error: Config file not found: {config_path}")
        sys.exit(1)
    
    # Load configuration from environment
    try:
        config = Config.from_env()
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Create test runner
    try:
        executor = RemoteExecutor(config)
        runner = TestRunner(
            config=config,
            executor=executor,
            config_path=str(config_path),
            results_dir=str(results_dir),
            max_pool_size=args.max_pool_size,
            connection_rate_limit=args.connection_rate_limit
        )
        
        # Run suite
        result = runner.run_suite(
            test_groups=args.groups,
            resume=args.resume,
            tags=args.tags
        )
        
        # Exit with error if any tests failed
        if result['failed'] > 0:
            sys.exit(1)
        
    except KeyboardInterrupt:
        print("\n\nTest suite interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()

