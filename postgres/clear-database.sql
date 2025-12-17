-- Clear database script for load testing
-- This script truncates all tables to ensure clean state before each test run

-- Truncate all tables in the correct order to handle foreign key constraints
-- Using CASCADE to handle any dependencies
TRUNCATE TABLE 
    loan_payment_entities,
    service_record_entities,
    loan_entities,
    car_entities
CASCADE;

-- Reset sequences (for tables that use SERIAL/auto-increment)
-- Note: Only service_record_entities uses SERIAL, others use VARCHAR IDs
ALTER SEQUENCE IF EXISTS service_record_entities_id_seq RESTART WITH 1;

-- Log the operation
DO $$
BEGIN
    RAISE NOTICE 'Database cleared successfully at %', NOW();
END $$;
