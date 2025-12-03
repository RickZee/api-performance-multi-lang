#!/bin/bash

# Deploy Debezium PostgreSQL Connector for Simple Events to Confluent Cloud
# This connector reads from local Postgres simple_events table and writes to Confluent Cloud Kafka

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONNECTOR_CONFIG="$SCRIPT_DIR/../connectors/postgres-debezium-simple-events-confluent-cloud.json"
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"

echo "======================================"
echo "Deploying Debezium Simple Events Connector"
echo "======================================"

# Check if Kafka Connect is running
echo ""
echo "Step 1: Checking Kafka Connect availability..."
if ! curl -sf "$KAFKA_CONNECT_URL" > /dev/null; then
    echo "ERROR: Kafka Connect is not available at $KAFKA_CONNECT_URL"
    echo "Please start Kafka Connect with: cd ../.. && docker-compose up -d kafka-connect"
    exit 1
fi

echo "✓ Kafka Connect is running"

# Check if connector config exists
if [ ! -f "$CONNECTOR_CONFIG" ]; then
    echo "ERROR: Connector configuration not found at $CONNECTOR_CONFIG"
    exit 1
fi

echo ""
echo "Step 2: Checking if connector already exists..."
CONNECTOR_NAME=$(jq -r '.name' "$CONNECTOR_CONFIG")

if curl -sf "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME" > /dev/null 2>&1; then
    echo "Connector '$CONNECTOR_NAME' already exists. Deleting it first..."
    curl -X DELETE "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME"
    sleep 2
fi

echo ""
echo "Step 3: Deploying connector..."
RESPONSE=$(curl -X POST "$KAFKA_CONNECT_URL/connectors" \
    -H "Content-Type: application/json" \
    -d @"$CONNECTOR_CONFIG" \
    -w "\nHTTP_STATUS:%{http_code}" \
    -s)

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
    echo "✓ Connector deployed successfully!"
    echo ""
    echo "$BODY" | jq '.'
else
    echo "✗ Failed to deploy connector (HTTP $HTTP_STATUS)"
    echo "$BODY" | jq '.'
    exit 1
fi

echo ""
echo "Step 4: Checking connector status..."
sleep 3

curl -s "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME/status" | jq '.'

echo ""
echo "======================================"
echo "Simple Events Connector Deployment Complete!"
echo "======================================"
echo ""
echo "Useful commands:"
echo "  Check status:   curl $KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME/status | jq"
echo "  View tasks:     curl $KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME/tasks | jq"
echo "  Check logs:     docker logs cdc-kafka-connect -f"
echo "  Restart:        curl -X POST $KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME/restart"
echo "  Delete:         curl -X DELETE $KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME"
echo ""


