#!/bin/bash
# Script to query DSQL database via RDS Data API or bastion host (non-interactive)
# Usage: ./scripts/query-dsql.sh [query]
# If no query provided, runs default table count query
# 
# This script will attempt to use RDS Data API if enabled, otherwise falls back to bastion host method.

set -e

# Get Terraform outputs (cache to avoid multiple calls)
TERRAFORM_DIR="$(dirname "$0")/../terraform"
cd "$TERRAFORM_DIR" || exit 1

# Get all outputs in one go to minimize terraform calls
TERRAFORM_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")

# Extract values from cached outputs
AWS_REGION=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.aws_region.value // "us-east-1"' 2>/dev/null || echo "us-east-1")
DATA_API_ENABLED=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.aurora_dsql_data_api_enabled.value // "false"' 2>/dev/null || echo "false")
DATA_API_RESOURCE_ARN=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.aurora_dsql_data_api_resource_arn.value // ""' 2>/dev/null || echo "")
DSQL_HOST=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.aurora_dsql_host.value // ""' 2>/dev/null || echo "")
BASTION_INSTANCE_ID=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.bastion_host_instance_id.value // ""' 2>/dev/null || echo "")

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
echo "Region: $AWS_REGION"
echo "Data API Enabled: $DATA_API_ENABLED"
if [ "$DATA_API_ENABLED" = "true" ] && [ -n "$DATA_API_RESOURCE_ARN" ]; then
    echo "Using: RDS Data API"
    echo "Resource ARN: $DATA_API_RESOURCE_ARN"
else
    echo "Using: Bastion Host (fallback)"
    echo "Bastion Host: $BASTION_INSTANCE_ID"
    echo "DSQL Host: $DSQL_HOST"
fi
echo ""

# Try RDS Data API first if enabled
if [ "$DATA_API_ENABLED" = "true" ] && [ -n "$DATA_API_RESOURCE_ARN" ]; then
    # Prepare query for Data API (need to set search_path and execute query)
    # Data API requires SQL statements to be properly formatted
    # Combine SET search_path with the actual query
    FULL_QUERY="SET search_path TO car_entities_schema; $QUERY"
    
    echo "Attempting to query via RDS Data API..."
    
    # Execute query via RDS Data API
    RESULT=$(aws rds-data execute-statement \
        --resource-arn "$DATA_API_RESOURCE_ARN" \
        --database postgres \
        --sql "$FULL_QUERY" \
        --region "$AWS_REGION" \
        2>&1)
    
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "=== Query Results (via RDS Data API) ==="
        # Parse and format the result
        echo "$RESULT" | jq -r '.records[]? | @tsv' 2>/dev/null || echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"
        exit 0
    else
        echo "Warning: RDS Data API query failed (exit code: $EXIT_CODE)"
        echo "Error: $RESULT"
        echo ""
        echo "Falling back to bastion host method..."
        echo ""
        
        # Check if error indicates DSQL doesn't support Data API
        if echo "$RESULT" | grep -qi "not.*support\|invalid.*resource\|not.*found"; then
            echo "Note: DSQL may not support RDS Data API. Using bastion host method instead."
            echo ""
        fi
    fi
fi

# Fallback to bastion host method
if [ -z "$BASTION_INSTANCE_ID" ]; then
    echo "Error: Bastion host not found. Make sure Terraform has been applied and bastion host is enabled."
    exit 1
fi

if [ -z "$DSQL_HOST" ]; then
    echo "Error: DSQL host not found. Make sure Terraform has been applied and DSQL cluster is enabled."
    exit 1
fi

# Build commands array using jq for proper JSON escaping
# Set search_path to car_entities_schema for DSQL queries
# Variables $AWS_REGION and $DSQL_HOST will be evaluated on the bastion after export
COMMANDS_JSON=$(jq -n \
    --arg dsql_host "$DSQL_HOST" \
    --arg aws_region "$AWS_REGION" \
    --arg query "$QUERY" \
    '[
        "export DSQL_HOST=" + $dsql_host,
        "export AWS_REGION=" + $aws_region,
        "# Cache psql command check (only check once per session)",
        "if [ -z \"$PSQL_CMD\" ]; then",
        "  if ! command -v psql >/dev/null 2>&1 && ! command -v psql16 >/dev/null 2>&1; then",
        "    echo \"Installing PostgreSQL client...\" >&2",
        "    dnf install -y postgresql16 >/dev/null 2>&1 || yum install -y postgresql16 >/dev/null 2>&1 || true",
        "  fi",
        "  export PSQL_CMD=$(command -v psql 2>/dev/null || command -v psql16 2>/dev/null || echo psql)",
        "fi",
        "# Generate token and execute query",
        "TOKEN=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST 2>&1) || { echo \"Error: Failed to generate token: $TOKEN\" >&2; exit 1; }",
        "export PGPASSWORD=$TOKEN",
        ("$PSQL_CMD -h $DSQL_HOST -U admin -d postgres -p 5432 -c " + ("SET search_path TO car_entities_schema; " + $query | @sh) + " 2>&1")
    ]')

# Send command to bastion host using proper JSON format
COMMAND_OUTPUT=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$COMMANDS_JSON}" \
    --output json 2>&1)

COMMAND_ID=$(echo "$COMMAND_OUTPUT" | jq -r '.Command.CommandId' 2>/dev/null || echo "")

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "null" ]; then
    echo "Error: Failed to send command to bastion host"
    echo "$COMMAND_OUTPUT" | jq . 2>/dev/null || echo "$COMMAND_OUTPUT"
    exit 1
fi

echo "Command ID: $COMMAND_ID"
echo "Waiting for command to complete..."
echo ""

# Poll for command completion (max 60 seconds, check every 1 second initially, then 2 seconds)
MAX_WAIT=60
WAIT_INTERVAL=1  # Reduced from 2 to 1 second for faster response
ELAPSED=0
STATUS="InProgress"
CONSECUTIVE_CHECKS=0

while [ "$STATUS" = "InProgress" ] && [ $ELAPSED -lt $MAX_WAIT ]; do
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
    CONSECUTIVE_CHECKS=$((CONSECUTIVE_CHECKS + 1))
    
    # After first few checks, increase interval to 2 seconds to reduce API calls
    if [ $CONSECUTIVE_CHECKS -gt 3 ]; then
        WAIT_INTERVAL=2
    fi
    
    STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query "Status" \
        --output text 2>/dev/null || echo "InProgress")
done

# Get full command invocation details
INVOCATION=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --output json 2>/dev/null)

FINAL_STATUS=$(echo "$INVOCATION" | jq -r '.Status' 2>/dev/null || echo "Unknown")
STDOUT=$(echo "$INVOCATION" | jq -r '.StandardOutputContent // ""' 2>/dev/null || echo "")
STDERR=$(echo "$INVOCATION" | jq -r '.StandardErrorContent // ""' 2>/dev/null || echo "")

if [ "$FINAL_STATUS" = "Success" ]; then
    echo "=== Query Results ==="
    if [ -n "$STDOUT" ]; then
        echo "$STDOUT"
    else
        echo "(No output)"
    fi
    if [ -n "$STDERR" ]; then
        echo ""
        echo "=== Warnings/Info ==="
        echo "$STDERR"
    fi
else
    echo "Error: Command status: $FINAL_STATUS"
    echo ""
    if [ -n "$STDERR" ]; then
        echo "=== Error Output ==="
        echo "$STDERR"
    fi
    if [ -n "$STDOUT" ]; then
        echo ""
        echo "=== Standard Output ==="
        echo "$STDOUT"
    fi
    exit 1
fi
