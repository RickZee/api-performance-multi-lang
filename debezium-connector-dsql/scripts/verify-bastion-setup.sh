#!/bin/bash
# Verify bastion setup is complete and ready for deployment
# This script runs from your local machine and checks bastion via SSM

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
echo "Verifying Bastion Setup"
echo "=========================================="
echo ""
echo "Bastion: $BASTION_INSTANCE_ID"
echo "Region: $BASTION_REGION"
echo ""

# Prepare verification commands
VERIFY_COMMANDS=(
    "echo '=== Checking Docker ==='"
    "docker --version 2>/dev/null && echo '✓ Docker installed' || echo '✗ Docker not found'"
    "docker ps > /dev/null 2>&1 && echo '✓ Docker daemon running' || echo '✗ Docker daemon not running'"
    "echo ''"
    "echo '=== Checking Java ==='"
    "java -version 2>&1 | head -1 && echo '✓ Java installed' || echo '✗ Java not found'"
    "echo ''"
    "echo '=== Checking Directory Structure ==='"
    "[ -d ~/debezium-connector-dsql ] && echo '✓ Project directory exists' || echo '✗ Project directory missing'"
    "[ -d ~/debezium-connector-dsql/lib ] && echo '✓ lib/ directory exists' || echo '✗ lib/ directory missing'"
    "[ -d ~/debezium-connector-dsql/config ] && echo '✓ config/ directory exists' || echo '✗ config/ directory missing'"
    "echo ''"
    "echo '=== Checking Connector JAR ==='"
    "[ -f ~/debezium-connector-dsql/lib/debezium-connector-dsql.jar ] && echo '✓ Connector JAR found' || echo '✗ Connector JAR missing'"
    "[ -f ~/debezium-connector-dsql/lib/debezium-connector-dsql.jar ] && ls -lh ~/debezium-connector-dsql/lib/debezium-connector-dsql.jar | awk '{print \"  Size: \" \$5}' || echo ''"
    "echo ''"
    "echo '=== Checking Configuration Files ==='"
    "[ -f ~/debezium-connector-dsql/.env.dsql ] && echo '✓ .env.dsql found' || echo '⚠ .env.dsql not found (needs to be created)'"
    "[ -f ~/debezium-connector-dsql/config/dsql-connector.json ] && echo '✓ connector config found' || echo '⚠ connector config not found (needs to be created)'"
    "echo ''"
    "echo '=== Checking Kafka Connect Container ==='"
    "docker ps | grep kafka-connect-dsql > /dev/null 2>&1 && echo '✓ Kafka Connect container running' || echo '⚠ Kafka Connect container not running'"
    "docker ps -a | grep kafka-connect-dsql > /dev/null 2>&1 && echo '  (Container exists but may be stopped)' || echo '  (Container does not exist)'"
    "echo ''"
    "echo '=== Checking AWS Credentials ==='"
    "aws sts get-caller-identity > /dev/null 2>&1 && echo '✓ AWS credentials configured' || echo '⚠ AWS credentials not configured'"
    "echo ''"
    "echo '=== Summary ==='"
    "echo 'Setup verification complete!'"
)

# Build JSON for commands
JSON_CMDS="["
for i in "${!VERIFY_COMMANDS[@]}"; do
    if [ $i -gt 0 ]; then
        JSON_CMDS+=","
    fi
    CMD="${VERIFY_COMMANDS[$i]//\"/\\\"}"
    JSON_CMDS+="\"$CMD\""
done
JSON_CMDS+="]"

echo "Sending verification commands to bastion..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$JSON_CMDS}" \
    --region "$BASTION_REGION" \
    --output text \
    --query 'Command.CommandId' 2>&1)

sleep 5

# Get output
echo ""
echo "=== Verification Results ==="
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent]' \
    --output text

echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
echo ""
echo "If any items show ✗ or ⚠, please address them before deployment."
echo ""
