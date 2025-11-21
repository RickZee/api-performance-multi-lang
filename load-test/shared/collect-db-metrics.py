#!/usr/bin/env python3
"""
Database Query Metrics Collector
Collects query performance metrics from pg_stat_statements for a test run
"""

import os
import sys
import psycopg2
from psycopg2.extras import RealDictCursor
from typing import List, Dict, Optional
from datetime import datetime
import json


# Database connection configuration for the application database (car_entities)
APP_DB_CONFIG = {
    'host': os.getenv('APP_DB_HOST', 'localhost'),
    'port': int(os.getenv('APP_DB_PORT', '5432')),
    'database': os.getenv('APP_DB_NAME', 'car_entities'),
    'user': os.getenv('APP_DB_USER', 'postgres'),
    'password': os.getenv('APP_DB_PASSWORD', 'password'),
    'connect_timeout': 10
}

# If running from Docker, use internal hostname
# Check if we're in a Docker container or if DB_HOST is set
if os.getenv('DB_HOST') == 'postgres-large' or os.path.exists('/.dockerenv'):
    APP_DB_CONFIG['host'] = os.getenv('APP_DB_HOST', 'postgres-large')
    APP_DB_CONFIG['port'] = int(os.getenv('APP_DB_PORT', '5432'))


def get_top_queries(limit: int = 20) -> List[Dict]:
    """Get top N queries by total execution time from pg_stat_statements"""
    try:
        conn = psycopg2.connect(**APP_DB_CONFIG)
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT 
                    queryid,
                    LEFT(query, 500) as query_text,
                    calls,
                    total_exec_time,
                    mean_exec_time,
                    min_exec_time,
                    max_exec_time,
                    stddev_exec_time,
                    rows,
                    shared_blks_hit,
                    shared_blks_read,
                    CASE 
                        WHEN (shared_blks_hit + shared_blks_read) > 0 
                        THEN 100.0 * shared_blks_hit / (shared_blks_hit + shared_blks_read)
                        ELSE 0
                    END AS cache_hit_ratio
                FROM pg_stat_statements
                WHERE query NOT LIKE '%pg_stat_statements%'
                  AND query NOT LIKE '%query_performance_summary%'
                ORDER BY total_exec_time DESC
                LIMIT %s
            """, (limit,))
            
            queries = []
            for row in cur.fetchall():
                queries.append(dict(row))
            
            conn.close()
            return queries
    except Exception as e:
        print(f"Error collecting DB query metrics: {e}", file=sys.stderr)
        return []


def get_connection_pool_stats() -> Dict:
    """Get connection pool statistics from pg_stat_activity"""
    try:
        conn = psycopg2.connect(**APP_DB_CONFIG)
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT 
                    COUNT(*) as total_connections,
                    COUNT(*) FILTER (WHERE state = 'active') as active_connections,
                    COUNT(*) FILTER (WHERE state = 'idle') as idle_connections,
                    COUNT(*) FILTER (WHERE state = 'idle in transaction') as idle_in_transaction,
                    COUNT(*) FILTER (WHERE wait_event_type IS NOT NULL) as waiting_connections
                FROM pg_stat_activity
                WHERE datname = %s
            """, (APP_DB_CONFIG['database'],))
            
            result = cur.fetchone()
            conn.close()
            return dict(result) if result else {}
    except Exception as e:
        print(f"Error collecting connection pool stats: {e}", file=sys.stderr)
        return {}


def reset_pg_stat_statements():
    """Reset pg_stat_statements to start fresh for a new test"""
    try:
        conn = psycopg2.connect(**APP_DB_CONFIG)
        with conn.cursor() as cur:
            cur.execute("SELECT pg_stat_statements_reset()")
            conn.commit()
            conn.close()
            return True
    except Exception as e:
        print(f"Error resetting pg_stat_statements: {e}", file=sys.stderr)
        return False


def collect_db_metrics_snapshot(test_run_id: Optional[int] = None) -> Dict:
    """Collect a snapshot of DB metrics for a test run"""
    timestamp = datetime.now()
    
    try:
        top_queries = get_top_queries(limit=50)
        pool_stats = get_connection_pool_stats()
        
        return {
            'timestamp': timestamp.isoformat(),
            'test_run_id': test_run_id,
            'top_queries': top_queries,
            'connection_pool_stats': pool_stats,
            'total_queries_tracked': len(top_queries)
        }
    except Exception as e:
        print(f"Error collecting DB metrics snapshot: {e}", file=sys.stderr)
        return {
            'timestamp': timestamp.isoformat(),
            'test_run_id': test_run_id,
            'top_queries': [],
            'connection_pool_stats': {},
            'total_queries_tracked': 0,
            'error': str(e)
        }


def main():
    """Main entry point for command-line usage"""
    if len(sys.argv) < 2:
        print("Usage: collect-db-metrics.py <action> [test_run_id]")
        print("Actions: snapshot, reset, top-queries")
        sys.exit(1)
    
    action = sys.argv[1]
    test_run_id = int(sys.argv[2]) if len(sys.argv) > 2 else None
    
    if action == 'snapshot':
        metrics = collect_db_metrics_snapshot(test_run_id)
        print(json.dumps(metrics, indent=2, default=str))
    elif action == 'reset':
        if reset_pg_stat_statements():
            print("pg_stat_statements reset successfully")
        else:
            print("Failed to reset pg_stat_statements", file=sys.stderr)
            sys.exit(1)
    elif action == 'top-queries':
        queries = get_top_queries(limit=20)
        print(json.dumps(queries, indent=2, default=str))
    else:
        print(f"Unknown action: {action}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()

