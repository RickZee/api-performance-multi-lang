#!/bin/bash
# Test Pipeline
# This script tests the end-to-end CDC streaming pipeline

set -e

KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-localhost:9092}"
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"
POSTGRES_HOST="${POSTGRES_HOST:-postgres-large}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-car_entities}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"

echo "=========================================="
echo "CDC Streaming Pipeline Test"
echo "=========================================="
echo ""

# Step 1: Check services
echo "Step 1: Checking services..."
echo "  - Kafka: $KAFKA_BOOTSTRAP_SERVERS"
if docker exec cdc-kafka kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1; then
    echo "    ✓ Kafka is running"
else
    echo "    ✗ Kafka is not accessible"
    exit 1
fi

echo "  - Kafka Connect: $KAFKA_CONNECT_URL"
if curl -f -s "$KAFKA_CONNECT_URL/connectors" > /dev/null 2>&1; then
    echo "    ✓ Kafka Connect is running"
else
    echo "    ✗ Kafka Connect is not accessible"
    exit 1
fi

echo "  - PostgreSQL: $POSTGRES_HOST:$POSTGRES_PORT"
if PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" > /dev/null 2>&1; then
    echo "    ✓ PostgreSQL is accessible"
else
    echo "    ✗ PostgreSQL is not accessible"
    exit 1
fi

echo ""

# Step 2: Check topics
echo "Step 2: Checking Kafka topics..."
TOPICS=("raw-business-events" "filtered-loan-events" "filtered-service-events" "filtered-car-events")
for topic in "${TOPICS[@]}"; do
    if docker exec cdc-kafka kafka-topics.sh --bootstrap-server localhost:9092 --list | grep -q "^${topic}$"; then
        echo "    ✓ Topic '$topic' exists"
    else
        echo "    ✗ Topic '$topic' does not exist"
        echo "      Run ./scripts/create-topics.sh to create topics"
    fi
done

echo ""

# Step 3: Check connector
echo "Step 3: Checking Postgres connector..."
CONNECTOR_NAME="postgres-source-connector"
if curl -f -s "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME" > /dev/null 2>&1; then
    echo "    ✓ Connector '$CONNECTOR_NAME' is registered"
    CONNECTOR_STATUS=$(curl -s "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME/status" | jq -r '.connector.state')
    echo "      Status: $CONNECTOR_STATUS"
else
    echo "    ✗ Connector '$CONNECTOR_NAME' is not registered"
    echo "      Run ./scripts/setup-connector.sh to set up the connector"
fi

echo ""

# Step 4: Test data insertion (optional)
echo "Step 4: Testing data flow..."
echo "  To test the pipeline:"
echo "  1. Insert test data into PostgreSQL using your producer APIs"
echo "  2. Monitor the raw-business-events topic:"
echo "     docker exec -it cdc-kafka kafka-console-consumer.sh \\"
echo "       --bootstrap-server localhost:9092 \\"
echo "       --topic raw-business-events \\"
echo "       --from-beginning"
echo ""
echo "  3. Monitor filtered topics:"
echo "     docker exec -it cdc-kafka kafka-console-consumer.sh \\"
echo "       --bootstrap-server localhost:9092 \\"
echo "       --topic filtered-loan-events \\"
echo "       --from-beginning"
echo ""
echo "  4. Check consumer logs:"
echo "     docker logs cdc-loan-consumer"
echo "     docker logs cdc-service-consumer"

echo ""
echo "=========================================="
echo "Test complete!"
echo "=========================================="
