-- Flink SQL Test Job for CDC Data on Confluent Cloud
-- Reads from cdc-raw topics and validates Flink connectivity

-- ============================================================================
-- Source Table: CDC Raw Car Entities (JSON format from Debezium)
-- ============================================================================
CREATE TABLE cdc_car_entities_source (
    `id` STRING,
    `entity_type` STRING,
    `created_at` STRING,
    `updated_at` STRING,
    `data` STRING,
    `__op` STRING,
    `__table` STRING,
    `__ts_ms` BIGINT,
    `proc_time` AS PROCTIME()
) WITH (
    'connector' = 'kafka',
    'topic' = 'cdc-raw.public.car_entities',
    'properties.bootstrap.servers' = 'pkc-oxqxx9.us-east-1.aws.confluent.cloud:9092',
    'properties.security.protocol' = 'SASL_SSL',
    'properties.sasl.mechanism' = 'PLAIN',
    'properties.sasl.jaas.config' = 'org.apache.kafka.common.security.plain.PlainLoginModule required username="A57DHIMR3NLB6PGI" password="cfltawpq47RbFYepsUN3x0whOK4tgfMbGweGAp1eNdULMf/W2RMwiLJFVPyoTxkg";',
    'properties.group.id' = 'flink-cdc-test-job',
    'format' = 'json',
    'scan.startup.mode' = 'earliest-offset'
);

-- ============================================================================
-- Sink Table: Car Events (pass-through test)
-- ============================================================================
CREATE TABLE car_events_sink (
    `id` STRING,
    `entity_type` STRING,
    `make` STRING,
    `model` STRING,
    `operation` STRING,
    `table_name` STRING,
    `timestamp` BIGINT
) WITH (
    'connector' = 'kafka',
    'topic' = 'flink-processed-car-events',
    'properties.bootstrap.servers' = 'pkc-oxqxx9.us-east-1.aws.confluent.cloud:9092',
    'properties.security.protocol' = 'SASL_SSL',
    'properties.sasl.mechanism' = 'PLAIN',
    'properties.sasl.jaas.config' = 'org.apache.kafka.common.security.plain.PlainLoginModule required username="A57DHIMR3NLB6PGI" password="cfltawpq47RbFYepsUN3x0whOK4tgfMbGweGAp1eNdULMf/W2RMwiLJFVPyoTxkg";',
    'format' = 'json'
);

-- ============================================================================
-- Simple transformation: Extract fields from JSON data
-- ============================================================================
INSERT INTO car_events_sink
SELECT 
    id,
    entity_type,
    COALESCE(JSON_VALUE(data, '$.make'), 'Unknown') AS make,
    COALESCE(JSON_VALUE(data, '$.model'), 'Unknown') AS model,
    __op AS operation,
    __table AS table_name,
    __ts_ms AS timestamp
FROM cdc_car_entities_source
WHERE __op IN ('c', 'u');  -- Only process create and update operations
