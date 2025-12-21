#!/bin/bash
# Simple connector deployment script that avoids JSON escaping issues
# Uses file upload/download approach instead of inline JSON

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$PROJECT_DIR"

# Get bastion info from terraform
TERRAFORM_DIR="../terraform"
if [ ! -d "$TERRAFORM_DIR" ]; then
    TERRAFORM_DIR="../../terraform"
fi

cd "$TERRAFORM_DIR"

BASTION_INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
BASTION_REGION=$(terraform output -raw bastion_host_ssm_command 2>/dev/null | sed -n 's/.*--region \([^ ]*\).*/\1/p' || echo "us-east-1")
DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")

if [ -z "$BASTION_INSTANCE_ID" ]; then
    echo -e "${RED}Error: Could not get bastion instance ID${NC}"
    exit 1
fi

if [ -z "$DSQL_HOST" ]; then
    echo -e "${YELLOW}Warning: Could not get DSQL host from terraform, using default${NC}"
    DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploying DSQL Connector${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Bastion: $BASTION_INSTANCE_ID"
echo "Region: $BASTION_REGION"
echo "DSQL Host: $DSQL_HOST"
echo ""

# Read the config template
CONFIG_TEMPLATE="$PROJECT_DIR/config/dsql-connector.json"
if [ ! -f "$CONFIG_TEMPLATE" ]; then
    echo -e "${RED}Error: Config template not found: $CONFIG_TEMPLATE${NC}"
    exit 1
fi

# Create temporary config file with actual values
TEMP_CONFIG="/tmp/dsql-connector-deploy-$$.json"
echo -e "${BLUE}Creating connector config...${NC}"

# Use sed and jq to substitute values (more reliable than Python)
# First, copy template and do basic substitutions
cp "$CONFIG_TEMPLATE" "$TEMP_CONFIG"

# Use jq to properly modify JSON
if command -v jq >/dev/null 2>&1; then
    # Use jq to modify the config
    # Remove Confluent Cloud-specific transforms and use standard Kafka Connect transforms
    jq \
        --arg dsql_host "$DSQL_HOST" \
        '.config["dsql.endpoint.primary"] = $dsql_host |
         .config["dsql.iam.username"] = "lambda_dsql_user" |
         .config["dsql.database.name"] = "mortgage_db" |
         del(.config["dsql.endpoint.secondary"]) |
         .config["transforms"] = "route" |
         .config["transforms.route.type"] = "org.apache.kafka.connect.transforms.RegexRouter" |
         .config["transforms.route.regex"] = "dsql-cdc\\.public\\.event_headers" |
         .config["transforms.route.replacement"] = "raw-event-headers"' \
        "$CONFIG_TEMPLATE" > "$TEMP_CONFIG"
else
    # Fallback: use sed for basic substitutions
    sed -e "s|\${DSQL_PRIMARY_ENDPOINT}|$DSQL_HOST|g" \
        -e 's|"admin"|"lambda_dsql_user"|g' \
        -e 's|"${DSQL_SECONDARY_ENDPOINT}"||g' \
        -e '/dsql.endpoint.secondary/d' \
        -e 's|io.confluent.connect.cloud.transforms.TopicRegexRouter|org.apache.kafka.connect.transforms.RegexRouter|g' \
        "$CONFIG_TEMPLATE" > "$TEMP_CONFIG"
fi

if [ ! -f "$TEMP_CONFIG" ]; then
    echo -e "${RED}Error: Failed to create config file${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Config created${NC}"
echo ""
echo "Config preview:"
cat "$TEMP_CONFIG" | head -15
echo "..."
echo ""

# Upload to S3
S3_BUCKET="producer-api-lambda-deployments-978300727880"
S3_KEY="dsql-connector-deploy.json"

echo -e "${BLUE}Uploading config to S3...${NC}"
aws s3 cp "$TEMP_CONFIG" "s3://${S3_BUCKET}/${S3_KEY}" --region "$BASTION_REGION" > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to upload config to S3${NC}"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

echo -e "${GREEN}✅ Config uploaded to S3${NC}"
echo ""

# Create connector on bastion
echo -e "${BLUE}Creating connector on bastion...${NC}"

# Use base64 encoding to avoid JSON escaping issues
CONFIG_B64=$(base64 -i "$TEMP_CONFIG" 2>/dev/null || base64 "$TEMP_CONFIG" 2>/dev/null)

# Build commands array (avoiding JSON escaping issues)
COMMANDS=(
    "echo 'Downloading connector config from S3...'"
    "aws s3 cp s3://${S3_BUCKET}/${S3_KEY} /tmp/connector-deploy.json 2>&1"
    "echo 'Config downloaded:'"
    "cat /tmp/connector-deploy.json"
    "echo ''"
    "echo 'Creating connector...'"
    "curl -X POST http://localhost:8083/connectors -H 'Content-Type: application/json' -d @/tmp/connector-deploy.json 2>&1"
    "echo ''"
    "echo 'Checking connector status...'"
    "sleep 3"
    "curl -s http://localhost:8083/connectors/dsql-cdc-source/status 2>&1 | head -50 || echo 'Connector may not be ready yet'"
)

# Build JSON array manually to avoid escaping issues
JSON_CMDS="["
for i in "${!COMMANDS[@]}"; do
    if [ $i -gt 0 ]; then
        JSON_CMDS+=","
    fi
    # Escape quotes and backslashes
    CMD="${COMMANDS[$i]//\\/\\\\}"
    CMD="${CMD//\"/\\\"}"
    JSON_CMDS+="\"$CMD\""
done
JSON_CMDS+="]"

COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$JSON_CMDS}" \
    --region "$BASTION_REGION" \
    --output text \
    --query 'Command.CommandId' 2>&1)

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "null" ]; then
    echo -e "${RED}Error: Failed to send command to bastion${NC}"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

echo "Command ID: $COMMAND_ID"
echo "Waiting for results..."
sleep 10

# Get output
echo ""
echo -e "${BLUE}=== Deployment Output ===${NC}"
OUTPUT=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent, StandardErrorContent]' \
    --output text 2>&1)

# Parse output - SSM returns: Status, StandardOutputContent, StandardErrorContent
STATUS=$(echo "$OUTPUT" | awk 'NR==1')
# Get everything between first and last line as stdout
STDOUT=$(echo "$OUTPUT" | awk 'NR>1 && NR<NF')
STDERR=$(echo "$OUTPUT" | awk 'NR==NF')

echo "Status: $STATUS"
echo ""
echo "Output:"
echo "$STDOUT"

if [ -n "$STDERR" ] && [ "$STDERR" != "None" ] && [ "$STDERR" != "null" ]; then
    echo ""
    echo "Errors:"
    echo "$STDERR"
fi

# Cleanup
rm -f "$TEMP_CONFIG"

echo ""
echo -e "${BLUE}========================================${NC}"

# Check if connector was created successfully
if echo "$STDOUT" | grep -q '"name": "dsql-cdc-source"'; then
    echo -e "${GREEN}✅ Connector created successfully!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Wait a few seconds for connector to initialize"
    echo "  2. Check status: ./scripts/monitor-pipeline.sh"
    echo "  3. Verify data flow: ./scripts/check-cdc-pipeline-data.sh"
elif echo "$STDOUT" | grep -qi "error\|failed\|exception"; then
    echo -e "${YELLOW}⚠️  Connector creation may have failed${NC}"
    echo "Check the output above for errors"
    exit 1
else
    echo -e "${YELLOW}⚠️  Unable to verify connector creation${NC}"
    echo "Check connector status manually:"
    echo "  aws ssm start-session --target $BASTION_INSTANCE_ID --region $BASTION_REGION"
    echo "  curl http://localhost:8083/connectors/dsql-cdc-source/status"
fi

echo -e "${BLUE}========================================${NC}"

