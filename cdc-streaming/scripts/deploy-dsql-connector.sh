#!/bin/bash
# Deploy Custom DSQL Debezium Connector to Confluent Cloud
# This script deploys the custom DSQL connector for event_headers table

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

CONNECTOR_CONFIG="$SCRIPT_DIR/../connectors/dsql-cdc-source-event-headers-confluent-cloud.json"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploy DSQL CDC Connector${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check prerequisites
if ! command -v confluent &> /dev/null; then
    echo -e "${RED}✗ Confluent CLI is not installed${NC}"
    echo "  Install with: brew install confluentinc/tap/cli"
    exit 1
fi

# Check if logged in
if ! confluent environment list &> /dev/null; then
    echo -e "${RED}✗ Not logged in to Confluent Cloud${NC}"
    echo "  Login with: confluent login"
    exit 1
fi

# Get environment and cluster from context or environment variables
ENV_ID="${CONFLUENT_ENV_ID:-$(confluent environment list --output json 2>/dev/null | jq -r '.[0].id' 2>/dev/null || echo '')}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-$(confluent kafka cluster list --output json 2>/dev/null | jq -r '.[0].id' 2>/dev/null || echo '')}"

if [ -z "$ENV_ID" ]; then
    echo -e "${RED}✗ No environment found${NC}"
    echo "  Set CONFLUENT_ENV_ID or ensure you have an environment"
    exit 1
fi

if [ -z "$CLUSTER_ID" ]; then
    echo -e "${RED}✗ No Kafka cluster found${NC}"
    echo "  Set KAFKA_CLUSTER_ID or ensure you have a cluster"
    exit 1
fi

echo -e "${CYAN}Configuration:${NC}"
echo "  Environment ID: $ENV_ID"
echo "  Cluster ID: $CLUSTER_ID"
echo "  Connector Config: $CONNECTOR_CONFIG"
echo ""

# Check if connector config exists
if [ ! -f "$CONNECTOR_CONFIG" ]; then
    echo -e "${RED}✗ Connector configuration not found: $CONNECTOR_CONFIG${NC}"
    exit 1
fi

# Read connector name
CONNECTOR_NAME=$(jq -r '.name' "$CONNECTOR_CONFIG" 2>/dev/null || echo "")

if [ -z "$CONNECTOR_NAME" ] || [ "$CONNECTOR_NAME" = "null" ]; then
    echo -e "${RED}✗ Invalid connector configuration: missing 'name' field${NC}"
    exit 1
fi

echo -e "${BLUE}Step 1: Checking if connector already exists...${NC}"
# Check using confluent connect list
EXISTING_CONNECTOR=$(confluent connect list --output json 2>/dev/null | jq -r ".[] | select(.name == \"$CONNECTOR_NAME\") | .id" | head -1 || echo "")

if [ -n "$EXISTING_CONNECTOR" ]; then
    echo -e "${YELLOW}⚠ Connector '$CONNECTOR_NAME' already exists (ID: $EXISTING_CONNECTOR)${NC}"
    read -p "Delete and recreate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deleting existing connector...${NC}"
        confluent connect delete "$EXISTING_CONNECTOR" --force 2>/dev/null || true
        sleep 3
    else
        echo "Aborted."
        exit 0
    fi
fi

echo ""
echo -e "${BLUE}Step 2: Preparing connector configuration...${NC}"

# Check for required environment variables
REQUIRED_VARS=("KAFKA_API_KEY" "KAFKA_API_SECRET" "DSQL_ENDPOINT_PRIMARY" "DSQL_IAM_USERNAME" "DSQL_DATABASE_NAME" "DSQL_CLUSTER_RESOURCE_ID")

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${RED}✗ Missing required environment variables:${NC}"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo -e "${CYAN}Example:${NC}"
    echo "  export KAFKA_API_KEY='your-key'"
    echo "  export KAFKA_API_SECRET='your-secret'"
    echo "  export DSQL_ENDPOINT_PRIMARY='vpce-xxx.dsql-fnh4.us-east-1.vpce.amazonaws.com'"
    echo "  export DSQL_IAM_USERNAME='lambda_dsql_user'"
    echo "  export DSQL_DATABASE_NAME='car_entities'"
    echo "  export DSQL_CLUSTER_RESOURCE_ID='vftmkydwxvxys6asbsc6ih2the'"
    echo ""
    echo -e "${CYAN}Optional variables:${NC}"
    echo "  export DSQL_ENDPOINT_SECONDARY='vpce-xxx.dsql-fnh4.us-east-1.vpce.amazonaws.com'"
    echo "  export DSQL_PORT='5432'"
    echo "  export DSQL_REGION='us-east-1'"
    echo "  export DSQL_TABLES='event_headers'"
    echo "  export DSQL_POLL_INTERVAL_MS='1000'"
    echo "  export DSQL_BATCH_SIZE='1000'"
    echo "  export TOPIC_PREFIX='dsql-cdc'"
    exit 1
fi

# Set defaults
export DSQL_ENDPOINT_SECONDARY="${DSQL_ENDPOINT_SECONDARY:-}"
export DSQL_PORT="${DSQL_PORT:-5432}"
export DSQL_REGION="${DSQL_REGION:-us-east-1}"
export DSQL_TABLES="${DSQL_TABLES:-event_headers}"
export DSQL_POLL_INTERVAL_MS="${DSQL_POLL_INTERVAL_MS:-1000}"
export DSQL_BATCH_SIZE="${DSQL_BATCH_SIZE:-1000}"
export TOPIC_PREFIX="${TOPIC_PREFIX:-dsql-cdc}"
export DB_SERVER_NAME="${DB_SERVER_NAME:-dsql-cdc}"

# Create a temporary config file with environment variables substituted
TEMP_CONFIG=$(mktemp)
if command -v envsubst &> /dev/null; then
    envsubst < "$CONNECTOR_CONFIG" > "$TEMP_CONFIG"
else
    # Fallback: simple substitution
    sed -e "s|\${KAFKA_API_KEY}|${KAFKA_API_KEY}|g" \
        -e "s|\${KAFKA_API_SECRET}|${KAFKA_API_SECRET}|g" \
        -e "s|\${DSQL_ENDPOINT_PRIMARY}|${DSQL_ENDPOINT_PRIMARY}|g" \
        -e "s|\${DSQL_ENDPOINT_SECONDARY}|${DSQL_ENDPOINT_SECONDARY}|g" \
        -e "s|\${DSQL_PORT}|${DSQL_PORT}|g" \
        -e "s|\${DSQL_REGION}|${DSQL_REGION}|g" \
        -e "s|\${DSQL_IAM_USERNAME}|${DSQL_IAM_USERNAME}|g" \
        -e "s|\${DSQL_DATABASE_NAME}|${DSQL_DATABASE_NAME}|g" \
        -e "s|\${DSQL_CLUSTER_RESOURCE_ID}|${DSQL_CLUSTER_RESOURCE_ID}|g" \
        -e "s|\${DSQL_TABLES}|${DSQL_TABLES}|g" \
        -e "s|\${DSQL_POLL_INTERVAL_MS}|${DSQL_POLL_INTERVAL_MS}|g" \
        -e "s|\${DSQL_BATCH_SIZE}|${DSQL_BATCH_SIZE}|g" \
        -e "s|\${TOPIC_PREFIX}|${TOPIC_PREFIX}|g" \
        -e "s|\${DB_SERVER_NAME}|${DB_SERVER_NAME}|g" \
        "$CONNECTOR_CONFIG" > "$TEMP_CONFIG"
fi

echo -e "${GREEN}✓ Configuration prepared${NC}"

# Display configuration (without secrets)
echo ""
echo -e "${CYAN}Connector Configuration (secrets hidden):${NC}"
jq -r '.config | to_entries | map(select(.key | contains("password") or contains("secret") or contains("key")) | .value = "***") | .[] | "\(.key)=\(.value)"' "$TEMP_CONFIG" 2>/dev/null | head -20

echo ""
echo -e "${BLUE}Step 3: Creating topic for CDC events...${NC}"

# Create topic if it doesn't exist
TOPIC_NAME="${TOPIC_PREFIX}.event_headers"
if confluent kafka topic describe "$TOPIC_NAME" &> /dev/null; then
    echo -e "${YELLOW}⚠ Topic '$TOPIC_NAME' already exists${NC}"
else
    confluent kafka topic create "$TOPIC_NAME" --partitions 3 --retention-ms -1 2>/dev/null || true
    echo -e "${GREEN}✓ Topic created${NC}"
fi

# Also create the routed topic
ROUTED_TOPIC="raw-event-headers"
if confluent kafka topic describe "$ROUTED_TOPIC" &> /dev/null; then
    echo -e "${YELLOW}⚠ Topic '$ROUTED_TOPIC' already exists${NC}"
else
    confluent kafka topic create "$ROUTED_TOPIC" --partitions 3 --retention-ms -1 2>/dev/null || true
    echo -e "${GREEN}✓ Routed topic created${NC}"
fi

echo ""
echo -e "${BLUE}Step 4: Deploying connector...${NC}"

# Note: Custom connectors need to be uploaded to Confluent Cloud first
# For now, we'll provide instructions and try REST API deployment
echo -e "${CYAN}Attempting deployment via Confluent Cloud...${NC}"

# Check if we have CONFLUENT_API_KEY for REST API
if [ -n "$CONFLUENT_API_KEY" ] && [ -n "$CONFLUENT_API_SECRET" ]; then
    # Try REST API deployment
    CONNECT_ENDPOINT=$(confluent connect cluster describe --output json 2>/dev/null | jq -r '.endpoint' || echo "")
    
    if [ -n "$CONNECT_ENDPOINT" ]; then
        echo -e "${CYAN}Deploying via REST API...${NC}"
        RESPONSE=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -u "$CONFLUENT_API_KEY:$CONFLUENT_API_SECRET" \
            -d @"$TEMP_CONFIG" \
            "$CONNECT_ENDPOINT/connectors" 2>&1)
        
        if echo "$RESPONSE" | jq -e '.name' &> /dev/null; then
            echo -e "${GREEN}✓ Connector deployed successfully via REST API!${NC}"
        else
            echo -e "${YELLOW}⚠ REST API deployment failed:${NC}"
            echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
            echo ""
            echo -e "${CYAN}Please deploy via Confluent Cloud Console:${NC}"
            echo "  1. Visit: https://confluent.cloud/environments/$ENV_ID/connectors"
            echo "  2. Click 'Add connector'"
            echo "  3. Select 'Custom connector' or upload the JAR"
            echo "  4. Use configuration from: $CONNECTOR_CONFIG"
            rm -f "$TEMP_CONFIG"
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ Connect cluster endpoint not found${NC}"
        echo ""
        echo -e "${CYAN}Please deploy via Confluent Cloud Console:${NC}"
        echo "  1. Visit: https://confluent.cloud/environments/$ENV_ID/connectors"
        echo "  2. Click 'Add connector'"
        echo "  3. Select 'Custom connector' or upload the JAR"
        echo "  4. Use configuration from: $CONNECTOR_CONFIG"
        rm -f "$TEMP_CONFIG"
        exit 0
    fi
else
    echo -e "${YELLOW}⚠ CONFLUENT_API_KEY not set. Using manual deployment instructions...${NC}"
    echo ""
    echo -e "${CYAN}Please deploy via Confluent Cloud Console:${NC}"
    echo "  1. Visit: https://confluent.cloud/environments/$ENV_ID/connectors"
    echo "  2. Click 'Add connector'"
    echo "  3. Select 'Custom connector'"
    echo "  4. Upload the connector JAR: debezium-connector-dsql/build/libs/debezium-connector-dsql-1.0.0.jar"
    echo "  5. Configure with these key settings:"
    echo "     - Connector class: io.debezium.connector.dsql.DsqlConnector"
    echo "     - DSQL endpoint: $DSQL_ENDPOINT_PRIMARY"
    echo "     - IAM username: $DSQL_IAM_USERNAME"
    echo "     - Database: $DSQL_DATABASE_NAME"
    echo "     - Tables: $DSQL_TABLES"
    echo ""
    echo "Full config available at: $CONNECTOR_CONFIG"
    echo "Temporary config with substitutions: $TEMP_CONFIG"
    rm -f "$TEMP_CONFIG"
    exit 0
fi

# Clean up temp files
rm -f "$TEMP_CONFIG"

echo ""
echo -e "${BLUE}Step 5: Checking connector status...${NC}"
sleep 5

# Check connector status
CONNECTOR_ID=$(confluent connect list --output json 2>/dev/null | jq -r ".[] | select(.name == \"$CONNECTOR_NAME\") | .id" | head -1 || echo "")

if [ -n "$CONNECTOR_ID" ]; then
    CONNECTOR_STATUS=$(confluent connect describe "$CONNECTOR_ID" --output json 2>/dev/null | jq -r '.status.connector.state' || echo "unknown")
    
    if [ "$CONNECTOR_STATUS" = "RUNNING" ]; then
        echo -e "${GREEN}✓ Connector is RUNNING${NC}"
    else
        echo -e "${YELLOW}⚠ Connector status: $CONNECTOR_STATUS${NC}"
        echo "  Check logs: confluent connect logs $CONNECTOR_ID"
    fi
else
    echo -e "${YELLOW}⚠ Could not find connector after deployment${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deployment Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Useful commands:${NC}"
echo "  List connectors: confluent connect list"
echo "  Check status:    confluent connect describe <connector-id>"
echo "  View logs:       confluent connect logs <connector-id>"
echo "  Monitor topic:   confluent kafka topic consume raw-event-headers --from-beginning"
echo ""
