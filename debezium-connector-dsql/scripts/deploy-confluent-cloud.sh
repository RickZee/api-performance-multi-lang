#!/bin/bash
# Deploy DSQL connector to Confluent Cloud

set -e

echo "Deploying DSQL Connector to Confluent Cloud..."

# Check if Confluent CLI is installed
if ! command -v confluent &> /dev/null; then
    echo "Error: Confluent CLI is not installed"
    echo "Install with: brew install confluentinc/tap/cli"
    exit 1
fi

# Check if JAR exists
JAR_FILE="build/libs/debezium-connector-dsql-1.0.0.jar"
if [ ! -f "$JAR_FILE" ]; then
    echo "JAR file not found. Building..."
    ./gradlew build
fi

# Check if config file exists
CONFIG_FILE="config/dsql-connector.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

echo "Connector JAR: $JAR_FILE"
echo "Config file: $CONFIG_FILE"
echo ""
echo "Next steps:"
echo "1. Log in to Confluent Cloud: confluent login"
echo "2. Upload the connector JAR via Confluent Cloud Console"
echo "3. Create connector using the config file: $CONFIG_FILE"
echo ""
echo "Or use the REST API:"
echo "  curl -X POST https://api.confluent.cloud/connect/v1/environments/<env-id>/clusters/<cluster-id>/connectors \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -H 'Authorization: Basic <base64-encoded-api-key:secret>' \\"
echo "    -d @$CONFIG_FILE"
