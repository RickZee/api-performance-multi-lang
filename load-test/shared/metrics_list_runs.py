#!/usr/bin/env python3
"""
List Test Runs
Display test runs from the metrics database with filtering options
"""
import sys
import os
from datetime import datetime
from pathlib import Path

# Add script directory to path
script_dir = Path(__file__).parent
sys.path.insert(0, str(script_dir))

from db_client import get_latest_test_runs, test_connection


def format_timestamp(ts):
    """Format timestamp for display"""
    if isinstance(ts, str):
        return ts
    if hasattr(ts, 'strftime'):
        return ts.strftime('%Y-%m-%d %H:%M:%S')
    return str(ts)


def list_test_runs(api_name=None, test_mode=None, payload_size=None, limit=50):
    """List test runs with optional filters"""
    if not test_connection():
        print("Error: Cannot connect to database. Make sure postgres-metrics is running.", file=sys.stderr)
        sys.exit(1)
    
    api_names = [api_name] if api_name else None
    runs = get_latest_test_runs(api_names, test_mode, payload_size, limit)
    
    if not runs:
        print("No test runs found matching the criteria.")
        return
    
    print(f"\nFound {len(runs)} test run(s):\n")
    print(f"{'ID':<6} {'API':<25} {'Mode':<10} {'Payload':<10} {'Protocol':<8} {'Status':<10} {'Started':<20} {'Samples':<8} {'Throughput':<12}")
    print("-" * 120)
    
    for run in runs:
        run_id = run.get('id', '-')
        api = run.get('api_name', '-')
        mode = run.get('test_mode', '-')
        payload = run.get('payload_size', '-')
        protocol = run.get('protocol', '-')
        status = run.get('status', '-')
        started = format_timestamp(run.get('started_at', '-'))
        samples = run.get('total_samples', 0) or 0
        throughput = run.get('throughput_req_per_sec', 0) or 0
        
        print(f"{run_id:<6} {api:<25} {mode:<10} {payload:<10} {protocol:<8} {status:<10} {started:<20} {samples:<8} {throughput:<12.2f}")


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='List test runs from the metrics database')
    parser.add_argument('--api', help='Filter by API name (e.g., producer-api-java-rest)')
    parser.add_argument('--mode', choices=['smoke', 'full', 'saturation'], help='Filter by test mode')
    parser.add_argument('--payload', help='Filter by payload size (e.g., 4k, 8k, default)')
    parser.add_argument('--limit', type=int, default=50, help='Maximum number of results (default: 50)')
    
    args = parser.parse_args()
    
    list_test_runs(args.api, args.mode, args.payload, args.limit)


if __name__ == '__main__':
    main()
