-- Flink SQL Job for Event Filtering and Routing
-- This file contains Flink SQL statements to filter and route events from raw-business-events
-- to consumer-specific topics based on filter rules defined in filters.yaml
--
-- Example structures:
-- - Car entity: data/entities/car/car-large.json
-- - Loan created event: data/schemas/event/samples/loan-created-event.json

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
-- Sink Table: Filtered Loan Created Events
-- Filters LoanCreated events based on data/schemas/event/samples/loan-created-event.json
-- Example: Events where eventType='LoanCreated' and entityType='Loan'
-- ============================================================================
CREATE TABLE filtered_loan_created_events (
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
    'topic' = 'filtered-loan-created-events',
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
-- Sink Table: Filtered Car Created Events
-- Filters CarCreated events based on data/schemas/event/samples/car-created-event.json
-- ============================================================================
CREATE TABLE filtered_car_created_events (
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
    'topic' = 'filtered-car-created-events',
    'properties.bootstrap.servers' = 'kafka:29092',
    'format' = 'avro',
    'avro.schema-registry.url' = 'http://schema-registry:8081',
    'sink.partitioner' = 'fixed'
);

-- ============================================================================
-- Sink Table: Filtered Loan Payment Submitted Events
-- Filters LoanPaymentSubmitted events based on data/schemas/event/samples/loan-payment-submitted-event.json
-- Example: Events where eventType='LoanPaymentSubmitted' and entityType='LoanPayment'
-- ============================================================================
CREATE TABLE filtered_loan_payment_submitted_events (
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
    'topic' = 'filtered-loan-payment-submitted-events',
    'properties.bootstrap.servers' = 'kafka:29092',
    'format' = 'avro',
    'avro.schema-registry.url' = 'http://schema-registry:8081',
    'sink.partitioner' = 'fixed'
);

-- ============================================================================
-- Filtering and Routing Queries
-- ============================================================================

-- Route Loan Created events (filter by eventType: LoanCreated)
INSERT INTO filtered_loan_created_events
SELECT 
    `eventHeader`,
    `eventBody`,
    `sourceMetadata`,
    ROW(
        'loan-created-filter',
        'loan-consumer',
        UNIX_TIMESTAMP() * 1000
    ) AS `filterMetadata`
FROM raw_business_events
WHERE `eventHeader`.`eventType` = 'LoanCreated';

-- Route Loan Payment Submitted events (filter by eventType: LoanPaymentSubmitted)
INSERT INTO filtered_loan_payment_submitted_events
SELECT 
    `eventHeader`,
    `eventBody`,
    `sourceMetadata`,
    ROW(
        'loan-payment-submitted-filter',
        'loan-consumer',
        UNIX_TIMESTAMP() * 1000
    ) AS `filterMetadata`
FROM raw_business_events
WHERE `eventHeader`.`eventType` = 'LoanPaymentSubmitted';

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

-- Route Car Created events (filter by eventType: CarCreated)
INSERT INTO filtered_car_created_events
SELECT 
    `eventHeader`,
    `eventBody`,
    `sourceMetadata`,
    ROW(
        'car-created-filter',
        'car-consumer',
        UNIX_TIMESTAMP() * 1000
    ) AS `filterMetadata`
FROM raw_business_events
WHERE `eventHeader`.`eventType` = 'CarCreated';






