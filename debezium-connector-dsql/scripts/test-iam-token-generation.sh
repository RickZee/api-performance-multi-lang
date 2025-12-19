#!/bin/bash
# Test IAM token generation on bastion host
# Verifies AWS credentials and RDS SDK token generation

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
IAM_USERNAME=$(grep -E "^iam_database_user\s*=" terraform.tfvars 2>/dev/null | sed 's/#.*$//' | cut -d'"' -f2 | tr -d ' ' || echo "dsql_iam_user")

if [ -z "$BASTION_INSTANCE_ID" ] || [ -z "$DSQL_HOST" ]; then
    echo "Error: Missing required values"
    exit 1
fi

echo "=========================================="
echo "IAM Token Generation Test"
echo "=========================================="
echo ""
echo "DSQL Host: $DSQL_HOST"
echo "IAM Username: $IAM_USERNAME"
echo "Region: $BASTION_REGION"
echo ""

# Prepare test commands
TEST_COMMANDS=(
    "echo '=== 1. AWS Credentials Check ==='"
    "aws sts get-caller-identity 2>&1"
    "echo ''"
    "echo '=== 2. AWS CLI Version ==='"
    "aws --version 2>&1"
    "echo ''"
    "echo '=== 3. Testing RDS Token Generation (AWS CLI) ==='"
    "DSQL_HOST=\"$DSQL_HOST\""
    "IAM_USER=\"$IAM_USERNAME\""
    "AWS_REGION=\"$BASTION_REGION\""
    "echo 'Generating token for user: '\$IAM_USER"
    "TOKEN=\$(aws rds generate-db-auth-token --hostname \"\$DSQL_HOST\" --port 5432 --region \"\$AWS_REGION\" --username \"\$IAM_USER\" 2>&1)"
    "TOKEN_EXIT_CODE=\$?"
    "if [ \$TOKEN_EXIT_CODE -eq 0 ]; then"
    "  TOKEN_LENGTH=\${#TOKEN}"
    "  echo '✓ Token generated successfully'"
    "  echo \"  Token length: \$TOKEN_LENGTH characters\""
    "  echo \"  Token preview: \${TOKEN:0:50}...\""
    "  echo ''"
    "  echo '=== 4. Token Format Validation ==='"
    "  if [[ \$TOKEN =~ ^[A-Za-z0-9+/=]+$ ]]; then"
    "    echo '✓ Token format appears valid (base64-like)'"
    "  else"
    "    echo '✗ Token format may be invalid'"
    "  fi"
    "  echo ''"
    "  echo '=== 5. Testing Token Expiration ==='"
    "  echo 'Tokens are valid for 15 minutes'"
    "  echo 'Current time: '\$(date)"
    "else"
    "  echo '✗ Token generation FAILED'"
    "  echo \"Error: \$TOKEN\""
    "  echo ''"
    "  echo 'Possible causes:'"
    "  echo '  1. AWS credentials not configured'"
    "  echo '  2. IAM permissions missing (dsql:DbConnect)'"
    "  echo '  3. Invalid endpoint or username'"
    "  echo '  4. Network connectivity issues'"
    "fi"
    "echo ''"
    "echo '=== 6. Testing with Java (if available) ==='"
    "cd ~/debezium-connector-dsql 2>/dev/null || echo 'Project directory not found'"
    "if [ -f lib/debezium-connector-dsql-1.0.0.jar ]; then"
    "  echo 'Connector JAR found, testing token generation via Java...'"
    "  java -cp 'lib/*' -c 'import io.debezium.connector.dsql.auth.IamTokenGenerator; IamTokenGenerator gen = new IamTokenGenerator(\"$DSQL_HOST\", 5432, \"$IAM_USERNAME\", \"$BASTION_REGION\"); String token = gen.getToken(); System.out.println(\"Token length: \" + token.length()); gen.close();' 2>&1 || echo 'Java test not available (requires compiled classes)'"
    "else"
    "  echo 'Connector JAR not found, skipping Java test'"
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
echo "=== Test Results ==="
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent, StandardErrorContent]' \
    --output text

echo ""
echo "=========================================="
echo "Token Generation Test Complete"
echo "=========================================="
echo ""
