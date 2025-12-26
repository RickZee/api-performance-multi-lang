-- Flink SQL Statements for Event Headers Filtering and Routing (Amazon MSK)
-- Processes 4 types of filtered event headers:
-- 1. Car Created (CarCreated)
-- 2. Loan Created (LoanCreated)
-- 3. Loan Payment Submitted (LoanPaymentSubmitted)
-- 4. Service Events (CarServiceDone)
--
-- Source: event_headers table from Aurora PostgreSQL via MSK Connect
-- Target: Filtered Kafka topics for each event type (with -msk suffix)
--
-- NOTE: Flink writes to -msk suffixed topics to distinguish from Confluent Cloud and Spring Boot processors.
-- Consumers should subscribe to the appropriate topic based on which processor is active.
--
-- DEPLOYMENT NOTE: This SQL is embedded in the Flink Java application and executed via Table API.
-- The application reads this SQL file and executes the statements programmatically.

-- ============================================================================
-- Step 1: Create Source Table
-- ============================================================================
-- Source Table: Raw Event Headers from MSK (Debezium CDC format)
-- Note: Uses Apache Flink Kafka connector (not Confluent connector)
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
    'connector' = 'kafka',
    'topic' = 'raw-event-headers',
    'properties.bootstrap.servers' = '${bootstrap.servers}',
    'properties.security.protocol' = 'SASL_SSL',
    'properties.sasl.mechanism' = 'AWS_MSK_IAM',
    'properties.sasl.jaas.config' = 'software.amazon.msk.auth.iam.IAMLoginModule required;',
    'properties.sasl.client.callback.handler.class' = 'software.amazon.msk.auth.iam.IAMClientCallbackHandler',
    'format' = 'json',
    'scan.startup.mode' = 'earliest-offset',
    'json.ignore-parse-errors' = 'true'
);

-- ============================================================================
-- Step 2: Create Sink Tables
-- ============================================================================

-- Sink Table: Car Created Events Filter (MSK)
-- Note: Flink writes to -msk suffixed topics to distinguish from other processors
CREATE TABLE `filtered-car-created-events-msk` (
    `id` STRING,
    `event_name` STRING,
    `event_type` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `header_data` STRING,
    `__op` STRING,
    `__table` STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'filtered-car-created-events-msk',
    'properties.bootstrap.servers' = '${bootstrap.servers}',
    'properties.security.protocol' = 'SASL_SSL',
    'properties.sasl.mechanism' = 'AWS_MSK_IAM',
    'properties.sasl.jaas.config' = 'software.amazon.msk.auth.iam.IAMLoginModule required;',
    'properties.sasl.client.callback.handler.class' = 'software.amazon.msk.auth.iam.IAMClientCallbackHandler',
    'format' = 'json',
    'json.ignore-parse-errors' = 'true',
    'sink.partitioner' = 'fixed'
);

-- Sink Table: Loan Created Events Filter (MSK)
CREATE TABLE `filtered-loan-created-events-msk` (
    `id` STRING,
    `event_name` STRING,
    `event_type` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `header_data` STRING,
    `__op` STRING,
    `__table` STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'filtered-loan-created-events-msk',
    'properties.bootstrap.servers' = '${bootstrap.servers}',
    'properties.security.protocol' = 'SASL_SSL',
    'properties.sasl.mechanism' = 'AWS_MSK_IAM',
    'properties.sasl.jaas.config' = 'software.amazon.msk.auth.iam.IAMLoginModule required;',
    'properties.sasl.client.callback.handler.class' = 'software.amazon.msk.auth.iam.IAMClientCallbackHandler',
    'format' = 'json',
    'json.ignore-parse-errors' = 'true',
    'sink.partitioner' = 'fixed'
);

-- Sink Table: Loan Payment Submitted Events Filter (MSK)
CREATE TABLE `filtered-loan-payment-submitted-events-msk` (
    `id` STRING,
    `event_name` STRING,
    `event_type` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `header_data` STRING,
    `__op` STRING,
    `__table` STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'filtered-loan-payment-submitted-events-msk',
    'properties.bootstrap.servers' = '${bootstrap.servers}',
    'properties.security.protocol' = 'SASL_SSL',
    'properties.sasl.mechanism' = 'AWS_MSK_IAM',
    'properties.sasl.jaas.config' = 'software.amazon.msk.auth.iam.IAMLoginModule required;',
    'properties.sasl.client.callback.handler.class' = 'software.amazon.msk.auth.iam.IAMClientCallbackHandler',
    'format' = 'json',
    'json.ignore-parse-errors' = 'true',
    'sink.partitioner' = 'fixed'
);

-- Sink Table: Service Events Filter (MSK)
CREATE TABLE `filtered-service-events-msk` (
    `id` STRING,
    `event_name` STRING,
    `event_type` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `header_data` STRING,
    `__op` STRING,
    `__table` STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'filtered-service-events-msk',
    'properties.bootstrap.servers' = '${bootstrap.servers}',
    'properties.security.protocol' = 'SASL_SSL',
    'properties.sasl.mechanism' = 'AWS_MSK_IAM',
    'properties.sasl.jaas.config' = 'software.amazon.msk.auth.iam.IAMLoginModule required;',
    'properties.sasl.client.callback.handler.class' = 'software.amazon.msk.auth.iam.IAMClientCallbackHandler',
    'format' = 'json',
    'json.ignore-parse-errors' = 'true',
    'sink.partitioner' = 'fixed'
);

-- ============================================================================
-- Step 3: Deploy INSERT Statements (one per filter)
-- ============================================================================

-- INSERT Statement: Car Created Events Filter (MSK)
-- Filters CarCreated events by eventType
-- Writes to filtered-car-created-events-msk topic
INSERT INTO `filtered-car-created-events-msk`
SELECT 
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

-- INSERT Statement: Loan Created Events Filter (MSK)
-- Filters LoanCreated events by eventType
-- Writes to filtered-loan-created-events-msk topic
INSERT INTO `filtered-loan-created-events-msk`
SELECT 
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

-- INSERT Statement: Loan Payment Submitted Events Filter (MSK)
-- Filters LoanPaymentSubmitted events by eventType
-- Writes to filtered-loan-payment-submitted-events-msk topic
INSERT INTO `filtered-loan-payment-submitted-events-msk`
SELECT 
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

-- INSERT Statement: Service Events Filter (MSK)
-- Filters CarServiceDone events by eventType
-- Writes to filtered-service-events-msk topic
INSERT INTO `filtered-service-events-msk`
SELECT 
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

