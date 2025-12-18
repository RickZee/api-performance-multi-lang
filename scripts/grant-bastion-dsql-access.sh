#!/bin/bash
# Grant bastion host IAM role access to DSQL IAM database user
# This is a one-time setup step

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$PROJECT_ROOT/terraform" || exit 1

# Get values from terraform
BASTION_INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
IAM_USERNAME=$(grep -E "^iam_database_user\s*=" terraform.tfvars 2>/dev/null | sed 's/#.*$//' | cut -d'"' -f2 | tr -d ' ' || echo "")
PROJECT_NAME=$(grep -E "^project_name\s*=" terraform.tfvars 2>/dev/null | sed 's/#.*$//' | cut -d'"' -f2 | tr -d ' ' || echo "producer-api")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

if [ -z "$BASTION_INSTANCE_ID" ] || [ -z "$DSQL_HOST" ] || [ -z "$IAM_USERNAME" ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Missing required values${NC}"
    echo "  BASTION_INSTANCE_ID: ${BASTION_INSTANCE_ID:-not found}"
    echo "  DSQL_HOST: ${DSQL_HOST:-not found}"
    echo "  IAM_USERNAME: ${IAM_USERNAME:-not found}"
    echo "  ACCOUNT_ID: ${ACCOUNT_ID:-not found}"
    exit 1
fi

BASTION_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_NAME}-bastion-role"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Granting Bastion IAM Access to DSQL${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Bastion Instance ID: $BASTION_INSTANCE_ID"
echo "DSQL Host: $DSQL_HOST"
echo "IAM Username: $IAM_USERNAME"
echo "Bastion Role ARN: $BASTION_ROLE_ARN"
echo "Region: $AWS_REGION"
echo ""

# Grant IAM access via bastion host
# Note: The ARN must be single-quoted in the SQL command
echo -e "${BLUE}Running IAM grant command on DSQL...${NC}"

# Build the SQL command with proper quoting
GRANT_SQL="AWS IAM GRANT ${IAM_USERNAME} TO '${BASTION_ROLE_ARN}';"

COMMANDS_JSON=$(jq -n \
    --arg dsql_host "$DSQL_HOST" \
    --arg aws_region "$AWS_REGION" \
    --arg grant_sql "$GRANT_SQL" \
    '[
        "export DSQL_HOST=" + $dsql_host,
        "export AWS_REGION=" + $aws_region,
        "TOKEN=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)",
        "export PGPASSWORD=$TOKEN",
        ("psql -h $DSQL_HOST -U admin -d postgres -p 5432 -c " + ($grant_sql | @sh))
    ]')

COMMAND_OUTPUT=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$COMMANDS_JSON}" \
    --output json 2>&1)

COMMAND_ID=$(echo "$COMMAND_OUTPUT" | jq -r '.Command.CommandId' 2>/dev/null || echo "")

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "null" ]; then
    echo -e "${RED}Error: Failed to send command to bastion host${NC}"
    echo "$COMMAND_OUTPUT" | jq . 2>/dev/null || echo "$COMMAND_OUTPUT"
    exit 1
fi

echo "Command ID: $COMMAND_ID"
echo "Waiting for results..."

# Wait for command to complete
sleep 10

STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query "Status" \
    --output text 2>/dev/null || echo "InProgress")

if [ "$STATUS" = "Success" ]; then
    OUTPUT=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query "StandardOutputContent" \
        --output text 2>/dev/null)
    
    echo -e "${GREEN}✅ IAM grant successful!${NC}"
    echo "$OUTPUT"
    
    # Verify the mapping
    echo ""
    echo -e "${BLUE}Verifying IAM role mapping...${NC}"
    VERIFY_QUERY="SELECT pg_role_name, arn FROM sys.iam_pg_role_mappings WHERE pg_role_name = '${IAM_USERNAME}';"
    
    VERIFY_COMMANDS_JSON=$(jq -n \
        --arg dsql_host "$DSQL_HOST" \
        --arg aws_region "$AWS_REGION" \
        --arg query "$VERIFY_QUERY" \
        '[
            "export DSQL_HOST=" + $dsql_host,
            "export AWS_REGION=" + $aws_region,
            "TOKEN=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)",
            "export PGPASSWORD=$TOKEN",
            "psql -h $DSQL_HOST -U admin -d postgres -p 5432 -c \u0027" + $query + "\u0027"
        ]')
    
    VERIFY_OUTPUT=$(aws ssm send-command \
        --instance-ids "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --document-name "AWS-RunShellScript" \
        --parameters "{\"commands\":$VERIFY_COMMANDS_JSON}" \
        --output json 2>&1)
    
    VERIFY_COMMAND_ID=$(echo "$VERIFY_OUTPUT" | jq -r '.Command.CommandId' 2>/dev/null || echo "")
    
    if [ -n "$VERIFY_COMMAND_ID" ] && [ "$VERIFY_COMMAND_ID" != "null" ]; then
        sleep 10
        VERIFY_RESULT=$(aws ssm get-command-invocation \
            --command-id "$VERIFY_COMMAND_ID" \
            --instance-id "$BASTION_INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query "StandardOutputContent" \
            --output text 2>/dev/null)
        echo "$VERIFY_RESULT"
    fi
else
    echo -e "${RED}Error: Command status: $STATUS${NC}"
    ERROR_OUTPUT=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" 2>&1)
    echo "$ERROR_OUTPUT" | jq -r '.StandardErrorContent // .Status' 2>&1
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Setup complete! The bastion host can now connect to DSQL.${NC}"
