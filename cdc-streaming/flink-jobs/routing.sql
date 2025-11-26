-- Flink SQL Job for Event Filtering and Routing
-- This file contains Flink SQL statements to filter and route events from raw-business-events
-- to consumer-specific topics based on filter rules defined in filters.yaml

-- ============================================================================
-- Source Table: Raw Business Events from Kafka
-- ============================================================================
CREATE TABLE raw_business_events (
    `eventHeader` ROW<
        `uuid` STRING,
        `eventName` STRING,
        `createdDate` BIGINT,
        `savedDate` BIGINT,
        `eventType` STRING
    >,
    `eventBody` ROW<
        `entities` ARRAY<ROW<
            `entityType` STRING,
            `entityId` STRING,
            `updatedAttributes` MAP<STRING, STRING>
        >>
    >,
    `sourceMetadata` ROW<
        `table` STRING,
        `operation` STRING,
        `timestamp` BIGINT
    >,
    `proctime` AS PROCTIME(),
    `eventtime` AS TO_TIMESTAMP_LTZ(`eventHeader`.`createdDate`, 3),
    WATERMARK FOR `eventtime` AS `eventtime` - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'raw-business-events',
    'properties.bootstrap.servers' = 'kafka:29092',
    'properties.group.id' = 'flink-routing-job',
    'format' = 'avro',
    'avro.schema-registry.url' = 'http://schema-registry:8081',
    'scan.startup.mode' = 'earliest-offset'
);

-- ============================================================================
-- Sink Table: Filtered Loan Events
-- ============================================================================
CREATE TABLE filtered_loan_events (
    `eventHeader` ROW<
        `uuid` STRING,
        `eventName` STRING,
        `createdDate` BIGINT,
        `savedDate` BIGINT,
        `eventType` STRING
    >,
    `eventBody` ROW<
        `entities` ARRAY<ROW<
            `entityType` STRING,
            `entityId` STRING,
            `updatedAttributes` MAP<STRING, STRING>
        >>
    >,
    `sourceMetadata` ROW<
        `table` STRING,
        `operation` STRING,
        `timestamp` BIGINT
    >,
    `filterMetadata` ROW<
        `filterId` STRING,
        `consumerId` STRING,
        `filteredAt` BIGINT
    >
) WITH (
    'connector' = 'kafka',
    'topic' = 'filtered-loan-events',
    'properties.bootstrap.servers' = 'kafka:29092',
    'format' = 'avro',
    'avro.schema-registry.url' = 'http://schema-registry:8081',
    'sink.partitioner' = 'fixed'
);

-- ============================================================================
-- Sink Table: Filtered Service Events
-- ============================================================================
CREATE TABLE filtered_service_events (
    `eventHeader` ROW<
        `uuid` STRING,
        `eventName` STRING,
        `createdDate` BIGINT,
        `savedDate` BIGINT,
        `eventType` STRING
    >,
    `eventBody` ROW<
        `entities` ARRAY<ROW<
            `entityType` STRING,
            `entityId` STRING,
            `updatedAttributes` MAP<STRING, STRING>
        >>
    >,
    `sourceMetadata` ROW<
        `table` STRING,
        `operation` STRING,
        `timestamp` BIGINT
    >,
    `filterMetadata` ROW<
        `filterId` STRING,
        `consumerId` STRING,
        `filteredAt` BIGINT
    >
) WITH (
    'connector' = 'kafka',
    'topic' = 'filtered-service-events',
    'properties.bootstrap.servers' = 'kafka:29092',
    'format' = 'avro',
    'avro.schema-registry.url' = 'http://schema-registry:8081',
    'sink.partitioner' = 'fixed'
);

-- ============================================================================
-- Sink Table: Filtered Car Events
-- ============================================================================
CREATE TABLE filtered_car_events (
    `eventHeader` ROW<
        `uuid` STRING,
        `eventName` STRING,
        `createdDate` BIGINT,
        `savedDate` BIGINT,
        `eventType` STRING
    >,
    `eventBody` ROW<
        `entities` ARRAY<ROW<
            `entityType` STRING,
            `entityId` STRING,
            `updatedAttributes` MAP<STRING, STRING>
        >>
    >,
    `sourceMetadata` ROW<
        `table` STRING,
        `operation` STRING,
        `timestamp` BIGINT
    >,
    `filterMetadata` ROW<
        `filterId` STRING,
        `consumerId` STRING,
        `filteredAt` BIGINT
    >
) WITH (
    'connector' = 'kafka',
    'topic' = 'filtered-car-events',
    'properties.bootstrap.servers' = 'kafka:29092',
    'format' = 'avro',
    'avro.schema-registry.url' = 'http://schema-registry:8081',
    'sink.partitioner' = 'fixed'
);

-- ============================================================================
-- Filtering and Routing Queries
-- ============================================================================

-- Route Loan-related events (LoanCreated, LoanPaymentSubmitted)
INSERT INTO filtered_loan_events
SELECT 
    `eventHeader`,
    `eventBody`,
    `sourceMetadata`,
    ROW(
        'loan-events-filter',
        'loan-consumer',
        UNIX_TIMESTAMP() * 1000
    ) AS `filterMetadata`
FROM raw_business_events
WHERE 
    (`eventHeader`.`eventName` = 'LoanCreated' OR `eventHeader`.`eventName` = 'LoanPaymentSubmitted')
    OR (`eventBody`.`entities`[1].`entityType` = 'Loan' OR `eventBody`.`entities`[1].`entityType` = 'LoanPayment');

-- Route Service-related events (CarServiceDone)
INSERT INTO filtered_service_events
SELECT 
    `eventHeader`,
    `eventBody`,
    `sourceMetadata`,
    ROW(
        'service-events-filter',
        'service-consumer',
        UNIX_TIMESTAMP() * 1000
    ) AS `filterMetadata`
FROM raw_business_events
WHERE 
    `eventHeader`.`eventName` = 'CarServiceDone'
    OR `eventBody`.`entities`[1].`entityType` = 'ServiceRecord';

-- Route Car creation events
INSERT INTO filtered_car_events
SELECT 
    `eventHeader`,
    `eventBody`,
    `sourceMetadata`,
    ROW(
        'car-creation-filter',
        'car-consumer',
        UNIX_TIMESTAMP() * 1000
    ) AS `filterMetadata`
FROM raw_business_events
WHERE 
    `eventHeader`.`eventName` = 'CarCreated'
    AND `eventBody`.`entities`[1].`entityType` = 'Car';





