-- Flink SQL Statements for Event Headers Filtering and Routing (Confluent Cloud)
-- Processes 4 types of filtered event headers:
-- 1. Car Created (CarCreated)
-- 2. Loan Created (LoanCreated)
-- 3. Loan Payment Submitted (LoanPaymentSubmitted)
-- 4. Service Events (CarServiceDone)
--
-- Source: event_headers table from Aurora PostgreSQL
-- Target: Filtered Kafka topics for each event type
--
-- DEPLOYMENT NOTE: Deploy statements in order:
-- 1. Source table (raw-event-headers)
-- 2. Sink tables (filtered-*-events)
-- 3. INSERT statements (one per filter)

-- ============================================================================
-- Step 1: Create Source Table
-- ============================================================================
-- Source Table: Raw Event Headers from Kafka (Debezium CDC format)
-- Note: Table name must match topic name exactly in Confluent Cloud
-- This table reads from the Debezium CDC output for event_headers table
-- The header_data column contains the event header JSON structure
CREATE TABLE `raw-event-headers` (
    `id` STRING,
    `event_name` STRING,
    `event_type` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `header_data` STRING,
    `__op` STRING,
    `__table` STRING,
    `__ts_ms` BIGINT
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry',
    'scan.startup.mode' = 'earliest-offset'
);

-- ============================================================================
-- Step 2: Create Sink Tables
-- ============================================================================

-- Sink Table: Car Created Events Filter
CREATE TABLE `filtered-car-created-events` (
    `key` BYTES,
    `id` STRING,
    `event_name` STRING,
    `event_type` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `header_data` STRING,
    `__op` STRING,
    `__table` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry'
);

-- Sink Table: Loan Created Events Filter
CREATE TABLE `filtered-loan-created-events` (
    `key` BYTES,
    `id` STRING,
    `event_name` STRING,
    `event_type` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `header_data` STRING,
    `__op` STRING,
    `__table` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry'
);

-- Sink Table: Loan Payment Submitted Events Filter
CREATE TABLE `filtered-loan-payment-submitted-events` (
    `key` BYTES,
    `id` STRING,
    `event_name` STRING,
    `event_type` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `header_data` STRING,
    `__op` STRING,
    `__table` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry'
);

-- Sink Table: Service Events Filter
CREATE TABLE `filtered-service-events` (
    `key` BYTES,
    `id` STRING,
    `event_name` STRING,
    `event_type` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `header_data` STRING,
    `__op` STRING,
    `__table` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry'
);

-- ============================================================================
-- Step 3: Deploy INSERT Statements (one per filter)
-- ============================================================================

-- INSERT Statement: Car Created Events Filter
-- Filters CarCreated events by eventType
INSERT INTO `filtered-car-created-events`
SELECT 
    CAST(`id` AS BYTES) AS `key`,
    `id`,
    `event_name`,
    `event_type`,
    `created_date`,
    `saved_date`,
    `header_data`,
    `__op`,
    `__table`
FROM `raw-event-headers`
WHERE `event_type` = 'CarCreated' AND `__op` = 'c';

-- INSERT Statement: Loan Created Events Filter
-- Filters LoanCreated events by eventType
INSERT INTO `filtered-loan-created-events`
SELECT 
    CAST(`id` AS BYTES) AS `key`,
    `id`,
    `event_name`,
    `event_type`,
    `created_date`,
    `saved_date`,
    `header_data`,
    `__op`,
    `__table`
FROM `raw-event-headers`
WHERE `event_type` = 'LoanCreated' AND `__op` = 'c';

-- INSERT Statement: Loan Payment Submitted Events Filter
-- Filters LoanPaymentSubmitted events by eventType
INSERT INTO `filtered-loan-payment-submitted-events`
SELECT 
    CAST(`id` AS BYTES) AS `key`,
    `id`,
    `event_name`,
    `event_type`,
    `created_date`,
    `saved_date`,
    `header_data`,
    `__op`,
    `__table`
FROM `raw-event-headers`
WHERE `event_type` = 'LoanPaymentSubmitted' AND `__op` = 'c';

-- INSERT Statement: Service Events Filter
-- Filters CarServiceDone events by eventType
INSERT INTO `filtered-service-events`
SELECT 
    CAST(`id` AS BYTES) AS `key`,
    `id`,
    `event_name`,
    `event_type`,
    `created_date`,
    `saved_date`,
    `header_data`,
    `__op`,
    `__table`
FROM `raw-event-headers`
WHERE `event_type` = 'CarServiceDone' AND `__op` = 'c';
