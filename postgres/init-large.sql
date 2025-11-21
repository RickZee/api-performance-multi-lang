-- Initialize PostgreSQL database for car entities
-- This script runs when the PostgreSQL container starts for the first time

-- Enable JSONB support (should be enabled by default in PostgreSQL 9.4+)
-- No specific action needed as JSONB is built-in

-- Create the car_entities table
CREATE TABLE IF NOT EXISTS car_entities (
    id VARCHAR(255) PRIMARY KEY,
    entity_type VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE,
    data JSONB NOT NULL
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_car_entities_entity_type ON car_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_car_entities_created_at ON car_entities(created_at);
CREATE INDEX IF NOT EXISTS idx_car_entities_data_gin ON car_entities USING GIN (data);

-- Grant permissions
GRANT ALL PRIVILEGES ON TABLE car_entities TO postgres;

-- Enable pg_stat_statements extension for query performance tracking
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Create a view for query performance analysis
CREATE OR REPLACE VIEW query_performance_summary AS
SELECT 
    queryid,
    LEFT(query, 100) as query_preview,
    calls,
    total_exec_time,
    mean_exec_time,
    min_exec_time,
    max_exec_time,
    stddev_exec_time,
    rows,
    100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0) AS cache_hit_ratio
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC;

-- Grant permissions
GRANT SELECT ON query_performance_summary TO postgres;

-- Log initialization
DO $$
BEGIN
    RAISE NOTICE 'Car entities database initialized successfully';
    RAISE NOTICE 'pg_stat_statements extension enabled for query performance tracking';
END $$;
