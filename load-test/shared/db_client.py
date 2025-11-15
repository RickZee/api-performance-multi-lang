#!/usr/bin/env python3
"""
Database Client for Performance Metrics
Handles all database operations for storing and retrieving test metrics
"""
import os
import sys
import psycopg2
from psycopg2.extras import execute_batch, RealDictCursor
from psycopg2.pool import SimpleConnectionPool
from contextlib import contextmanager
from typing import Optional, Dict, List, Any
from datetime import datetime
import json


# Database connection configuration
# When running from host, use localhost:5433 (external port)
# When running from Docker container, use postgres-metrics:5432 (internal)
DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_PORT = int(os.getenv('DB_PORT', '5433'))  # Default to external port for host access

# If DB_HOST is 'postgres-metrics', use internal port 5432
if DB_HOST == 'postgres-metrics':
    DB_PORT = 5432

DB_CONFIG = {
    'host': DB_HOST,
    'port': DB_PORT,
    'database': os.getenv('DB_NAME', 'performance_metrics'),
    'user': os.getenv('DB_USER', 'postgres'),
    'password': os.getenv('DB_PASSWORD', 'password'),
    'connect_timeout': 10
}

# Connection pool (initialized on first use)
_connection_pool: Optional[SimpleConnectionPool] = None


def get_connection_pool():
    """Get or create connection pool"""
    global _connection_pool
    if _connection_pool is None:
        try:
            _connection_pool = SimpleConnectionPool(
                minconn=1,
                maxconn=10,
                **DB_CONFIG
            )
        except Exception as e:
            print(f"Error creating connection pool: {e}", file=sys.stderr)
            raise
    return _connection_pool


@contextmanager
def get_connection():
    """Get a database connection from the pool"""
    pool = get_connection_pool()
    conn = pool.getconn()
    try:
        yield conn
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise
    finally:
        pool.putconn(conn)


def test_connection() -> bool:
    """Test database connection"""
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                return True
    except Exception as e:
        print(f"Database connection test failed: {e}", file=sys.stderr)
        return False


# ============================================================================
# INSERT FUNCTIONS
# ============================================================================

def create_test_run(
    api_name: str,
    test_mode: str,
    payload_size: str,
    protocol: str,
    k6_json_file_path: Optional[str] = None
) -> int:
    """Create a new test run and return its ID"""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO test_runs 
                (api_name, test_mode, payload_size, protocol, started_at, status, k6_json_file_path)
                VALUES (%s, %s, %s, %s, NOW(), 'running', %s)
                RETURNING id
            """, (api_name, test_mode, payload_size, protocol, k6_json_file_path))
            test_run_id = cur.fetchone()[0]
            return test_run_id


def update_test_run_completion(
    test_run_id: int,
    status: str = 'completed',
    duration_seconds: Optional[float] = None
) -> bool:
    """Update test run with completion time and status"""
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                if duration_seconds is not None:
                    cur.execute("""
                        UPDATE test_runs 
                        SET completed_at = NOW(), 
                            status = %s, 
                            duration_seconds = %s
                        WHERE id = %s
                    """, (status, duration_seconds, test_run_id))
                else:
                    cur.execute("""
                        UPDATE test_runs 
                        SET completed_at = NOW(), 
                            status = %s
                        WHERE id = %s
                    """, (status, test_run_id))
                return cur.rowcount > 0
    except Exception as e:
        print(f"Error updating test run {test_run_id}: {e}", file=sys.stderr)
        return False


def insert_performance_metrics(
    test_run_id: int,
    total_samples: int,
    success_samples: int,
    error_samples: int,
    throughput_req_per_sec: float,
    avg_response_time_ms: float,
    min_response_time_ms: float,
    max_response_time_ms: float,
    error_rate_percent: float,
    p50_response_time_ms: Optional[float] = None,
    p90_response_time_ms: Optional[float] = None,
    p95_response_time_ms: Optional[float] = None,
    p99_response_time_ms: Optional[float] = None
) -> bool:
    """Insert performance metrics for a test run"""
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO performance_metrics 
                    (test_run_id, total_samples, success_samples, error_samples,
                     throughput_req_per_sec, avg_response_time_ms, min_response_time_ms,
                     max_response_time_ms, p50_response_time_ms, p90_response_time_ms,
                     p95_response_time_ms, p99_response_time_ms, error_rate_percent)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (test_run_id) DO UPDATE SET
                        total_samples = EXCLUDED.total_samples,
                        success_samples = EXCLUDED.success_samples,
                        error_samples = EXCLUDED.error_samples,
                        throughput_req_per_sec = EXCLUDED.throughput_req_per_sec,
                        avg_response_time_ms = EXCLUDED.avg_response_time_ms,
                        min_response_time_ms = EXCLUDED.min_response_time_ms,
                        max_response_time_ms = EXCLUDED.max_response_time_ms,
                        p50_response_time_ms = EXCLUDED.p50_response_time_ms,
                        p90_response_time_ms = EXCLUDED.p90_response_time_ms,
                        p95_response_time_ms = EXCLUDED.p95_response_time_ms,
                        p99_response_time_ms = EXCLUDED.p99_response_time_ms,
                        error_rate_percent = EXCLUDED.error_rate_percent
                """, (
                    test_run_id, total_samples, success_samples, error_samples,
                    throughput_req_per_sec, avg_response_time_ms, min_response_time_ms,
                    max_response_time_ms, p50_response_time_ms, p90_response_time_ms,
                    p95_response_time_ms, p99_response_time_ms, error_rate_percent
                ))
                return True
    except Exception as e:
        print(f"Error inserting performance metrics: {e}", file=sys.stderr)
        return False


def insert_resource_metrics_batch(
    test_run_id: int,
    metrics: List[Dict[str, Any]]
) -> bool:
    """Insert resource metrics in batch for efficiency"""
    if not metrics:
        return True
    
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                execute_batch(cur, """
                    INSERT INTO resource_metrics 
                    (test_run_id, timestamp, cpu_percent, memory_percent,
                     memory_used_mb, memory_limit_mb, network_io_rx, network_io_tx,
                     block_io_read, block_io_write)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, [
                    (
                        test_run_id,
                        m.get('timestamp'),
                        m.get('cpu_percent', 0),
                        m.get('memory_percent', 0),
                        m.get('memory_used_mb', 0),
                        m.get('memory_limit_mb', 0),
                        m.get('network_io_rx'),
                        m.get('network_io_tx'),
                        m.get('block_io_read'),
                        m.get('block_io_write')
                    )
                    for m in metrics
                ])
                return True
    except Exception as e:
        print(f"Error inserting resource metrics batch: {e}", file=sys.stderr)
        return False


def insert_test_phase(
    test_run_id: int,
    phase_number: int,
    phase_name: Optional[str],
    target_vus: int,
    duration_seconds: int,
    requests_count: int,
    avg_cpu_percent: float,
    max_cpu_percent: float,
    avg_memory_mb: float,
    max_memory_mb: float,
    cpu_percent_per_request: float,
    ram_mb_per_request: float
) -> bool:
    """Insert test phase metrics"""
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO test_phases 
                    (test_run_id, phase_number, phase_name, target_vus, duration_seconds,
                     requests_count, avg_cpu_percent, max_cpu_percent, avg_memory_mb,
                     max_memory_mb, cpu_percent_per_request, ram_mb_per_request)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (test_run_id, phase_number) DO UPDATE SET
                        phase_name = EXCLUDED.phase_name,
                        target_vus = EXCLUDED.target_vus,
                        duration_seconds = EXCLUDED.duration_seconds,
                        requests_count = EXCLUDED.requests_count,
                        avg_cpu_percent = EXCLUDED.avg_cpu_percent,
                        max_cpu_percent = EXCLUDED.max_cpu_percent,
                        avg_memory_mb = EXCLUDED.avg_memory_mb,
                        max_memory_mb = EXCLUDED.max_memory_mb,
                        cpu_percent_per_request = EXCLUDED.cpu_percent_per_request,
                        ram_mb_per_request = EXCLUDED.ram_mb_per_request
                """, (
                    test_run_id, phase_number, phase_name, target_vus, duration_seconds,
                    requests_count, avg_cpu_percent, max_cpu_percent, avg_memory_mb,
                    max_memory_mb, cpu_percent_per_request, ram_mb_per_request
                ))
                return True
    except Exception as e:
        print(f"Error inserting test phase: {e}", file=sys.stderr)
        return False


# ============================================================================
# QUERY FUNCTIONS
# ============================================================================

def get_latest_test_runs(
    api_names: Optional[List[str]] = None,
    test_mode: Optional[str] = None,
    payload_size: Optional[str] = None,
    limit: int = 100
) -> List[Dict[str, Any]]:
    """Get latest test runs with optional filters"""
    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            query = """
                SELECT tr.*, 
                       pm.total_samples, pm.success_samples, pm.error_samples,
                       pm.throughput_req_per_sec, pm.avg_response_time_ms,
                       pm.min_response_time_ms, pm.max_response_time_ms,
                       pm.p50_response_time_ms, pm.p90_response_time_ms,
                       pm.p95_response_time_ms, pm.p99_response_time_ms,
                       pm.error_rate_percent
                FROM test_runs tr
                LEFT JOIN performance_metrics pm ON tr.id = pm.test_run_id
                WHERE 1=1
            """
            params = []
            
            if api_names:
                query += f" AND tr.api_name = ANY(%s)"
                params.append(api_names)
            if test_mode:
                query += " AND tr.test_mode = %s"
                params.append(test_mode)
            if payload_size:
                query += " AND tr.payload_size = %s"
                params.append(payload_size)
            
            query += " ORDER BY tr.started_at DESC LIMIT %s"
            params.append(limit)
            
            cur.execute(query, params)
            return [dict(row) for row in cur.fetchall()]


def get_latest_test_run_per_api(
    test_mode: Optional[str] = None,
    payload_size: Optional[str] = None
) -> Dict[str, Dict[str, Any]]:
    """Get the latest test run for each API"""
    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            query = """
                SELECT DISTINCT ON (tr.api_name)
                    tr.*,
                    pm.total_samples, pm.success_samples, pm.error_samples,
                    pm.throughput_req_per_sec, pm.avg_response_time_ms,
                    pm.min_response_time_ms, pm.max_response_time_ms,
                    pm.p50_response_time_ms, pm.p90_response_time_ms,
                    pm.p95_response_time_ms, pm.p99_response_time_ms,
                    pm.error_rate_percent
                FROM test_runs tr
                LEFT JOIN performance_metrics pm ON tr.id = pm.test_run_id
                WHERE tr.status = 'completed'
            """
            params = []
            
            if test_mode:
                query += " AND tr.test_mode = %s"
                params.append(test_mode)
            if payload_size:
                query += " AND tr.payload_size = %s"
                params.append(payload_size)
            
            query += " ORDER BY tr.api_name, tr.started_at DESC"
            
            cur.execute(query, params)
            results = {}
            for row in cur.fetchall():
                api_name = row['api_name']
                if api_name not in results:
                    results[api_name] = dict(row)
            return results


def get_resource_metrics(
    test_run_id: int,
    start_time: Optional[datetime] = None,
    end_time: Optional[datetime] = None
) -> List[Dict[str, Any]]:
    """Get resource metrics for a test run"""
    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            query = """
                SELECT * FROM resource_metrics
                WHERE test_run_id = %s
            """
            params = [test_run_id]
            
            if start_time:
                query += " AND timestamp >= %s"
                params.append(start_time)
            if end_time:
                query += " AND timestamp <= %s"
                params.append(end_time)
            
            query += " ORDER BY timestamp ASC"
            
            cur.execute(query, params)
            return [dict(row) for row in cur.fetchall()]


def get_resource_metrics_summary(test_run_id: int) -> Optional[Dict[str, Any]]:
    """Get aggregated resource metrics summary for a test run"""
    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT 
                    AVG(cpu_percent) as avg_cpu_percent,
                    MAX(cpu_percent) as max_cpu_percent,
                    AVG(memory_percent) as avg_memory_percent,
                    MAX(memory_percent) as max_memory_percent,
                    AVG(memory_used_mb) as avg_memory_mb,
                    MAX(memory_used_mb) as max_memory_mb,
                    COUNT(*) as sample_count
                FROM resource_metrics
                WHERE test_run_id = %s
            """, (test_run_id,))
            row = cur.fetchone()
            return dict(row) if row else None


def get_test_phases(test_run_id: int) -> List[Dict[str, Any]]:
    """Get all phases for a test run"""
    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT * FROM test_phases
                WHERE test_run_id = %s
                ORDER BY phase_number ASC
            """, (test_run_id,))
            return [dict(row) for row in cur.fetchall()]


def get_all_apis_resource_summary(
    test_mode: Optional[str] = None,
    payload_size: Optional[str] = None
) -> Dict[str, Dict[str, Any]]:
    """Get resource summary for all APIs (latest test run per API)"""
    test_runs = get_latest_test_run_per_api(test_mode, payload_size)
    results = {}
    
    for api_name, test_run in test_runs.items():
        test_run_id = test_run['id']
        resource_summary = get_resource_metrics_summary(test_run_id)
        
        if resource_summary:
            results[api_name] = {
                'test_run_id': test_run_id,
                'api_name': api_name,
                'avg_cpu_percent': float(resource_summary.get('avg_cpu_percent', 0) or 0),
                'max_cpu_percent': float(resource_summary.get('max_cpu_percent', 0) or 0),
                'avg_memory_percent': float(resource_summary.get('avg_memory_percent', 0) or 0),
                'max_memory_percent': float(resource_summary.get('max_memory_percent', 0) or 0),
                'avg_memory_mb': float(resource_summary.get('avg_memory_mb', 0) or 0),
                'max_memory_mb': float(resource_summary.get('max_memory_mb', 0) or 0),
                'sample_count': int(resource_summary.get('sample_count', 0))
            }
    
    return results


# ============================================================================
# MAIN (for testing)
# ============================================================================

def insert_resource_metric_cli(
    test_run_id: int,
    timestamp: str,
    cpu_percent: float,
    memory_percent: float,
    memory_used_mb: float,
    memory_limit_mb: float,
    network_io_rx: Optional[str] = None,
    network_io_tx: Optional[str] = None,
    block_io_read: Optional[str] = None,
    block_io_write: Optional[str] = None
) -> bool:
    """Insert a single resource metric (CLI wrapper)"""
    try:
        from datetime import datetime
        timestamp_dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
    except:
        timestamp_dt = datetime.now()
    
    return insert_resource_metrics_batch(test_run_id, [{
        'timestamp': timestamp_dt,
        'cpu_percent': cpu_percent,
        'memory_percent': memory_percent,
        'memory_used_mb': memory_used_mb,
        'memory_limit_mb': memory_limit_mb,
        'network_io_rx': network_io_rx,
        'network_io_tx': network_io_tx,
        'block_io_read': block_io_read,
        'block_io_write': block_io_write
    }])


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: db_client.py <command> [args...]")
        print("Commands: test, create_test_run, get_latest, insert_resource_metric, insert_performance_metrics, update_test_run_completion")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == 'test':
        if test_connection():
            print("Database connection successful")
            sys.exit(0)
        else:
            print("Database connection failed")
            sys.exit(1)
    elif command == 'create_test_run':
        if len(sys.argv) < 6:
            print("Usage: db_client.py create_test_run <api_name> <test_mode> <payload_size> <protocol> [k6_json_file_path]")
            sys.exit(1)
        k6_json_path = sys.argv[6] if len(sys.argv) > 6 else None
        test_run_id = create_test_run(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], k6_json_path)
        print(f"{test_run_id}")
    elif command == 'get_latest':
        results = get_latest_test_run_per_api()
        print(json.dumps(results, indent=2, default=str))
    elif command == 'get_all_apis_resource_summary':
        test_mode = sys.argv[2] if len(sys.argv) > 2 else None
        payload_size = sys.argv[3] if len(sys.argv) > 3 else None
        results = get_all_apis_resource_summary(test_mode, payload_size)
        print(json.dumps(results, indent=2, default=str))
    elif command == 'insert_resource_metric':
        if len(sys.argv) < 8:
            print("Usage: db_client.py insert_resource_metric <test_run_id> <timestamp> <cpu_percent> <memory_percent> <memory_used_mb> <memory_limit_mb> [network_io_rx] [network_io_tx] [block_io_read] [block_io_write]")
            sys.exit(1)
        success = insert_resource_metric_cli(
            int(sys.argv[2]),
            sys.argv[3],
            float(sys.argv[4]),
            float(sys.argv[5]),
            float(sys.argv[6]),
            float(sys.argv[7]),
            sys.argv[8] if len(sys.argv) > 8 else None,
            sys.argv[9] if len(sys.argv) > 9 else None,
            sys.argv[10] if len(sys.argv) > 10 else None,
            sys.argv[11] if len(sys.argv) > 11 else None
        )
        sys.exit(0 if success else 1)
    elif command == 'insert_performance_metrics':
        if len(sys.argv) < 10:
            print("Usage: db_client.py insert_performance_metrics <test_run_id> <total_samples> <success_samples> <error_samples> <throughput> <avg_response> <min_response> <max_response> <error_rate> [p50] [p90] [p95] [p99]")
            sys.exit(1)
        success = insert_performance_metrics(
            int(sys.argv[2]),
            int(sys.argv[3]),
            int(sys.argv[4]),
            int(sys.argv[5]),
            float(sys.argv[6]),
            float(sys.argv[7]),
            float(sys.argv[8]),
            float(sys.argv[9]),
            float(sys.argv[10]),
            float(sys.argv[11]) if len(sys.argv) > 11 and sys.argv[11] else None,
            float(sys.argv[12]) if len(sys.argv) > 12 and sys.argv[12] else None,
            float(sys.argv[13]) if len(sys.argv) > 13 and sys.argv[13] else None,
            float(sys.argv[14]) if len(sys.argv) > 14 and sys.argv[14] else None
        )
        sys.exit(0 if success else 1)
    elif command == 'update_test_run_completion':
        if len(sys.argv) < 3:
            print("Usage: db_client.py update_test_run_completion <test_run_id> <status> [duration_seconds]")
            sys.exit(1)
        duration = float(sys.argv[4]) if len(sys.argv) > 4 else None
        success = update_test_run_completion(int(sys.argv[2]), sys.argv[3], duration)
        sys.exit(0 if success else 1)
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

