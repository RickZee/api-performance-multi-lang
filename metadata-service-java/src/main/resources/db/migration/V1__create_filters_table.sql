-- Create filters table for storing filter configurations
CREATE TABLE IF NOT EXISTS filters (
    id VARCHAR(255) PRIMARY KEY,
    schema_version VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    consumer_id VARCHAR(255),
    output_topic VARCHAR(255) NOT NULL,
    conditions TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT true,
    condition_logic VARCHAR(10) NOT NULL DEFAULT 'AND',
    status VARCHAR(50) NOT NULL DEFAULT 'pending_approval',
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    approved_at TIMESTAMP WITH TIME ZONE,
    approved_by VARCHAR(255),
    deployed_at TIMESTAMP WITH TIME ZONE,
    deployment_error TEXT,
    flink_statement_ids TEXT
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_filters_schema_version ON filters(schema_version);
CREATE INDEX IF NOT EXISTS idx_filters_status ON filters(status);
CREATE INDEX IF NOT EXISTS idx_filters_enabled ON filters(enabled);
CREATE INDEX IF NOT EXISTS idx_filters_schema_version_enabled ON filters(schema_version, enabled);
CREATE INDEX IF NOT EXISTS idx_filters_schema_version_status ON filters(schema_version, status);

-- Add comment to table
COMMENT ON TABLE filters IS 'Stores filter configurations for event routing with schema version association';

