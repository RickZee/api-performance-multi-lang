-- Generated Flink SQL Statements for Event Headers Filtering and Routing
-- Generated at: 2025-12-21T15:47:46.000560
-- Source: config/filters.json
-- DO NOT EDIT MANUALLY - This file is auto-generated

-- Source: event_headers table from Aurora PostgreSQL
-- Target: Filtered Kafka topics for each event type (with -flink suffix)

-- NOTE: Flink writes to -flink suffixed topics to distinguish from Spring Boot processor.
-- Consumers should subscribe to the appropriate topic based on which processor is active.

-- DEPLOYMENT NOTE: Deploy statements in order:
-- 1. Source table (raw-event-headers)
-- 2. Sink tables (filtered-*-events-flink)
-- 3. INSERT statements (one per filter)

-- ============================================================================
-- Step 1: Create Source Table
-- ============================================================================
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
    'value.format' = 'json',
    'scan.startup.mode' = 'earliest-offset'
);

-- ============================================================================
-- Step 2: Create Sink Tables
-- ============================================================================

-- Sink Table: Car Created Events Filter (Flink)
-- Note: Flink writes to -flink suffixed topics to distinguish from Spring Boot processor
CREATE TABLE `filtered-car-created-events-flink` (
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

-- Sink Table: Loan Created Events Filter (Flink)
-- Note: Flink writes to -flink suffixed topics to distinguish from Spring Boot processor
CREATE TABLE `filtered-loan-created-events-flink` (
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

-- Sink Table: Loan Payment Submitted Events Filter (Flink)
-- Note: Flink writes to -flink suffixed topics to distinguish from Spring Boot processor
CREATE TABLE `filtered-loan-payment-submitted-events-flink` (
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

-- Sink Table: Service Events Filter (Flink)
-- Note: Flink writes to -flink suffixed topics to distinguish from Spring Boot processor
CREATE TABLE `filtered-service-events-flink` (
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

-- INSERT Statement: Car Created Events
-- Filters CarCreated events by event_type
-- Writes to filtered-car-created-events-flink topic
INSERT INTO `filtered-car-created-events-flink`
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

-- INSERT Statement: Loan Created Events
-- Filters LoanCreated events by event_type
-- Writes to filtered-loan-created-events-flink topic
INSERT INTO `filtered-loan-created-events-flink`
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

-- INSERT Statement: Loan Payment Submitted Events
-- Filters LoanPaymentSubmitted events by event_type
-- Writes to filtered-loan-payment-submitted-events-flink topic
INSERT INTO `filtered-loan-payment-submitted-events-flink`
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

-- INSERT Statement: Service Events
-- Filters CarServiceDone events by event_type
-- Writes to filtered-service-events-flink topic
INSERT INTO `filtered-service-events-flink`
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
