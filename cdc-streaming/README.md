# A system to stream and filter database changes to different consumers

A configurable streaming architecture that enables event-based consumers to subscribe to filtered subsets of events. This implementation uses Confluent Platform (Kafka, Schema Registry, Control Center, Connect), **Confluent Managed PostgreSQL CDC Source Connector** (for Confluent Cloud) or Debezium connectors (for local development) for CDC, and Flink SQL for stream processing.

## Overview

This CDC streaming system captures changes from PostgreSQL database tables and streams them through Kafka, where Flink SQL jobs filter and route events to consumer-specific topics. The architecture is designed for:

- **Configurability at CI/CD Level**: Filtering and routing rules are defined as code (YAML/JSON files and Flink SQL scripts) stored in version control
- **Scalability and Resilience**: Built for horizontal scaling with Kafka partitioning and Flink parallelism
- **Integration with Existing Stack**: Events ingress via existing Ingestion APIs and PostgreSQL database
- **Security and Observability**: Schema Registry for schema enforcement, monitoring via Control Center
- **Cost Efficiency**: Stateful processing with Flink and efficient filtering/routing

## Screenshots

The system captures database changes via CDC, streams them through Kafka, and uses Flink SQL to filter and route events to consumer-specific topics. Key components include Confluent Platform (Kafka, Schema Registry, Kafka Connect), Flink for stream processing, and **Confluent Managed PostgreSQL CDC Source Connector** (for Confluent Cloud) or Debezium-based PostgreSQL CDC connector (for local development).

For comprehensive architecture documentation including detailed data flow diagrams, component deep dives, and how consumers interact with the system, see [ARCHITECTURE.md](ARCHITECTURE.md).

### Screenshots

The following screenshots illustrate key components and views of the CDC streaming system:

<img src="screenshots/1-connector.png" alt="PostgreSQL CDC Connector Configuration" width="800"/>

*Figure 1: PostgreSQL CDC Source Connector configuration in Confluent Cloud*

<img src="screenshots/2-main-topic-lineage.png" alt="Main Topic Lineage" width="800"/>

*Figure 2: Data lineage showing the flow from PostgreSQL CDC connector through Kafka topics*

<img src="screenshots/3-all-topics.png" alt="All Topics Overview" width="800"/>

*Figure 3: Overview of all Kafka topics in the system, including raw and filtered event topics*

<img src="screenshots/4-flink-insert-statement.png" alt="Flink Insert Statement" width="800"/>

*Figure 4: Flink SQL insert statement for filtering and routing events to consumer-specific topics*

<img src="screenshots/5-consumer-log.png" alt="Consumer Application Logs" width="800"/>

*Figure 5: Example consumer application logs showing event processing*

## Prerequisites

### For Docker Compose (Local Development)

- Docker and Docker Compose
- PostgreSQL 15+ (can use existing `postgres-large` service)
- jq (for JSON processing in scripts)
- curl (for API calls)
- Access to existing producer APIs for generating test events

### For Confluent Cloud

- Confluent Cloud account (sign up at https://confluent.cloud)
- Confluent CLI installed (`brew install confluentinc/tap/cli`)
- AWS account (if using AWS cloud provider)
- PostgreSQL database (Aurora PostgreSQL or self-managed)
- Network connectivity between Confluent Cloud and PostgreSQL

**For complete Confluent Cloud setup instructions, see [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md).**

## Quick Start

### 1. Start Infrastructure Services

#### Option A: Docker Compose (Local Development)

**Note:** This setup uses Confluent Cloud for Kafka, Schema Registry, and Kafka Connect. Local Kafka and Zookeeper services have been removed.

Start the local Flink cluster and consumers:

```bash
cd cdc-streaming

# Set your Confluent Cloud bootstrap servers (required)
export KAFKA_BOOTSTRAP_SERVERS="pkc-xxxxx.us-east-1.aws.confluent.cloud:9092"
export KAFKA_API_KEY="your-api-key"
export KAFKA_API_SECRET="your-api-secret"

docker-compose up -d
```

This will start:
- Flink JobManager (port 8082)
- Flink TaskManager
- Example consumers (loan-consumer, loan-payment-consumer, service-consumer, car-consumer)

**Note:** For Confluent Cloud, use Confluent Cloud Flink instead of local Flink. Local Flink is for development/testing only.

**Monitoring:** Use Confluent Cloud Console at https://confluent.cloud for monitoring Kafka, Schema Registry, connectors, and Flink statements.

#### Option B: Confluent Cloud

For complete Confluent Cloud setup instructions, see **[CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md)**.

The setup guide includes:
- Step-by-step account and cluster setup
- Topic creation and configuration
- Connector deployment
- Flink SQL deployment
- CI/CD alternatives (Terraform, REST API, GitHub Actions)
- Advanced topics (multi-region, PrivateLink, etc.)

### 2. Create Kafka Topics

**Note:** Topics are created in Confluent Cloud, not locally.

For topic creation in Confluent Cloud, see [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md#topic-creation) - Topic Creation section.

**Note**: Filtered topics (`filtered-loan-created-events`, `filtered-car-created-events`, `filtered-loan-payment-submitted-events`, `filtered-service-events`, etc.) are automatically created by Flink when it writes to them. Only `raw-business-events` needs manual creation.

### 3. Set Up Postgres Connector

**Note:** Connectors are deployed in Confluent Cloud, not locally.

For connector deployment in Confluent Cloud, see [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md#connector-setup) - Connector Setup section.

### 4. Deploy Flink SQL Jobs

#### Option A: Confluent Cloud Flink

For Flink SQL deployment in Confluent Cloud, see [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md#flink-compute-pool-setup) for Flink Compute Pool Setup and [Deploy Flink SQL Statements](CONFLUENT_CLOUD_SETUP_GUIDE.md#deploy-flink-sql-statements) sections.

Confluent Cloud Flink provides:
- Managed infrastructure with auto-scaling
- High availability and automatic failover
- Built-in integration with Schema Registry
- SQL-based deployment without JAR files
- Real-time metrics and monitoring

#### Option B: Self-Managed Flink (Local Development Only)

Deploy the Flink SQL routing job to self-managed Flink cluster. This option is intended for local development and testing only:

```bash
# Copy SQL file to Flink job directory (already mounted in docker-compose)
# Submit the job via Flink REST API or SQL Client

# Using Flink SQL Client (from Flink container)
docker exec -it cdc-flink-jobmanager ./bin/sql-client.sh embedded -f /opt/flink/jobs/routing-local-docker.sql

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

### 5. Verify Pipeline

#### Option A: Docker Compose (Local Development)

Test the end-to-end pipeline by checking connector status, Flink statements, and topic message counts using the Confluent Cloud CLI.

#### Option B: Confluent Cloud

Verify the pipeline in Confluent Cloud:

```bash
# Check connector status
confluent connector describe postgres-source-connector

# Check topics have messages
confluent kafka topic describe raw-business-events --output json | jq '.partitions[].offset'

# Check Flink statement is running
confluent flink statement list --compute-pool <compute-pool-id>

# Check filtered topics have messages
confluent kafka topic describe filtered-loan-created-events --output json | jq '.partitions[].offset'

# Check consumer groups
confluent kafka consumer-group describe <consumer-group-name>

# Consume sample messages
confluent kafka topic consume raw-business-events --max-messages 10
confluent kafka topic consume filtered-loan-created-events --max-messages 10
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment
- Check connector status and metrics
- Verify topics have messages and throughput
- Monitor Flink statement execution and metrics
- Check consumer group lag and offsets

## Configuration

### Filter Configuration

Filtering rules are defined directly in Flink SQL files. Edit the SQL files in `flink-jobs/` to modify filtering rules.

### Flink SQL Jobs

Edit the Flink SQL files directly:
- `flink-jobs/business-events-routing-confluent-cloud.sql` - Main routing job for Confluent Cloud
- `flink-jobs/business-events-routing-confluent-cloud-no-op.sql` - No-op version for testing

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

## Data Model

This system uses a **deeply nested data model** for representing entity attributes with hierarchical JSON structures.

### Deeply Nested Data Model

The **deeply nested data model** uses hierarchical JSON structures where attributes can contain nested objects and arrays. This is the natural structure used by producer APIs when creating events.

**Example Structure:**

See [`data/schemas/event/samples/loan-created-event.json`](../data/schemas/event/samples/loan-created-event.json) for a complete example of a deeply nested event structure. The entity structure is defined in [`data/schemas/entity/loan.json`](../data/schemas/entity/loan.json).

**Database Schema (DDL):**
```sql
CREATE TABLE loan_entities (
    id VARCHAR(255) PRIMARY KEY,
    entity_type VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_attributes JSONB NOT NULL
);

-- Index for JSONB queries
CREATE INDEX idx_loan_entities_updated_attributes_gin 
    ON loan_entities USING GIN (updated_attributes);

-- Example query accessing nested structure
SELECT 
    id,
    updated_attributes->'loan'->>'loanAmount' as loan_amount,
    updated_attributes->'borrower'->>'name' as borrower_name
FROM loan_entities
WHERE (updated_attributes->'loan'->>'loanAmount')::numeric > 100000;
```

**Schema Definitions:**

Data model schemas are defined in the `data/` folder:
- Event schema: [`data/schemas/event/event.json`](../data/schemas/event/event.json)
- Event header schema: [`data/schemas/event/event-header.json`](../data/schemas/event/event-header.json)
- Entity schemas: [`data/schemas/entity/car.json`](../data/schemas/entity/car.json), [`data/schemas/entity/loan.json`](../data/schemas/entity/loan.json), and others
- Sample event data: [`data/schemas/event/samples/loan-created-event.json`](../data/schemas/event/samples/loan-created-event.json) and others
- Sample entity data: [`data/entities/car/car-large.json`](../data/entities/car/car-large.json) and others

For complete schema definitions and examples, see the [data folder README](../data/README.md).

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

### Current Implementation

The current implementation uses deeply nested JSON structures:

1. **Producer APIs**: Accept deeply nested JSON structures
2. **PostgreSQL Storage**: Stores as JSONB (preserves nested structure)
3. **CDC Capture**: Debezium captures the JSONB as-is
4. **Flink SQL Processing**: Uses JSON parsing functions for nested field access

**Schema Definition:**
- `schemas/raw-event.avsc`: Defines `updatedAttributes` as `MAP<STRING, STRING>`
- `schemas/filtered-event.avsc`: Same structure with added `filterMetadata`

### Recommendations

- **For Existing Systems**: Use JSON parsing functions in Flink SQL to access nested fields, preserving API compatibility
- **For Type Safety**: Consider Avro schema-first design with explicit nested record types

## Monitoring

### Kafka Topics

**Note:** All Kafka topics are in Confluent Cloud. Use Confluent Cloud CLI or Console to monitor them.

Monitor topics via Confluent Cloud:

```bash
# Consume messages via CLI
confluent kafka topic consume raw-business-events --from-beginning
confluent kafka topic consume filtered-loan-created-events --from-beginning

# View topic details and metrics
confluent kafka topic describe raw-business-events
confluent kafka topic describe filtered-loan-created-events

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

#### Option B: Confluent Cloud

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

#### Option A: Docker Compose (Local Development - Testing Only)

**Note:** For production, use Confluent Cloud Flink. Local Flink is for development/testing only.

Access Flink Web UI at: http://localhost:8082

- View running jobs
- Monitor job metrics
- Check checkpoint status
- View task manager details

#### Option B: Confluent Cloud

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


## Testing

### Generate Test Events

#### Using Test Data Generation

Generate test data based on the example structures (`car-large.json` and `loan-created-event.json`):

```bash
cd cdc-streaming/scripts

# Generate test events from examples
./generate-test-data-from-examples.sh
```

This script:
- Reads `data/entities/car/car-large.json` for car entity structure
- Reads `data/schemas/event/samples/loan-created-event.json` for loan created event structure
- Generates events matching these exact structures
- Sends events to the producer API

#### Using the Consolidated k6 Batch Events Script

Use the consolidated `send-batch-events.js` script to send a configurable number of events of each type (always sends all 4 types: Car Created, Loan Created, Loan Payment Submitted, Car Service Done):

**Basic Usage:**

```bash
# Send 5 events of each type (default, 4 types = 20 total)
k6 run --env HOST=producer-api-java-rest --env PORT=8081 ../../load-test/k6/send-batch-events.js

# Send 1000 events of each type (4 types = 4000 total)
k6 run --env HOST=producer-api-java-rest --env PORT=8081 --env EVENTS_PER_TYPE=1000 ../../load-test/k6/send-batch-events.js

# Lambda API with 1000 events per type
k6 run --env LAMBDA_PYTHON_REST_API_URL=https://xxxxx.execute-api.us-east-1.amazonaws.com --env EVENTS_PER_TYPE=1000 ../../load-test/k6/send-batch-events.js
```

**Parallel Execution with Multiple VUs:**

The script supports configurable parallelism to distribute events of each type across multiple Virtual Users (VUs) for improved throughput:

```bash
# Send 10 events of each type with 1 VU per event type (4 total VUs, sequential)
k6 run --env LAMBDA_PYTHON_REST_API_URL=https://xxxxx.execute-api.us-east-1.amazonaws.com \
  --env EVENTS_PER_TYPE=10 \
  --env VUS_PER_EVENT_TYPE=1 \
  ../../load-test/k6/send-batch-events.js

# Send 100 events of each type with 5 VUs per event type (20 total VUs, parallel)
k6 run --env LAMBDA_PYTHON_REST_API_URL=https://xxxxx.execute-api.us-east-1.amazonaws.com \
  --env EVENTS_PER_TYPE=100 \
  --env VUS_PER_EVENT_TYPE=5 \
  ../../load-test/k6/send-batch-events.js

# Send 1000 events of each type with 10 VUs per event type (40 total VUs, highly parallel)
k6 run --env LAMBDA_PYTHON_REST_API_URL=https://xxxxx.execute-api.us-east-1.amazonaws.com \
  --env EVENTS_PER_TYPE=1000 \
  --env VUS_PER_EVENT_TYPE=10 \
  ../../load-test/k6/send-batch-events.js
```
