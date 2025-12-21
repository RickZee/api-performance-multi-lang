#!/bin/bash
# Script to drop and recreate all tables in DSQL database
# Usage: ./scripts/recreate-dsql-tables.sh

set -e

# Get project root and schema file path before changing directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEMA_FILE="$PROJECT_ROOT/data/schema-dsql.sql"

# Get Terraform outputs
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
cd "$TERRAFORM_DIR" || exit 1

TERRAFORM_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")

AWS_REGION=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.aws_region.value // "us-east-1"' 2>/dev/null || echo "us-east-1")
DSQL_HOST=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.aurora_dsql_host.value // ""' 2>/dev/null || echo "")
BASTION_INSTANCE_ID=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.bastion_host_instance_id.value // ""' 2>/dev/null || echo "")

if [ -z "$BASTION_INSTANCE_ID" ]; then
    echo "Error: Bastion host not found. Make sure Terraform has been applied and bastion host is enabled."
    exit 1
fi

if [ -z "$DSQL_HOST" ]; then
    echo "Error: DSQL host not found. Make sure Terraform has been applied and DSQL cluster is enabled."
    exit 1
fi

if [ ! -f "$SCHEMA_FILE" ]; then
    echo "Error: Schema file not found: $SCHEMA_FILE"
    exit 1
fi

echo "=== Dropping and Recreating DSQL Tables ==="
echo "Region: $AWS_REGION"
echo "DSQL Host: $DSQL_HOST"
echo "Bastion Host: $BASTION_INSTANCE_ID"
echo ""

# Create SQL content: drop tables first, then recreate from schema
DROP_SQL="SET search_path TO car_entities_schema;
DROP TABLE IF EXISTS car_entities_schema.service_record_entities CASCADE;
DROP TABLE IF EXISTS car_entities_schema.loan_payment_entities CASCADE;
DROP TABLE IF EXISTS car_entities_schema.loan_entities CASCADE;
DROP TABLE IF EXISTS car_entities_schema.car_entities CASCADE;
DROP TABLE IF EXISTS car_entities_schema.event_headers CASCADE;
DROP TABLE IF EXISTS car_entities_schema.business_events CASCADE;"

SCHEMA_SQL=$(cat "$SCHEMA_FILE")
FULL_SQL="$DROP_SQL
$SCHEMA_SQL"

# Base64 encode the SQL to pass it safely through SSM
SQL_B64=$(echo "$FULL_SQL" | base64 | tr -d '\n')

echo "Step 1: Dropping all tables..."
echo "Step 2: Recreating tables from schema..."

# Build commands array - write SQL to temp file and execute it
COMMANDS_JSON=$(jq -n \
    --arg dsql_host "$DSQL_HOST" \
    --arg aws_region "$AWS_REGION" \
    --arg sql_b64 "$SQL_B64" \
    '[
        "export DSQL_HOST=" + $dsql_host,
        "export AWS_REGION=" + $aws_region,
        "if [ -z \"$PSQL_CMD\" ]; then",
        "  if ! command -v psql >/dev/null 2>&1 && ! command -v psql16 >/dev/null 2>&1; then",
        "    echo \"Installing PostgreSQL client...\" >&2",
        "    dnf install -y postgresql16 >/dev/null 2>&1 || yum install -y postgresql16 >/dev/null 2>&1 || true",
        "  fi",
        "  export PSQL_CMD=$(command -v psql 2>/dev/null || command -v psql16 2>/dev/null || echo psql)",
        "fi",
        "TMP_FILE=$(mktemp /tmp/recreate-schema-XXXXXX.sql)",
        "echo " + ($sql_b64 | @sh) + " | base64 -d > \"$TMP_FILE\"",
        "TOKEN=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST 2>&1) || { echo \"Error: Failed to generate token: $TOKEN\" >&2; exit 1; }",
        "export PGPASSWORD=$TOKEN",
        "$PSQL_CMD -h $DSQL_HOST -U admin -d postgres -p 5432 -f \"$TMP_FILE\"",
        "rm -f \"$TMP_FILE\""
    ]')

# Send command to bastion host
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

# Poll for command completion (max 120 seconds for schema creation)
MAX_WAIT=120
WAIT_INTERVAL=2
ELAPSED=0
STATUS="InProgress"

while [ "$STATUS" = "InProgress" ] && [ $ELAPSED -lt $MAX_WAIT ]; do
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
    
    STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query "Status" \
        --output text 2>/dev/null || echo "InProgress")
    
    if [ "$STATUS" != "InProgress" ]; then
        break
    fi
    
    echo -n "."
done

echo ""
echo ""

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
    echo "✅ Tables dropped and recreated successfully!"
    echo ""
    if [ -n "$STDOUT" ]; then
        echo "=== Output ==="
        echo "$STDOUT"
    fi
    if [ -n "$STDERR" ]; then
        echo ""
        echo "=== Warnings/Info ==="
        echo "$STDERR"
    fi
else
    echo "❌ Error: Command status: $FINAL_STATUS"
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

echo ""
echo "Verifying tables were created..."

# Verify tables exist
VERIFY_QUERY="SET search_path TO car_entities_schema;
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'car_entities_schema' 
ORDER BY table_name;"

COMMANDS_JSON=$(jq -n \
    --arg dsql_host "$DSQL_HOST" \
    --arg aws_region "$AWS_REGION" \
    --arg query "$VERIFY_QUERY" \
    '[
        "export DSQL_HOST=" + $dsql_host,
        "export AWS_REGION=" + $aws_region,
        "if [ -z \"$PSQL_CMD\" ]; then",
        "  export PSQL_CMD=$(command -v psql 2>/dev/null || command -v psql16 2>/dev/null || echo psql)",
        "fi",
        "TOKEN=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST 2>&1) || { echo \"Error: Failed to generate token: $TOKEN\" >&2; exit 1; }",
        "export PGPASSWORD=$TOKEN",
        ("$PSQL_CMD -h $DSQL_HOST -U admin -d postgres -p 5432 -c " + ($query | @sh) + " 2>&1")
    ]')

COMMAND_OUTPUT=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$COMMANDS_JSON}" \
    --output json 2>&1)

COMMAND_ID=$(echo "$COMMAND_OUTPUT" | jq -r '.Command.CommandId' 2>/dev/null || echo "")

if [ -n "$COMMAND_ID" ] && [ "$COMMAND_ID" != "null" ]; then
    sleep 3
    INVOCATION=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null)
    
    STDOUT=$(echo "$INVOCATION" | jq -r '.StandardOutputContent // ""' 2>/dev/null || echo "")
    
    if [ -n "$STDOUT" ]; then
        echo "$STDOUT"
    fi
fi

echo ""
echo "✅ Done!"
