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

- **Confluent Platform**: Kafka, Schema Registry, Kafka Connect, Control Center
- **Flink Cluster**: JobManager, TaskManager, Flink SQL for stream processing
- **Postgres Source Connector**: Debezium-based CDC connector
- **Consumer Applications**: Process filtered events from consumer-specific topics

For detailed architecture information, component deep dives, and how consumers interact with the system, see [ARCHITECTURE.md](ARCHITECTURE.md).

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

1. **Check Raw Events**: Verify events appear in `raw-business-events` topic
2. **Check Filtered Events**: Verify filtered events appear in consumer-specific topics
3. **Check Consumer Logs**: Verify consumers receive and process events

### Validate Data in Kafka and Flink

#### Validate Kafka Topics

Check Kafka topics using the Confluent Cloud CLI:

```bash
# List topics
confluent kafka topic list

# Describe a topic
confluent kafka topic describe raw-business-events

# Consume messages
confluent kafka topic consume raw-business-events --value-format json --max-messages 10
```

#### Validate Flink Jobs

Check Flink job status using the Confluent Cloud CLI:

```bash
# List all Flink statements
confluent flink statement list --compute-pool <pool-id>

# Describe a specific statement
confluent flink statement describe <statement-name> --compute-pool <pool-id>
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

#### Option A: Docker Compose (Local Development)

Check connector status:

```bash
curl http://localhost:8083/connectors/postgres-source-connector/status | jq
```

Common issues:
- PostgreSQL not accessible: Check network connectivity
- Replication slot already exists: Drop and recreate slot
- Missing tables: Ensure tables exist in PostgreSQL

#### Option B: Confluent Cloud (Production)

Check connector status:

```bash
# Via CLI
confluent connector describe postgres-source-connector

# View connector status and metrics
confluent connector describe postgres-source-connector --output json | jq '.status'

# View connector logs
confluent connector logs postgres-source-connector

# Check connector health
confluent connector health-check postgres-source-connector
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment → Connectors
- View connector status, metrics, and logs
- Check connector task status and errors
- View connector configuration

**Common Issues:**
- **PostgreSQL not accessible**: Verify network connectivity, security groups, and VPC endpoints
- **Replication slot already exists**: Drop and recreate slot: `SELECT pg_drop_replication_slot('debezium_slot');`
- **Missing tables**: Ensure tables exist in PostgreSQL and are included in `table.include.list`
- **Schema Registry authentication**: Verify API keys for Schema Registry access
- **Connector cluster unavailable**: Check connector cluster status and health

**Troubleshooting Steps:**
1. Check connector status: `confluent connector describe <connector-name>`
2. Review connector logs: `confluent connector logs <connector-name>`
3. Verify PostgreSQL connectivity from connector cluster
4. Check Schema Registry connectivity and authentication
5. Verify topic exists: `confluent kafka topic describe <topic-name>`
6. Restart connector: `confluent connector update <connector-name> --config-file <config-file>`

### Flink Job Failing

#### Option A: Docker Compose (Local Development)

Check Flink job logs:

```bash
docker logs cdc-flink-jobmanager
docker logs cdc-flink-taskmanager
```

Common issues:
- Schema mismatch: Verify Avro schemas in Schema Registry
- Topic not found: Ensure topics are created
- Serialization errors: Check schema compatibility

#### Option B: Confluent Cloud (Production)

Check Flink statement status and logs:

```bash
# Check statement status
confluent flink statement describe <statement-id> --compute-pool <compute-pool-id>

# View statement logs
confluent flink statement logs <statement-id> --compute-pool <compute-pool-id>

# Check compute pool status
confluent flink compute-pool describe <compute-pool-id>

# View statement metrics (includes error rates)
confluent flink statement describe <statement-id> \
  --compute-pool <compute-pool-id> \
  --output json | jq '.metrics'

# List all statements in compute pool
confluent flink statement list --compute-pool <compute-pool-id>
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment → Flink
- View statement status, metrics, and execution logs
- Check for backpressure, checkpoint failures, or errors
- Monitor CFU utilization and auto-scaling events

**Common Issues:**
- **Schema mismatch**: Verify Avro schemas in Schema Registry match SQL table definitions
- **Topic not found**: Ensure topics exist: `confluent kafka topic list`
- **Serialization errors**: Check schema compatibility and Schema Registry authentication
- **Checkpoint failures**: Check checkpoint configuration and storage access
- **Backpressure**: Increase CFU limit or optimize SQL queries
- **Statement not starting**: Check SQL syntax, bootstrap servers, and API key permissions

**Troubleshooting Steps:**
1. Check statement status: `confluent flink statement describe <statement-id> --compute-pool <pool-id>`
2. Review statement logs: `confluent flink statement logs <statement-id> --compute-pool <pool-id>`
3. Verify topics exist: `confluent kafka topic list`
4. Check Schema Registry: `confluent schema-registry subject list`
5. Verify compute pool health: `confluent flink compute-pool describe <pool-id>`
6. Check CFU utilization: Monitor if max CFU limit is reached
7. Update statement: `confluent flink statement update <statement-id> --compute-pool <pool-id> --statement-file <sql-file>`

### Consumers Not Receiving Events

#### Option A: Docker Compose (Local Development)

Check consumer configuration:

```bash
docker logs cdc-loan-consumer
docker logs cdc-service-consumer
```

Common issues:
- Wrong topic name: Verify topic names match
- Consumer group offset: Reset consumer group if needed
- Network issues: Verify Kafka connectivity

#### Option B: Confluent Cloud (Production)

Check consumer group status and lag:

```bash
# View consumer groups
confluent kafka consumer-group list

# Describe consumer group (shows lag, offsets, members)
confluent kafka consumer-group describe <consumer-group-name>

# Check consumer lag
confluent kafka consumer-group describe <consumer-group-name> --output json | jq '.lag'

# View consumer group metrics
confluent kafka consumer-group describe <consumer-group-name> --output json | jq '.metrics'

# Check topic message count
confluent kafka topic describe <topic-name> --output json | jq '.partitions[].offset'
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment → Consumers
- View consumer group lag, offsets, and member status
- Check if consumers are actively consuming
- Monitor consumer group health and throughput

**Common Issues:**
- **Wrong topic name**: Verify topic names match: `confluent kafka topic list`
- **Consumer group offset**: Check offsets: `confluent kafka consumer-group describe <group-name>`
- **Network issues**: Verify bootstrap servers and network connectivity
- **No messages in topic**: Check if Flink jobs are writing to topics
- **Consumer not running**: Verify consumer application is running and connected
- **Authentication issues**: Verify API keys and credentials

**Troubleshooting Steps:**
1. Check consumer group status: `confluent kafka consumer-group describe <group-name>`
2. Verify topic exists and has messages: `confluent kafka topic describe <topic-name>`
3. Check consumer lag: If lag is high, consumers may be slow or stopped
4. Verify bootstrap servers in consumer configuration
5. Check API keys and authentication
6. Review consumer application logs (via your logging infrastructure)
7. Reset consumer group if needed: `confluent kafka consumer-group delete <group-name>` (then restart consumers)

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
    ├── generate-test-data.sh       # Generate test data using k6 and Java REST API
    ├── deploy-flink-confluent-cloud.sh  # Deploy Flink SQL to Confluent Cloud
    └── generate-flink-sql.py      # Generate Flink SQL from filters.yaml
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

