-- Database Schema for Event Storage System - DSQL Compatible Version
-- Database: Amazon Aurora DSQL
-- 
-- NOTE: DSQL has significant limitations compared to regular PostgreSQL:
-- - Does not support JSONB (using TEXT instead)
-- - Does not support CREATE DATABASE via SQL (databases must be created via AWS API/Console)
-- - Does not support FOREIGN KEY constraints
-- - Does not support CREATE INDEX (indexes must be created separately via ASYNC syntax or not at all)
-- - Limited PostgreSQL feature set
-- 
-- This schema is idempotent - safe to run multiple times without data loss
-- Uses IF NOT EXISTS to avoid dropping/recreating tables

-- ============================================================================
-- Create Schema
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS car_entities_schema;

-- Set search path to use car_entities_schema
SET search_path TO car_entities_schema;

-- ============================================================================
-- Business Events Table
-- Stores complete events with eventHeader fields as columns and full event JSON
-- ============================================================================
CREATE TABLE IF NOT EXISTS car_entities_schema.business_events (
    id VARCHAR(255) PRIMARY KEY,  -- from eventHeader.uuid
    event_name VARCHAR(255) NOT NULL,  -- from eventHeader.eventName
    event_type VARCHAR(255),  -- from eventHeader.eventType
    created_date TIMESTAMP WITH TIME ZONE,  -- from eventHeader.createdDate
    saved_date TIMESTAMP WITH TIME ZONE,  -- from eventHeader.savedDate
    event_data TEXT NOT NULL  -- entire event JSON as TEXT (DSQL doesn't support JSONB)
);

-- ============================================================================
-- Event Headers Table
-- Stores event header data with hybrid structure (relational columns + TEXT JSON)
-- Note: Foreign key removed - DSQL doesn't support FOREIGN KEY constraints
-- ============================================================================
CREATE TABLE IF NOT EXISTS car_entities_schema.event_headers (
    id VARCHAR(255) PRIMARY KEY,  -- from eventHeader.uuid (same as business_events.id)
    event_name VARCHAR(255) NOT NULL,  -- from eventHeader.eventName
    event_type VARCHAR(255),  -- from eventHeader.eventType
    created_date TIMESTAMP WITH TIME ZONE,  -- from eventHeader.createdDate
    saved_date TIMESTAMP WITH TIME ZONE,  -- from eventHeader.savedDate
    header_data TEXT NOT NULL  -- full eventHeader JSON as TEXT (DSQL doesn't support JSONB)
);

-- ============================================================================
-- Entity Tables
-- Each entity type has its own table with entityHeader fields as columns
-- and entity data (without entityHeader) stored as TEXT JSON
-- Note: Foreign keys removed - DSQL doesn't support FOREIGN KEY constraints
-- ============================================================================

-- Car Entities Table
CREATE TABLE IF NOT EXISTS car_entities_schema.car_entities (
    entity_id VARCHAR(255) PRIMARY KEY,  -- from entityHeader.entityId
    entity_type VARCHAR(255) NOT NULL,  -- from entityHeader.entityType
    created_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.createdAt
    updated_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.updatedAt
    entity_data TEXT NOT NULL,  -- entity object without entityHeader as TEXT (DSQL doesn't support JSONB)
    event_id VARCHAR(255)  -- reference to event_headers.id (no foreign key constraint - DSQL limitation)
);

-- Loan Entities Table
<<<<<<< HEAD
CREATE TABLE IF NOT EXISTS car_entities_schema.loan_entities (
=======
CREATE TABLE IF NOT EXISTS loan_entities (
>>>>>>> 437618cdc0389cc9af0651cecbab072c0888a1cb
    entity_id VARCHAR(255) PRIMARY KEY,  -- from entityHeader.entityId
    entity_type VARCHAR(255) NOT NULL,  -- from entityHeader.entityType
    created_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.createdAt
    updated_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.updatedAt
    entity_data TEXT NOT NULL,  -- entity object without entityHeader as TEXT (DSQL doesn't support JSONB)
    event_id VARCHAR(255)  -- reference to event_headers.id (no foreign key constraint - DSQL limitation)
);

-- Loan Payment Entities Table
CREATE TABLE IF NOT EXISTS car_entities_schema.loan_payment_entities (
    entity_id VARCHAR(255) PRIMARY KEY,  -- from entityHeader.entityId
    entity_type VARCHAR(255) NOT NULL,  -- from entityHeader.entityType
    created_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.createdAt
    updated_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.updatedAt
    entity_data TEXT NOT NULL,  -- entity object without entityHeader as TEXT (DSQL doesn't support JSONB)
    event_id VARCHAR(255)  -- reference to event_headers.id (no foreign key constraint - DSQL limitation)
);

-- Service Record Entities Table
<<<<<<< HEAD
CREATE TABLE IF NOT EXISTS car_entities_schema.service_record_entities (
=======
CREATE TABLE IF NOT EXISTS service_record_entities (
>>>>>>> 437618cdc0389cc9af0651cecbab072c0888a1cb
    entity_id VARCHAR(255) PRIMARY KEY,  -- from entityHeader.entityId
    entity_type VARCHAR(255) NOT NULL,  -- from entityHeader.entityType
    created_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.createdAt
    updated_at TIMESTAMP WITH TIME ZONE,  -- from entityHeader.updatedAt
    entity_data TEXT NOT NULL,  -- entity object without entityHeader as TEXT (DSQL doesn't support JSONB)
    event_id VARCHAR(255)  -- reference to event_headers.id (no foreign key constraint - DSQL limitation)
);

-- Grant permissions to lambda_dsql_user
-- Note: User must be created separately via admin connection
-- DSQL doesn't support ALTER DEFAULT PRIVILEGES, so we only grant on existing tables
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA car_entities_schema TO lambda_dsql_user;
GRANT USAGE ON SCHEMA car_entities_schema TO lambda_dsql_user;
