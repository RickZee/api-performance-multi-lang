-- Migration: Add Database Query Metrics Tables
-- This migration adds tables to store database query performance metrics
-- collected from pg_stat_statements during test runs

-- Database Query Metrics Snapshot Table
-- Stores snapshots of top queries from pg_stat_statements for each test run
CREATE TABLE IF NOT EXISTS db_query_metrics_snapshots (
    id BIGSERIAL PRIMARY KEY,
    test_run_id BIGINT NOT NULL REFERENCES test_runs(id) ON DELETE CASCADE,
    snapshot_timestamp TIMESTAMP NOT NULL,
    total_queries_tracked INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Database Query Details Table
-- Stores individual query performance metrics from pg_stat_statements
CREATE TABLE IF NOT EXISTS db_query_details (
    id BIGSERIAL PRIMARY KEY,
    snapshot_id BIGINT NOT NULL REFERENCES db_query_metrics_snapshots(id) ON DELETE CASCADE,
    queryid BIGINT NOT NULL,
    query_text TEXT NOT NULL,
    calls BIGINT NOT NULL DEFAULT 0,
    total_exec_time_ms NUMERIC(12, 2) NOT NULL DEFAULT 0,
    mean_exec_time_ms NUMERIC(12, 2) NOT NULL DEFAULT 0,
    min_exec_time_ms NUMERIC(12, 2) NOT NULL DEFAULT 0,
    max_exec_time_ms NUMERIC(12, 2) NOT NULL DEFAULT 0,
    stddev_exec_time_ms NUMERIC(12, 2),
    rows_processed BIGINT NOT NULL DEFAULT 0,
    shared_blks_hit BIGINT NOT NULL DEFAULT 0,
    shared_blks_read BIGINT NOT NULL DEFAULT 0,
    cache_hit_ratio NUMERIC(5, 2),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Connection Pool Statistics Table
-- Stores connection pool statistics at the time of snapshot
CREATE TABLE IF NOT EXISTS db_connection_pool_stats (
    id BIGSERIAL PRIMARY KEY,
    snapshot_id BIGINT NOT NULL REFERENCES db_query_metrics_snapshots(id) ON DELETE CASCADE,
    total_connections INTEGER NOT NULL DEFAULT 0,
    active_connections INTEGER NOT NULL DEFAULT 0,
    idle_connections INTEGER NOT NULL DEFAULT 0,
    idle_in_transaction INTEGER NOT NULL DEFAULT 0,
    waiting_connections INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_db_query_metrics_snapshots_test_run_id 
    ON db_query_metrics_snapshots(test_run_id);
CREATE INDEX IF NOT EXISTS idx_db_query_metrics_snapshots_timestamp 
    ON db_query_metrics_snapshots(snapshot_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_db_query_details_snapshot_id 
    ON db_query_details(snapshot_id);
CREATE INDEX IF NOT EXISTS idx_db_query_details_total_exec_time 
    ON db_query_details(snapshot_id, total_exec_time_ms DESC);
CREATE INDEX IF NOT EXISTS idx_db_connection_pool_stats_snapshot_id 
    ON db_connection_pool_stats(snapshot_id);

-- Comments for documentation
COMMENT ON TABLE db_query_metrics_snapshots IS 'Stores snapshots of database query metrics for each test run';
COMMENT ON TABLE db_query_details IS 'Stores individual query performance metrics from pg_stat_statements';
COMMENT ON TABLE db_connection_pool_stats IS 'Stores connection pool statistics at snapshot time';
