DROP TABLE IF EXISTS car_entities CASCADE;

CREATE TABLE car_entities (
    id VARCHAR(255) PRIMARY KEY,
    entity_type VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE,
    data TEXT NOT NULL
);

-- Basic indexes
CREATE INDEX IF NOT EXISTS idx_car_entities_entity_type ON car_entities(entity_type);
