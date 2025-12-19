#!/bin/bash
# Setup DSQL connector configuration from Terraform outputs
# Gets DSQL info from Terraform and sets up configuration on bastion

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

# Get DSQL info from Terraform
echo "=========================================="
echo "Getting DSQL Configuration from Terraform"
echo "=========================================="
echo ""

DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
DSQL_PORT=$(terraform output -raw aurora_dsql_port 2>/dev/null || echo "5432")
DSQL_DATABASE=$(terraform output -raw aurora_database_name 2>/dev/null || echo "car_entities")

if [ -z "$DSQL_HOST" ]; then
    echo "Error: Could not get DSQL host from Terraform"
    exit 1
fi

echo "DSQL Configuration:"
echo "  Host: $DSQL_HOST"
echo "  Port: $DSQL_PORT"
echo "  Database: $DSQL_DATABASE"
echo ""

# Get IAM username (default or from env)
DSQL_IAM_USERNAME="${DSQL_IAM_USERNAME:-dsql_iam_user}"
DSQL_TABLES="${DSQL_TABLES:-event_headers}"
DSQL_TOPIC_PREFIX="${DSQL_TOPIC_PREFIX:-dsql-cdc}"

echo "Other Configuration:"
echo "  IAM Username: $DSQL_IAM_USERNAME"
echo "  Tables: $DSQL_TABLES"
echo "  Topic Prefix: $DSQL_TOPIC_PREFIX"
echo ""

# Get Confluent info
echo "=========================================="
echo "Confluent Cloud Configuration"
echo "=========================================="
echo ""

# Check for Confluent info in environment or files
CC_BOOTSTRAP_SERVERS="${CC_BOOTSTRAP_SERVERS:-}"
CC_KAFKA_API_KEY="${CC_KAFKA_API_KEY:-}"
CC_KAFKA_API_SECRET="${CC_KAFKA_API_SECRET:-}"

# Try to read from connect.env if it exists
CONNECT_ENV_FILE="$TERRAFORM_DIR/debezium-connector-dsql/connect.env"
if [ -f "$CONNECT_ENV_FILE" ]; then
    echo "Found connect.env file, reading Confluent config..."
    source "$CONNECT_ENV_FILE"
    CC_BOOTSTRAP_SERVERS="${CC_BOOTSTRAP_SERVERS:-$CC_BOOTSTRAP_SERVERS}"
    CC_KAFKA_API_KEY="${CC_KAFKA_API_KEY:-$CC_KAFKA_API_KEY}"
    CC_KAFKA_API_SECRET="${CC_KAFKA_API_SECRET:-$CC_KAFKA_API_SECRET}"
fi

# Prompt if still missing
if [ -z "$CC_BOOTSTRAP_SERVERS" ]; then
    read -p "Enter Confluent Cloud Bootstrap Servers (e.g., pkc-xxxxx.us-east-1.aws.confluent.cloud:9092): " CC_BOOTSTRAP_SERVERS
fi

if [ -z "$CC_KAFKA_API_KEY" ]; then
    read -p "Enter Confluent Cloud Kafka API Key: " CC_KAFKA_API_KEY
fi

if [ -z "$CC_KAFKA_API_SECRET" ]; then
    read -s -p "Enter Confluent Cloud Kafka API Secret: " CC_KAFKA_API_SECRET
    echo ""
fi

echo ""
echo "Confluent Configuration:"
echo "  Bootstrap Servers: $CC_BOOTSTRAP_SERVERS"
echo "  API Key: ${CC_KAFKA_API_KEY:0:10}..."
echo ""

# Prepare setup commands for bastion
SETUP_COMMANDS=(
    "echo '=== Creating .env.dsql file ==='"
    "cd ~/debezium-connector-dsql"
    "cat > .env.dsql <<'EOF'"
    "export DSQL_ENDPOINT_PRIMARY=\"$DSQL_HOST\""
    "export DSQL_DATABASE_NAME=\"$DSQL_DATABASE\""
    "export DSQL_REGION=\"$BASTION_REGION\""
    "export DSQL_IAM_USERNAME=\"$DSQL_IAM_USERNAME\""
    "export DSQL_TABLES=\"$DSQL_TABLES\""
    "export DSQL_PORT=\"$DSQL_PORT\""
    "export DSQL_TOPIC_PREFIX=\"$DSQL_TOPIC_PREFIX\""
    "EOF"
    "chmod 600 .env.dsql"
    "echo '✓ .env.dsql created'"
    "echo ''"
    "echo '=== Creating connector configuration ==='"
    "mkdir -p config"
    "cat > config/dsql-connector.json <<'EOFCONFIG'"
    "{"
    "  \"name\": \"dsql-cdc-source\","
    "  \"config\": {"
    "    \"connector.class\": \"io.debezium.connector.dsql.DsqlConnector\","
    "    \"tasks.max\": \"1\","
    "    \"dsql.endpoint.primary\": \"$DSQL_HOST\","
    "    \"dsql.port\": \"$DSQL_PORT\","
    "    \"dsql.region\": \"$BASTION_REGION\","
    "    \"dsql.iam.username\": \"$DSQL_IAM_USERNAME\","
    "    \"dsql.database.name\": \"$DSQL_DATABASE\","
    "    \"dsql.tables\": \"$DSQL_TABLES\","
    "    \"dsql.poll.interval.ms\": \"1000\","
    "    \"dsql.batch.size\": \"1000\","
    "    \"dsql.pool.max.size\": \"10\","
    "    \"dsql.pool.min.idle\": \"1\","
    "    \"dsql.pool.connection.timeout.ms\": \"30000\","
    "    \"topic.prefix\": \"$DSQL_TOPIC_PREFIX\","
    "    \"output.data.format\": \"JSON\""
    "  }"
    "}"
    "EOFCONFIG"
    "echo '✓ connector config created'"
    "echo ''"
    "echo '=== Configuration Summary ==='"
    "echo 'DSQL Endpoint: $DSQL_HOST'"
    "echo 'Database: $DSQL_DATABASE'"
    "echo 'Tables: $DSQL_TABLES'"
    "echo 'Topic Prefix: $DSQL_TOPIC_PREFIX'"
)

# Build JSON for commands
JSON_CMDS="["
for i in "${!SETUP_COMMANDS[@]}"; do
    if [ $i -gt 0 ]; then
        JSON_CMDS+=","
    fi
    CMD="${SETUP_COMMANDS[$i]//\"/\\\"}"
    JSON_CMDS+="\"$CMD\""
done
JSON_CMDS+="]"

echo "Setting up configuration on bastion..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$JSON_CMDS}" \
    --region "$BASTION_REGION" \
    --output text \
    --query 'Command.CommandId' 2>&1)

sleep 5

# Get output
echo ""
echo "=== Setup Output ==="
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent]' \
    --output text

echo ""
echo "=========================================="
echo "Configuration Complete!"
echo "=========================================="
echo ""
echo "Next: Deploy Kafka Connect with Confluent Cloud"
echo ""
echo "Run:"
echo "  export KAFKA_BOOTSTRAP_SERVERS=\"$CC_BOOTSTRAP_SERVERS\""
echo "  export CC_KAFKA_API_KEY=\"$CC_KAFKA_API_KEY\""
echo "  export CC_KAFKA_API_SECRET=\"$CC_KAFKA_API_SECRET\""
echo "  ./scripts/deploy-kafka-connect-bastion.sh \"$CC_BOOTSTRAP_SERVERS\""
echo ""
