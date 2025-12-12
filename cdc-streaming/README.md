# CDC Streaming Architecture

A configurable streaming architecture that enables event-based consumers to subscribe to filtered subsets of events. This implementation uses Confluent Platform (Kafka, Schema Registry, Control Center, Connect), **Confluent Managed PostgreSQL CDC Source Connector** (for Confluent Cloud) or Debezium connectors (for local development) for CDC, and Flink SQL for stream processing.


## Overview

This CDC streaming system captures changes from PostgreSQL database tables and streams them through Kafka, where Flink SQL jobs filter and route events to consumer-specific topics. The architecture is designed for:

- **Configurability at CI/CD Level**: Filtering and routing rules are defined as code (YAML/JSON files and Flink SQL scripts) stored in version control
- **Scalability and Resilience**: Built for horizontal scaling with Kafka partitioning and Flink parallelism
- **Integration with Existing Stack**: Events ingress via existing Ingestion APIs and PostgreSQL database
- **Security and Observability**: Schema Registry for schema enforcement, monitoring via Control Center
- **Cost Efficiency**: Stateful processing with Flink and efficient filtering/routing

## Architecture

The system captures database changes via CDC, streams them through Kafka, and uses Flink SQL to filter and route events to consumer-specific topics. Key components include Confluent Platform (Kafka, Schema Registry, Kafka Connect), Flink for stream processing, and **Confluent Managed PostgreSQL CDC Source Connector** (for Confluent Cloud) or Debezium-based PostgreSQL CDC connector (for local development).

For comprehensive architecture documentation including detailed data flow diagrams, component deep dives, and how consumers interact with the system, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Example Data Structures

This system uses specific example structures for car entities and loan created events:

- **Car Entity Example**: [`data/entities/car/car-large.json`](../data/entities/car/car-large.json)
  - Large car entity structure with all required fields
  - Used as reference for car entity validation and test data generation
  
- **Loan Created Event Example**: [`data/schemas/event/samples/loan-created-event.json`](../data/schemas/event/samples/loan-created-event.json)
  - Complete loan created event structure
  - Used as reference for loan event filtering and validation

These examples are used by:
- Test data generation scripts (`scripts/generate-test-data-from-examples.sh`)
- Entity validation scripts (`scripts/validate-entity-structure.py`)
- Filter configuration in Flink SQL jobs - specifically targets `LoanCreated` events
- Schema documentation and examples

For generating test data based on these examples, see the [Testing - Generate Test Events](#testing) section below.

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

**Note:** For production, use Confluent Cloud Flink instead of local Flink. Local Flink is for development/testing only.

**Monitoring:** Use Confluent Cloud Console at https://confluent.cloud for monitoring Kafka, Schema Registry, connectors, and Flink statements.

#### Option B: Confluent Cloud (Production)

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

## Data Model Comparison

This system supports two different data model approaches for representing entity attributes: **deeply nested** and **flat**. Understanding the differences is important for filtering, processing, and schema design decisions.

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
- Entity schemas: [`data/schemas/entity/`](../data/schemas/entity/)
- Sample event data: [`data/schemas/event/samples/`](../data/schemas/event/samples/)
- Sample entity data: [`data/entities/`](../data/entities/)

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

### Flat Data Model

The **flat data model** uses a key-value map structure where all values are strings and nested paths are represented using dot notation in keys.

**Example Structure:**

The flat data model uses dot notation in keys to represent nested paths. For the underlying entity structure, see [`data/schemas/entity/loan.json`](../data/schemas/entity/loan.json). The flat representation would convert nested attributes to dot-notation keys (e.g., `loan.loanAmount`, `loan.balance`).

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

-- Example query accessing flat structure
SELECT 
    id,
    updated_attributes->>'loan.loanAmount' as loan_amount,
    updated_attributes->>'borrower.name' as borrower_name
FROM loan_entities
WHERE (updated_attributes->>'loan.loanAmount')::numeric > 100000;
```

**Schema Definitions:**

For flat data model structures, refer to the entity schemas in the `data/` folder. The schemas define the structure that can be flattened using dot notation for keys. See [`data/schemas/entity/`](../data/schemas/entity/) for complete entity schema definitions.

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

### Confluent Cloud Console

**Note:** Use Confluent Cloud Console for all monitoring. Local Control Center has been removed.

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

#### Using Example-Based Test Data Generation

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

#### Using the k6 Test Data Generation Script

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

Quick verification:
1. **Check Raw Events**: Verify events appear in `raw-business-events` topic
2. **Check Filtered Events**: Verify filtered events appear in consumer-specific topics
3. **Check Consumer Logs**: Verify consumers receive and process events

## Shared Scripts

The `scripts/shared/` subdirectory contains shared scripts for managing Confluent Cloud connectors and Flink statements.

### `scripts/shared/deploy-connector.sh`

Deploy Confluent Cloud CDC connectors with consistent error handling and validation.

**Usage:**
```bash
./scripts/shared/deploy-connector.sh <config-file> [options]
```

**Parameters:**
- `config-file`: Path to connector configuration JSON file (relative to `connectors/` directory or absolute path)
- `--env-id ENV_ID`: Confluent environment ID (optional)
- `--cluster-id CLUSTER_ID`: Kafka cluster ID (optional)
- `--force`: Force deletion of existing connector without confirmation

**Example:**
```bash
./scripts/shared/deploy-connector.sh \
  postgres-cdc-source-business-events-confluent-cloud.json
```

**Required Environment Variables:**
- `KAFKA_API_KEY`: Confluent Cloud API key
- `KAFKA_API_SECRET`: Confluent Cloud API secret
- `DB_HOSTNAME`: Database hostname
- `DB_USERNAME`: Database username
- `DB_PASSWORD`: Database password
- `DB_NAME`: Database name

**Migration from Individual Scripts:**

The following individual scripts can now use the shared script:
- `deploy-business-events-connector.sh` → `deploy-connector.sh postgres-cdc-source-business-events-confluent-cloud.json`
- `deploy-connector-with-unwrap.sh` → `deploy-connector.sh postgres-cdc-source-business-events-confluent-cloud-fixed.json`

### `scripts/shared/flink-manager.sh`

Manage Flink SQL statements with a unified interface.

**Usage:**
```bash
./scripts/shared/flink-manager.sh <action> [options]
```

**Actions:**
- `cleanup`: Remove COMPLETED and FAILED statements (no confirmation)
- `delete-failed`: Delete FAILED and COMPLETED statements (with confirmation)
- `list`: List all statements
- `status <name>`: Get status of a specific statement
- `delete <name>`: Delete a specific statement

**Example:**
```bash
# List all statements
./scripts/shared/flink-manager.sh list

# Cleanup completed/failed statements
./scripts/shared/flink-manager.sh cleanup

# Delete with confirmation
./scripts/shared/flink-manager.sh delete-failed

# Get status of a statement
./scripts/shared/flink-manager.sh status my-statement

# Delete specific statement
./scripts/shared/flink-manager.sh delete my-statement
```

**Environment Variables:**
- `FLINK_COMPUTE_POOL_ID`: Flink compute pool ID (default: `lfcp-2xqo0m`)
- `KAFKA_CLUSTER_ID`: Kafka cluster ID (default: `lkc-rno3vp`)

**Migration from Individual Scripts:**

The following individual scripts can now use the shared script:
- `cleanup-flink-statements.sh` → `flink-manager.sh cleanup`
- `delete-failed-completed-flink-statements.sh` → `flink-manager.sh delete-failed`

For detailed usage information, see the [Shared Scripts Documentation](../scripts/README.md#shared-scripts).
