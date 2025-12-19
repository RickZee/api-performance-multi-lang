#!/bin/bash
# Test full DSQL connection with IAM authentication
# Tests token generation, JDBC connection, and table access

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# Get bastion and DSQL info
TERRAFORM_DIR="../terraform"
if [ ! -d "$TERRAFORM_DIR" ]; then
    TERRAFORM_DIR="../../terraform"
fi

cd "$TERRAFORM_DIR"

BASTION_INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
BASTION_REGION=$(terraform output -raw bastion_host_ssm_command 2>/dev/null | sed -n 's/.*--region \([^ ]*\).*/\1/p' || echo "us-east-1")
DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
DSQL_DATABASE=$(terraform output -raw aurora_database_name 2>/dev/null || echo "car_entities")
IAM_USERNAME=$(grep -E "^iam_database_user\s*=" terraform.tfvars 2>/dev/null | sed 's/#.*$//' | cut -d'"' -f2 | tr -d ' ' || echo "dsql_iam_user")

if [ -z "$BASTION_INSTANCE_ID" ] || [ -z "$DSQL_HOST" ]; then
    echo "Error: Missing required values"
    exit 1
fi

echo "=========================================="
echo "DSQL Connection Test"
echo "=========================================="
echo ""
echo "DSQL Host: $DSQL_HOST"
echo "Database: $DSQL_DATABASE"
echo "IAM Username: $IAM_USERNAME"
echo "Region: $BASTION_REGION"
echo ""

# Prepare test commands
TEST_COMMANDS=(
    "echo '=== 1. Generate IAM Token ==='"
    "DSQL_HOST=\"$DSQL_HOST\""
    "IAM_USER=\"$IAM_USERNAME\""
    "AWS_REGION=\"$BASTION_REGION\""
    "DB_NAME=\"$DSQL_DATABASE\""
    "TOKEN=\$(aws rds generate-db-auth-token --hostname \"\$DSQL_HOST\" --port 5432 --region \"\$AWS_REGION\" --username \"\$IAM_USER\" 2>&1)"
    "if [ \$? -ne 0 ]; then"
    "  echo '✗ Token generation failed'"
    "  echo \"Error: \$TOKEN\""
    "  exit 1"
    "fi"
    "echo '✓ Token generated (length: '\${#TOKEN}')'"
    "echo ''"
    "echo '=== 2. Test JDBC Connection ==='"
    "export PGPASSWORD=\"\$TOKEN\""
    "JDBC_URL=\"postgresql://\$IAM_USER@\$DSQL_HOST:5432/\$DB_NAME?sslmode=require\""
    "echo 'Connection string: postgresql://'\$IAM_USER'@'\$DSQL_HOST':5432/'\$DB_NAME'?sslmode=require'"
    "echo 'Attempting connection...'"
    "CONN_TEST=\$(psql \"\$JDBC_URL\" -c 'SELECT version();' 2>&1)"
    "CONN_EXIT_CODE=\$?"
    "if [ \$CONN_EXIT_CODE -eq 0 ]; then"
    "  echo '✓ Connection successful!'"
    "  echo \"Database version:\""
    "  echo \"\$CONN_TEST\""
    "  echo ''"
    "  echo '=== 3. Test Table Access ==='"
    "  TABLE_TEST=\$(psql \"\$JDBC_URL\" -c \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'event_headers';\" -t -A 2>&1)"
    "  if [ \$? -eq 0 ]; then"
    "    if [ \"\$TABLE_TEST\" = \"1\" ]; then"
    "      echo '✓ Table event_headers exists'"
    "    else"
    "      echo '✗ Table event_headers does not exist'"
    "    fi"
    "  else"
    "    echo '✗ Failed to query tables'"
    "    echo \"Error: \$TABLE_TEST\""
    "  fi"
    "  echo ''"
    "  echo '=== 4. Test saved_date Column ==='"
    "  COLUMN_TEST=\$(psql \"\$JDBC_URL\" -c \"SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'event_headers' AND column_name = 'saved_date';\" -t -A 2>&1)"
    "  if [ \$? -eq 0 ] && [ \"\$COLUMN_TEST\" = \"saved_date\" ]; then"
    "    echo '✓ Column saved_date exists'"
    "  else"
    "    echo '✗ Column saved_date does not exist'"
    "  fi"
    "  echo ''"
    "  echo '=== 5. Test Primary Key ==='"
    "  PK_TEST=\$(psql \"\$JDBC_URL\" -c \"SELECT a.attname FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey) WHERE i.indrelid = 'public.event_headers'::regclass AND i.indisprimary LIMIT 1;\" -t -A 2>&1)"
    "  if [ \$? -eq 0 ] && [ -n \"\$PK_TEST\" ]; then"
    "    echo '✓ Primary key found: '\$PK_TEST"
    "  else"
    "    echo '✗ No primary key found'"
    "  fi"
    "else"
    "  echo '✗ Connection FAILED'"
    "  echo \"Error: \$CONN_TEST\""
    "  echo ''"
    "  echo 'Common causes:'"
    "  echo '  1. IAM role not mapped to IAM user in DSQL'"
    "  echo '  2. Invalid token (expired or malformed)'"
    "  echo '  3. Network connectivity issues'"
    "  echo '  4. Security group blocking connection'"
    "  echo '  5. SSL/TLS handshake failure'"
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
echo "=== Connection Test Results ==="
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent, StandardErrorContent]' \
    --output text

echo ""
echo "=========================================="
echo "Connection Test Complete"
echo "=========================================="
echo ""
