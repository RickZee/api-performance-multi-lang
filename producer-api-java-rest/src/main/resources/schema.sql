DROP TABLE IF EXISTS car_entities CASCADE;
DROP TABLE IF EXISTS simple_events CASCADE;

CREATE TABLE car_entities (
    id VARCHAR(255) PRIMARY KEY,
    entity_type VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE,
    data TEXT NOT NULL
);

CREATE TABLE simple_events (
    id VARCHAR(255) PRIMARY KEY,
    event_name VARCHAR(255) NOT NULL,
    created_date TIMESTAMP WITH TIME ZONE,
    saved_date TIMESTAMP WITH TIME ZONE,
    event_type VARCHAR(255)
);

-- Basic indexes
CREATE INDEX IF NOT EXISTS idx_car_entities_entity_type ON car_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_simple_events_event_name ON simple_events(event_name);
