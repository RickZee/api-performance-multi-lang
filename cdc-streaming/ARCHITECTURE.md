# CDC Streaming Architecture Documentation

## Executive Summary

This document describes a comprehensive Change Data Capture (CDC) streaming architecture that enables real-time event processing from PostgreSQL databases to Kafka, with intelligent filtering and routing using Apache Flink. The system is designed for our use case requiring high availability, compliance, auditability, and real-time data processing capabilities.

### Key Capabilities

- **Real-time CDC**: Captures database changes (INSERT, UPDATE, DELETE) from PostgreSQL tables and streams them to Kafka
- **Intelligent Filtering**: Configurable YAML-based filter definitions that automatically generate Flink SQL for event filtering
- **Multi-topic Routing**: Routes filtered events to consumer-specific Kafka topics based on business rules
- **Schema Management**: Avro schema enforcement via Schema Registry for data contract validation
- **Scalable Processing**: Apache Flink for stateful stream processing with horizontal scaling
- **Code Generation**: Automated SQL generation from declarative filter configurations
- **CI/CD Integration**: Infrastructure-as-code ready with validation and testing capabilities

### Relevance to Our Use Case

Our use case requires:

- **Real-time Processing**: Immediate visibility into transactions, loan applications, and service events
- **Compliance & Audit**: Complete data lineage from source database to consumers with metadata tracking
- **High Availability**: Multi-region deployment with active-active replication
- **Security**: Encrypted data in transit, schema validation, and access controls
- **Scalability**: Handle millions of events per day with horizontal scaling
- **Operational Excellence**: Monitoring, alerting, and automated recovery mechanisms

This architecture addresses all these requirements through its component design and operational patterns.

---

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
│                    Kafka Connect (Source Connector)                     │
│              Confluent Postgres Source Connector                        │
│              (Debezium-based CDC)                                       │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ Avro Serialized Events
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Schema Registry                                 │
│              Schema Validation & Evolution                              │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ Validated Events
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Kafka: raw-business-events                           │
│              (3 partitions, Avro format)                                │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ Stream Processing
                               ▼
┌────────────────────────────────────────────────────────────────────────┐
│                    Apache Flink Cluster                                │
│  ┌──────────────────┐              ┌──────────────────┐                │
│  │  JobManager      │              │  TaskManager(s)  │                │
│  │  - Coordinates   │◄────────────►│  - Executes      │                │
│  │  - Schedules     │              │  - Processes     │                │
│  └──────────────────┘              └──────────────────┘                │
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
│  │filtered-loan-events  │  │filtered-service-    │  │filtered-car- │   │
│  │                      │  │events               │  │events        │   │
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

**Key Point**: Consumers **do NOT connect to Flink**. They connect directly to **Kafka** and read from filtered topics that Flink writes to.

**Complete Flow**:

1. **PostgreSQL** → Database changes captured via CDC
2. **CDC Connector** → Publishes to `raw-business-events` Kafka topic
3. **Flink SQL Job** →
   - Consumes from `raw-business-events` (acts as Kafka consumer)
   - Filters and transforms events
   - **Writes to filtered Kafka topics** (acts as Kafka producer):
     - `filtered-loan-events`
     - `filtered-service-events`
     - `filtered-car-events`
4. **Consumer Applications** →
   - Connect to **Kafka brokers** (not Flink)
   - Subscribe to filtered topics using Kafka consumer groups
   - Process events independently of Flink

**Architecture Benefits**:

- **Decoupling**: Consumers are completely decoupled from Flink
- **Scalability**: Scale consumers independently without affecting Flink
- **Fault Tolerance**: Consumer failures don't affect Flink jobs
- **Replay Capability**: Consumers can reprocess events by resetting offsets
- **Multiple Consumers**: Multiple consumer groups can read from the same filtered topic

For detailed component descriptions, see the [Component Deep Dive](#component-deep-dive) section below.

---

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

**Relevance to Our Use Case**:

- **Audit Trail**: WAL provides immutable record of all changes
- **Zero Impact**: Logical replication doesn't lock tables or impact application performance
- **Point-in-Time Recovery**: WAL enables recovery to any point in time
- **Compliance**: Complete change history for regulatory reporting

### 2. Confluent Postgres Source Connector (Debezium)

**Purpose**: Captures database changes and streams them to Kafka

**How It Works**:

- Uses Debezium PostgreSQL connector (based on logical replication)
- Connects to PostgreSQL replication slot
- Reads WAL changes and converts them to change events
- Publishes events to Kafka topics in Avro format
- Maintains offset tracking for exactly-once semantics

**Configuration**: See `connectors/postgres-source-connector.json`

**Relevance to Our Use Case**:

- **Exactly-Once Semantics**: Ensures no duplicate or lost events
- **Transaction Integrity**: Captures complete transactions
- **Low Latency**: Sub-second change propagation
- **Schema Evolution**: Handles schema changes gracefully with Schema Registry

### 3. Kafka Broker

**Purpose**: Distributed streaming platform for event storage and distribution

**How It Works**:

- Topics organize events by category
- Partitions enable parallel processing and scalability
- Replication ensures high availability
- Consumer groups enable multiple consumers to process different partitions
- Retention policies control data lifecycle

**Key Topics**:

- `raw-business-events`: All CDC events from PostgreSQL (3 partitions)
- `filtered-loan-events`: Loan-related events (3 partitions)
- `filtered-service-events`: Service-related events (3 partitions)
- `filtered-car-events`: Car-related events (3 partitions)

**Relevance to Our Use Case**:

- **Durability**: Events are persisted to disk with replication
- **Ordering**: Partition-level ordering guarantees for related events
- **Scalability**: Add partitions to increase throughput
- **Replay Capability**: Consumers can reprocess historical events
- **Multi-Region**: Cluster linking enables active-active replication

### 4. Schema Registry

**Purpose**: Centralized schema management and validation for Avro-formatted events

**How It Works**:

- Stores Avro schemas for Kafka topics
- Validates producer messages against registered schemas
- Enforces schema evolution policies (BACKWARD, FORWARD, FULL)
- Provides schema versioning and compatibility checking
- Enables schema-less consumers (schema embedded in messages)

**Relevance to Our Use Case**:

- **Data Contract Enforcement**: Prevents invalid data from entering the system
- **Schema Evolution**: Supports adding fields without breaking consumers (BACKWARD compatibility)
- **Audit Trail**: Schema versions tracked for compliance
- **Type Safety**: Avro provides strong typing and validation
- **Data Governance**: Centralized schema management for data lineage

### 5. Apache Flink Cluster

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

#### Self-Managed Flink (Alternative)

For self-managed deployments, Flink runs as a traditional cluster:

- **JobManager**: Coordinates job execution, manages checkpoints
- **TaskManager**: Executes tasks, manages network buffers, maintains state
- **Deployment**: Deploy as JAR files or SQL scripts via Flink CLI or REST API
- **Manual Scaling**: Manually add TaskManagers for scaling
- **Infrastructure Management**: You manage all infrastructure components

**Important**: Flink does **not** directly serve events to consumer applications. Instead, Flink writes filtered events to Kafka topics, and consumers read from those topics independently.

**Relevance to Our Use Case**:

- **Exactly-Once Processing**: Guarantees no duplicate or lost events
- **Stateful Processing**: Maintains state for windowed aggregations and joins
- **Low Latency**: Sub-second event processing
- **Fault Tolerance**: Automatic recovery from failures via checkpoints (managed automatically in Confluent Cloud)
- **Scalability**: Horizontal scaling by adding TaskManagers (or auto-scaling in Confluent Cloud)
- **Operational Simplicity**: Managed service reduces operational overhead
- **Cost Efficiency**: Pay only for compute resources used (auto-scaling)

### 6. Flink SQL Jobs

**Purpose**: Declarative stream processing queries for filtering and routing events

#### Confluent Cloud Flink SQL Statements

In **Confluent Cloud**, Flink jobs are deployed as **SQL statements** rather than JAR files:

- **Statement-Based Deployment**: Deploy SQL directly without compiling to JARs
- **Version Control**: SQL statements are versioned and can be updated in place
- **Zero-Downtime Updates**: Update statements without stopping processing
- **Built-in Monitoring**: Each statement has built-in metrics and monitoring
- **Auto-Scaling**: Statements automatically scale based on input topic rates

**How It Works**:

- **Source Tables**: Defines source tables that read from Kafka topics (e.g., `raw-business-events`)
- **Sink Tables**: Defines sink tables that write to filtered Kafka topics (e.g., `filtered-loan-events`)
- **Filtering**: Uses SQL WHERE clauses to filter events based on business rules
- **Transformation**: SELECT statements transform and enrich events (adds `filterMetadata`)
- **Routing**: Routes matching events to different Kafka topics based on filter conditions
- **Time Processing**: Watermarks enable time-based processing and windowing
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

**Topic Creation**: The filtered topics (`filtered-loan-events`, etc.) must exist in Kafka before Flink can write to them. Create topics via Confluent Cloud Console, CLI, or Terraform.

**Filter Types Supported**:

- **Event Name Filtering**: Filter by `eventHeader.eventName`
- **Entity Type Filtering**: Filter by `eventBody.entities[].entityType`
- **Value-Based Filtering**: Numeric comparisons (>, <, >=, <=, BETWEEN)
- **Pattern Matching**: Regex patterns for string fields
- **Multi-Condition Filtering**: Combine conditions with AND/OR logic

**Relevance to Our Use Case**:

- **Business Logic as Code**: SQL queries are version-controlled and auditable
- **Real-Time Filtering**: Immediate routing based on business rules
- **Metadata Enrichment**: Adds filterId and consumerId for audit trails
- **Flexible Rules**: Easy to modify filters without code changes
- **Performance**: Efficient filtering using Flink's optimized execution engine

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

3. **Event Flow**:

   ```text
   PostgreSQL → CDC Connector → raw-business-events (Kafka)
                                      ↓
                                 Flink SQL Job
                                      ↓
                    filtered-loan-events (Kafka topic)
                                      ↓
                              Loan Consumer (Kafka consumer)
   ```

**How It Works**:

- **Connect to Kafka**: Consumers connect to Kafka brokers (not Flink)
- **Subscribe to Filtered Topics**: Subscribe to consumer-specific topics (e.g., `filtered-loan-events`)
- **Use Consumer Groups**: Join consumer groups for parallel processing and fault tolerance
- **Deserialize Messages**: Deserialize Avro messages using Schema Registry
- **Process Events**: Process events according to business logic
- **Commit Offsets**: Commit offsets to track processing progress
- **Handle Errors**: Implement error handling and retries gracefully

**Example Consumer Configuration**:

```python
# Consumer connects to Kafka, not Flink
consumer_config = {
    'bootstrap.servers': 'kafka:29092',  # Kafka broker address
    'group.id': 'loan-consumer-group',
    'auto.offset.reset': 'earliest',
    'enable.auto.commit': True
}

# Subscribe to filtered topic (created/written by Flink)
consumer = Consumer(consumer_config)
consumer.subscribe(['filtered-loan-events'])  # Topic written by Flink SQL job
```

**Topic Creation**:

- Filtered topics can be created:
  1. **Manually**: Using `kafka-topics.sh` or Confluent Cloud Console before deploying Flink jobs
  2. **Automatically**: By Flink when it first writes to the topic (if `auto.create.topics.enable=true` in Kafka)
  3. **Via Infrastructure as Code**: Using Terraform or similar tools

**Relevance to Our Use Case**:

- **Isolated Processing**: Each consumer processes only relevant events from its dedicated topic
- **Decoupling**: Consumers are completely decoupled from Flink - they only depend on Kafka
- **Parallel Processing**: Multiple consumers in a group process different partitions
- **Fault Tolerance**: Consumer failures don't affect other consumers or Flink jobs
- **Scalability**: Add consumers to increase processing capacity independently of Flink
- **Replay Capability**: Consumers can reprocess historical events by resetting offsets
- **Audit Trail**: Consumer logs provide processing history

---

## Fundamentals Section

### Change Data Capture (CDC)

**Concept**: Capture and track changes to data in a database in real-time

**How It Works**:

1. **Logical Replication**: PostgreSQL WAL contains all changes
2. **Replication Slot**: Connector creates a slot to read WAL changes
3. **Change Events**: Each INSERT/UPDATE/DELETE becomes an event
4. **Event Structure**: Contains before/after state and metadata
5. **Streaming**: Events are immediately published to Kafka

**Benefits**:

- **Real-Time**: Changes propagate within seconds
- **Low Impact**: Doesn't affect database performance
- **Complete History**: All changes are captured
- **Decoupling**: Applications don't need to poll database

### Kafka Fundamentals

**Topics**: Categories or feeds of events

- **Partitions**: Topics are divided into partitions for parallelism
- **Replication**: Partitions are replicated across brokers for durability
- **Ordering**: Events within a partition are ordered

**Producers**: Applications that publish events to topics

- **Partitioning**: Events can be partitioned by key for ordering
- **Acknowledgment**: Configurable acknowledgment levels (0, 1, all)

**Consumers**: Applications that read events from topics

- **Consumer Groups**: Multiple consumers share work via consumer groups
- **Offset Management**: Track position in partition for each consumer
- **Rebalancing**: Automatic redistribution when consumers join/leave

### Flink Streaming Fundamentals

**Stream Processing**: Continuous processing of unbounded data streams

**Key Concepts**:

- **Sources**: Read from Kafka, files, or other systems
- **Sinks**: Write to Kafka, databases, or other systems
- **Operators**: Transform, filter, aggregate, join streams
- **State**: Maintain state for windowed operations and joins
- **Watermarks**: Handle late-arriving events in time-based processing
- **Checkpoints**: Periodic snapshots for fault tolerance

**Exactly-Once Semantics**:

- **Checkpoints**: Periodic snapshots of operator state
- **Two-Phase Commit**: Ensures atomic writes to sinks
- **Recovery**: Restore from checkpoint after failure

---

## Our Use Case Relevance

### Compliance and Audit Requirements

**Data Lineage**:

- Every event includes `sourceMetadata` (table, operation, timestamp)
- `filterMetadata` tracks which filter matched and when
- Complete traceability from database to consumer

**Audit Trail**:

- All changes captured in WAL and streamed to Kafka
- Events are immutable and timestamped
- Consumer logs provide processing history

### Real-Time Processing Needs

**Loan Processing**:

- Immediate notification when loan is created
- Real-time fraud detection on loan applications
- Instant updates to credit scoring systems

**Latency Requirements**:

- **CDC Capture**: < 1 second
- **Kafka Propagation**: < 100ms
- **Flink Processing**: < 500ms
- **Total End-to-End**: < 2 seconds

### Scalability and Resilience

**Horizontal Scaling**:

- **Kafka**: Add partitions and brokers
- **Flink**: Add TaskManagers
- **Consumers**: Add consumer instances

**Fault Tolerance**:

- **Kafka**: Replicated partitions survive broker failures
- **Flink**: Checkpoints enable recovery without data loss
- **Connectors**: Automatic retry and error handling

---

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

---

## Conclusion

This CDC streaming architecture provides a robust, scalable, and compliant solution for real-time data processing in our use case. Key strengths include:

- **Real-Time Processing**: Sub-second event propagation and processing
- **Scalability**: Horizontal scaling for high throughput
- **Fault Tolerance**: Automatic recovery and exactly-once semantics
- **Compliance**: Complete audit trail and data lineage
- **Operational Excellence**: Monitoring, alerting, and automated deployments
- **Flexibility**: Configurable filters and code generation

The system is production-ready and can be deployed to Confluent Cloud or self-managed infrastructure with appropriate security, monitoring, and disaster recovery configurations.

---

## Related Documentation

- **[CODE_GENERATION.md](CODE_GENERATION.md)**: Guide to YAML filter configuration and SQL code generation
- **[DISASTER_RECOVERY.md](DISASTER_RECOVERY.md)**: Comprehensive disaster recovery procedures and failover mechanisms
- **[PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md)**: Performance optimization strategies and tuning guides
- **[CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md)**: Complete Confluent Cloud setup guide

## References

- [Confluent Platform Documentation](https://docs.confluent.io/)
- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Apache Flink Documentation](https://nightlies.apache.org/flink/flink-docs-stable/)
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)
- [Schema Registry Documentation](https://docs.confluent.io/platform/current/schema-registry/index.html)
