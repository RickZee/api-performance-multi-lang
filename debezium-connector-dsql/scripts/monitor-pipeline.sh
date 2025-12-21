#!/bin/bash
# Monitor the entire DSQL CDC pipeline
# Checks connector status, logs, errors, and Kafka topics

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
echo "DSQL CDC Pipeline Monitoring"
echo "=========================================="
echo ""
echo "Bastion: $BASTION_INSTANCE_ID"
echo "Region: $BASTION_REGION"
echo "Timestamp: $(date)"
echo ""

# Prepare monitoring commands
MONITOR_COMMANDS=(
    "echo '=== 1. Connector Status ==='"
    "curl -s http://localhost:8083/connectors/dsql-cdc-source/status | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8083/connectors/dsql-cdc-source/status"
    "echo ''"
    "echo '=== 2. Connector Configuration ==='"
    "curl -s http://localhost:8083/connectors/dsql-cdc-source/config | python3 -m json.tool 2>/dev/null | head -20 || curl -s http://localhost:8083/connectors/dsql-cdc-source/config | head -20"
    "echo ''"
    "echo '=== 3. Connector Tasks ==='"
    "curl -s http://localhost:8083/connectors/dsql-cdc-source/tasks | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8083/connectors/dsql-cdc-source/tasks"
    "echo ''"
    "echo '=== 4. All Connectors ==='"
    "curl -s http://localhost:8083/connectors | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8083/connectors"
    "echo ''"
    "echo '=== 5. Container Status ==='"
    "docker ps | grep kafka-connect || echo 'No Kafka Connect container found'"
    "echo ''"
    "echo '=== 6. Recent Errors (last 20) ==='"
    "docker logs kafka-connect-dsql 2>&1 | grep -iE 'error|exception|failed|fatal' | tail -20 || echo 'No errors found'"
    "echo ''"
    "echo '=== 7. Recent Logs (last 30 lines) ==='"
    "docker logs --tail 30 kafka-connect-dsql 2>&1 | tail -30"
    "echo ''"
    "echo '=== 8. Connector Plugins ==='"
    "curl -s http://localhost:8083/connector-plugins | python3 -m json.tool 2>/dev/null | grep -A 5 'DsqlConnector' || curl -s http://localhost:8083/connector-plugins | grep -A 5 'DsqlConnector' || echo 'DSQL Connector plugin not found'"
)

# Build JSON for commands
JSON_CMDS="["
for i in "${!MONITOR_COMMANDS[@]}"; do
    if [ $i -gt 0 ]; then
        JSON_CMDS+=","
    fi
    CMD="${MONITOR_COMMANDS[$i]//\"/\\\"}"
    JSON_CMDS+="\"$CMD\""
done
JSON_CMDS+="]"

echo "Collecting pipeline status..."
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
echo "=== Pipeline Status ==="
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent]' \
    --output text

echo ""
echo "=========================================="
echo "Monitoring Complete"
echo "=========================================="
echo ""
echo "For continuous monitoring, run:"
echo "  watch -n 5 './scripts/monitor-pipeline.sh'"
echo ""
