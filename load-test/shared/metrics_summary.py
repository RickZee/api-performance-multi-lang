#!/usr/bin/env python3
"""
Metrics Summary
Display summary statistics about test runs in the database
"""
import sys
import os
from datetime import datetime
from pathlib import Path

# Add script directory to path
script_dir = Path(__file__).parent
sys.path.insert(0, str(script_dir))

from db_client import get_connection, test_connection


def show_summary():
    """Show summary statistics"""
    if not test_connection():
        print("Error: Cannot connect to database.", file=sys.stderr)
        sys.exit(1)
    
    with get_connection() as conn:
        with conn.cursor() as cur:
            # Total test runs
            cur.execute("SELECT COUNT(*) FROM test_runs")
            total_runs = cur.fetchone()[0]
            
            # Runs by status
            cur.execute("""
                SELECT status, COUNT(*) 
                FROM test_runs 
                GROUP BY status
            """)
            status_counts = dict(cur.fetchall())
            
            # Runs by API
            cur.execute("""
                SELECT api_name, COUNT(*) 
                FROM test_runs 
                GROUP BY api_name
                ORDER BY api_name
            """)
            api_counts = dict(cur.fetchall())
            
            # Runs by test mode
            cur.execute("""
                SELECT test_mode, COUNT(*) 
                FROM test_runs 
                GROUP BY test_mode
            """)
            mode_counts = dict(cur.fetchall())
            
            # Oldest and newest runs
            cur.execute("""
                SELECT MIN(started_at), MAX(started_at)
                FROM test_runs
            """)
            oldest, newest = cur.fetchone()
            
            # Total resource metrics samples
            cur.execute("SELECT COUNT(*) FROM resource_metrics")
            total_resource_samples = cur.fetchone()[0]
            
            # Total performance metrics records
            cur.execute("SELECT COUNT(*) FROM performance_metrics")
            total_perf_records = cur.fetchone()[0]
            
            # Print summary
            print("\n" + "=" * 60)
            print("METRICS DATABASE SUMMARY")
            print("=" * 60)
            print(f"\nTotal Test Runs: {total_runs}")
            print(f"Total Resource Metrics Samples: {total_resource_samples:,}")
            print(f"Total Performance Metrics Records: {total_perf_records}")
            
            if oldest and newest:
                print(f"\nDate Range:")
                print(f"  Oldest: {oldest}")
                print(f"  Newest: {newest}")
            
            print(f"\nTest Runs by Status:")
            for status, count in sorted(status_counts.items()):
                print(f"  {status}: {count}")
            
            print(f"\nTest Runs by API:")
            for api, count in sorted(api_counts.items()):
                print(f"  {api}: {count}")
            
            print(f"\nTest Runs by Mode:")
            for mode, count in sorted(mode_counts.items()):
                print(f"  {mode}: {count}")
            
            print("\n" + "=" * 60 + "\n")


def show_api_comparison():
    """Show comparison of latest test runs for each API"""
    if not test_connection():
        print("Error: Cannot connect to database.", file=sys.stderr)
        sys.exit(1)
    
    from db_client import get_latest_test_run_per_api
    
    latest_runs = get_latest_test_run_per_api()
    
    if not latest_runs:
        print("No test runs found.")
        return
    
    print("\n" + "=" * 100)
    print("LATEST TEST RUNS BY API")
    print("=" * 100)
    print(f"{'API':<25} {'Mode':<10} {'Payload':<10} {'Status':<10} {'Samples':<8} {'Throughput':<12} {'Avg Resp':<10} {'Error %':<8}")
    print("-" * 100)
    
    for api_name, run in sorted(latest_runs.items()):
        mode = run.get('test_mode', '-')
        payload = run.get('payload_size', '-')
        status = run.get('status', '-')
        samples = run.get('total_samples', 0) or 0
        throughput = run.get('throughput_req_per_sec', 0) or 0
        avg_resp = run.get('avg_response_time_ms', 0) or 0
        error_rate = run.get('error_rate_percent', 0) or 0
        
        print(f"{api_name:<25} {mode:<10} {payload:<10} {status:<10} {samples:<8} {throughput:<12.2f} {avg_resp:<10.2f} {error_rate:<8.2f}")
    
    print("=" * 100 + "\n")


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Show summary statistics about the metrics database')
    parser.add_argument('--comparison', action='store_true', help='Show latest test run comparison by API')
    
    args = parser.parse_args()
    
    if args.comparison:
        show_api_comparison()
    else:
        show_summary()


if __name__ == '__main__':
    main()

