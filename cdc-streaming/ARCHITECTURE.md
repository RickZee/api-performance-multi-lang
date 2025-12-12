# CDC Streaming Architecture Documentation

## Summary

Change Data Capture (CDC) streaming architecture that enables real-time event processing from PostgreSQL databases to Kafka, with filtering and routing using Apache Flink.

### Key Capabilities

- **Real-time CDC**: Captures database changes (INSERT, UPDATE, DELETE) from PostgreSQL tables and streams them to Kafka
- **Intelligent Filtering**: Configurable YAML-based filter definitions that automatically generate Flink SQL for event filtering
- **Multi-topic Routing**: Routes filtered events to consumer-specific Kafka topics based on business rules
- **Schema Management**: Schema Registry available for schema validation (currently using JSON format, Avro schemas available for future use)
- **Scalable Processing**: Apache Flink for stateful stream processing with horizontal scaling
- **Code Generation**: Automated SQL generation from declarative filter configurations
- **CI/CD Integration**: Infrastructure-as-code ready with validation and testing capabilities
- **Cost Optimization**: Aurora auto-start/stop functionality for dev/staging environments (automatically stops database after inactivity, starts on API requests)

### Example Data Structures

This architecture uses specific example structures for validation and testing:

- **Car Entity**: [`data/entities/car/car-large.json`](../data/entities/car/car-large.json) - Large car entity with all required fields
- **Loan Created Event**: [`data/schemas/event/samples/loan-created-event.json`](../data/schemas/event/samples/loan-created-event.json) - Complete loan created event structure

These examples are used throughout the system for:

- Filter configuration (specifically targeting `LoanCreated` events)
- Test data generation
- Entity validation
- Schema documentation

## System Architecture Overview

### High-Level Data Flow

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                         PostgreSQL Database                             │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ business_events table                                            │   │
│  │ - id, event_name, event_type, created_date, saved_date           │   │
│  │ - event_data (JSONB) - full event structure                      │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ CDC Capture (Logical Replication)
                               │ Captures relational columns + event_data JSONB
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                 Kafka Connect (Source Connector)                        │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Confluent Managed PostgresCdcSource OR Debezium Connector        │   │
│  │ - Extracts relational columns (id, event_name, event_type, etc.) │   │
│  │ - Includes event_data as JSON string                             │   │
│  │ - Adds CDC metadata (__op, __table, __ts_ms)                     │   │
│  │ - Uses ExtractNewRecordState transform                           │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ JSON Serialized Events
                               │ (Relational structure with event_data JSONB)
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        Schema Registry                                  │
│  Available for schema validation (currently JSON format)                │
│  Avro schemas available for future use                                  │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ JSON Events
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Kafka: raw-business-events                           │
│  Format: JSON                                                           │
│  Structure: id, event_name, event_type, created_date, saved_date,       │
│            event_data (JSON string), __op, __table, __ts_ms             │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ Stream Processing
                               ▼
┌────────────────────────────────────────────────────────────────────────┐
│                    Confluent Flink                                     │
│                                                                        │
│  Flink SQL Jobs:                                                       │
│  - Filter by event_type, __op (operation type)                         │
│  - Route to consumer-specific topics                                   │
│  - Preserves relational structure + event_data                         │
└──────────────────────────────┬─────────────────────────────────────────┘
                               │
                               │ Filtered & Routed Events (JSON)
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Consumer-Specific Kafka Topics                       │
│  ┌──────────────────────────┐    ┌──────────────────────────┐           │
│  │filtered-loan-created-    │    │filtered-service-events   │           │
│  │events                    │    └──────────────────────────┘           │
│  └──────────────────────────┘    ┌──────────────────────────┐           │
│  ┌──────────────────────────┐    │filtered-car-created-     │           │
│  │filtered-loan-payment-    │    │events                    │           │
│  │submitted-events          │    └──────────────────────────┘           │
│  └──────────────────────────┘                                           │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               │ Consume Events
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Consumer Applications                                │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐       │
│  │ Loan Consumer    │  │Loan Payment      │  │Service Consumer  │       │
│  │ - Topic:         │  │Consumer          │  │ - Topic:         │       │
│  │   filtered-loan- │  │ - Topic:         │  │   filtered-      │       │
│  │   created-events │  │   filtered-loan- │  │   service-events │       │
│  │ - Parses relational │   payment-       │  │ - Parses relational      │
│  │   structure +    │  │   submitted-     │  │   structure +    │       │
│  │   event_data     │  │   events         │  │   event_data     │       │
│  │   JSON string    │  │ - Parses relational │   JSON string    │       │
│  └──────────────────┘  │   structure +    │  └──────────────────┘       │
│  ┌──────────────────┐  │   event_data     │  ┌──────────────────┐       │
│  │ Car Consumer     │  │   JSON string    │  │ All consumers    │       │
│  │ - Topic:         │  └──────────────────┘  │ connect to       │       │
│  │   filtered-car-  │                        │ Confluent Cloud  │       │
│  │   created-events │                        │  with SASL_SSL   │       │
│  │ - Parses relational                       │ authentication   │       │
│  │   structure +    │                        └──────────────────┘       │
│  │   event_data     │                                                   │
│  │   JSON string    │                                                   │
│  └──────────────────┘                                                   │
└─────────────────────────────────────────────────────────────────────────┘
```


## Data Model Architecture

### Hybrid Data Model: Relational Columns + JSONB

The architecture uses a **hybrid data model** that combines the benefits of both relational structures and nested JSON:

**Database Layer (PostgreSQL)**:

```sql
CREATE TABLE business_events (
    -- Relational columns for efficient filtering and querying
    id VARCHAR(255) PRIMARY KEY,
    event_name VARCHAR(255) NOT NULL,
    event_type VARCHAR(255),
    created_date TIMESTAMP WITH TIME ZONE,
    saved_date TIMESTAMP WITH TIME ZONE,
    
    -- JSONB column for full event structure
    event_data JSONB NOT NULL  -- Contains: {eventHeader: {...}, eventBody: {...}}
);
```

**Benefits of This Approach**:

1. **Efficient Filtering**: Relational columns (`event_type`, `event_name`) enable fast filtering in Flink SQL without JSON parsing
2. **Full Data Preservation**: JSONB `event_data` column preserves complete nested event structure
3. **Index Support**: PostgreSQL can index relational columns for fast queries
4. **Flexibility**: Consumers can access both relational metadata and nested entity data
5. **CDC Compatibility**: CDC connectors can efficiently capture both column values and JSONB content

**Data Flow Through the System**:

1. **Producer APIs** → Insert events with:
   - Relational columns extracted from `eventHeader`
   - Full event JSON stored in `event_data` JSONB column

2. **CDC Connector** → Captures:
   - Relational column values as separate fields
   - `event_data` JSONB as JSON string
   - Adds CDC metadata (`__op`, `__table`, `__ts_ms`)

3. **Kafka Topics** → Store events as JSON with:
   - Relational structure: `id`, `event_name`, `event_type`, `created_date`, `saved_date`
   - `event_data`: JSON string containing full nested structure
   - CDC metadata: `__op`, `__table`, `__ts_ms`

4. **Flink SQL** → Filters using:
   - Relational columns (`event_type`, `__op`) for efficient filtering
   - Preserves `event_data` JSON string for consumers

5. **Consumers** → Process events by:
   - Using relational columns for routing/metadata
   - Parsing `event_data` JSON string to access nested structure

**Example Event Structure**:

**In Database (business_events table)**:

```sql
id: "event-123"
event_name: "LoanCreated"
event_type: "LoanCreated"
created_date: "2024-01-15T10:30:00Z"
saved_date: "2024-01-15T10:30:05Z"
event_data: {
  "eventHeader": {
    "uuid": "event-123",
    "eventName": "LoanCreated",
    "createdDate": 1705312200000,
    "savedDate": 1705312205000,
    "eventType": "LoanCreated"
  },
  "eventBody": {
    "entities": [{
      "entityType": "Loan",
      "entityId": "loan-456",
      "updatedAttributes": {
        "loan": {
          "loanAmount": 50000,
          "balance": 50000,
          "status": "active"
        }
      }
    }]
  }
}
```

**In Kafka (raw-business-events topic)**:

The event structure in Kafka depends on the connector configuration:

**With ExtractNewRecordState Transform** (Recommended connectors):

```json
{
  "id": "event-123",
  "event_name": "LoanCreated",
  "event_type": "LoanCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "event_data": "{\"eventHeader\":{...},\"eventBody\":{...}}",
  "__op": "c",
  "__table": "business_events",
  "__ts_ms": 1705312205000
}
```

## Component Deep Dive

### 1. PostgreSQL Database (Source)

**Purpose**: The source of truth for business events stored in the `business_events` table

**Database Schema**:

The `business_events` table schema is defined in the [Data Model Architecture](#data-model-architecture) section. It uses a hybrid approach combining relational columns for efficient filtering and a JSONB column for full event data.

**How It Works**:

- Producer APIs insert events into `business_events` table with both relational columns and full JSONB data
- PostgreSQL Write-Ahead Log (WAL) records all changes
- Logical replication slots enable CDC capture without impacting database performance
- CDC connector captures both relational column values and the `event_data` JSONB content
- Relational columns enable efficient filtering in Flink SQL
- JSONB column preserves full event structure for consumers

**Configuration**:

```sql
-- Enable logical replication
ALTER SYSTEM SET wal_level = logical;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET max_wal_senders = 10;

-- Create replication slot (done by connector)
SELECT pg_create_logical_replication_slot('business_events_cdc_slot', 'pgoutput');
```

**Back-End Infrastructure**:

For details on RDS Proxy, Aurora Auto-Start/Stop, and Lambda functions, see [BACKEND_IMPLEMENTATION.md](BACKEND_IMPLEMENTATION.md).

### 2. CDC Source Connector

**Purpose**: Captures database changes from `business_events` table and streams them to Kafka

**Connector Configuration**:

**PostgresCdcSourceV2 (Debezium) - Recommended**
   - **Connector Class**: `PostgresCdcSourceV2`
   - **Configuration**: `connectors/postgres-cdc-source-v2-debezium-business-events-confluent-cloud.json`
   - **Features**:
     - Fully managed connector service with V2 architecture
     - Full CDC metadata support (`__op`, `__table`, `__ts_ms`, `__deleted`)
     - Proper ExtractNewRecordState transform support
     - Best for Confluent Cloud deployments
   - **Flink SQL**: Use `business-events-routing-confluent-cloud.sql`

**How It Works**:

- Connects to PostgreSQL replication slot (created automatically)
- Reads WAL changes via logical replication
- Captures relational column values (`id`, `event_name`, `event_type`, `created_date`, `saved_date`)
- Captures `event_data` JSONB column as JSON string
- **PostgresCdcSourceV2** applies **ExtractNewRecordState** transform to unwrap Debezium envelope:
  - Extracts actual record data (not before/after structure)
  - Adds CDC metadata: `__op` (operation: 'c'=create, 'u'=update, 'd'=delete), `__table`, `__ts_ms`
- Applies **RegexRouter** transform to route to `raw-business-events` topic
- Publishes events to Kafka in **JSON format** (not Avro)
- Maintains offset tracking for exactly-once semantics

**Event Structure Output**:

The connector output structure matches the event structure in Kafka as defined in the [Data Model Architecture](#data-model-architecture) section. The PostgresCdcSourceV2 connector includes ExtractNewRecordState transform, so events include CDC metadata fields (`__op`, `__table`, `__ts_ms`, `__deleted`).

**Key Configuration**:

- **Format**: JSON (using `JsonConverter` with `schemas.enable=false`)
- **Transform**: `ExtractNewRecordState` to unwrap Debezium envelope
- **Transform**: `TopicRegexRouter` (`io.confluent.connect.cloud.transforms.TopicRegexRouter`) to route to `raw-business-events` topic
- **Table**: `public.business_events`
- **Replication Slot**: Created automatically by connector

**Configuration File**:

- `connectors/postgres-cdc-source-v2-debezium-business-events-confluent-cloud.json` - Recommended connector configuration

### 3. Kafka Broker

**Key Topics**:

- `raw-business-events`: All CDC events from PostgreSQL (3 partitions)
  - Format: JSON
  - Structure: Relational columns + `event_data` JSONB + CDC metadata
- `filtered-loan-created-events`: Loan created events (auto-created by Flink)
- `filtered-loan-payment-submitted-events`: Loan payment events (auto-created by Flink)
- `filtered-service-events`: Service-related events (auto-created by Flink)
- `filtered-car-created-events`: Car created events (auto-created by Flink)

**Topic Format**: All topics use JSON format (not Avro). Schema Registry is available for future Avro migration.

### 4. Schema Registry

**Purpose**: Centralized schema management and validation (available for future use)

**Current Implementation**:

- **Format**: Currently using JSON format for Kafka messages (no schema validation)
- **Avro Schemas**: Avro schema files exist in `schemas/` directory:
  - `schemas/raw-event.avsc` - Raw event Avro schema
  - `schemas/filtered-event.avsc` - Filtered event Avro schema
- **Future Use**: Avro schemas are available for migration when schema validation is needed

**How It Works** (when using Avro):

- Stores Avro schemas for Kafka topics
- Validates producer messages against registered schemas
- Enforces schema evolution policies (BACKWARD, FORWARD, FULL)
- Provides schema versioning and compatibility checking

**When to Use Avro vs JSON**:

- **JSON (Current)**: Simpler setup, no schema enforcement, easier debugging
- **Avro (Future)**: Schema validation, better performance, type safety, schema evolution

### 5. Flink Cluster

**Purpose**: Stateful stream processing engine for filtering and routing events

For detailed Flink setup, configuration, and SQL job deployment, see [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md).

**Overview**:

- **Consumes from Kafka**: Reads events from `raw-business-events` topic (acts as Kafka consumer)
- **Applies Filtering**: Applies filtering logic defined in Flink SQL statements using relational columns (`event_type`, `__op`)
- **Writes to Kafka**: Writes filtered events to consumer-specific Kafka topics (acts as Kafka producer)
  - `filtered-loan-created-events`
  - `filtered-loan-payment-submitted-events`
  - `filtered-service-events`
  - `filtered-car-created-events`
- **Preserves Structure**: Maintains relational structure + `event_data` JSONB field for consumers
- **Maintains State**: Maintains exactly-once semantics via automatic checkpoints
- **Auto-Scales**: Automatically adjusts compute resources based on throughput

### 6. Consumer Applications

**Purpose**: Process filtered events from consumer-specific Kafka topics

**Available Consumers**:

The system includes 4 dockerized consumers, one for each filtered topic:

1. **Loan Consumer** (`consumers/loan-consumer/`)
   - Topic: `filtered-loan-created-events`
   - Consumer Group: `loan-consumer-group`
   - Processes `LoanCreated` events

2. **Loan Payment Consumer** (`consumers/loan-payment-consumer/`)
   - Topic: `filtered-loan-payment-submitted-events`
   - Consumer Group: `loan-payment-consumer-group`
   - Processes `LoanPaymentSubmitted` events

3. **Service Consumer** (`consumers/service-consumer/`)
   - Topic: `filtered-service-events`
   - Consumer Group: `service-consumer-group`
   - Processes `CarServiceDone` events

4. **Car Consumer** (`consumers/car-consumer/`)
   - Topic: `filtered-car-created-events`
   - Consumer Group: `car-consumer-group`
   - Processes `CarCreated` events

**How Consumers Get Filtered Events**:

Consumers **do NOT connect to Flink**. Instead, they connect directly to **Kafka** (local or Confluent Cloud) and subscribe to the filtered topics that Flink writes to. Here's the complete flow:

1. **Flink SQL Jobs Write to Kafka Topics**:
   - Flink SQL jobs consume from `raw-business-events` topic
   - After filtering and transformation, Flink writes filtered events to consumer-specific Kafka topics:
     - `filtered-loan-created-events`
     - `filtered-loan-payment-submitted-events`
     - `filtered-service-events`
     - `filtered-car-created-events`
   - These topics are **created in Kafka** automatically by Flink when it first writes to them
   - Flink acts as a **producer** to these filtered topics
   - Events maintain the relational structure: `id`, `event_name`, `event_type`, `created_date`, `saved_date`, `event_data` (JSON string), `__op`, `__table`

2. **Consumers Connect to Kafka**:
   - Consumer applications connect to Kafka brokers using `bootstrap.servers`
   - They subscribe to the filtered topics using Kafka consumer groups
   - Consumers are standard Kafka consumers - they have no direct connection to Flink
   - Consumers receive JSON messages with relational structure

**Confluent Cloud Connection**:

All consumers support connecting to both local Kafka (for development) and Confluent Cloud (for production). Configuration is done via environment variables:

**Local Kafka (Development)**:

```yaml
environment:
  KAFKA_BOOTSTRAP_SERVERS: kafka:29092
  KAFKA_TOPIC: filtered-loan-created-events
  CONSUMER_GROUP_ID: loan-consumer-group
```

**Confluent Cloud**:

```yaml
environment:
  KAFKA_BOOTSTRAP_SERVERS: pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
  KAFKA_TOPIC: filtered-loan-created-events
  KAFKA_API_KEY: <your-api-key>
  KAFKA_API_SECRET: <your-api-secret>
  CONSUMER_GROUP_ID: loan-consumer-group
```

When `KAFKA_API_KEY` and `KAFKA_API_SECRET` are provided, consumers automatically use SASL_SSL authentication:

```python
consumer_config = {
    'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
    'security.protocol': 'SASL_SSL',
    'sasl.mechanism': 'PLAIN',
    'sasl.username': KAFKA_API_KEY,
    'sasl.password': KAFKA_API_SECRET,
    'group.id': CONSUMER_GROUP_ID,
    'auto.offset.reset': 'earliest',
    'enable.auto.commit': True,
}
```

**Docker Compose Configuration**:

All consumers are defined in `docker-compose.yml` and can be started together:

```bash
# Start all consumers
docker-compose up -d loan-consumer loan-payment-consumer service-consumer car-consumer

# View logs
docker-compose logs -f loan-consumer
docker-compose logs -f loan-payment-consumer
docker-compose logs -f service-consumer
docker-compose logs -f car-consumer
```

To connect to Confluent Cloud, set environment variables before starting:

```bash
export KAFKA_BOOTSTRAP_SERVERS="pkc-xxxxx.us-east-1.aws.confluent.cloud:9092"
export KAFKA_API_KEY="<your-api-key>"
export KAFKA_API_SECRET="<your-api-secret>"
docker-compose up -d
```

**Event Processing in Consumers**:

Consumers receive events in the relational structure format defined in the [Data Model Architecture](#data-model-architecture) section. The implementation pattern:

1. **Parse Relational Structure**: Extract metadata from relational columns (`event_type`, `event_name`, `__op`)
2. **Parse Event Data**: Parse the `event_data` JSON string to access nested structure:

   ```python
   import json
   
   # Extract relational fields
   event_type = message['event_type']
   event_name = message['event_name']
   
   # Parse nested structure from event_data
   event_data = json.loads(message['event_data'])
   event_header = event_data['eventHeader']
   event_body = event_data['eventBody']
   entities = event_body['entities']
   ```

3. **Process Entities**: Access nested entity data from the parsed `event_data`

See `consumers/loan-consumer/consumer.py` for a complete implementation example.

**Key Points**:

- All consumers parse the **relational structure** first (id, event_name, event_type, etc.)
- The `event_data` field is a **JSON string** that must be parsed with `json.loads()`
- After parsing `event_data`, consumers can access the nested structure (eventHeader, eventBody, entities)
- Each consumer processes entity-specific attributes based on the entity type

**Topic Creation**:

- Filtered topics are automatically created by Flink when it first writes to them
- No manual topic creation is required for filtered topics
- Only the `raw-business-events` topic needs to be created manually before deploying the CDC connector

**Consumer Deployment**:

All 4 consumers are dockerized and can be deployed via Docker Compose:

```bash
# Build and start all consumers
cd cdc-streaming
docker-compose up -d loan-consumer loan-payment-consumer service-consumer car-consumer

# Check consumer status
docker-compose ps

# View consumer logs
docker-compose logs -f loan-consumer
```

For Confluent Cloud deployment, ensure environment variables are set:

```bash
export KAFKA_BOOTSTRAP_SERVERS="pkc-xxxxx.us-east-1.aws.confluent.cloud:9092"
export KAFKA_API_KEY="<your-api-key>"
export KAFKA_API_SECRET="<your-api-secret>"
docker-compose up -d
```

Each consumer prints events to stdout with detailed information including:

- Relational structure fields (id, event_name, event_type, created_date, saved_date)
- CDC metadata (`__op`, `__table`)
- Parsed nested structure from event_data (eventHeader, eventBody, entities)
- Entity-specific attributes based on entity type

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

**Supported Operators**:

- `equals`: Exact match
- `in`: Match any value in list
- `notIn`: Exclude values in list
- `greaterThan`, `lessThan`, `greaterThanOrEqual`, `lessThanOrEqual`: Numeric comparisons
- `between`: Range check
- `matches`: Regex pattern matching
- `isNull`, `isNotNull`: Null checks

---

## Confluent Cloud Deployment Considerations

### Disaster Recovery

For comprehensive disaster recovery procedures, backup strategies, failover mechanisms, and testing methodologies, see [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md).

**Summary**:

- **Backup Strategy**: Multi-level backup approach with replication, snapshots, and savepoints
- **Recovery Procedures**: Component-specific recovery steps for Kafka, Flink, connectors, and consumers
- **RTO/RPO Targets**: < 1 hour RTO, < 5 minutes RPO
- **Multi-Region**: Active-active setup with automatic failover
- **Testing**: Regular disaster recovery drills and automated testing

### Performance Tuning

**Key Areas for Optimization**:

- **Kafka Tuning**: Broker configuration, topic settings, producer/consumer optimization
- **Flink Tuning**: Parallelism, state backend, checkpoint configuration, operator optimization
- **Connector Tuning**: Batch settings, parallel processing, PostgreSQL optimization
- **Consumer Tuning**: Batch processing, parallel processing, consumer group scaling
- **Infrastructure Tuning**: Network, disk I/O, CPU, memory optimization
- **Monitoring**: Key metrics, performance testing, troubleshooting procedures

## Related Documentation

- **[BACKEND_IMPLEMENTATION.md](BACKEND_IMPLEMENTATION.md)**: Back-end infrastructure including Lambda, Aurora, and RDS Proxy
- **[CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md)**: Complete Confluent Cloud setup guide including Flink configuration
- **[DISASTER_RECOVERY.md](DISASTER_RECOVERY.md)**: Comprehensive disaster recovery procedures and failover mechanisms

## References

- [Confluent Platform Documentation](https://docs.confluent.io/)
- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Apache Flink Documentation](https://nightlies.apache.org/flink/flink-docs-stable/)
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)
- [Schema Registry Documentation](https://docs.confluent.io/platform/current/schema-registry/index.html)
