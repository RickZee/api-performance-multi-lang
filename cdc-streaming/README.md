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

The system captures database changes via CDC, streams them through Kafka, and uses Flink SQL to filter and route events to consumer-specific topics. Key components include Confluent Platform (Kafka, Schema Registry, Kafka Connect), Flink for stream processing, and Debezium-based PostgreSQL CDC connector.

For comprehensive architecture documentation including detailed data flow diagrams, component deep dives, and how consumers interact with the system, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Prerequisites

### For Docker Compose (Local Development)

- Docker and Docker Compose
- PostgreSQL 15+ (can use existing `postgres-large` service)
- jq (for JSON processing in scripts)
- curl (for API calls)
- Access to existing producer APIs for generating test events

### For Confluent Cloud (Production)

- Confluent Cloud account (sign up at https://confluent.cloud)
- Confluent CLI installed (`brew install confluentinc/tap/cli`)
- AWS account (if using AWS cloud provider)
- PostgreSQL database (Aurora PostgreSQL or self-managed)
- Network connectivity between Confluent Cloud and PostgreSQL

**For complete Confluent Cloud setup instructions, see [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md).**

## Quick Start

### 1. Start Infrastructure Services

#### Option A: Docker Compose (Local Development)

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

#### Option B: Confluent Cloud (Production)

For complete Confluent Cloud setup instructions, see **[CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md)**.

**Quick Start:**
```bash
# Login to Confluent Cloud
confluent login

# Create environment
confluent environment create prod --stream-governance

# Create Kafka cluster
confluent kafka cluster create prod-kafka-east \
  --cloud aws \
  --region us-east-1 \
  --type dedicated \
  --cku 2

# Create Flink compute pool
confluent flink compute-pool create prod-flink-east \
  --cloud aws \
  --region us-east-1 \
  --max-cfu 4
```

**What's Included:**
- Managed Kafka cluster (auto-scaling, multi-zone)
- Schema Registry (auto-enabled with Stream Governance)
- Flink compute pools (managed Flink infrastructure)
- Built-in monitoring and alerting
- High availability and automatic failover

For detailed setup steps, CI/CD alternatives (Terraform, REST API, GitHub Actions), and advanced topics, see [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md).

### 2. Create Kafka Topics

#### Option A: Docker Compose (Local Development)

Create the necessary Kafka topics:

```bash
./scripts/create-topics.sh
```

This creates:
- `raw-business-events` (3 partitions)

**Note**: Filtered topics (`filtered-loan-events`, `filtered-service-events`, etc.) are automatically created by Flink when it writes to them for the first time. No manual creation is required.

#### Option B: Confluent Cloud (Production)

Create topics in Confluent Cloud:

```bash
# Set cluster context
confluent kafka cluster use <cluster-id>

# Create raw-business-events topic (only topic that needs manual creation)
confluent kafka topic create raw-business-events --partitions 6

# Note: Filtered topics are automatically created by Flink when it writes to them.
# No manual creation is required for filtered topics.
```

For detailed topic creation steps, CI/CD alternatives (Terraform, REST API, GitHub Actions), and topic configuration, see [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md).

### 3. Set Up Postgres Connector

#### Option A: Docker Compose (Local Development)

Register the Postgres Source Connector:

```bash
./scripts/setup-connector.sh
```

This will:
- Register the connector with Kafka Connect
- Configure it to capture changes from entity tables
- Start streaming changes to `raw-business-events` topic

#### Option B: Confluent Cloud (Production)

Deploy Postgres Source Connector to Confluent Cloud:

```bash
# Using Confluent Cloud managed connectors
confluent connector create postgres-source \
  --kafka-cluster <cluster-id> \
  --config-file connectors/postgres-source-connector.json
```

For detailed connector setup steps, configuration examples, and CI/CD alternatives (Terraform, REST API, GitHub Actions), see [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md).

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

For detailed Flink SQL deployment steps, SQL configuration, and CI/CD alternatives (Terraform, REST API, GitHub Actions, Jenkins, Kubernetes), see [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md).

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

#### Option A: Docker Compose (Local Development)

Test the end-to-end pipeline by checking connector status, Flink statements, and topic message counts using the Confluent Cloud CLI.

#### Option B: Confluent Cloud (Production)

Verify the pipeline in Confluent Cloud:

```bash
# Check connector status
confluent connector describe postgres-source-connector

# Check topics have messages
confluent kafka topic describe raw-business-events --output json | jq '.partitions[].offset'

# Check Flink statement is running
confluent flink statement list --compute-pool <compute-pool-id>

# Check filtered topics have messages
confluent kafka topic describe filtered-loan-events --output json | jq '.partitions[].offset'

# Check consumer groups
confluent kafka consumer-group describe <consumer-group-name>

# Consume sample messages
confluent kafka topic consume raw-business-events --max-messages 10
confluent kafka topic consume filtered-loan-events --max-messages 10
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment
- Check connector status and metrics
- Verify topics have messages and throughput
- Monitor Flink statement execution and metrics
- Check consumer group lag and offsets

## Configuration

### Filter Configuration

Edit `flink-jobs/filters.yaml` to modify filtering rules. See `flink-jobs/filters-examples.yaml` for comprehensive examples.

**Code Generation**: Flink SQL queries can be automatically generated from YAML filter configurations. For detailed information on filter configuration, available operators, examples, and SQL generation, see [CODE_GENERATION.md](CODE_GENERATION.md).

Quick start:
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

### Flink SQL Jobs

**Option 1: Generated SQL (Recommended)**
- SQL is automatically generated from `filters.yaml`
- See [CODE_GENERATION.md](CODE_GENERATION.md) for code generation guide
- Generated file: `flink-jobs/routing-generated.sql`

**Option 2: Manual SQL**
- Edit `flink-jobs/routing.sql` manually for custom queries
- See `flink-jobs/routing-examples.sql` for comprehensive examples

For detailed Flink SQL examples, query types, table definitions, and deployment patterns, see [ARCHITECTURE.md](ARCHITECTURE.md).

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

## Data Model Comparison

This system supports two different data model approaches for representing entity attributes: **deeply nested** and **flat**. Understanding the differences is important for filtering, processing, and schema design decisions.

### Deeply Nested Data Model

The **deeply nested data model** uses hierarchical JSON structures where attributes can contain nested objects and arrays. This is the natural structure used by producer APIs when creating events.

**Example Structure:**
```json
{
  "updatedAttributes": {
    "loan": {
      "loanAmount": 50000,
      "balance": 50000,
      "status": "active"
    },
    "borrower": {
      "name": "John Doe",
      "creditScore": 750
    }
  }
}
```

**Characteristics:**
- Preserves type information (numbers, booleans, strings)
- Maintains logical grouping of related attributes
- Supports complex nested structures
- Natural representation for API consumers
- Stored as JSONB in PostgreSQL

**Limitations:**
- Cannot directly filter on nested paths in Flink SQL with `MAP<STRING, STRING>` type
- Requires JSON parsing functions for nested field access
- More complex query syntax for filtering

### Flat Data Model

The **flat data model** uses a key-value map structure where all values are strings and nested paths are represented using dot notation in keys.

**Example Structure:**
```json
{
  "updatedAttributes": {
    "loan.loanAmount": "50000",
    "loan.balance": "50000",
    "loan.status": "active",
    "borrower.name": "John Doe",
    "borrower.creditScore": "750"
  }
}
```

**Characteristics:**
- Compatible with Flink SQL `MAP<STRING, STRING>` type
- Simple filtering syntax: `updatedAttributes['loan.loanAmount']`
- Direct key-value access without JSON parsing
- All values are strings (type information lost)
- Requires flattening transformation at API or CDC level

**Limitations:**
- Loss of type information (everything becomes strings)
- Requires type casting for numeric comparisons
- Breaking change to API contract if implemented at API level
- Less intuitive for API consumers

### Current Implementation

The current implementation uses a **hybrid approach**:

1. **Producer APIs**: Accept deeply nested JSON structures
2. **PostgreSQL Storage**: Stores as JSONB (preserves nested structure)
3. **CDC Capture**: Debezium captures the JSONB as-is
4. **Flink SQL Processing**: Uses `MAP<STRING, STRING>` for `updatedAttributes`, which requires:
   - Flattening nested structures before filtering, OR
   - Using JSON parsing functions for nested field access

**Schema Definition:**
- `schemas/raw-event.avsc`: Defines `updatedAttributes` as `MAP<STRING, STRING>`
- `schemas/filtered-event.avsc`: Same structure with added `filterMetadata`

### Trade-offs

| Aspect | Deeply Nested | Flat |
|--------|---------------|------|
| **Type Safety** | Preserves types | All strings |
| **Filtering Simplicity** | Requires JSON parsing | Direct key access |
| **API Compatibility** | Natural structure | Breaking change |
| **Performance** | JSON parsing overhead | Direct access |
| **Flexibility** | Supports any structure | Limited to key-value |
| **Schema Evolution** | Flexible | Key naming conventions |

### Recommendations

- **For New Implementations**: Consider flattening at the API level if filtering performance is critical and you can coordinate API versioning
- **For Existing Systems**: Use JSON parsing functions in Flink SQL to access nested fields, preserving API compatibility
- **For Type Safety**: Consider Avro schema-first design with explicit nested record types (see `confluent-flink-cdc-problems.md` for details)

For detailed solutions, workarounds, and implementation patterns addressing nested vs flat data model challenges, see [confluent-flink-cdc-problems.md](confluent-flink-cdc-problems.md).

## Monitoring

### Kafka Topics

#### Option A: Docker Compose (Local Development)

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

#### Option B: Confluent Cloud (Production)

Monitor topics via Confluent Cloud:

```bash
# Consume messages via CLI
confluent kafka topic consume raw-business-events --from-beginning
confluent kafka topic consume filtered-loan-events --from-beginning

# View topic details and metrics
confluent kafka topic describe raw-business-events
confluent kafka topic describe filtered-loan-events

# View topic metrics (message count, throughput, etc.)
confluent kafka topic describe raw-business-events --output json | jq '.metrics'
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment → Topics
- View real-time metrics: throughput, latency, message count
- Monitor consumer lag per topic
- View partition-level details

**Via REST API:**

```python
# scripts/monitor-topics-confluent-cloud.py
import requests
import base64

def get_topic_metrics(cluster_id, topic_name, api_key, api_secret):
    url = f"https://api.confluent.cloud/kafka/v3/clusters/{cluster_id}/topics/{topic_name}"
    auth = base64.b64encode(f'{api_key}:{api_secret}'.encode()).decode()
    headers = {"Authorization": f"Basic {auth}"}
    response = requests.get(url, headers=headers)
    return response.json()
```

### Consumer Logs

#### Option A: Docker Compose (Local Development)

View consumer application logs:

```bash
# Loan consumer
docker logs -f cdc-loan-consumer

# Service consumer
docker logs -f cdc-service-consumer
```

#### Option B: Confluent Cloud (Production)

Monitor consumer groups and lag:

```bash
# View consumer groups
confluent kafka consumer-group list

# Describe consumer group (shows lag, offsets)
confluent kafka consumer-group describe loan-consumer-group

# View consumer lag details
confluent kafka consumer-group describe loan-consumer-group --output json | jq '.lag'

# Monitor consumer group metrics
confluent kafka consumer-group describe loan-consumer-group --output json | jq '.metrics'
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment → Consumers
- View consumer group lag, offsets, and throughput
- Monitor consumer group health
- Set up alerts for lag thresholds

**Application Logs:**
- Access application logs via your logging infrastructure (CloudWatch, Datadog, etc.)
- Consumer applications should log to standard output/structured logging
- Use log aggregation tools for centralized monitoring

### Flink Dashboard

#### Option A: Docker Compose (Local Development)

Access Flink Web UI at: http://localhost:8081

- View running jobs
- Monitor job metrics
- Check checkpoint status
- View task manager details

#### Option B: Confluent Cloud (Production)

Monitor Flink statements via Confluent Cloud:

```bash
# List all Flink statements
confluent flink statement list --compute-pool <compute-pool-id>

# Describe statement (shows status, metrics, logs)
confluent flink statement describe <statement-id> --compute-pool <compute-pool-id>

# View statement metrics
confluent flink statement describe <statement-id> \
  --compute-pool <compute-pool-id> \
  --output json | jq '.metrics'

# View statement logs
confluent flink statement logs <statement-id> --compute-pool <compute-pool-id>

# Monitor compute pool
confluent flink compute-pool describe <compute-pool-id>
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment → Flink
- View statement status, metrics, and logs
- Monitor compute pool CFU utilization
- View throughput, latency, and backpressure metrics
- Access statement execution logs

**Key Metrics to Monitor:**
- `numRecordsInPerSecond`: Input records per second
- `numRecordsOutPerSecond`: Output records per second
- `latency`: End-to-end latency
- `backpressured-time-per-second`: Backpressure time
- `checkpoint-duration`: Checkpoint duration
- `cfu-usage`: Current CFU utilization

### Control Center / Confluent Cloud Console

#### Option A: Docker Compose (Local Development)

Access Control Center at: http://localhost:9021 (if enabled)

- Monitor Kafka cluster health
- View topic metrics
- Monitor connectors
- View consumer lag

#### Option B: Confluent Cloud Console (Production)

Access Confluent Cloud Console at: https://confluent.cloud

**Dashboard Features:**
- **Overview**: System health, throughput, and key metrics
- **Topics**: Topic-level metrics, partitions, and configuration
- **Consumers**: Consumer group lag, offsets, and throughput
- **Connectors**: Connector status, metrics, and logs
- **Flink**: Statement status, metrics, and compute pool utilization
- **Schema Registry**: Schema versions, compatibility, and evolution
- **Alerts**: Configure alerts for lag, throughput, errors

**Built-in Monitoring:**
- Real-time metrics dashboards
- Historical metrics and trends
- Custom alert rules
- Performance insights and recommendations
- Cost optimization suggestions

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

For comprehensive pipeline validation including detailed steps for verifying events in Kafka, validating Flink jobs, troubleshooting common issues, and end-to-end testing procedures, see [PIPELINE_VALIDATION.md](PIPELINE_VALIDATION.md).

Quick verification:
1. **Check Raw Events**: Verify events appear in `raw-business-events` topic
2. **Check Filtered Events**: Verify filtered events appear in consumer-specific topics
3. **Check Consumer Logs**: Verify consumers receive and process events
