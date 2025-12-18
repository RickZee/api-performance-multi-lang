#!/bin/bash
# Deploy and Test Debezium Connector on EC2 Instance
# This script sets up a minimal Kafka Connect environment for testing

set -e

# Configuration
DSQL_ENDPOINT="${DSQL_ENDPOINT:-vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com}"
IAM_USER="${IAM_USER:-lambda_dsql_user}"
DB_NAME="${DB_NAME:-car_entities}"
REGION="${AWS_REGION:-us-east-1}"

echo "=== Debezium Connector Deployment Test ==="
echo "This script will:"
echo "1. Set up minimal Kafka Connect environment"
echo "2. Deploy the DSQL connector"
echo "3. Test CDC functionality"
echo ""

# Install Docker if not available
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    sudo dnf install -y docker
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
fi

# Generate IAM token
echo "Generating IAM token..."
TOKEN=$(aws rds generate-db-auth-token \
  --hostname $DSQL_ENDPOINT \
  --port 5432 \
  --username $IAM_USER \
  --region $REGION)

# Create docker-compose.yml for testing
cat > docker-compose.test.yml << EOF
version: '3.8'
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.4.0
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000

  kafka:
    image: confluentinc/cp-kafka:7.4.0
    depends_on:
      - zookeeper
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092,PLAINTEXT_HOST://localhost:29092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1

  kafka-connect:
    image: confluentinc/cp-kafka-connect:7.4.0
    depends_on:
      - kafka
    ports:
      - "8083:8083"
    environment:
      CONNECT_BOOTSTRAP_SERVERS: kafka:9092
      CONNECT_REST_ADVERTISED_HOST_NAME: kafka-connect
      CONNECT_REST_PORT: 8083
      CONNECT_GROUP_ID: dsql-connect-group
      CONNECT_CONFIG_STORAGE_TOPIC: _dsql-connect-configs
      CONNECT_OFFSET_STORAGE_TOPIC: _dsql-connect-offsets
      CONNECT_STATUS_STORAGE_TOPIC: _dsql-connect-status
      CONNECT_KEY_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_VALUE_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE: "false"
      CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE: "false"
      CONNECT_INTERNAL_KEY_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_INTERNAL_VALUE_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_PLUGIN_PATH: /usr/share/java,/usr/share/confluent-hub-components
    volumes:
      - ./debezium-connector-dsql/build/libs:/usr/share/confluent-hub-components/debezium-connector-dsql
    command:
      - bash
      - -c
      - |
        echo "Waiting for Kafka..."
        cub kafka-ready -b kafka:9092 1 60
        echo "Starting Kafka Connect..."
        /etc/confluent/docker/run

  postgres-test:
    image: postgres:15
    environment:
      POSTGRES_DB: test_db
      POSTGRES_USER: test_user
      POSTGRES_PASSWORD: test_pass
    ports:
      - "5433:5432"
    volumes:
      - ./init-test-db.sql:/docker-entrypoint-initdb.d/init-test-db.sql
EOF

# Create test database initialization
cat > init-test-db.sql << EOF
-- Create test database schema matching event_headers table structure
-- Based on current production schema from data/schema.sql
CREATE TABLE event_headers (
    id VARCHAR(255) PRIMARY KEY,
    event_name VARCHAR(255) NOT NULL,
    event_type VARCHAR(255) NOT NULL,
    created_date TIMESTAMP NOT NULL,
    saved_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    header_data JSONB NOT NULL
);

-- Create index on event_type for filtering
CREATE INDEX idx_event_headers_event_type ON event_headers(event_type);

-- Insert test data matching production event types
INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data)
VALUES
    ('test-1', 'CarCreated', 'CarCreated', NOW(), NOW(), '{"uuid": "test-1", "eventName": "CarCreated", "eventType": "CarCreated"}'::jsonb),
    ('test-2', 'LoanCreated', 'LoanCreated', NOW(), NOW(), '{"uuid": "test-2", "eventName": "LoanCreated", "eventType": "LoanCreated"}'::jsonb),
    ('test-3', 'LoanPaymentSubmitted', 'LoanPaymentSubmitted', NOW(), NOW(), '{"uuid": "test-3", "eventName": "LoanPaymentSubmitted", "eventType": "LoanPaymentSubmitted"}'::jsonb),
    ('test-4', 'CarServiceDone', 'CarServiceDone', NOW(), NOW(), '{"uuid": "test-4", "eventName": "CarServiceDone", "eventType": "CarServiceDone"}'::jsonb);
EOF

# Create connector configuration
# Updated to match current event_headers table structure and use ExtractNewRecordState transform
cat > dsql-connector-test.json << EOF
{
  "name": "dsql-cdc-connector",
  "config": {
    "connector.class": "io.debezium.connector.dsql.DsqlConnector",
    "tasks.max": "1",
    "dsql.endpoint.primary": "$DSQL_ENDPOINT",
    "dsql.port": "5432",
    "dsql.region": "$REGION",
    "dsql.iam.username": "$IAM_USER",
    "dsql.database.name": "$DB_NAME",
    "dsql.tables": "event_headers",
    "dsql.poll.interval.ms": "1000",
    "dsql.batch.size": "100",
    "topic.prefix": "dsql-test",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter.schemas.enable": "false",
    "transforms": "unwrap,route",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "false",
    "transforms.unwrap.add.fields": "op,table,ts_ms",
    "transforms.unwrap.add.fields.prefix": "__",
    "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.route.regex": "dsql-test\\.public\\.event_headers",
    "transforms.route.replacement": "raw-event-headers-test"
  }
}
EOF

echo "Starting test environment..."
docker-compose -f docker-compose.test.yml up -d

echo "Waiting for services to start..."
sleep 60

echo "Checking service health..."
docker-compose -f docker-compose.test.yml ps

echo "Testing Kafka Connect API..."
curl -X GET http://localhost:8083/ | head -n 10

echo ""
echo "=== Manual Testing Steps ==="
echo "1. Check connector plugins:"
echo "   curl -X GET http://localhost:8083/connector-plugins | jq '.[] | select(.class | contains(\"Dsql\"))'"
echo ""
echo "2. Deploy connector:"
echo "   curl -X POST -H 'Content-Type: application/json' -d @dsql-connector-test.json http://localhost:8083/connectors"
echo ""
echo "3. Check connector status:"
echo "   curl -X GET http://localhost:8083/connectors/dsql-cdc-connector/status"
echo ""
echo "4. Insert test data into DSQL event_headers table:"
echo "   PGPASSWORD='$TOKEN' psql -h $DSQL_ENDPOINT -p 5432 -U $IAM_USER -d $DB_NAME -c \"INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) VALUES ('test-new', 'CarCreated', 'CarCreated', NOW(), NOW(), '{\\\"uuid\\\": \\\"test-new\\\", \\\"eventName\\\": \\\"CarCreated\\\", \\\"eventType\\\": \\\"CarCreated\\\"}'::jsonb);\""
echo ""
echo "5. Check Kafka topics (should route to raw-event-headers-test):"
echo "   docker exec \$(docker-compose -f docker-compose.test.yml ps -q kafka) kafka-console-consumer --bootstrap-server localhost:9092 --topic raw-event-headers-test --from-beginning"
echo ""
echo "   Note: Events should have __op, __table, __ts_ms fields from ExtractNewRecordState transform"
echo ""
echo "6. Clean up:"
echo "   docker-compose -f docker-compose.test.yml down -v"
