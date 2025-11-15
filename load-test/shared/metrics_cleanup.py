#!/usr/bin/env python3
"""
Cleanup Old Metrics
Remove old test runs and their associated metrics from the database
"""
import sys
import os
from datetime import datetime, timedelta
from pathlib import Path

# Add script directory to path
script_dir = Path(__file__).parent
sys.path.insert(0, str(script_dir))

from db_client import get_connection, test_connection


def cleanup_old_runs(days_old=30, dry_run=True):
    """Remove test runs older than specified days"""
    if not test_connection():
        print("Error: Cannot connect to database.", file=sys.stderr)
        sys.exit(1)
    
    cutoff_date = datetime.now() - timedelta(days=days_old)
    
    with get_connection() as conn:
        with conn.cursor() as cur:
            # Count old runs
            cur.execute("""
                SELECT COUNT(*) FROM test_runs
                WHERE started_at < %s
            """, (cutoff_date,))
            count = cur.fetchone()[0]
            
            if count == 0:
                print(f"No test runs older than {days_old} days found.")
                return
            
            print(f"Found {count} test run(s) older than {days_old} days (before {cutoff_date.strftime('%Y-%m-%d %H:%M:%S')})")
            
            if dry_run:
                print("\nDRY RUN - No data will be deleted.")
                print("Run with --execute to actually delete the data.")
                
                # Show some examples
                cur.execute("""
                    SELECT id, api_name, test_mode, started_at
                    FROM test_runs
                    WHERE started_at < %s
                    ORDER BY started_at ASC
                    LIMIT 10
                """, (cutoff_date,))
                
                print("\nExample runs that would be deleted:")
                print(f"{'ID':<6} {'API':<25} {'Mode':<10} {'Started':<20}")
                print("-" * 70)
                for row in cur.fetchall():
                    print(f"{row[0]:<6} {row[1]:<25} {row[2]:<10} {row[3]}")
            else:
                # Actually delete (CASCADE will handle related records)
                cur.execute("""
                    DELETE FROM test_runs
                    WHERE started_at < %s
                """, (cutoff_date,))
                deleted = cur.rowcount
                print(f"\nDeleted {deleted} test run(s) and all associated metrics.")


def cleanup_by_count(keep_count=100, dry_run=True):
    """Keep only the N most recent test runs per API"""
    if not test_connection():
        print("Error: Cannot connect to database.", file=sys.stderr)
        sys.exit(1)
    
    with get_connection() as conn:
        with conn.cursor() as cur:
            # Get all APIs
            cur.execute("SELECT DISTINCT api_name FROM test_runs")
            apis = [row[0] for row in cur.fetchall()]
            
            total_to_delete = 0
            
            for api_name in apis:
                # Count runs for this API
                cur.execute("""
                    SELECT COUNT(*) FROM test_runs
                    WHERE api_name = %s
                """, (api_name,))
                total = cur.fetchone()[0]
                
                if total <= keep_count:
                    continue
                
                # Get IDs to delete (oldest ones)
                cur.execute("""
                    SELECT id FROM test_runs
                    WHERE api_name = %s
                    ORDER BY started_at DESC
                    OFFSET %s
                """, (api_name, keep_count))
                
                ids_to_delete = [row[0] for row in cur.fetchall()]
                total_to_delete += len(ids_to_delete)
                
                if dry_run:
                    print(f"{api_name}: {total} runs, would keep {keep_count}, delete {len(ids_to_delete)}")
                else:
                    # Delete old runs for this API
                    for run_id in ids_to_delete:
                        cur.execute("DELETE FROM test_runs WHERE id = %s", (run_id,))
            
            if total_to_delete == 0:
                print("No test runs need to be deleted.")
            elif dry_run:
                print(f"\nDRY RUN - Would delete {total_to_delete} test run(s) total.")
                print("Run with --execute to actually delete the data.")
            else:
                print(f"\nDeleted {total_to_delete} test run(s) total.")


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Cleanup old test runs from the metrics database')
    parser.add_argument('--days', type=int, default=30, help='Delete runs older than N days (default: 30)')
    parser.add_argument('--keep', type=int, help='Keep only N most recent runs per API (alternative to --days)')
    parser.add_argument('--execute', action='store_true', help='Actually delete data (default is dry-run)')
    
    args = parser.parse_args()
    
    if args.keep:
        cleanup_by_count(args.keep, dry_run=not args.execute)
    else:
        cleanup_old_runs(args.days, dry_run=not args.execute)


if __name__ == '__main__':
    main()

