-- Database Schema for Event Storage System
-- Reusable across all APIs
-- Database: Aurora RDS PostgreSQL
-- 
-- NOTE: This schema is idempotent - safe to run multiple times without data loss
-- Uses IF NOT EXISTS to avoid dropping/recreating tables

-- ============================================================================
-- Business Events Table
-- Stores complete events with eventHeader fields as columns and full event JSON
-- ============================================================================
CREATE TABLE IF NOT EXISTS business_events (
    id VARCHAR(255) PRIMARY KEY,  -- from eventHeader.uuid
    event_name VARCHAR(255) NOT NULL,  -- from eventHeader.eventName
    event_type VARCHAR(255),  -- from eventHeader.eventType
    created_date TIMESTAMP WITH TIME ZONE,  -- from eventHeader.createdDate
    saved_date TIMESTAMP WITH TIME ZONE,  -- from eventHeader.savedDate
    event_data JSONB NOT NULL  -- entire event JSON including eventHeader + entities
);

-- Indexes for business_events
CREATE INDEX IF NOT EXISTS idx_business_events_event_type ON business_events(event_type);
CREATE INDEX IF NOT EXISTS idx_business_events_created_date ON business_events(created_date);

-- ============================================================================
-- Event Headers Table
-- Stores event header data with hybrid structure (relational columns + JSONB)
-- Foreign key to business_events for referential integrity
-- ============================================================================
CREATE TABLE IF NOT EXISTS event_headers (
    id VARCHAR(255) PRIMARY KEY,  -- from eventHeader.uuid (same as business_events.id)
    event_name VARCHAR(255) NOT NULL,  -- from eventHeader.eventName
    event_type VARCHAR(255),  -- from eventHeader.eventType
    created_date TIMESTAMP WITH TIME ZONE,  -- from eventHeader.createdDate
    saved_date TIMESTAMP WITH TIME ZONE,  -- from eventHeader.savedDate
    header_data JSONB NOT NULL,  -- full eventHeader JSON
    CONSTRAINT fk_event_headers_business_events 
        FOREIGN KEY (id) REFERENCES business_events(id) 
        ON DELETE CASCADE
);

-- Indexes for event_headers
CREATE INDEX IF NOT EXISTS idx_event_headers_event_type ON event_headers(event_type);
CREATE INDEX IF NOT EXISTS idx_event_headers_created_date ON event_headers(created_date);

-- ============================================================================
-- Entity Tables
-- Each entity type has its own table with entityHeader fields as columns
-- and entity data (without entityHeader) stored as JSONB
-- ============================================================================

-- Car Entities Table
CREATE TABLE IF NOT EXISTS car_entities (
    entity_id VARCHAR(255) PRIMARY KEY,  -- from entityHeader.entityId
    entity_type VARCHAR(255) NOT NULL,  -- from entityHeader.entityType
    created_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.createdAt
    updated_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.updatedAt
    entity_data JSONB NOT NULL,  -- entity object without entityHeader
    event_id VARCHAR(255),  -- foreign key to event_headers.id (tracks which event last updated this entity)
    CONSTRAINT fk_car_entities_event_headers 
        FOREIGN KEY (event_id) REFERENCES event_headers(id) 
        ON DELETE SET NULL
);

-- Indexes for car_entities
CREATE INDEX IF NOT EXISTS idx_car_entities_entity_type ON car_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_car_entities_created_at ON car_entities(created_at);
CREATE INDEX IF NOT EXISTS idx_car_entities_updated_at ON car_entities(updated_at);
CREATE INDEX IF NOT EXISTS idx_car_entities_event_id ON car_entities(event_id);

-- Loan Entities Table
CREATE TABLE IF NOT EXISTS loan_entities (
    entity_id VARCHAR(255) PRIMARY KEY,  -- from entityHeader.entityId
    entity_type VARCHAR(255) NOT NULL,  -- from entityHeader.entityType
    created_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.createdAt
    updated_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.updatedAt
    entity_data JSONB NOT NULL,  -- entity object without entityHeader
    event_id VARCHAR(255),  -- foreign key to event_headers.id (tracks which event last updated this entity)
    CONSTRAINT fk_loan_entities_event_headers 
        FOREIGN KEY (event_id) REFERENCES event_headers(id) 
        ON DELETE SET NULL
);

-- Indexes for loan_entities
CREATE INDEX IF NOT EXISTS idx_loan_entities_entity_type ON loan_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_loan_entities_created_at ON loan_entities(created_at);
CREATE INDEX IF NOT EXISTS idx_loan_entities_updated_at ON loan_entities(updated_at);
CREATE INDEX IF NOT EXISTS idx_loan_entities_event_id ON loan_entities(event_id);

-- Loan Payment Entities Table
CREATE TABLE IF NOT EXISTS loan_payment_entities (
    entity_id VARCHAR(255) PRIMARY KEY,  -- from entityHeader.entityId
    entity_type VARCHAR(255) NOT NULL,  -- from entityHeader.entityType
    created_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.createdAt
    updated_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.updatedAt
    entity_data JSONB NOT NULL,  -- entity object without entityHeader
    event_id VARCHAR(255),  -- foreign key to event_headers.id (tracks which event last updated this entity)
    CONSTRAINT fk_loan_payment_entities_event_headers 
        FOREIGN KEY (event_id) REFERENCES event_headers(id) 
        ON DELETE SET NULL
);

-- Indexes for loan_payment_entities
CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_entity_type ON loan_payment_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_created_at ON loan_payment_entities(created_at);
CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_updated_at ON loan_payment_entities(updated_at);
CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_event_id ON loan_payment_entities(event_id);

-- Service Record Entities Table
CREATE TABLE IF NOT EXISTS service_record_entities (
    entity_id VARCHAR(255) PRIMARY KEY,  -- from entityHeader.entityId
    entity_type VARCHAR(255) NOT NULL,  -- from entityHeader.entityType
    created_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.createdAt
    updated_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.updatedAt
    entity_data JSONB NOT NULL,  -- entity object without entityHeader
    event_id VARCHAR(255),  -- foreign key to event_headers.id (tracks which event last updated this entity)
    CONSTRAINT fk_service_record_entities_event_headers 
        FOREIGN KEY (event_id) REFERENCES event_headers(id) 
        ON DELETE SET NULL
);

-- Indexes for service_record_entities
CREATE INDEX IF NOT EXISTS idx_service_record_entities_entity_type ON service_record_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_service_record_entities_created_at ON service_record_entities(created_at);
CREATE INDEX IF NOT EXISTS idx_service_record_entities_updated_at ON service_record_entities(updated_at);
CREATE INDEX IF NOT EXISTS idx_service_record_entities_event_id ON service_record_entities(event_id);
