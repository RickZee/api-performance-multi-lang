# CDC Streaming Architecture

A configurable streaming architecture that enables event-based consumers to subscribe to filtered subsets of events. This implementation uses Confluent Platform (Kafka, Schema Registry, Control Center, Connect), Confluent Postgres Source Connector for CDC, and Flink SQL for stream processing.

## Overview

This CDC streaming system captures changes from PostgreSQL database tables and streams them through Kafka, where Flink SQL jobs filter and route events to consumer-specific topics. The architecture is designed for:

- **Configurability at CI/CD Level**: Filtering and routing rules are defined as code (YAML/JSON files and Flink SQL scripts) stored in version control
- **Scalability and Resilience**: Built for horizontal scaling with Kafka partitioning and Flink parallelism
- **Integration with Existing Stack**: Events ingress via existing Ingestion APIs and PostgreSQL database
- **Security and Observability**: Schema Registry for schema enforcement, monitoring via Control Center
- **Cost Efficiency**: Stateful processing with Flink and efficient filtering/routing

## Architecture

### Data Flow

```
[PostgreSQL Entity Tables] 
  → [Confluent Postgres Source Connector (Debezium)] 
  → [Kafka: raw-business-events topic]
  → [Flink SQL Jobs (filtering/routing)]
  → [Consumer-specific Kafka topics]
  → [Example Consumers]
```

### Components

1. **Confluent Platform**:
   - Zookeeper: Coordination service for Kafka
   - Kafka Broker: Message streaming platform
   - Schema Registry: Schema management for Avro
   - Kafka Connect: Connector framework for CDC
   - Control Center: Monitoring and management UI (optional)

2. **Flink Cluster**:
   - JobManager: Coordinates Flink jobs
   - TaskManager: Executes Flink tasks
   - Flink SQL: Declarative stream processing

3. **Postgres Source Connector**:
   - Debezium-based connector
   - Captures INSERT/UPDATE/DELETE from entity tables
   - Publishes to `raw-business-events` topic

4. **Example Consumers**:
   - Loan Consumer: Consumes filtered loan events
   - Service Consumer: Consumes filtered service events

## Prerequisites

- Docker and Docker Compose
- PostgreSQL 15+ (can use existing `postgres-large` service)
- jq (for JSON processing in scripts)
- curl (for API calls)
- Access to existing producer APIs for generating test events

## Quick Start

### 1. Start Infrastructure Services

Start the Confluent Platform stack and Flink cluster:

```bash
cd cdc-streaming
docker-compose up -d
```

This will start:
- Zookeeper (port 2181)
- Kafka (port 9092)
- Schema Registry (port 8081)
- Kafka Connect (port 8083)
- Flink JobManager (port 8081)
- Flink TaskManager
- Example consumers (loan-consumer, service-consumer)

Optional: Start Control Center for monitoring:

```bash
docker-compose --profile monitoring up -d control-center
```

Access Control Center at: http://localhost:9021

### 2. Create Kafka Topics

Create the necessary Kafka topics:

```bash
./scripts/create-topics.sh
```

This creates:
- `raw-business-events` (3 partitions)
- `filtered-loan-events` (3 partitions)
- `filtered-service-events` (3 partitions)
- `filtered-car-events` (3 partitions)
- `filtered-high-value-loans` (3 partitions)

### 3. Set Up Postgres Connector

Register the Postgres Source Connector:

```bash
./scripts/setup-connector.sh
```

This will:
- Register the connector with Kafka Connect
- Configure it to capture changes from entity tables
- Start streaming changes to `raw-business-events` topic

### 4. Deploy Flink SQL Jobs

#### Option A: Confluent Cloud Flink (Recommended for Production)

Deploy Flink SQL statements to Confluent Cloud compute pools:

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

# Monitor statement
confluent flink statement describe ss-456789 \
  --compute-pool cp-east-123
```

For detailed Confluent Cloud setup, see [confluent-setup.md](confluent-setup.md).

#### Option B: Self-Managed Flink (Docker Compose)

Deploy the Flink SQL routing job to self-managed Flink cluster:

```bash
# Copy SQL file to Flink job directory (already mounted in docker-compose)
# Submit the job via Flink REST API or SQL Client

# Using Flink SQL Client (from Flink container)
docker exec -it cdc-flink-jobmanager ./bin/sql-client.sh embedded -f /opt/flink/jobs/routing.sql

# Or using Flink REST API
curl -X POST http://localhost:8081/v1/jobs \
  -H "Content-Type: application/json" \
  -d @- << EOF
{
  "jobName": "event-routing-job",
  "parallelism": 2
}
EOF
```

**Note**: For production deployments, Confluent Cloud Flink is recommended for managed infrastructure, auto-scaling, and high availability.

### 5. Verify Pipeline

Test the end-to-end pipeline:

```bash
./scripts/test-pipeline.sh
```

## Configuration

### Filter Configuration

Edit `flink-jobs/filters.yaml` to modify filtering rules. See `flink-jobs/filters-examples.yaml` for comprehensive examples.

**Code Generation**: Flink SQL queries can be automatically generated from YAML filter configurations. See [CODE_GENERATION.md](CODE_GENERATION.md) for details.

To generate SQL from filters:
```bash
# Validate filters
python scripts/validate-filters.py

# Generate SQL
python scripts/generate-flink-sql.py \
  --config flink-jobs/filters.yaml \
  --output flink-jobs/routing-generated.sql

# Validate generated SQL
python scripts/validate-sql.py --sql flink-jobs/routing-generated.sql
```

Basic example:

```yaml
filters:
  - id: loan-events-filter
    name: "Loan Events Filter"
    consumerId: loan-consumer
    outputTopic: filtered-loan-events
    conditions:
      - field: eventHeader.eventName
        operator: in
        values: ["LoanCreated", "LoanPaymentSubmitted"]
    enabled: true
```

**Available Operators:**
- `equals`: Exact match
- `in`: Match any value in list
- `greaterThan`: Numeric comparison
- `lessThan`: Numeric comparison
- `greaterThanOrEqual`: Numeric comparison
- `lessThanOrEqual`: Numeric comparison
- `between`: Range check
- `matches`: Regex pattern matching
- `notIn`: Exclude values in list

**Example Filter Types:**
- **Event Name Filter**: Filter by specific event types
- **Value-Based Filter**: Filter by numeric thresholds (e.g., loan amount > 100000)
- **Status-Based Filter**: Filter by entity status (e.g., active loans only)
- **Time-Based Filter**: Filter by timestamp (e.g., last 24 hours)
- **Multi-Condition Filter**: Combine multiple conditions with AND logic
- **Pattern Matching**: Filter using regex patterns

See `flink-jobs/filters-examples.yaml` for 20+ example configurations.

### Flink SQL Jobs

**Option 1: Generated SQL (Recommended)**
- SQL is automatically generated from `filters.yaml`
- See [CODE_GENERATION.md](CODE_GENERATION.md) for code generation guide
- Generated file: `flink-jobs/routing-generated.sql`

**Option 2: Manual SQL**
- Edit `flink-jobs/routing.sql` manually for custom queries
- See `flink-jobs/routing-examples.sql` for comprehensive examples

Basic example:

```sql
-- Route Loan-related events
INSERT INTO filtered_loan_events
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('loan-events-filter', 'loan-consumer', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'LoanCreated' OR eventHeader.eventName = 'LoanPaymentSubmitted';
```

**Example Query Types:**
- **Basic Filtering**: Filter by event name, entity type, or field values
- **Value-Based Filtering**: Numeric comparisons (>, <, >=, <=, BETWEEN)
- **Status Filtering**: Filter by entity status or state
- **Time-Based Filtering**: Filter by timestamp or time windows
- **Pattern Matching**: Use LIKE or REGEXP for pattern matching
- **Windowed Aggregations**: Tumbling or sliding window aggregations
- **Multi-Topic Routing**: Route to different topics based on conditions
- **Joins**: Join with reference data tables
- **Error Handling**: Route invalid events to dead letter queue

See `flink-jobs/routing-examples.sql` for 19+ example SQL queries including:
- Basic and advanced filtering
- Windowed aggregations
- Multi-topic routing
- Join operations
- Error handling patterns

### Postgres Connector

Edit `connectors/postgres-source-connector.json` to modify connector configuration:

```json
{
  "name": "postgres-source-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "postgres-large",
    "table.include.list": "public.car_entities,public.loan_entities,..."
  }
}
```

## Monitoring

### Kafka Topics

Monitor topic messages:

```bash
# Raw events
docker exec -it cdc-kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic raw-business-events \
  --from-beginning

# Filtered loan events
docker exec -it cdc-kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic filtered-loan-events \
  --from-beginning
```

### Consumer Logs

View consumer application logs:

```bash
# Loan consumer
docker logs -f cdc-loan-consumer

# Service consumer
docker logs -f cdc-service-consumer
```

### Flink Dashboard

Access Flink Web UI at: http://localhost:8081

- View running jobs
- Monitor job metrics
- Check checkpoint status
- View task manager details

### Control Center

Access Control Center at: http://localhost:9021 (if enabled)

- Monitor Kafka cluster health
- View topic metrics
- Monitor connectors
- View consumer lag

## Testing

### Generate Test Events

#### Using the Test Data Generation Script (Recommended)

Use the provided script to generate test data using k6 and the Java REST API:

```bash
cd cdc-streaming/scripts

# Basic usage (10 virtual users for 30 seconds)
./generate-test-data.sh

# Custom configuration
VUS=20 DURATION=60s PAYLOAD_SIZE=4k ./generate-test-data.sh

# With request rate limit
VUS=50 DURATION=120s RATE=10 PAYLOAD_SIZE=8k ./generate-test-data.sh
```

Configuration options:
- `VUS`: Number of virtual users (default: 10)
- `DURATION`: Test duration (default: 30s)
- `RATE`: Request rate per second (optional)
- `PAYLOAD_SIZE`: Payload size - 400b, 4k, 8k, 32k, 64k (default: 4k)
- `API_HOST`: API hostname (default: producer-api-java-rest)
- `API_PORT`: API port (default: 8081)

The script will:
1. Generate events using k6 load testing tool
2. Send events to the Java REST API
3. Events are stored in PostgreSQL
4. CDC connector captures changes and streams to Kafka
5. Flink filters and routes events to consumer topics

#### Manual Event Generation

You can also manually generate test events using curl:

```bash
# Example: Using Java REST API
curl -X POST http://localhost:9081/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "eventHeader": {
      "eventName": "LoanCreated",
      "eventType": "LoanCreated"
    },
    "eventBody": {
      "entities": [{
        "entityType": "Loan",
        "entityId": "loan-123",
        "updatedAttributes": {
          "loanAmount": 50000,
          "balance": 50000,
          "status": "active"
        }
      }]
    }
  }'
```

### Verify Event Flow

1. **Check Raw Events**: Verify events appear in `raw-business-events` topic
2. **Check Filtered Events**: Verify filtered events appear in consumer-specific topics
3. **Check Consumer Logs**: Verify consumers receive and process events

### Validate Data in Kafka and Flink

#### Validate Kafka Topics

Use the validation script to check Kafka topics:

```bash
cd cdc-streaming/scripts

# Validate raw events topic
./validate-kafka.sh raw-business-events

# Validate filtered loan events
./validate-kafka.sh filtered-loan-events

# Validate with custom limit
LIMIT=20 ./validate-kafka.sh filtered-service-events
```

The script will:
- Check if the topic exists
- Show topic information (partitions, replication)
- Display message count
- Show sample messages
- Validate message structure (JSON format)

#### Validate Flink Jobs

Use the validation script to check Flink job status:

```bash
cd cdc-streaming/scripts

# Validate all Flink jobs
./validate-flink.sh

# Validate specific job by name
./validate-flink.sh event-routing-job
```

The script will:
- Check Flink cluster status
- List all jobs
- Show job details (status, metrics, operators)
- Display processing metrics (records in/out, throughput)
- Check for errors or failures

#### Manual Validation

You can also manually validate using Kafka and Flink tools:

```bash
# Check Kafka topic messages
docker exec -it cdc-kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic raw-business-events \
  --from-beginning \
  --max-messages 10

# Check Flink job status via REST API
curl http://localhost:8081/jobs | jq

# Check Flink job metrics
curl http://localhost:8081/jobs/<job-id>/metrics | jq
```

## Troubleshooting

### Connector Not Starting

Check connector status:

```bash
curl http://localhost:8083/connectors/postgres-source-connector/status | jq
```

Common issues:
- PostgreSQL not accessible: Check network connectivity
- Replication slot already exists: Drop and recreate slot
- Missing tables: Ensure tables exist in PostgreSQL

### Flink Job Failing

Check Flink job logs:

```bash
docker logs cdc-flink-jobmanager
docker logs cdc-flink-taskmanager
```

Common issues:
- Schema mismatch: Verify Avro schemas in Schema Registry
- Topic not found: Ensure topics are created
- Serialization errors: Check schema compatibility

### Consumers Not Receiving Events

Check consumer configuration:

```bash
docker logs cdc-loan-consumer
docker logs cdc-service-consumer
```

Common issues:
- Wrong topic name: Verify topic names match
- Consumer group offset: Reset consumer group if needed
- Network issues: Verify Kafka connectivity

## File Structure

```
cdc-streaming/
├── docker-compose.yml              # Docker Compose configuration
├── README.md                       # This file
├── .env.example                    # Environment variables template
├── connectors/
│   └── postgres-source-connector.json  # Postgres connector config
├── flink-jobs/
│   ├── filters.yaml               # Filter configuration
│   ├── filters-examples.yaml       # Example filter configurations
│   ├── routing.sql                # Flink SQL routing job
│   └── routing-examples.sql       # Example Flink SQL queries
├── schemas/
│   ├── raw-event.avsc             # Avro schema for raw events
│   └── filtered-event.avsc        # Avro schema for filtered events
├── consumers/
│   ├── loan-consumer/             # Loan event consumer
│   │   ├── Dockerfile
│   │   ├── consumer.py
│   │   └── requirements.txt
│   └── service-consumer/           # Service event consumer
│       ├── Dockerfile
│       ├── consumer.py
│       └── requirements.txt
├── config/
│   ├── kafka-connect.properties   # Kafka Connect worker config
│   └── flink-conf.yaml            # Flink configuration
└── scripts/
    ├── setup-connector.sh          # Connector setup script
    ├── create-topics.sh            # Topic creation script
    ├── test-pipeline.sh            # Pipeline test script
    ├── generate-test-data.sh       # Generate test data using k6 and Java REST API
    ├── validate-kafka.sh           # Validate data in Kafka topics
    └── validate-flink.sh           # Validate Flink job status and metrics
```

## Integration with Existing Stack

This CDC streaming system integrates with:

- **PostgreSQL Database**: Uses existing `postgres-large` service or connects to existing PostgreSQL instance
- **Producer APIs**: Events generated by existing producer APIs (Go, Rust, Java) are captured via CDC
- **Event Schema**: Aligns with existing event structure from `data/event-templates.json`
- **Entity Types**: Supports existing entity types: Car, Loan, LoanPayment, ServiceRecord

## Production Considerations

For production deployment:

1. **Multi-Region**: Use Confluent Cluster Linking for multi-region replication
2. **Security**: Enable SASL/SSL for Kafka, use IAM roles for AWS
3. **Monitoring**: Integrate with ELK stack for centralized logging
4. **CI/CD**: Deploy Flink jobs via Jenkins pipelines with Terraform or REST API
5. **Schema Evolution**: Use Schema Registry compatibility modes for schema evolution
6. **Backup**: Configure Flink savepoints for job state backup
7. **Scaling**: Adjust Flink parallelism and Kafka partitions based on load

## References

- [Confluent Platform Documentation](https://docs.confluent.io/)
- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Apache Flink SQL](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)

## License

See main project LICENSE file.

