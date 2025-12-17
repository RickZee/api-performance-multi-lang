-- Flink SQL Statements for Event Headers Filtering and Routing (Confluent Cloud)
-- Modified version: Works WITHOUT __op field (PostgresCdcSource doesn't add it)
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
-- Source Table: Raw Event Headers from Kafka (PostgresCdcSource output)
-- Note: PostgresCdcSource outputs flat structure without __op, __table, __ts_ms
CREATE TABLE `raw-event-headers` (
    `id` STRING,
    `event_name` STRING,
    `event_type` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `header_data` STRING
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
-- Filters CarCreated events by eventType (no __op filter)
INSERT INTO `filtered-car-created-events`
SELECT 
    `id`,
    `event_name`,
    `event_type`,
    `created_date`,
    `saved_date`,
    `header_data`,
    'c' AS `__op`,                    -- Add __op = 'c' in Flink (assumes all are inserts)
    'event_headers' AS `__table`     -- Add __table in Flink
FROM `raw-event-headers`
WHERE `event_type` = 'CarCreated';

-- INSERT Statement: Loan Created Events Filter
-- Filters LoanCreated events by eventType (no __op filter)
INSERT INTO `filtered-loan-created-events`
SELECT 
    `id`,
    `event_name`,
    `event_type`,
    `created_date`,
    `saved_date`,
    `header_data`,
    'c' AS `__op`,                    -- Add __op = 'c' in Flink
    'event_headers' AS `__table`    -- Add __table in Flink
FROM `raw-event-headers`
WHERE `event_type` = 'LoanCreated';

-- INSERT Statement: Loan Payment Submitted Events Filter
-- Filters LoanPaymentSubmitted events by eventType (no __op filter)
INSERT INTO `filtered-loan-payment-submitted-events`
SELECT 
    `id`,
    `event_name`,
    `event_type`,
    `created_date`,
    `saved_date`,
    `header_data`,
    'c' AS `__op`,                    -- Add __op = 'c' in Flink
    'event_headers' AS `__table`    -- Add __table in Flink
FROM `raw-event-headers`
WHERE `event_type` = 'LoanPaymentSubmitted';

-- INSERT Statement: Service Events Filter
-- Filters CarServiceDone events by eventName (no __op filter)
INSERT INTO `filtered-service-events`
SELECT 
    `id`,
    `event_name`,
    `event_type`,
    `created_date`,
    `saved_date`,
    `header_data`,
    'c' AS `__op`,                    -- Add __op = 'c' in Flink
    'event_headers' AS `__table`    -- Add __table in Flink
FROM `raw-event-headers`
WHERE `event_name` = 'CarServiceDone';
