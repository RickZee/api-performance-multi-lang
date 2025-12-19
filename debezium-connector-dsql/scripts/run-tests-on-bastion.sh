#!/bin/bash
# Script to run real DSQL tests on bastion host
# Assumes connector JAR and .env.dsql are already on bastion

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

echo "Running real DSQL tests on bastion..."
echo "Instance: $BASTION_INSTANCE_ID"
echo ""

# Prepare test commands
TEST_COMMANDS=(
    "cd ~/debezium-connector-dsql"
    "if [ -f .env.dsql ]; then source .env.dsql; fi"
    "export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto"
    "java -version"
    "echo 'Running connection validation...'"
    "java -cp 'lib/*:build/classes/java/test:build/classes/java/main' io.debezium.connector.dsql.testutil.DsqlConnectionTester" || echo "Connection tester not available, continuing..."
    "echo 'Running integration tests...'"
    "java -cp 'lib/*:build/classes/java/test:build/classes/java/main' org.junit.platform.console.ConsoleLauncher --class-path . --select-tag real-dsql --details verbose"
)

# Build JSON for commands
JSON_CMDS="["
for i in "${!TEST_COMMANDS[@]}"; do
    if [ $i -gt 0 ]; then
        JSON_CMDS+=","
    fi
    # Escape quotes in command
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

echo "Command ID: $COMMAND_ID"
echo "Waiting for execution..."
sleep 5

# Get output
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent, StandardErrorContent]' \
    --output text
