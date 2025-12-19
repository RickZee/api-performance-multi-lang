#!/bin/bash
# Verify IAM role mapping for DSQL authentication
# Checks if bastion IAM role is mapped to dsql_iam_user in DSQL

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
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
PROJECT_NAME=$(grep -E "^project_name\s*=" terraform.tfvars 2>/dev/null | sed 's/#.*$//' | cut -d'"' -f2 | tr -d ' ' || echo "producer-api")
IAM_USERNAME=$(grep -E "^iam_database_user\s*=" terraform.tfvars 2>/dev/null | sed 's/#.*$//' | cut -d'"' -f2 | tr -d ' ' || echo "dsql_iam_user")

if [ -z "$BASTION_INSTANCE_ID" ] || [ -z "$DSQL_HOST" ] || [ -z "$ACCOUNT_ID" ]; then
    echo "Error: Missing required values"
    echo "  BASTION_INSTANCE_ID: ${BASTION_INSTANCE_ID:-not found}"
    echo "  DSQL_HOST: ${DSQL_HOST:-not found}"
    echo "  ACCOUNT_ID: ${ACCOUNT_ID:-not found}"
    exit 1
fi

BASTION_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_NAME}-bastion-role"

echo "=========================================="
echo "IAM Role Mapping Verification"
echo "=========================================="
echo ""
echo "DSQL Host: $DSQL_HOST"
echo "IAM Username: $IAM_USERNAME"
echo "Bastion Role ARN: $BASTION_ROLE_ARN"
echo ""

# Prepare verification commands
VERIFY_COMMANDS=(
    "echo '=== Checking IAM Role Mapping ==='"
    "echo 'Querying sys.iam_pg_role_mappings for user: $IAM_USERNAME'"
    "echo ''"
    "DSQL_HOST=\"$DSQL_HOST\""
    "AWS_REGION=\"$BASTION_REGION\""
    "IAM_USER=\"$IAM_USERNAME\""
    "ROLE_ARN=\"$BASTION_ROLE_ARN\""
    "echo 'Generating admin token...'"
    "TOKEN=\$(aws rds generate-db-auth-token --hostname \"\$DSQL_HOST\" --port 5432 --region \"\$AWS_REGION\" --username postgres 2>&1)"
    "if [ \$? -ne 0 ]; then"
    "  echo 'ERROR: Failed to generate admin token'"
    "  echo 'Error: '\$TOKEN"
    "  echo ''"
    "  echo 'Note: This requires a user/role with admin access to DSQL'"
    "  echo 'The postgres user must be mapped to an IAM role/user with admin permissions'"
    "  exit 1"
    "fi"
    "export PGPASSWORD=\"\$TOKEN\""
    "echo 'Connecting to DSQL...'"
    "QUERY=\"SELECT pg_role_name, arn FROM sys.iam_pg_role_mappings WHERE pg_role_name = '\$IAM_USER';\""
    "RESULT=\$(psql -h \"\$DSQL_HOST\" -U postgres -d postgres -p 5432 -t -A -c \"\$QUERY\" 2>&1)"
    "if [ \$? -eq 0 ] && [ -n \"\$RESULT\" ]; then"
    "  echo '✓ IAM Role Mappings Found:'"
    "  echo \"\$RESULT\""
    "  echo ''"
    "  if echo \"\$RESULT\" | grep -q \"\$ROLE_ARN\"; then"
    "    echo '✓ SUCCESS: Bastion role is mapped to IAM user'"
    "    echo \"  Found: \$IAM_USER -> \$ROLE_ARN\""
    "  else"
    "    echo '✗ WARNING: Bastion role is NOT mapped'"
    "    echo \"  Expected: \$IAM_USER -> \$ROLE_ARN\""
    "    echo \"  Found mappings:\""
    "    echo \"\$RESULT\""
    "    echo ''"
    "    echo 'To fix, run this SQL command (requires admin access):'"
    "    echo \"  AWS IAM GRANT \$IAM_USER TO '\$ROLE_ARN';\""
    "  fi"
    "else"
    "  echo '✗ ERROR: Failed to query IAM role mappings'"
    "  echo \"Error: \$RESULT\""
    "  echo ''"
    "  echo 'Possible causes:'"
    "  echo '  1. IAM user does not exist in DSQL'"
    "  echo '  2. No mappings exist for this user'"
    "  echo '  3. Connection/authentication failed'"
    "fi"
    "echo ''"
    "echo '=== Checking if IAM user exists ==='"
    "USER_QUERY=\"SELECT rolname FROM pg_roles WHERE rolname = '\$IAM_USER';\""
    "USER_RESULT=\$(psql -h \"\$DSQL_HOST\" -U postgres -d postgres -p 5432 -t -A -c \"\$USER_QUERY\" 2>&1)"
    "if [ \$? -eq 0 ] && [ -n \"\$USER_RESULT\" ]; then"
    "  echo '✓ IAM user exists: '\$USER_RESULT"
    "else"
    "  echo '✗ IAM user does not exist or cannot be queried'"
    "  echo \"Error: \$USER_RESULT\""
    "fi"
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

sleep 8

# Get output
echo ""
echo "=== Verification Results ==="
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent, StandardErrorContent]' \
    --output text

echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
echo ""
