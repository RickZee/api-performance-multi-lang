#!/bin/bash
# Script to query DSQL database via bastion host (non-interactive)
# Usage: ./scripts/query-dsql.sh [query]
# If no query provided, runs default table count query

set -e

# Get Terraform outputs
cd "$(dirname "$0")/../terraform" || exit 1

# Get bastion host instance ID
BASTION_INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
if [ -z "$BASTION_INSTANCE_ID" ]; then
    echo "Error: Bastion host not found. Make sure Terraform has been applied and bastion host is enabled."
    exit 1
fi

# Get DSQL host
DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
if [ -z "$DSQL_HOST" ]; then
    echo "Error: DSQL host not found. Make sure Terraform has been applied and DSQL cluster is enabled."
    exit 1
fi

# Get AWS region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

# Default query if none provided
# Note: search_path will be set automatically, so we can use unqualified table names
DEFAULT_QUERY="SELECT 'business_events' as table_name, COUNT(*) as count FROM business_events
UNION ALL SELECT 'event_headers', COUNT(*) FROM event_headers
UNION ALL SELECT 'car_entities', COUNT(*) FROM car_entities
UNION ALL SELECT 'loan_entities', COUNT(*) FROM loan_entities
UNION ALL SELECT 'loan_payment_entities', COUNT(*) FROM loan_payment_entities
UNION ALL SELECT 'service_record_entities', COUNT(*) FROM service_record_entities
ORDER BY table_name;"

QUERY="${1:-$DEFAULT_QUERY}"

echo "=== Querying DSQL Database ==="
echo "Bastion Host: $BASTION_INSTANCE_ID"
echo "DSQL Host: $DSQL_HOST"
echo "Region: $AWS_REGION"
echo ""

# Escape the query for embedding in psql command
# Replace single quotes with '\'' (bash quote escaping) and preserve newlines as spaces
ESCAPED_QUERY=$(echo "$QUERY" | sed "s/'/'\"'\"'/g" | tr '\n' ' ')

# Build commands array using jq for proper JSON escaping
# Set search_path to car_entities_schema for DSQL queries
COMMANDS_JSON=$(jq -n \
    --arg dsql_host "$DSQL_HOST" \
    --arg aws_region "$AWS_REGION" \
    --arg query "$ESCAPED_QUERY" \
    '[
        "export DSQL_HOST=" + $dsql_host,
        "export AWS_REGION=" + $aws_region,
        "TOKEN=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)",
        "export PGPASSWORD=$TOKEN",
        "psql -h $DSQL_HOST -U admin -d postgres -p 5432 -c \u0027SET search_path TO car_entities_schema; " + $query + "\u0027"
    ]')

# Send command to bastion host using proper JSON format
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$COMMANDS_JSON}" \
    --output json 2>&1 | jq -r '.Command.CommandId' 2>&1)

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "null" ]; then
    echo "Error: Failed to send command to bastion host"
    exit 1
fi

echo "Command ID: $COMMAND_ID"
echo "Waiting for results..."
echo ""

# Wait for command to complete
sleep 15

# Get command status
STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query "Status" \
    --output text 2>&1)

if [ "$STATUS" = "Success" ]; then
    echo "=== Query Results ==="
    aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query "StandardOutputContent" \
        --output text 2>&1
else
    echo "Error: Command status: $STATUS"
    aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" 2>&1 | jq -r '.StandardErrorContent // .Status' 2>&1
    exit 1
fi
