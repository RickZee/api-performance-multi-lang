# Local Dockerized CDC Setup Guide

This guide explains how to run the CDC streaming system locally using Docker, replacing AWS Aurora Postgres and Confluent Kafka with local alternatives.

## Architecture Overview

The local setup uses:
- **PostgreSQL**: Local Postgres container with logical replication enabled
- **Redpanda**: Kafka-compatible message broker (simpler than Kafka, no Zookeeper)
- **Kafka Connect**: With Debezium PostgreSQL connector for CDC
- **Stream Processors**: Spring Boot Kafka Streams for event filtering
- **Consumers**: Python consumers for filtered events

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

### 6. Start Stream Processor and Consumers

Start the Spring Boot stream processor and consumers:

```bash
# From project root
cd cdc-streaming
docker-compose up -d stream-processor loan-consumer car-consumer service-consumer loan-payment-consumer
```

Monitor the stream processor logs:

```bash
docker logs -f cdc-stream-processor
```

## Service URLs

- **Redpanda Console**: http://localhost:8084 (Web UI for topic management)
- **Kafka Connect REST API**: http://localhost:8083
- **Stream Processor Health**: http://localhost:8083/actuator/health
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
   docker exec -it redpanda rpk cluster health
   ```

3. Verify network connectivity:
   ```bash
   docker network inspect api-performance-multi-lang_car_network | grep redpanda
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

The Spring Boot stream processor:
- Consumes from `raw-event-headers` topic
- Filters events based on `filters.yml` configuration
- Routes filtered events to topic-specific topics:
  - `filtered-loan-created-events-spring`
  - `filtered-car-created-events-spring`
  - `filtered-service-events-spring`
  - `filtered-loan-payment-submitted-events-spring`

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

## Additional Resources

- [Redpanda Documentation](https://docs.redpanda.com/)
- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Spring Boot Kafka Streams](https://docs.spring.io/spring-kafka/reference/kafka-streams.html)

