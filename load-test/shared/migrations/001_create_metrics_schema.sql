-- Performance Metrics Database Schema
-- This schema stores test run metadata, performance metrics, resource utilization, and phase data

-- Test Runs Table
-- Stores metadata for each test execution
CREATE TABLE IF NOT EXISTS test_runs (
    id BIGSERIAL PRIMARY KEY,
    api_name VARCHAR(100) NOT NULL,
    test_mode VARCHAR(50) NOT NULL,
    payload_size VARCHAR(20) NOT NULL DEFAULT 'default',
    protocol VARCHAR(10) NOT NULL,
    started_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP,
    duration_seconds NUMERIC(10, 2),
    status VARCHAR(20) NOT NULL DEFAULT 'running',
    k6_json_file_path TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Performance Metrics Table
-- Stores aggregated performance metrics per test run
CREATE TABLE IF NOT EXISTS performance_metrics (
    id BIGSERIAL PRIMARY KEY,
    test_run_id BIGINT NOT NULL REFERENCES test_runs(id) ON DELETE CASCADE,
    total_samples INTEGER NOT NULL DEFAULT 0,
    success_samples INTEGER NOT NULL DEFAULT 0,
    error_samples INTEGER NOT NULL DEFAULT 0,
    throughput_req_per_sec NUMERIC(10, 2) NOT NULL DEFAULT 0,
    avg_response_time_ms NUMERIC(10, 2) NOT NULL DEFAULT 0,
    min_response_time_ms NUMERIC(10, 2) NOT NULL DEFAULT 0,
    max_response_time_ms NUMERIC(10, 2) NOT NULL DEFAULT 0,
    p50_response_time_ms NUMERIC(10, 2),
    p90_response_time_ms NUMERIC(10, 2),
    p95_response_time_ms NUMERIC(10, 2),
    p99_response_time_ms NUMERIC(10, 2),
    error_rate_percent NUMERIC(5, 2) NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(test_run_id)
);

-- Resource Metrics Table
-- Stores time-series resource utilization data
CREATE TABLE IF NOT EXISTS resource_metrics (
    id BIGSERIAL PRIMARY KEY,
    test_run_id BIGINT NOT NULL REFERENCES test_runs(id) ON DELETE CASCADE,
    timestamp TIMESTAMP NOT NULL,
    cpu_percent NUMERIC(5, 2) NOT NULL DEFAULT 0,
    memory_percent NUMERIC(5, 2) NOT NULL DEFAULT 0,
    memory_used_mb NUMERIC(10, 2) NOT NULL DEFAULT 0,
    memory_limit_mb NUMERIC(10, 2) NOT NULL DEFAULT 0,
    network_io_rx TEXT,
    network_io_tx TEXT,
    block_io_read TEXT,
    block_io_write TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Test Phases Table
-- Stores phase-specific metrics for multi-phase tests
CREATE TABLE IF NOT EXISTS test_phases (
    id BIGSERIAL PRIMARY KEY,
    test_run_id BIGINT NOT NULL REFERENCES test_runs(id) ON DELETE CASCADE,
    phase_number INTEGER NOT NULL,
    phase_name VARCHAR(100),
    target_vus INTEGER NOT NULL DEFAULT 0,
    duration_seconds INTEGER NOT NULL DEFAULT 0,
    requests_count INTEGER NOT NULL DEFAULT 0,
    avg_cpu_percent NUMERIC(5, 2) NOT NULL DEFAULT 0,
    max_cpu_percent NUMERIC(5, 2) NOT NULL DEFAULT 0,
    avg_memory_mb NUMERIC(10, 2) NOT NULL DEFAULT 0,
    max_memory_mb NUMERIC(10, 2) NOT NULL DEFAULT 0,
    cpu_percent_per_request NUMERIC(10, 4) NOT NULL DEFAULT 0,
    ram_mb_per_request NUMERIC(10, 4) NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(test_run_id, phase_number)
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_test_runs_api_mode_payload ON test_runs(api_name, test_mode, payload_size);
CREATE INDEX IF NOT EXISTS idx_test_runs_status ON test_runs(status);
CREATE INDEX IF NOT EXISTS idx_test_runs_started_at ON test_runs(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_performance_metrics_test_run_id ON performance_metrics(test_run_id);
CREATE INDEX IF NOT EXISTS idx_resource_metrics_test_run_id ON resource_metrics(test_run_id);
CREATE INDEX IF NOT EXISTS idx_resource_metrics_timestamp ON resource_metrics(test_run_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_test_phases_test_run_id ON test_phases(test_run_id);
CREATE INDEX IF NOT EXISTS idx_test_phases_phase_number ON test_phases(test_run_id, phase_number);

-- Comments for documentation
COMMENT ON TABLE test_runs IS 'Stores metadata for each test execution';
COMMENT ON TABLE performance_metrics IS 'Stores aggregated performance metrics per test run';
COMMENT ON TABLE resource_metrics IS 'Stores time-series resource utilization data';
COMMENT ON TABLE test_phases IS 'Stores phase-specific metrics for multi-phase tests';
