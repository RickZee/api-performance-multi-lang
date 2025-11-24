-- Example Flink SQL Routing Queries
-- This file contains additional examples of filtering and routing logic
-- Copy and modify these examples to create your own routing jobs

-- ============================================================================
-- Basic Filtering Examples
-- ============================================================================

-- Example 1: Filter by Event Name
CREATE TABLE filtered_car_created AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('car-created-filter', 'car-inventory-service', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'CarCreated';

-- Example 2: Filter by Entity Type
CREATE TABLE filtered_loan_entities AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('loan-entity-filter', 'loan-service', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventBody.entities[1].entityType = 'Loan';

-- Example 3: Filter by Multiple Event Names (IN clause)
CREATE TABLE filtered_payment_events AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('payment-events-filter', 'payment-service', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName IN ('LoanPaymentSubmitted', 'PaymentProcessed', 'PaymentFailed');

-- ============================================================================
-- Value-Based Filtering Examples
-- ============================================================================

-- Example 4: High Value Loans (greater than threshold)
CREATE TABLE filtered_high_value_loans AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('high-value-loan-filter', 'loan-approval-service', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'LoanCreated'
  AND CAST(eventBody.entities[1].updatedAttributes['loan.loanAmount'] AS DOUBLE) > 100000;

-- Example 5: Low Cost Services (less than threshold)
CREATE TABLE filtered_low_cost_services AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('low-cost-service-filter', 'service-analytics', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'CarServiceDone'
  AND CAST(eventBody.entities[1].updatedAttributes['service.amountPaid'] AS DOUBLE) < 100;

-- Example 6: Range Filter (between two values)
CREATE TABLE filtered_medium_loans AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('medium-loan-filter', 'loan-processing', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'LoanCreated'
  AND CAST(eventBody.entities[1].updatedAttributes['loan.loanAmount'] AS DOUBLE) >= 25000
  AND CAST(eventBody.entities[1].updatedAttributes['loan.loanAmount'] AS DOUBLE) <= 75000;

-- ============================================================================
-- Status-Based Filtering Examples
-- ============================================================================

-- Example 7: Active Loans Only
CREATE TABLE filtered_active_loans AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('active-loan-filter', 'loan-management', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'LoanCreated'
  AND eventBody.entities[1].updatedAttributes['loan.status'] = 'active';

-- Example 8: Failed Payments
CREATE TABLE filtered_failed_payments AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('failed-payment-filter', 'payment-retry-service', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'LoanPaymentSubmitted'
  AND eventBody.entities[1].updatedAttributes['loanPayment.status'] = 'failed';

-- ============================================================================
-- Time-Based Filtering Examples
-- ============================================================================

-- Example 9: Recent Events (last 24 hours)
CREATE TABLE filtered_recent_events AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('recent-events-filter', 'real-time-analytics', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.createdDate > UNIX_TIMESTAMP() * 1000 - 86400000;  -- 24 hours in milliseconds

-- Example 10: Business Hours Events (9 AM - 5 PM)
CREATE TABLE filtered_business_hours_events AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('business-hours-filter', 'business-hours-processor', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE HOUR(FROM_UNIXTIME(eventHeader.createdDate / 1000)) >= 9
  AND HOUR(FROM_UNIXTIME(eventHeader.createdDate / 1000)) < 17;

-- ============================================================================
-- Multi-Condition Filtering Examples
-- ============================================================================

-- Example 11: Premium Customer High Value Loans
CREATE TABLE filtered_premium_loans AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('premium-customer-loan-filter', 'premium-services', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'LoanCreated'
  AND CAST(eventBody.entities[1].updatedAttributes['loan.loanAmount'] AS DOUBLE) > 50000
  AND eventBody.entities[1].updatedAttributes['customer.tier'] = 'premium';

-- Example 12: Urgent High Value Services
CREATE TABLE filtered_urgent_services AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('urgent-service-filter', 'urgent-service-handler', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'CarServiceDone'
  AND eventBody.entities[1].updatedAttributes['service.priority'] = 'urgent'
  AND CAST(eventBody.entities[1].updatedAttributes['service.amountPaid'] AS DOUBLE) > 500;

-- ============================================================================
-- Pattern Matching Examples
-- ============================================================================

-- Example 13: Entity ID Pattern Matching
CREATE TABLE filtered_pattern_events AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('pattern-match-filter', 'pattern-processor', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventBody.entities[1].entityId LIKE 'loan-%premium';

-- Example 14: Regex Pattern Matching (using Flink's REGEXP function)
CREATE TABLE filtered_regex_events AS
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('regex-filter', 'regex-processor', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE REGEXP(eventBody.entities[1].entityId, '^loan-.*-premium$');

-- ============================================================================
-- Aggregation and Window Examples
-- ============================================================================

-- Example 15: Windowed Aggregation - Count Events per Minute
CREATE TABLE event_counts_per_minute AS
SELECT 
    TUMBLE_START(eventtime, INTERVAL '1' MINUTE) AS window_start,
    eventHeader.eventName,
    COUNT(*) AS event_count
FROM raw_business_events
GROUP BY TUMBLE(eventtime, INTERVAL '1' MINUTE), eventHeader.eventName;

-- Example 16: Sliding Window - Average Loan Amount per 5 Minutes
CREATE TABLE avg_loan_amount_sliding AS
SELECT 
    HOP_START(eventtime, INTERVAL '1' MINUTE, INTERVAL '5' MINUTE) AS window_start,
    AVG(CAST(eventBody.entities[1].updatedAttributes['loan.loanAmount'] AS DOUBLE)) AS avg_loan_amount
FROM raw_business_events
WHERE eventHeader.eventName = 'LoanCreated'
  AND eventBody.entities[1].updatedAttributes['loan.loanAmount'] IS NOT NULL
GROUP BY HOP(eventtime, INTERVAL '1' MINUTE, INTERVAL '5' MINUTE);

-- ============================================================================
-- Multi-Topic Routing Examples
-- ============================================================================

-- Example 17: Route to Multiple Topics Based on Loan Amount
-- Small Loans
INSERT INTO filtered_small_loans
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('loan-amount-routing', 'loan-router-small', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'LoanCreated'
  AND CAST(eventBody.entities[1].updatedAttributes['loan.loanAmount'] AS DOUBLE) < 10000;

-- Medium Loans
INSERT INTO filtered_medium_loans
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('loan-amount-routing', 'loan-router-medium', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'LoanCreated'
  AND CAST(eventBody.entities[1].updatedAttributes['loan.loanAmount'] AS DOUBLE) >= 10000
  AND CAST(eventBody.entities[1].updatedAttributes['loan.loanAmount'] AS DOUBLE) <= 50000;

-- Large Loans
INSERT INTO filtered_large_loans
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('loan-amount-routing', 'loan-router-large', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'LoanCreated'
  AND CAST(eventBody.entities[1].updatedAttributes['loan.loanAmount'] AS DOUBLE) > 50000;

-- ============================================================================
-- Join Examples
-- ============================================================================

-- Example 18: Join Events with Reference Data
-- Note: This requires a reference table (e.g., customer data)
CREATE TABLE customer_reference (
    customer_id STRING,
    customer_tier STRING,
    region STRING,
    PRIMARY KEY (customer_id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:postgresql://postgres-large:5432/car_entities',
    'table-name' = 'customers'
);

CREATE TABLE enriched_loan_events AS
SELECT 
    r.eventHeader,
    r.eventBody,
    r.sourceMetadata,
    c.customer_tier,
    c.region,
    ROW('enriched-loan-filter', 'enriched-processor', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events AS r
LEFT JOIN customer_reference FOR SYSTEM_TIME AS OF r.eventtime AS c
ON r.eventBody.entities[1].entityId = c.customer_id
WHERE r.eventHeader.eventName = 'LoanCreated';

-- ============================================================================
-- Error Handling Examples
-- ============================================================================

-- Example 19: Dead Letter Queue for Invalid Events
CREATE TABLE dead_letter_queue (
    eventHeader ROW<...>,
    eventBody ROW<...>,
    sourceMetadata ROW<...>,
    error_message STRING,
    error_timestamp BIGINT
) WITH (
    'connector' = 'kafka',
    'topic' = 'dead-letter-queue',
    'properties.bootstrap.servers' = 'kafka:29092',
    'format' = 'avro',
    'avro.schema-registry.url' = 'http://schema-registry:8081'
);

-- Route invalid events to dead letter queue
INSERT INTO dead_letter_queue
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    'Missing required field: eventName' AS error_message,
    UNIX_TIMESTAMP() * 1000 AS error_timestamp
FROM raw_business_events
WHERE eventHeader.eventName IS NULL OR eventHeader.eventName = '';

