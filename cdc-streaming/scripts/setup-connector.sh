#!/bin/bash
# Setup Postgres Source Connector
# This script registers the Postgres CDC connector with Kafka Connect

set -e

KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"
CONNECTOR_CONFIG="${CONNECTOR_CONFIG:-./connectors/postgres-source-connector.json}"

echo "Setting up Postgres Source Connector..."
echo "Kafka Connect URL: $KAFKA_CONNECT_URL"
echo "Connector Config: $CONNECTOR_CONFIG"

# Check if connector config exists
if [ ! -f "$CONNECTOR_CONFIG" ]; then
    echo "Error: Connector config file not found: $CONNECTOR_CONFIG"
    exit 1
fi

# Check if Kafka Connect is available
echo "Checking Kafka Connect availability..."
if ! curl -f -s "$KAFKA_CONNECT_URL/connectors" > /dev/null; then
    echo "Error: Kafka Connect is not available at $KAFKA_CONNECT_URL"
    echo "Make sure Kafka Connect is running and accessible"
    exit 1
fi

# Get connector name from config
CONNECTOR_NAME=$(jq -r '.name' "$CONNECTOR_CONFIG")

# Check if connector already exists
if curl -f -s "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME" > /dev/null 2>&1; then
    echo "Connector '$CONNECTOR_NAME' already exists. Updating..."
    curl -X PUT "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME/config" \
        -H "Content-Type: application/json" \
        -d @"$CONNECTOR_CONFIG" | jq '.'
else
    echo "Creating new connector '$CONNECTOR_NAME'..."
    curl -X POST "$KAFKA_CONNECT_URL/connectors" \
        -H "Content-Type: application/json" \
        -d @"$CONNECTOR_CONFIG" | jq '.'
fi

# Wait a moment for connector to initialize
sleep 2

# Check connector status
echo ""
echo "Connector Status:"
curl -s "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME/status" | jq '.'

echo ""
echo "Connector setup complete!"






