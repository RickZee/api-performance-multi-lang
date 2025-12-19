#!/bin/bash
# Deploy Kafka Connect container on bastion host with DSQL connector
# This script runs from your local machine and deploys via SSM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# Get bastion info
TERRAFORM_DIR="../terraform"
if [ ! -d "$TERRAFORM_DIR" ]; then
    TERRAFORM_DIR="../../terraform"
fi

cd "$TERRAFORM_DIR"

BASTION_INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
BASTION_REGION=$(terraform output -raw bastion_host_ssm_command 2>/dev/null | sed -n 's/.*--region \([^ ]*\).*/\1/p' || echo "us-east-1")

if [ -z "$BASTION_INSTANCE_ID" ]; then
    echo "Error: Could not get bastion instance ID"
    exit 1
fi

echo "=========================================="
echo "Deploying Kafka Connect on Bastion"
echo "=========================================="
echo ""
echo "Bastion: $BASTION_INSTANCE_ID"
echo "Region: $BASTION_REGION"
echo ""

# Check for Confluent Cloud credentials
CC_BOOTSTRAP_SERVERS="${CC_BOOTSTRAP_SERVERS:-}"
CC_KAFKA_API_KEY="${CC_KAFKA_API_KEY:-}"
CC_KAFKA_API_SECRET="${CC_KAFKA_API_SECRET:-}"

# Try to read from connect.env if it exists
CONNECT_ENV_FILE="$TERRAFORM_DIR/debezium-connector-dsql/connect.env"
if [ -f "$CONNECT_ENV_FILE" ]; then
    echo "Found connect.env file, reading Confluent config..."
    source "$CONNECT_ENV_FILE"
    CC_BOOTSTRAP_SERVERS="${CC_BOOTSTRAP_SERVERS:-}"
    CC_KAFKA_API_KEY="${CC_KAFKA_API_KEY:-}"
    CC_KAFKA_API_SECRET="${CC_KAFKA_API_SECRET:-}"
fi

# Check for required environment variables
KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-$CC_BOOTSTRAP_SERVERS}"

if [ -z "$KAFKA_BOOTSTRAP_SERVERS" ]; then
    echo "⚠ Warning: KAFKA_BOOTSTRAP_SERVERS or CC_BOOTSTRAP_SERVERS not set"
    echo "  Set it before running this script:"
    echo "  export KAFKA_BOOTSTRAP_SERVERS='your-kafka-brokers:9092'"
    echo "  Or: export CC_BOOTSTRAP_SERVERS='pkc-xxxxx.us-east-1.aws.confluent.cloud:9092'"
    echo ""
    echo "Or provide it as an argument:"
    echo "  $0 <kafka-bootstrap-servers>"
    echo ""
    read -p "Enter Kafka bootstrap servers (or press Enter to skip): " KAFKA_BOOTSTRAP_SERVERS
    if [ -z "$KAFKA_BOOTSTRAP_SERVERS" ]; then
        echo "Skipping Kafka Connect deployment. You can deploy manually later."
        exit 0
    fi
fi

# Use first argument if provided
if [ -n "$1" ]; then
    KAFKA_BOOTSTRAP_SERVERS="$1"
fi

# Check if this is Confluent Cloud (has .confluent.cloud in hostname)
IS_CONFLUENT_CLOUD=false
if [[ "$KAFKA_BOOTSTRAP_SERVERS" == *".confluent.cloud"* ]]; then
    IS_CONFLUENT_CLOUD=true
    if [ -z "$CC_KAFKA_API_KEY" ] || [ -z "$CC_KAFKA_API_SECRET" ]; then
        echo "⚠ Warning: Confluent Cloud detected but API credentials not found"
        echo "  Please set:"
        echo "    export CC_KAFKA_API_KEY='your-api-key'"
        echo "    export CC_KAFKA_API_SECRET='your-api-secret'"
        echo ""
        if [ -z "$CC_KAFKA_API_KEY" ]; then
            read -p "Enter Confluent Cloud API Key: " CC_KAFKA_API_KEY
        fi
        if [ -z "$CC_KAFKA_API_SECRET" ]; then
            read -s -p "Enter Confluent Cloud API Secret: " CC_KAFKA_API_SECRET
            echo ""
        fi
    fi
fi

echo "Kafka Bootstrap Servers: $KAFKA_BOOTSTRAP_SERVERS"
echo ""

# Prepare deployment commands
DEPLOY_COMMANDS=(
    "echo '=== Stopping existing Kafka Connect container (if any) ==='"
    "docker stop kafka-connect-dsql 2>/dev/null || true"
    "docker rm kafka-connect-dsql 2>/dev/null || true"
    "echo ''"
    "echo '=== Pulling Debezium Connect image ==='"
    "docker pull quay.io/quay.io/debezium/connect:2.6"
    "echo ''"
    "echo '=== Creating connector directory ==='"
    "mkdir -p ~/debezium-connector-dsql/connector"
    "cp ~/debezium-connector-dsql/lib/debezium-connector-dsql.jar ~/debezium-connector-dsql/connector/ 2>/dev/null || echo 'JAR already in place'"
    "echo ''"
    "echo '=== Starting Kafka Connect container ==='"
    "if [ '$IS_CONFLUENT_CLOUD' = 'true' ]; then"
    "  echo 'Configuring for Confluent Cloud with SASL/SSL...'"
    "  docker run -d --name kafka-connect-dsql --restart unless-stopped -p 8083:8083 -v ~/debezium-connector-dsql/connector:/kafka/connect/debezium-connector-dsql -e CONNECT_BOOTSTRAP_SERVERS='$KAFKA_BOOTSTRAP_SERVERS' -e CONNECT_REST_PORT=8083 -e CONNECT_REST_ADVERTISED_HOST_NAME=localhost -e CONNECT_GROUP_ID=dsql-connect-cluster -e CONNECT_CONFIG_STORAGE_TOPIC=dsql-connect-config -e CONNECT_OFFSET_STORAGE_TOPIC=dsql-connect-offsets -e CONNECT_STATUS_STORAGE_TOPIC=dsql-connect-status -e CONNECT_KEY_CONVERTER=org.apache.kafka.connect.json.JsonConverter -e CONNECT_VALUE_CONVERTER=org.apache.kafka.connect.json.JsonConverter -e CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE=false -e CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE=false -e CONNECT_PLUGIN_PATH=/kafka/connect -e CONNECT_SASL_MECHANISM=PLAIN -e CONNECT_SECURITY_PROTOCOL=SASL_SSL -e CONNECT_SASL_JAAS_CONFIG=\"org.apache.kafka.common.security.plain.PlainLoginModule required username='$CC_KAFKA_API_KEY' password='$CC_KAFKA_API_SECRET';\" -e CONNECT_PRODUCER_SASL_MECHANISM=PLAIN -e CONNECT_PRODUCER_SECURITY_PROTOCOL=SASL_SSL -e CONNECT_PRODUCER_SASL_JAAS_CONFIG=\"org.apache.kafka.common.security.plain.PlainLoginModule required username='$CC_KAFKA_API_KEY' password='$CC_KAFKA_API_SECRET';\" -e CONNECT_CONSUMER_SASL_MECHANISM=PLAIN -e CONNECT_CONSUMER_SECURITY_PROTOCOL=SASL_SSL -e CONNECT_CONSUMER_SASL_JAAS_CONFIG=\"org.apache.kafka.common.security.plain.PlainLoginModule required username='$CC_KAFKA_API_KEY' password='$CC_KAFKA_API_SECRET';\" quay.io/debezium/connect:2.6"
    "else"
    "  echo 'Configuring for standard Kafka...'"
    "  docker run -d --name kafka-connect-dsql --restart unless-stopped -p 8083:8083 -v ~/debezium-connector-dsql/connector:/kafka/connect/debezium-connector-dsql -e CONNECT_BOOTSTRAP_SERVERS='$KAFKA_BOOTSTRAP_SERVERS' -e CONNECT_REST_PORT=8083 -e CONNECT_REST_ADVERTISED_HOST_NAME=localhost -e CONNECT_GROUP_ID=dsql-connect-cluster -e CONNECT_CONFIG_STORAGE_TOPIC=dsql-connect-config -e CONNECT_OFFSET_STORAGE_TOPIC=dsql-connect-offsets -e CONNECT_STATUS_STORAGE_TOPIC=dsql-connect-status -e CONNECT_KEY_CONVERTER=org.apache.kafka.connect.json.JsonConverter -e CONNECT_VALUE_CONVERTER=org.apache.kafka.connect.json.JsonConverter -e CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE=false -e CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE=false -e CONNECT_PLUGIN_PATH=/kafka/connect quay.io/debezium/connect:2.6"
    "fi"
    "echo ''"
    "echo '=== Waiting for Kafka Connect to start ==='"
    "sleep 10"
    "echo ''"
    "echo '=== Checking container status ==='"
    "docker ps | grep kafka-connect-dsql || echo 'Container not running'"
    "echo ''"
    "echo '=== Checking Kafka Connect health ==='"
    "curl -s http://localhost:8083/connector-plugins | head -20 || echo 'Kafka Connect not ready yet'"
    "echo ''"
    "echo '=== Deployment complete! ==='"
    "echo ''"
    "echo 'Next steps:'"
    "echo '1. Check logs: docker logs -f kafka-connect-dsql'"
    "echo '2. List connector plugins: curl http://localhost:8083/connector-plugins'"
    "echo '3. Create connector: curl -X POST http://localhost:8083/connectors -H \"Content-Type: application/json\" -d @config/dsql-connector.json'"
)

# Build JSON for commands
JSON_CMDS="["
for i in "${!DEPLOY_COMMANDS[@]}"; do
    if [ $i -gt 0 ]; then
        JSON_CMDS+=","
    fi
    CMD="${DEPLOY_COMMANDS[$i]//\"/\\\"}"
    JSON_CMDS+="\"$CMD\""
done
JSON_CMDS+="]"

echo "Sending deployment commands to bastion..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$JSON_CMDS}" \
    --region "$BASTION_REGION" \
    --output text \
    --query 'Command.CommandId' 2>&1)

echo "Command ID: $COMMAND_ID"
echo "Waiting for deployment..."
sleep 15

# Get output
echo ""
echo "=== Deployment Output ==="
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent, StandardErrorContent]' \
    --output text

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "To check status, connect to bastion:"
echo "  aws ssm start-session --target $BASTION_INSTANCE_ID --region $BASTION_REGION"
echo ""
echo "Then run:"
echo "  docker ps | grep kafka-connect"
echo "  docker logs kafka-connect-dsql"
echo "  curl http://localhost:8083/connector-plugins"
echo ""
