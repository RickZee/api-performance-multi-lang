# CDC Streaming Architecture Documentation

## Summary

Change Data Capture (CDC) streaming architecture that enables real-time event processing from PostgreSQL databases to Kafka, with filtering and routing using Apache Flink.

### Key Capabilities

- **Real-time CDC**: Captures database changes (INSERT, UPDATE, DELETE) from PostgreSQL tables and streams them to Kafka
- **Intelligent Filtering**: Configurable YAML-based filter definitions that automatically generate Flink SQL for event filtering
- **Multi-topic Routing**: Routes filtered events to consumer-specific Kafka topics based on business rules
- **Schema Management**: Avro schema enforcement via Schema Registry for data contract validation
- **Scalable Processing**: Apache Flink for stateful stream processing with horizontal scaling
- **Code Generation**: Automated SQL generation from declarative filter configurations
- **CI/CD Integration**: Infrastructure-as-code ready with validation and testing capabilities

## System Architecture Overview

### High-Level Data Flow

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                         PostgreSQL Database                             │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐                  │
│  │ car_entities │  │loan_entities │  |service_record │  ...             │
│  └──────────────┘  └──────────────┘  └───────────────┘                  │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ CDC Capture (Debezium)
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                 Kafka Connect (Source Connector)                        │
│              Confluent Postgres Source Connector                        │
│                   (Debezium-based CDC)                                  │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ Avro Serialized Events
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        Schema Registry                                  │
│                 Schema Validation & Evolution                           │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ Validated Events
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Kafka: raw-business-events                           │
│                        (Avro format)                                    │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ Stream Processing
                               ▼
┌────────────────────────────────────────────────────────────────────────┐
│                    Confluent Flink                                     │
│                                                                        │
│  Flink SQL Jobs:                                                       │
│  - Filter by eventName, entityType, values                             │
│  - Route to consumer-specific topics                                   │
│  - Add filterMetadata (filterId, consumerId, timestamp)                │
└──────────────────────────────┬─────────────────────────────────────────┘
                               │
                               │ Filtered & Routed Events
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Consumer-Specific Kafka Topics                       │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────┐   │
│  │filtered-loan-events  │  │filtered-service-     │  │filtered-car- │   │
│  │                      │  │events                │  │events        │   │
│  └──────────────────────┘  └──────────────────────┘  └──────────────┘   │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ Consume Events
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Consumer Applications                                │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐       │
│  │ Loan Consumer    │  │Service Consumer  │  │  Car Consumer    │       │
│  │ - Processes      │  │ - Processes      │  │  - Processes     │       │
│  │   loan events    │  │   service events │  │   car events     │       │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘       │
└─────────────────────────────────────────────────────────────────────────┘
```

### How Consumers Get Filtered Events

**Complete Flow**:

1. **PostgreSQL** → Database changes captured via CDC
2. **CDC Connector** → Publishes to `raw-business-events` Kafka topic
3. **Flink SQL Job** →
   - Consumes from `raw-business-events` (acts as Kafka consumer)
   - Filters events
   - **Writes to filtered Kafka topics** (acts as Kafka producer):
     - `filtered-loan-events`
     - `filtered-service-events`
     - `filtered-car-events`
4. **Consumer Applications** →
   - Connect to Kafka brokers
   - Subscribe to filtered topics using Kafka consumer groups
   - Process events independently of Flink

## Component Deep Dive

### 1. PostgreSQL Database (Source)

**Purpose**: The source of truth for business entities (loans, cars, service records, etc.)

**How It Works**:

- Stores entity data in normalized tables
- PostgreSQL Write-Ahead Log (WAL) records all changes
- Logical replication slots enable CDC capture without impacting database performance
- Tables are monitored for INSERT, UPDATE, DELETE operations

**Configuration**:

```sql
-- Enable logical replication
ALTER SYSTEM SET wal_level = logical;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET max_wal_senders = 10;

-- Create replication slot (done by connector)
SELECT pg_create_logical_replication_slot('debezium_slot', 'pgoutput');
```

### 2. Confluent Postgres Source Connector (Debezium)

**Purpose**: Captures database changes and streams them to Kafka

**How It Works**:

- Uses Debezium PostgreSQL connector (based on logical replication)
- Connects to PostgreSQL replication slot
- Reads WAL changes and converts them to change events
- Publishes events to Kafka topics in Avro format
- Maintains offset tracking for exactly-once semantics

**Configuration**: See `connectors/postgres-source-connector.json`

### 3. Kafka Broker

**Key Topics**:

- `raw-business-events`: All CDC events from PostgreSQL (3 partitions)
- `filtered-loan-events`: Loan-related events (3 partitions)
- `filtered-service-events`: Service-related events (3 partitions)
- `filtered-car-events`: Car-related events (3 partitions)

### 4. Schema Registry

**Purpose**: Centralized schema management and validation for Avro-formatted events

**How It Works**:

- Stores Avro schemas for Kafka topics
- Validates producer messages against registered schemas
- Enforces schema evolution policies (BACKWARD, FORWARD, FULL)
- Provides schema versioning and compatibility checking

### 5. Flink Cluster

**Purpose**: Stateful stream processing engine for filtering and routing events

#### Confluent Cloud for Apache Flink (Managed Service)

**Confluent Cloud for Apache Flink** is a fully managed, cloud-native Flink service that provides:

- **Compute Pools**: Resource allocation units measured in CFUs (Confluent Flink Units)
- **SQL Statements**: Deploy Flink jobs as SQL statements (no JAR files required)
- **Auto-Scaling**: Automatically adjusts resources based on workload demands
- **Managed Infrastructure**: No need to manage JobManager or TaskManager instances
- **Built-in Integration**: Seamless integration with Schema Registry, RBAC, and private networking
- **High Availability**: Automatic failover and data replication

**Compute Pools**:

- **Purpose**: Isolated compute resources for Flink SQL statements
- **Sizing**: Configured with maximum CFUs (e.g., 4 CFU, 8 CFU)
- **Auto-Scaling**: Automatically scales up/down based on input topic rates
- **Multi-Region**: Deploy separate compute pools per region for active-active setup

**SQL Statements**:

- **Deployment Model**: Flink jobs are deployed as SQL statements, not JAR files
- **Management**: Create, update, and delete statements via Console, CLI, or REST API
- **Versioning**: SQL statements are versioned and can be updated without downtime
- **Monitoring**: Built-in monitoring and metrics for each statement

**How It Works**:

- **Consumes from Kafka**: Reads events from `raw-business-events` topic (acts as Kafka consumer)
- **Applies Filtering**: Applies filtering logic defined in Flink SQL statements
- **Writes to Kafka**: Writes filtered events to consumer-specific Kafka topics (acts as Kafka producer)
  - `filtered-loan-events`
  - `filtered-service-events`
  - `filtered-car-events`
- **Enriches Events**: Adds `filterMetadata` (filterId, consumerId, timestamp) to each event
- **Maintains State**: Maintains exactly-once semantics via automatic checkpoints
- **Auto-Scales**: Automatically adjusts compute resources based on throughput

**Deployment Example** (Confluent Cloud):

```bash
# Create compute pool
confluent flink compute-pool create prod-flink-east \
  --cloud aws \
  --region us-east-1 \
  --max-cfu 4

# Deploy SQL statement
confluent flink statement create \
  --compute-pool cp-east-123 \
  --statement-name event-routing-job \
  --statement-file flink-jobs/routing-generated.sql
```

### 6. Flink SQL Jobs

**Purpose**: Declarative stream processing queries for filtering and routing events

#### Confluent Cloud Flink SQL Statements

In **Confluent Cloud**, Flink jobs are deployed as **SQL statements** rather than JAR files:

- **Statement-Based Deployment**: Deploy SQL directly without compiling to JARs
- **Version Control**: SQL statements are versioned and can be updated in place
- **Built-in Monitoring**: Each statement has built-in metrics and monitoring
- **Auto-Scaling**: Statements automatically scale based on input topic rates

**How It Works**:

- **Source Tables**: Defines source tables that read from Kafka topics (e.g., `raw-business-events`)
- **Sink Tables**: Defines sink tables that write to filtered Kafka topics (e.g., `filtered-loan-events`)
  - **Auto-Topic Creation (anti-pattern?)**: Filtered topics are automatically created by Flink when it writes to them for the first time
- **Filtering**: Uses SQL WHERE clauses to filter events based on business rules
- **Routing**: Routes matching events to different Kafka topics based on filter conditions
- **Fault Tolerance**: Automatic checkpoints ensure exactly-once semantics (managed by Confluent Cloud)

**Example Flink SQL Statement**:

```sql
-- Source: Read from raw-business-events topic
CREATE TABLE raw_business_events (
  eventHeader ROW<uuid STRING, eventName STRING, createdDate BIGINT, savedDate BIGINT, eventType STRING>,
  eventBody ROW<entities ARRAY<ROW<entityType STRING, entityId STRING, updatedAttributes MAP<STRING, STRING>>>>,
  sourceMetadata ROW<table STRING, operation STRING, timestamp BIGINT>,
  proctime AS PROCTIME(),
  eventtime AS TO_TIMESTAMP_LTZ(eventHeader.createdDate, 3),
  WATERMARK FOR eventtime AS eventtime - INTERVAL '5' SECOND
) WITH (
  'connector' = 'kafka',
  'topic' = 'raw-business-events',  -- Input topic
  'properties.bootstrap.servers' = 'pkc-xxxxx.us-east-1.aws.confluent.cloud:9092',
  'properties.security.protocol' = 'SASL_SSL',
  'properties.sasl.jaas.config' = 'org.apache.kafka.common.security.plain.PlainLoginModule required username="..." password="...";',
  'format' = 'avro',
  'avro.schema-registry.url' = 'https://psrc-xxxxx.us-east-1.aws.confluent.cloud',
  'scan.startup.mode' = 'earliest-offset'
);

-- Sink: Write to filtered-loan-events topic
CREATE TABLE filtered_loan_events (
  eventHeader ROW<uuid STRING, eventName STRING, createdDate BIGINT, savedDate BIGINT, eventType STRING>,
  eventBody ROW<entities ARRAY<ROW<entityType STRING, entityId STRING, updatedAttributes MAP<STRING, STRING>>>>,
  sourceMetadata ROW<table STRING, operation STRING, timestamp BIGINT>,
  filterMetadata ROW<filterId STRING, consumerId STRING, filteredAt BIGINT>
) WITH (
  'connector' = 'kafka',
  'topic' = 'filtered-loan-events',  -- Output topic (consumers read from here)
  'properties.bootstrap.servers' = 'pkc-xxxxx.us-east-1.aws.confluent.cloud:9092',
  'properties.security.protocol' = 'SASL_SSL',
  'properties.sasl.jaas.config' = 'org.apache.kafka.common.security.plain.PlainLoginModule required username="..." password="...";',
  'format' = 'avro',
  'avro.schema-registry.url' = 'https://psrc-xxxxx.us-east-1.aws.confluent.cloud',
  'sink.partitioner' = 'fixed'
);

-- Filter and route: Flink writes filtered events to the sink topic
INSERT INTO filtered_loan_events
SELECT 
  eventHeader,
  eventBody,
  sourceMetadata,
  ROW('loan-events-filter', 'loan-consumer', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'LoanCreated' 
   OR eventHeader.eventName = 'LoanPaymentSubmitted';
```

**Deployment** (Confluent Cloud):

```bash
# Deploy SQL statement to compute pool
confluent flink statement create \
  --compute-pool cp-east-123 \
  --statement-name event-routing-job \
  --statement-file flink-jobs/routing-generated.sql

# Update existing statement
confluent flink statement update \
  --compute-pool cp-east-123 \
  --statement-id ss-456789 \
  --statement-file flink-jobs/routing-generated.sql

# List statements
confluent flink statement list --compute-pool cp-east-123

# Get statement status
confluent flink statement describe ss-456789 --compute-pool cp-east-123
```

**Topic Creation**: Filtered topics (`filtered-loan-events`, etc.) are automatically created by Flink when it writes to them for the first time. No manual topic creation is required for filtered topics. Only the `raw-business-events` topic needs to be created manually before deploying the CDC connector.

**Filter Types Supported**:

- **Event Name Filtering**: Filter by `eventHeader.eventName`
- **Entity Type Filtering**: Filter by `eventBody.entities[].entityType`
- **Value-Based Filtering**: Numeric comparisons (>, <, >=, <=, BETWEEN)
- **Pattern Matching**: Regex patterns for string fields
- **Multi-Condition Filtering**: Combine conditions with AND/OR logic

### 7. Consumer Applications

**Purpose**: Process filtered events from consumer-specific Kafka topics

**How Consumers Get Filtered Events**:

Consumers **do NOT connect to Flink**. Instead, they connect directly to **Kafka** and subscribe to the filtered topics that Flink writes to. Here's the complete flow:

1. **Flink SQL Jobs Write to Kafka Topics**:
   - Flink SQL jobs consume from `raw-business-events` topic
   - After filtering and transformation, Flink writes filtered events to consumer-specific Kafka topics:
     - `filtered-loan-events`
     - `filtered-service-events`
     - `filtered-car-events`
   - These topics are **created in Kafka** (either manually or automatically by Flink)
   - Flink acts as a **producer** to these filtered topics

2. **Consumers Connect to Kafka**:
   - Consumer applications connect to Kafka brokers using `bootstrap.servers`
   - They subscribe to the filtered topics using Kafka consumer groups
   - Consumers are standard Kafka consumers - they have no direct connection to Flink

**Topic Creation**:

- Filtered topics can be created:
  1. **Manually**: Using `kafka-topics.sh` or Confluent Cloud Console before deploying Flink jobs
  2. **Automatically (anti-pattern)**: By Flink when it first writes to the topic (if `auto.create.topics.enable=true` in Kafka)
  3. **Via Infrastructure as Code**: Using Terraform or similar tools

## Fundamentals Section

### Change Data Capture (CDC)

**Concept**: Capture and track changes to data in a database in real-time

**How It Works**:

1. **Logical Replication**: PostgreSQL WAL contains all changes
2. **Replication Slot**: Connector creates a slot to read WAL changes
3. **Change Events**: Each INSERT/UPDATE/DELETE becomes an event
4. **Event Structure**: Contains before/after state and metadata
5. **Streaming**: Events are immediately published to Kafka

## Configuration and Code Generation

### YAML Filter Configuration System

**Purpose**: Declarative filter definitions that generate Flink SQL automatically

**Structure**: See `flink-jobs/filters.yaml` for examples

**Supported Operators**:

- `equals`: Exact match
- `in`: Match any value in list
- `notIn`: Exclude values in list
- `greaterThan`, `lessThan`, `greaterThanOrEqual`, `lessThanOrEqual`: Numeric comparisons
- `between`: Range check
- `matches`: Regex pattern matching
- `isNull`, `isNotNull`: Null checks

For detailed information, see [CODE_GENERATION.md](CODE_GENERATION.md).

---

## Production Deployment Considerations

### Disaster Recovery

For comprehensive disaster recovery procedures, backup strategies, failover mechanisms, and testing methodologies, see [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md).

**Summary**:

- **Backup Strategy**: Multi-level backup approach with replication, snapshots, and savepoints
- **Recovery Procedures**: Component-specific recovery steps for Kafka, Flink, connectors, and consumers
- **RTO/RPO Targets**: < 1 hour RTO, < 5 minutes RPO
- **Multi-Region**: Active-active setup with automatic failover
- **Testing**: Regular disaster recovery drills and automated testing

### Performance Tuning

For comprehensive performance tuning strategies, optimization techniques, and troubleshooting guides, see [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md).

**Summary**:

- **Kafka Tuning**: Broker configuration, topic settings, producer/consumer optimization
- **Flink Tuning**: Parallelism, state backend, checkpoint configuration, operator optimization
- **Connector Tuning**: Batch settings, parallel processing, PostgreSQL optimization
- **Consumer Tuning**: Batch processing, parallel processing, consumer group scaling
- **Infrastructure Tuning**: Network, disk I/O, CPU, memory optimization
- **Monitoring**: Key metrics, performance testing, troubleshooting procedures

## Related Documentation

- **[DISASTER_RECOVERY.md](DISASTER_RECOVERY.md)**: Comprehensive disaster recovery procedures and failover mechanisms
- **[PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md)**: Performance optimization strategies and tuning guides
- **[CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md)**: Complete Confluent Cloud setup guide

## References

- [Confluent Platform Documentation](https://docs.confluent.io/)
- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Apache Flink Documentation](https://nightlies.apache.org/flink/flink-docs-stable/)
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)
- [Schema Registry Documentation](https://docs.confluent.io/platform/current/schema-registry/index.html)
