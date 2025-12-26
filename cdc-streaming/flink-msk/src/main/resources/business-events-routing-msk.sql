-- Flink SQL Statements for Event Headers Filtering and Routing (Amazon MSK)
-- This file is embedded in the Flink application JAR and executed at runtime.
-- Bootstrap servers are replaced from environment variable BOOTSTRAP_SERVERS.

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
-- Step 3: Deploy INSERT Statements
-- ============================================================================

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

