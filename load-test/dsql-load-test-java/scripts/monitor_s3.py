#!/usr/bin/env python3
"""
Standalone S3-based monitoring script for test suite.
Can run independently of test runner process.
"""

import sys
import os
import argparse
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from test_suite.s3_monitor import monitor_s3_progress, MonitorConfig


def main():
    parser = argparse.ArgumentParser(
        description='Monitor DSQL performance test suite progress via S3 (inexpensive)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Monitor S3 bucket (requires S3_BUCKET env var)
  python3 scripts/monitor_s3.py

  # Custom check interval
  python3 scripts/monitor_s3.py --interval 5

  # Specify total tests manually
  python3 scripts/monitor_s3.py --total-tests 32

Benefits of S3 monitoring:
  - Real-time: See results as soon as they're uploaded to S3
  - Inexpensive: ~$0.0004 per 1000 requests (vs expensive SSM commands)
  - Independent: Can run separately from test runner
  - Reliable: No dependency on local file downloads
        """
    )
    
    parser.add_argument(
        '--interval',
        type=int,
        default=10,
        help='Check interval in seconds (default: 10)'
    )
    
    parser.add_argument(
        '--total-tests',
        type=int,
        help='Total number of tests (if not provided, will try to infer from test-config.json)'
    )
    
    parser.add_argument(
        '--config',
        type=str,
        help='Path to test-config.json (default: test-config.json in project root)'
    )
    
    args = parser.parse_args()
    
    # Try to load from Terraform outputs if env vars not set
    script_dir = Path(__file__).parent.parent
    terraform_dir = script_dir.parent / 'terraform'
    
    # Check if required env vars are missing
    s3_bucket = os.getenv("S3_BUCKET")
    if not s3_bucket and terraform_dir.exists():
        try:
            import subprocess
            result = subprocess.run(
                ['terraform', 'output', '-raw', 's3_bucket_name'],
                cwd=str(terraform_dir),
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                s3_bucket = result.stdout.strip()
                os.environ['S3_BUCKET'] = s3_bucket
                print(f"Loaded S3_BUCKET from Terraform: {s3_bucket}")
        except Exception:
            pass
    
    # Load AWS_REGION from Terraform if not set
    aws_region = os.getenv("AWS_REGION")
    if not aws_region and terraform_dir.exists():
        try:
            import subprocess
            result = subprocess.run(
                ['terraform', 'output', '-raw', 'aws_region'],
                cwd=str(terraform_dir),
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                aws_region = result.stdout.strip()
                os.environ['AWS_REGION'] = aws_region
        except Exception:
            pass
    
    # Load configuration from environment (only needs S3_BUCKET for monitoring)
    try:
        config = MonitorConfig.from_env()
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Determine config path
    script_dir = Path(__file__).parent.parent
    if args.config:
        config_path = Path(args.config)
    else:
        config_path = script_dir / 'test-config.json'
    
    if not config_path.exists():
        config_path = None
        if args.total_tests is None:
            print("Warning: test-config.json not found, cannot determine total tests", file=sys.stderr)
            print("Use --total-tests to specify manually", file=sys.stderr)
    
    # Start monitoring
    try:
        monitor_s3_progress(
            config=config,
            total_tests=args.total_tests,
            interval=args.interval,
            config_path=config_path
        )
    except KeyboardInterrupt:
        print("\nMonitoring stopped")
        sys.exit(0)
    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()

