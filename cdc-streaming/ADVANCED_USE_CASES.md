# Advanced Use Cases and Commands

This document covers advanced scenarios, detailed commands, and complex use cases for the CDC streaming system.

## Table of Contents

1. [Advanced Monitoring](#advanced-monitoring)
2. [Advanced Testing Scenarios](#advanced-testing-scenarios)
3. [Self-Managed Flink Deployment](#self-managed-flink-deployment)
4. [Advanced Configuration](#advanced-configuration)
5. [REST API Integration](#rest-api-integration)

## Advanced Monitoring

### Detailed Kafka Topic Monitoring

Monitor topics via Confluent Cloud CLI:

```bash
# Consume messages via CLI
confluent kafka topic consume raw-event-headers --from-beginning
confluent kafka topic consume filtered-loan-created-events --from-beginning

# View topic details and metrics
confluent kafka topic describe raw-event-headers
confluent kafka topic describe filtered-loan-created-events

# View topic metrics (message count, throughput, etc.)
confluent kafka topic describe raw-event-headers --output json | jq '.metrics'
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment → Topics
- View real-time metrics: throughput, latency, message count
- Monitor consumer lag per topic
- View partition-level details

### Consumer Group Monitoring

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

### Flink Statement Monitoring

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

### Local Flink Dashboard (Development Only)

**Note:** For production, use Confluent Cloud Flink. Local Flink is for development/testing only.

Access Flink Web UI at: http://localhost:8082

- View running jobs
- Monitor job metrics
- Check checkpoint status
- View task manager details

### Docker Compose Consumer Logs

View consumer application logs:

```bash
# Loan consumer
docker logs -f cdc-loan-consumer

# Service consumer
docker logs -f cdc-service-consumer
```

## Advanced Testing Scenarios

### Using the Consolidated k6 Batch Events Script

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

### Using Test Data Generation Scripts

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

## Self-Managed Flink Deployment

**Note:** This option is intended for local development and testing only. For production, use Confluent Cloud Flink.

Deploy the Flink SQL routing job to self-managed Flink cluster:

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

## Advanced Configuration

### Postgres Connector Configuration

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

### Flink SQL Jobs Configuration

Edit the Flink SQL files directly:
- `flink-jobs/business-events-routing-confluent-cloud.sql` - Main routing job for Confluent Cloud
- `flink-jobs/business-events-routing-confluent-cloud-no-op.sql` - No-op version for testing

For detailed Flink SQL examples, query types, table definitions, and deployment patterns, see [ARCHITECTURE.md](ARCHITECTURE.md).

## REST API Integration

### Monitoring Topics via REST API

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

## Detailed Pipeline Verification

### Confluent Cloud Verification

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

## Related Documentation

- [README.md](README.md): Main documentation and quick start guide
- [ARCHITECTURE.md](ARCHITECTURE.md): System architecture details
- [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md): Complete Confluent Cloud setup guide
- [BACKEND_IMPLEMENTATION.md](BACKEND_IMPLEMENTATION.md): Back-end infrastructure details
