CREATE TABLE IF NOT EXISTS car_entities (
    id VARCHAR(255) PRIMARY KEY,
    entity_type VARCHAR(255) NOT NULL,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    data CLOB NOT NULL
);

CREATE TABLE IF NOT EXISTS simple_events (
    id VARCHAR(255) PRIMARY KEY,
    event_name VARCHAR(255) NOT NULL,
    created_date TIMESTAMP,
    saved_date TIMESTAMP,
    event_type VARCHAR(255)
);

-- Basic indexes
CREATE INDEX IF NOT EXISTS idx_car_entities_entity_type ON car_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_simple_events_event_name ON simple_events(event_name);
