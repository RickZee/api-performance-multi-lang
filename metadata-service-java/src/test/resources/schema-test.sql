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
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    approved_at TIMESTAMP,
    approved_by VARCHAR(255),
    deployed_at TIMESTAMP,
    deployment_error TEXT,
    flink_statement_ids TEXT
);

