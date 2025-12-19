#!/bin/bash
# Test Kafka/Confluent Cloud connectivity and SASL authentication
# Verifies network connectivity and authentication configuration

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

# Get Confluent config
CC_BOOTSTRAP_SERVERS="${CC_BOOTSTRAP_SERVERS:-}"
CC_KAFKA_API_KEY="${CC_KAFKA_API_KEY:-}"
CC_KAFKA_API_SECRET="${CC_KAFKA_API_SECRET:-}"

# Try to read from connect.env
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

if [ -z "$CC_BOOTSTRAP_SERVERS" ]; then
    echo "Error: CC_BOOTSTRAP_SERVERS not set"
    echo "Set it or ensure connect.env or cdc-streaming/.env is available"
    exit 1
fi

# Extract hostname and port
KAFKA_HOST=$(echo "$CC_BOOTSTRAP_SERVERS" | cut -d: -f1)
KAFKA_PORT=$(echo "$CC_BOOTSTRAP_SERVERS" | cut -d: -f2)

echo "=========================================="
echo "Kafka Connectivity Test"
echo "=========================================="
echo ""
echo "Bootstrap Servers: $CC_BOOTSTRAP_SERVERS"
echo "Host: $KAFKA_HOST"
echo "Port: $KAFKA_PORT"
echo "API Key: ${CC_KAFKA_API_KEY:0:10}..."
echo ""

# Prepare test commands
TEST_COMMANDS=(
    "echo '=== 1. DNS Resolution ==='"
    "nslookup $KAFKA_HOST 2>&1 | head -10 || echo 'DNS resolution failed'"
    "echo ''"
    "echo '=== 2. TCP Port Connectivity ==='"
    "timeout 10 bash -c '</dev/tcp/$KAFKA_HOST/$KAFKA_PORT' 2>&1 && echo '✓ Port $KAFKA_PORT is reachable' || echo '✗ Port $KAFKA_PORT is NOT reachable'"
    "echo ''"
    "echo '=== 3. Test with telnet/nc ==='"
    "if command -v nc >/dev/null 2>&1; then"
    "  timeout 5 nc -zv $KAFKA_HOST $KAFKA_PORT 2>&1 || echo 'Connection test failed'"
    "elif command -v telnet >/dev/null 2>&1; then"
    "  timeout 5 bash -c 'echo | telnet $KAFKA_HOST $KAFKA_PORT' 2>&1 | grep -i 'connected\|refused\|timeout' || echo 'Connection test inconclusive'"
    "else"
    "  echo 'nc or telnet not available, using basic TCP test'"
    "fi"
    "echo ''"
    "echo '=== 4. Security Group Check ==='"
    "echo 'Checking if outbound traffic to port $KAFKA_PORT is allowed...'"
    "echo 'Note: This requires checking security group rules'"
    "echo ''"
    "echo '=== 5. Test from Docker Container ==='"
    "if docker ps | grep -q kafka-connect; then"
    "  echo 'Testing connectivity from Kafka Connect container...'"
    "  docker exec dsql-kafka-connect timeout 5 bash -c '</dev/tcp/$KAFKA_HOST/$KAFKA_PORT' 2>&1 && echo '✓ Container can reach Kafka' || echo '✗ Container cannot reach Kafka'"
    "else"
    "  echo 'Kafka Connect container not running'"
    "fi"
    "echo ''"
    "echo '=== 6. Kafka Connect Configuration Check ==='"
    "if docker ps | grep -q kafka-connect; then"
    "  echo 'Checking SASL configuration in container...'"
    "  docker exec dsql-kafka-connect env | grep -E 'SASL|SECURITY|BOOTSTRAP' | sed 's/=.*/=***HIDDEN***/' || echo 'No SASL config found'"
    "else"
    "  echo 'Kafka Connect container not running'"
    "fi"
    "echo ''"
    "echo '=== 7. Network Route Check ==='"
    "echo 'Checking route to Kafka broker...'"
    "traceroute -m 10 $KAFKA_HOST 2>&1 | head -15 || echo 'traceroute not available or failed'"
    "echo ''"
    "echo '=== 8. Firewall/iptables Check ==='"
    "if command -v iptables >/dev/null 2>&1; then"
    "  echo 'Checking iptables rules (if accessible)...'"
    "  sudo iptables -L OUTPUT -n 2>&1 | head -10 || echo 'Cannot check iptables (requires sudo)'"
    "else"
    "  echo 'iptables not available'"
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
echo "=== Connectivity Test Results ==="
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent, StandardErrorContent]' \
    --output text

echo ""
echo "=========================================="
echo "Connectivity Test Complete"
echo "=========================================="
echo ""
