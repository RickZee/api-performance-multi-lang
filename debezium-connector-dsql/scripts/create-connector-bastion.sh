#!/bin/bash
# Create DSQL connector in Kafka Connect running on bastion
# This script runs from your local machine and creates the connector via SSM

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
echo "Creating DSQL Connector on Bastion"
echo "=========================================="
echo ""

# Check if config file exists
CONFIG_FILE="$PROJECT_DIR/config/dsql-connector.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Upload config file to bastion
echo "Uploading connector config to bastion..."
aws s3 cp "$CONFIG_FILE" \
    "s3://producer-api-lambda-deployments-978300727880/dsql-connector.json" \
    --region "$BASTION_REGION" > /dev/null 2>&1

# Prepare commands to download config and create connector
CREATE_COMMANDS=(
    "echo '=== Downloading connector config ==='"
    "mkdir -p ~/debezium-connector-dsql/config"
    "aws s3 cp s3://producer-api-lambda-deployments-978300727880/dsql-connector.json ~/debezium-connector-dsql/config/ 2>/dev/null || echo 'Config already exists'"
    "echo ''"
    "echo '=== Checking Kafka Connect status ==='"
    "curl -s http://localhost:8083/connector-plugins | grep -i dsql || echo 'Kafka Connect may not be running or connector not loaded'"
    "echo ''"
    "echo '=== Creating connector (you may need to edit config first) ==='"
    "echo 'Note: Edit ~/debezium-connector-dsql/config/dsql-connector.json with your DSQL details'"
    "echo 'Then run: curl -X POST http://localhost:8083/connectors -H \"Content-Type: application/json\" -d @~/debezium-connector-dsql/config/dsql-connector.json'"
    "echo ''"
    "echo '=== Current connector config ==='"
    "cat ~/debezium-connector-dsql/config/dsql-connector.json 2>/dev/null || echo 'Config file not found'"
)

# Build JSON for commands
JSON_CMDS="["
for i in "${!CREATE_COMMANDS[@]}"; do
    if [ $i -gt 0 ]; then
        JSON_CMDS+=","
    fi
    CMD="${CREATE_COMMANDS[$i]//\"/\\\"}"
    JSON_CMDS+="\"$CMD\""
done
JSON_CMDS+="]"

echo "Sending commands to bastion..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$JSON_CMDS}" \
    --region "$BASTION_REGION" \
    --output text \
    --query 'Command.CommandId' 2>&1)

sleep 3

# Get output
echo ""
echo "=== Output ==="
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent]' \
    --output text

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Connect to bastion:"
echo "   aws ssm start-session --target $BASTION_INSTANCE_ID --region $BASTION_REGION"
echo ""
echo "2. Edit connector config with your DSQL details:"
echo "   cd ~/debezium-connector-dsql"
echo "   vi config/dsql-connector.json"
echo ""
echo "3. Create the connector:"
echo "   curl -X POST http://localhost:8083/connectors \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d @config/dsql-connector.json"
echo ""
echo "4. Check connector status:"
echo "   curl http://localhost:8083/connectors/dsql-cdc-source/status"
echo ""
