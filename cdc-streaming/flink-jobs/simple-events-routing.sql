-- Flink SQL Job for Simple Events Routing by Event Type
-- This file routes events from simple-business-events to different topics based on event_type
-- Note: Confluent Cloud Flink requires separate statements for each CREATE TABLE and INSERT

-- ============================================================================
-- Source Table: Simple Business Events from Kafka
-- ============================================================================
CREATE TABLE `simple-business-events` (
    `id` STRING,
    `event_name` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `event_type` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'avro-registry',
    'scan.startup.mode' = 'earliest-offset'
);

-- ============================================================================
-- Sink Table: Type A Events (LoanPaymentSubmitted)
-- ============================================================================
CREATE TABLE `simple-events-loan-payment` (
    `id` STRING,
    `event_name` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `event_type` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'avro-registry'
);

-- ============================================================================
-- Sink Table: Type B Events (LoanCreated)
-- ============================================================================
CREATE TABLE `simple-events-loan-created` (
    `id` STRING,
    `event_name` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `event_type` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'avro-registry'
);

-- ============================================================================
-- Sink Table: Type C Events (CarServiceDone)
-- ============================================================================
CREATE TABLE `simple-events-car-service` (
    `id` STRING,
    `event_name` STRING,
    `created_date` STRING,
    `saved_date` STRING,
    `event_type` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'avro-registry'
);

-- ============================================================================
-- Routing Query: Route LoanPaymentSubmitted events
-- ============================================================================
INSERT INTO `simple-events-loan-payment`
SELECT 
    `id`,
    `event_name`,
    `created_date`,
    `saved_date`,
    `event_type`
FROM `simple-business-events`
WHERE `event_type` = 'LoanPaymentSubmitted';

-- ============================================================================
-- Routing Query: Route LoanCreated events
-- ============================================================================
INSERT INTO `simple-events-loan-created`
SELECT 
    `id`,
    `event_name`,
    `created_date`,
    `saved_date`,
    `event_type`
FROM `simple-business-events`
WHERE `event_type` = 'LoanCreated';

-- ============================================================================
-- Routing Query: Route CarServiceDone events
-- ============================================================================
INSERT INTO `simple-events-car-service`
SELECT 
    `id`,
    `event_name`,
    `created_date`,
    `saved_date`,
    `event_type`
FROM `simple-business-events`
WHERE `event_type` = 'CarServiceDone';
