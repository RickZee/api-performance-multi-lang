# Local Dockerized CDC Setup Guide

This guide explains how to run the CDC streaming system locally using Docker, replacing AWS Aurora Postgres and Confluent Kafka with local alternatives.

## Architecture Overview

The local setup uses:
- **PostgreSQL**: Local Postgres container with logical replication enabled
- **Redpanda**: Kafka-compatible message broker (simpler than Kafka, no Zookeeper)
- **Kafka Connect**: With Debezium PostgreSQL connector for CDC
- **Stream Processors**: 
  - Spring Boot Kafka Streams for event filtering
  - Apache Flink for event filtering (runs alongside Spring Boot)
- **Consumers**: Python consumers for filtered events (both Spring Boot and Flink topics)

## Prerequisites

- Docker and Docker Compose installed
- `jq` installed (for JSON parsing in scripts)
- At least 8GB of available RAM (recommended)

## Quick Start

### 1. Start Infrastructure Services

Start the core infrastructure (Postgres, Redpanda, Kafka Connect):

```bash
# From project root
docker-compose up -d postgres-large redpanda redpanda-console kafka-connect
```

Wait for services to be healthy:
```bash
docker-compose ps
```

You should see all services in "healthy" or "running" state.

### 2. Verify Database Schema

Connect to Postgres and verify the `event_headers` table exists:

```bash
docker exec -it car_entities_postgres_large psql -U postgres -d car_entities -c "\d event_headers"
```

You should see the table with columns: `id`, `event_name`, `event_type`, `created_date`, `saved_date`, `header_data`.

### 3. Deploy Debezium Connector

Deploy the CDC connector to capture changes from `event_headers` table:

```bash
cd cdc-streaming
./scripts/deploy-debezium-connector-local.sh
```

The script will:
- Wait for Kafka Connect to be ready
- Check if connector already exists
- Deploy the connector configuration
- Verify connector status

### 4. Verify Connector Status

Check that the connector is running:

```bash
curl http://localhost:8083/connectors/postgres-debezium-event-headers-local/status | jq
```

You should see `"state": "RUNNING"` for both connector and task.

### 5. Test CDC Pipeline

Insert a test event into the database:

```bash
docker exec -it car_entities_postgres_large psql -U postgres -d car_entities << EOF
INSERT INTO business_events (id, event_name, event_type, created_date, saved_date, event_data)
VALUES (
  'test-event-001',
  'LoanCreated',
  'Loan',
  NOW(),
  NOW(),
  '{"eventHeader": {"uuid": "test-event-001", "eventName": "LoanCreated"}}'::jsonb
);

INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data)
VALUES (
  'test-event-001',
  'LoanCreated',
  'Loan',
  NOW(),
  NOW(),
  '{"uuid": "test-event-001", "eventName": "LoanCreated", "eventType": "Loan"}'::jsonb
);
EOF
```

Verify the event appears in Kafka:

```bash
# Using Redpanda CLI
docker exec -it redpanda rpk topic consume raw-event-headers --num 1

# Or using kcat (if installed)
kcat -C -b localhost:19092 -t raw-event-headers -c 1
```

### 6. Start Stream Processors

Start the Spring Boot stream processor:

```bash
# From project root
cd cdc-streaming
docker-compose -f docker-compose-local.yml up -d stream-processor
```

Monitor the stream processor logs:

```bash
docker logs -f cdc-local-stream-processor
```

### 7. Start Flink Cluster (Optional)

Start the Flink cluster for Flink SQL-based stream processing:

```bash
cd cdc-streaming
docker-compose -f docker-compose-local.yml up -d flink-jobmanager flink-taskmanager
```

Wait for Flink to be ready (check Flink Web UI at http://localhost:8082), then deploy Flink SQL statements:

```bash
cd cdc-streaming
./scripts/deploy-flink-local.sh
```

This will deploy the Flink SQL statements from `flink-jobs/business-events-routing-local-docker.sql`.

### 8. Start Consumers

Start consumers for both Spring Boot and Flink processed events:

```bash
# Spring Boot consumers
docker-compose -f docker-compose-local.yml up -d loan-consumer car-consumer service-consumer loan-payment-consumer

# Flink consumers
docker-compose -f docker-compose-local.yml up -d loan-consumer-flink car-consumer-flink service-consumer-flink loan-payment-consumer-flink
```

## Service URLs

- **Redpanda Console**: http://localhost:8086 (Web UI for topic management)
- **Kafka Connect REST API**: http://localhost:8085
- **Spring Boot Stream Processor Health**: http://localhost:8083/actuator/health
- **Flink Web UI**: http://localhost:8082 (Flink cluster management)
- **Flink REST API**: http://localhost:8082/v1/statements
- **Metadata Service**: http://localhost:8081/api/v1/health

## Configuration

### Environment Variables

The system uses environment variables with sensible defaults for local development:

- `KAFKA_BOOTSTRAP_SERVERS`: Defaults to `redpanda:9092` (internal Docker network)
- `KAFKA_SECURITY_PROTOCOL`: Defaults to `PLAINTEXT` (no auth for local)
- `DATABASE_URL`: Defaults to `jdbc:postgresql://postgres-large:5432/car_entities`

### Override for Confluent Cloud

To use Confluent Cloud instead of local Redpanda, set:

```bash
export KAFKA_BOOTSTRAP_SERVERS=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
export KAFKA_API_KEY=your-key
export KAFKA_API_SECRET=your-secret
export KAFKA_SECURITY_PROTOCOL=SASL_SSL
```

Then start services - they will use Confluent Cloud instead of local Redpanda.

## Troubleshooting

### Connector Not Starting

1. Check Kafka Connect logs:
   ```bash
   docker logs kafka-connect
   ```

2. Verify Postgres logical replication is enabled:
   ```bash
   docker exec -it car_entities_postgres_large psql -U postgres -d car_entities -c "SHOW wal_level;"
   ```
   Should return `logical`.

3. Check replication slots:
   ```bash
   docker exec -it car_entities_postgres_large psql -U postgres -d car_entities -c "SELECT * FROM pg_replication_slots;"
   ```

### No Events in Topics

1. Verify connector is running:
   ```bash
   curl http://localhost:8083/connectors/postgres-debezium-event-headers-local/status | jq
   ```

2. Check if events exist in database:
   ```bash
   docker exec -it car_entities_postgres_large psql -U postgres -d car_entities -c "SELECT COUNT(*) FROM event_headers;"
   ```

3. Check connector task logs:
   ```bash
   curl http://localhost:8083/connectors/postgres-debezium-event-headers-local/tasks/0/logs | jq
   ```

### Redpanda Not Accessible

1. Check Redpanda is running:
   ```bash
   docker ps | grep redpanda
   ```

2. Check Redpanda health:
   ```bash
   docker exec -it cdc-local-redpanda rpk cluster health
   ```

3. Verify network connectivity:
   ```bash
   docker network inspect cdc_local_network | grep redpanda
   ```

### Flink Cluster Not Starting

1. Check Flink JobManager logs:
   ```bash
   docker logs cdc-local-flink-jobmanager
   ```

2. Check Flink TaskManager logs:
   ```bash
   docker logs cdc-local-flink-taskmanager
   ```

3. Verify Flink REST API is accessible:
   ```bash
   curl http://localhost:8082/overview
   ```

4. Check if Flink containers are on the correct network:
   ```bash
   docker network inspect cdc_local_network | grep flink
   ```

### Flink SQL Statements Not Deploying

1. Verify Flink cluster is running and accessible:
   ```bash
   curl http://localhost:8082/overview | jq
   ```

2. Check if statements already exist:
   ```bash
   curl http://localhost:8082/v1/statements | jq
   ```

3. Check deployment script logs:
   ```bash
   ./scripts/deploy-flink-local.sh
   ```

4. Verify SQL file syntax:
   ```bash
   cat cdc-streaming/flink-jobs/business-events-routing-local-docker.sql
   ```

### Metadata Service Not Deploying to Local Flink

1. Verify local Flink is enabled:
   ```bash
   docker exec cdc-local-metadata-service-java env | grep FLINK_LOCAL
   ```

2. Check metadata service can reach Flink:
   ```bash
   docker exec cdc-local-metadata-service-java curl -f http://flink-jobmanager:8081/overview
   ```

3. Verify metadata service configuration:
   ```bash
   docker exec cdc-local-metadata-service-java cat /app/application.yml | grep -A 3 flink
   ```

## Database Schema

The `event_headers` table structure:

```sql
CREATE TABLE event_headers (
    id VARCHAR(255) PRIMARY KEY,
    event_name VARCHAR(255) NOT NULL,
    event_type VARCHAR(255),
    created_date TIMESTAMP WITH TIME ZONE,
    saved_date TIMESTAMP WITH TIME ZONE,
    header_data JSONB NOT NULL,
    CONSTRAINT fk_event_headers_business_events 
        FOREIGN KEY (id) REFERENCES business_events(id) 
        ON DELETE CASCADE
);
```

## Connector Configuration

The Debezium connector is configured to:
- Capture changes from `public.event_headers` table
- Use `pgoutput` plugin for logical replication
- Route events to `raw-event-headers` topic
- Add CDC metadata fields: `__op`, `__table`, `__ts_ms`
- Unwrap Debezium envelope using `ExtractNewRecordState` transform

Configuration file: `cdc-streaming/connectors/postgres-debezium-local.json`

## Stream Processing

### Spring Boot Stream Processor

The Spring Boot stream processor:
- Consumes from `raw-event-headers` topic
- Filters events based on `filters.yml` configuration
- Routes filtered events to topic-specific topics (with `-spring` suffix):
  - `filtered-loan-created-events-spring`
  - `filtered-car-created-events-spring`
  - `filtered-service-events-spring`
  - `filtered-loan-payment-submitted-events-spring`

### Flink Stream Processor

The Flink stream processor:
- Consumes from `raw-event-headers` topic
- Uses Flink SQL statements for filtering (defined in `flink-jobs/business-events-routing-local-docker.sql`)
- Routes filtered events to topic-specific topics (with `-flink` suffix):
  - `filtered-loan-created-events-flink`
  - `filtered-car-created-events-flink`
  - `filtered-service-events-flink`
  - `filtered-loan-payment-submitted-events-flink`

**Deploying Flink SQL Statements:**

You can deploy Flink SQL statements either:
1. **Manually**: Use the deployment script `./scripts/deploy-flink-local.sh`
2. **Via Metadata Service**: Enable local Flink in metadata service and deploy filters via API

To enable local Flink in metadata service, set:
```bash
export FLINK_LOCAL_ENABLED=true
export FLINK_LOCAL_REST_API_URL=http://flink-jobmanager:8081
```

Then deploy filters via the metadata service API:
```bash
curl -X POST "http://localhost:8081/api/v1/filters/{filter-id}/deployments/flink" \
  -H "Content-Type: application/json" \
  -d '{"force": false}'
```

**Flink vs Spring Boot:**

Both processors run simultaneously and process the same events from `raw-event-headers`. Consumers can choose which processor's output to consume:
- Use `-spring` suffixed topics for Spring Boot processed events
- Use `-flink` suffixed topics for Flink processed events

This allows you to compare performance and behavior between the two processing engines.

## Cleanup

To stop all services:

```bash
docker-compose down
```

To remove volumes (deletes all data):

```bash
docker-compose down -v
```

To remove only CDC-related services:

```bash
docker-compose stop redpanda redpanda-console kafka-connect
docker-compose rm -f redpanda redpanda-console kafka-connect
```

## Next Steps

1. **Produce Test Events**: Use producer APIs to insert events into the database
2. **Monitor Topics**: Use Redpanda Console to view topics and messages
3. **Verify Consumers**: Check consumer logs to see filtered events
4. **Scale Services**: Add more consumer instances or stream processor replicas

## Differences from Production

| Component | Local | Production |
|-----------|-------|------------|
| Database | Docker Postgres | AWS Aurora Postgres |
| Message Broker | Redpanda | Confluent Cloud Kafka |
| Authentication | None (PLAINTEXT) | SASL_SSL with API keys |
| Schema Registry | Redpanda built-in | Confluent Cloud Schema Registry |
| Kafka Connect | Local Docker | Confluent Cloud Managed |
| Flink | Local Docker Cluster | Confluent Cloud Flink |
| Flink Connector | Standard Kafka connector | Confluent connector |

## Additional Resources

- [Redpanda Documentation](https://docs.redpanda.com/)
- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Spring Boot Kafka Streams](https://docs.spring.io/spring-kafka/reference/kafka-streams.html)

