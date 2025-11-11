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

-- Log initialization
DO $$
BEGIN
    RAISE NOTICE 'Car entities database initialized successfully';
END $$;
