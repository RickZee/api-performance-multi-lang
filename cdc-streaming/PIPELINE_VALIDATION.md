# Simple Events CDC Pipeline Validation Guide

This document provides instructions for validating the complete simple-events CDC pipeline.

## Pipeline Overview

The simple-events pipeline consists of:

1. **Java REST API** - Accepts POST requests to `/api/v1/events/events-simple`
2. **PostgreSQL Database** - Stores events in `simple_events` table
3. **Debezium CDC Connector** - Captures database changes
4. **Kafka** - Receives events in `simple-business-events` topic

## Prerequisites

1. Docker and Docker Compose installed
2. PostgreSQL container running with logical replication enabled
3. Java REST API running (port 8081)
4. Kafka Connect running (port 8083) - configured for Confluent Cloud

## Validation Steps

### Step 1: Start Required Services

```bash
# Start PostgreSQL (if not running)
docker-compose up -d postgres-large

# Enable logical replication (if not already done)
cd cdc-streaming/scripts
./enable-postgres-replication.sh

# Start Java REST API
cd ../../producer-api-java-rest
./gradlew bootRun

# In another terminal, start Kafka Connect
cd cdc-streaming
docker-compose -f docker-compose.confluent-cloud.yml up -d kafka-connect-cloud
```

### Step 2: Deploy CDC Connector

```bash
cd cdc-streaming/scripts
./deploy-debezium-simple-events-connector.sh
```

### Step 3: Run Validation Scripts

#### Quick Validation

```bash
cd cdc-streaming/scripts
./validate-simple-events-pipeline.sh
```

#### Full End-to-End Test

```bash
cd cdc-streaming/scripts
./test-simple-events-pipeline.sh
```

### Step 4: Manual Testing

#### Test API Endpoint

```bash
curl -X POST http://localhost:8081/api/v1/events/events-simple \
  -H "Content-Type: application/json" \
  -d '{
    "uuid": "550e8400-e29b-41d4-a716-446655440000",
    "eventName": "LoanPaymentSubmitted",
    "createdDate": "2024-01-15T10:30:00Z",
    "savedDate": "2024-01-15T10:30:05Z",
    "eventType": "LoanPaymentSubmitted"
  }'
```

Expected response: `200 OK` with message "Simple event processed successfully"

#### Verify Event in Database

```bash
docker exec car_entities_postgres_large psql -U postgres -d car_entities -c "SELECT * FROM simple_events ORDER BY saved_date DESC LIMIT 5;"
```

#### Check Connector Status

```bash
curl http://localhost:8083/connectors/postgres-debezium-simple-events-confluent-cloud/status | jq
```

Expected: Connector and task state should be "RUNNING"

#### Verify Events in Kafka Topic

If using Confluent Cloud:

- Check the Confluent Cloud UI for the `simple-business-events` topic
- Use kafka-console-consumer if you have CLI access configured

If using local Kafka:

```bash
docker exec -it cdc-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic simple-business-events \
  --from-beginning
```

## Validation Checklist

- [ ] Java REST API is running and healthy
- [ ] `simple_events` table exists in PostgreSQL
- [ ] API endpoint accepts POST requests
- [ ] Events are saved to database
- [ ] CDC connector is deployed and running
- [ ] Connector status shows RUNNING
- [ ] Events appear in Kafka topic `simple-business-events`

## Troubleshooting

### API Not Responding

- Check if API is running: `curl http://localhost:8081/api/v1/events/health`
- Check logs: Look at the terminal where `./gradlew bootRun` is running
- Verify port 8081 is not in use by another service

### Database Table Missing

- The table should be created automatically when the API starts (via `schema.sql`)
- Manually create if needed:

  ```sql
  CREATE TABLE simple_events (
      id VARCHAR(255) PRIMARY KEY,
      event_name VARCHAR(255) NOT NULL,
      created_date TIMESTAMP WITH TIME ZONE,
      saved_date TIMESTAMP WITH TIME ZONE,
      event_type VARCHAR(255)
  );
  CREATE INDEX idx_simple_events_event_name ON simple_events(event_name);
  ```

### Connector Not Deploying

- Check Kafka Connect is running: `curl http://localhost:8083`
- Check connector logs: `docker logs cdc-kafka-connect-cloud -f`
- Verify connector config JSON is valid: `jq . cdc-streaming/connectors/postgres-debezium-simple-events-confluent-cloud.json`

### Events Not Appearing in Kafka

- Verify connector is RUNNING (not just deployed)
- Check connector logs for errors
- Verify PostgreSQL logical replication is enabled
- Check that the replication slot exists:

  ```sql
  SELECT * FROM pg_replication_slots WHERE slot_name = 'confluent_cloud_cdc_simple_slot';
  ```

## Test Results

After running the validation, you should see:

- All unit tests passing (SimpleEventControllerTest)
- API endpoint accepting and processing events
- Events persisted in database
- CDC connector capturing changes
- Events flowing to Kafka topic

## Next Steps

Once validated:

1. Monitor the pipeline for production readiness
2. Set up consumers for the `simple-business-events` topic
3. Configure Flink jobs if needed for event processing
4. Set up alerting for connector failures
