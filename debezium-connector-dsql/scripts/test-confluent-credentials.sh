#!/bin/bash
# Test Confluent Cloud API credentials
# Verifies credentials are valid and have required permissions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# Get Confluent config
CC_BOOTSTRAP_SERVERS="${CC_BOOTSTRAP_SERVERS:-}"
CC_KAFKA_API_KEY="${CC_KAFKA_API_KEY:-}"
CC_KAFKA_API_SECRET="${CC_KAFKA_API_SECRET:-}"

# Try to read from connect.env
TERRAFORM_DIR="../terraform"
if [ ! -d "$TERRAFORM_DIR" ]; then
    TERRAFORM_DIR="../../terraform"
fi

CONNECT_ENV_FILE="$TERRAFORM_DIR/debezium-connector-dsql/connect.env"
if [ -f "$CONNECT_ENV_FILE" ]; then
    source "$CONNECT_ENV_FILE" 2>/dev/null || true
fi

# Try to read from cdc-streaming/.env
CDC_ENV_FILE="../cdc-streaming/.env"
if [ -f "$CDC_ENV_FILE" ]; then
    source "$CDC_ENV_FILE" 2>/dev/null || true
    CC_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-$CC_BOOTSTRAP_SERVERS}"
    CC_KAFKA_API_KEY="${KAFKA_API_KEY:-$CC_KAFKA_API_KEY}"
    CC_KAFKA_API_SECRET="${KAFKA_API_SECRET:-$CC_KAFKA_API_SECRET}"
fi

if [ -z "$CC_BOOTSTRAP_SERVERS" ] || [ -z "$CC_KAFKA_API_KEY" ] || [ -z "$CC_KAFKA_API_SECRET" ]; then
    echo "Error: Missing Confluent Cloud credentials"
    echo "  CC_BOOTSTRAP_SERVERS: ${CC_BOOTSTRAP_SERVERS:-not set}"
    echo "  CC_KAFKA_API_KEY: ${CC_KAFKA_API_KEY:-not set}"
    echo "  CC_KAFKA_API_SECRET: ${CC_KAFKA_API_SECRET:-not set}"
    echo ""
    echo "Set these variables or ensure connect.env or cdc-streaming/.env is available"
    exit 1
fi

echo "=========================================="
echo "Confluent Cloud Credentials Test"
echo "=========================================="
echo ""
echo "Bootstrap Servers: $CC_BOOTSTRAP_SERVERS"
echo "API Key: ${CC_KAFKA_API_KEY:0:10}..."
echo ""

# Extract hostname
KAFKA_HOST=$(echo "$CC_BOOTSTRAP_SERVERS" | cut -d: -f1)

# Get bastion info
cd "$TERRAFORM_DIR"
BASTION_INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
BASTION_REGION=$(terraform output -raw bastion_host_ssm_command 2>/dev/null | sed -n 's/.*--region \([^ ]*\).*/\1/p' || echo "us-east-1")

if [ -z "$BASTION_INSTANCE_ID" ]; then
    echo "Error: Could not get bastion instance ID"
    exit 1
fi

# Prepare test commands
TEST_COMMANDS=(
    "echo '=== 1. Test SASL Authentication ==='"
    "echo 'Creating test SASL properties file...'"
    "cat > /tmp/test-sasl.properties <<'EOF'"
    "security.protocol=SASL_SSL"
    "sasl.mechanism=PLAIN"
    "sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$CC_KAFKA_API_KEY\" password=\"$CC_KAFKA_API_SECRET\";"
    "EOF"
    "echo '✓ Properties file created'"
    "echo ''"
    "echo '=== 2. Test with kafka-console-producer (if available) ==='"
    "if command -v kafka-console-producer >/dev/null 2>&1; then"
    "  echo 'Testing authentication with kafka-console-producer...'"
    "  echo 'test-message' | timeout 10 kafka-console-producer --bootstrap-server \"$CC_BOOTSTRAP_SERVERS\" --producer.config /tmp/test-sasl.properties --topic test-topic-$$ 2>&1 | head -5 || echo 'Producer test failed (this is expected if topic does not exist)'"
    "else"
    "  echo 'kafka-console-producer not available'"
    "fi"
    "echo ''"
    "echo '=== 3. Test with kafka-broker-api-versions (if available) ==='"
    "if command -v kafka-broker-api-versions >/dev/null 2>&1; then"
    "  echo 'Testing API version negotiation...'"
    "  timeout 10 kafka-broker-api-versions --bootstrap-server \"$CC_BOOTSTRAP_SERVERS\" --command-config /tmp/test-sasl.properties 2>&1 | head -10 || echo 'API version test failed'"
    "else"
    "  echo 'kafka-broker-api-versions not available'"
    "fi"
    "echo ''"
    "echo '=== 4. Test from Kafka Connect Container ==='"
    "if docker ps | grep -q kafka-connect; then"
    "  echo 'Testing credentials from container...'"
    "  docker exec dsql-kafka-connect env | grep -E 'SASL_JAAS_CONFIG' | head -1 | sed 's/.*username=\([^;]*\).*/API Key: \1.../' || echo 'SASL config not found in container'"
    "  echo 'Checking container logs for authentication errors...'"
    "  docker logs dsql-kafka-connect 2>&1 | grep -iE 'authentication|sasl|unauthorized|forbidden' | tail -5 || echo 'No authentication errors in recent logs'"
    "else"
    "  echo 'Kafka Connect container not running'"
    "fi"
    "echo ''"
    "echo '=== 5. Manual Credential Validation ==='"
    "echo 'API Key format: ${CC_KAFKA_API_KEY:0:10}...'"
    "echo 'API Secret format: ${CC_KAFKA_API_SECRET:0:10}...'"
    "if [ \${#CC_KAFKA_API_KEY} -lt 10 ]; then"
    "  echo '✗ WARNING: API Key appears too short'"
    "else"
    "  echo '✓ API Key length appears valid'"
    "fi"
    "if [ \${#CC_KAFKA_API_SECRET} -lt 10 ]; then"
    "  echo '✗ WARNING: API Secret appears too short'"
    "else"
    "  echo '✓ API Secret length appears valid'"
    "fi"
    "echo ''"
    "echo '=== 6. Test HTTP API (if Confluent CLI available) ==='"
    "if command -v confluent >/dev/null 2>&1; then"
    "  echo 'Testing with Confluent CLI...'"
    "  confluent kafka cluster list --api-key \"$CC_KAFKA_API_KEY\" --api-secret \"$CC_KAFKA_API_SECRET\" 2>&1 | head -10 || echo 'Confluent CLI test failed'"
    "else"
    "  echo 'Confluent CLI not available'"
    "fi"
)

# Build JSON for commands
JSON_CMDS="["
for i in "${!TEST_COMMANDS[@]}"; do
    if [ $i -gt 0 ]; then
        JSON_CMDS+=","
    fi
    CMD="${TEST_COMMANDS[$i]//\"/\\\"}"
    JSON_CMDS+="\"$CMD\""
done
JSON_CMDS+="]"

echo "Sending test commands to bastion..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$JSON_CMDS}" \
    --region "$BASTION_REGION" \
    --output text \
    --query 'Command.CommandId' 2>&1)

sleep 8

# Get output
echo ""
echo "=== Credentials Test Results ==="
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent, StandardErrorContent]' \
    --output text

echo ""
echo "=========================================="
echo "Credentials Test Complete"
echo "=========================================="
echo ""
echo "Note: If credentials are invalid, you may need to:"
echo "  1. Regenerate API key/secret in Confluent Cloud"
echo "  2. Update connect.env or cdc-streaming/.env"
echo "  3. Restart Kafka Connect container"
echo ""
