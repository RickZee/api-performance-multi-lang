#!/bin/bash
# Deploy Confluent Cloud Managed PostgreSQL CDC Connector for event_headers table
# Based on archive/cdc-streaming/scripts/deploy-confluent-postgres-cdc-connector.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

CONNECTOR_CONFIG="$SCRIPT_DIR/../connectors/postgres-cdc-source-event-headers-confluent-cloud.json"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploy Event Headers CDC Connector${NC}"
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
ENV_ID="${CONFLUENT_ENV_ID:-$(confluent environment list --output json 2>/dev/null | jq -r '.[0].id' 2>/dev/null || echo 'env-q9n81p')}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-$(confluent kafka cluster list --output json 2>/dev/null | jq -r '.[0].id' 2>/dev/null || echo 'lkc-rno3vp')}"

if [ -z "$ENV_ID" ]; then
    echo -e "${RED}✗ No environment found${NC}"
    exit 1
fi

if [ -z "$CLUSTER_ID" ]; then
    echo -e "${RED}✗ No Kafka cluster found${NC}"
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
REQUIRED_VARS=("KAFKA_API_KEY" "KAFKA_API_SECRET" "DB_HOSTNAME" "DB_USERNAME" "DB_PASSWORD" "DB_NAME")

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
    echo "  export DB_HOSTNAME='your-db-host'"
    echo "  export DB_USERNAME='postgres'"
    echo "  export DB_PASSWORD='password'"
    echo "  export DB_NAME='car_entities'"
    echo "  export TABLE_INCLUDE_LIST='public.event_headers'"
    exit 1
fi

# Set defaults
export TABLE_INCLUDE_LIST="${TABLE_INCLUDE_LIST:-public.event_headers}"
export TOPIC_PREFIX="${TOPIC_PREFIX:-aurora-cdc}"
export SLOT_NAME="${SLOT_NAME:-event_headers_cdc_slot}"
export DB_SERVER_NAME="${DB_SERVER_NAME:-aurora-postgres-cdc}"
export DB_PORT="${DB_PORT:-5432}"

# Create a temporary config file with environment variables substituted
TEMP_CONFIG=$(mktemp)
envsubst < "$CONNECTOR_CONFIG" > "$TEMP_CONFIG"

echo -e "${GREEN}✓ Configuration prepared${NC}"

# Display configuration (without secrets)
echo ""
echo -e "${CYAN}Connector Configuration (secrets hidden):${NC}"
jq -r '.config | to_entries | map(select(.key | contains("password") or contains("secret")) | .value = "***") | .[] | "\(.key)=\(.value)"' "$TEMP_CONFIG" 2>/dev/null | head -15

echo ""
echo -e "${BLUE}Step 3: Deploying connector...${NC}"

# Note: The newer Confluent CLI doesn't support --plugin flag directly
# We need to use the Confluent Cloud UI or REST API
# For now, provide instructions and try alternative methods

echo -e "${CYAN}Attempting deployment via Confluent Cloud...${NC}"

# Try to create connector - the CLI syntax may vary
# First, let's check what connect commands are available
if confluent connect create --help &>/dev/null; then
    # Try the create command if it exists
    if confluent connect create \
        --config-file "$TEMP_CONFIG" \
        --kafka-cluster "$CLUSTER_ID" 2>&1; then
        echo -e "${GREEN}✓ Connector deployed successfully!${NC}"
    else
        echo -e "${YELLOW}⚠ CLI deployment failed. Using alternative method...${NC}"
        echo ""
        echo -e "${CYAN}Please deploy via Confluent Cloud Console:${NC}"
        echo "  1. Visit: https://confluent.cloud/environments/$ENV_ID/connectors"
        echo "  2. Click 'Add connector'"
        echo "  3. Select 'PostgresCdcSource'"
        echo "  4. Use configuration from: $CONNECTOR_CONFIG"
        echo ""
        echo "Or set CONFLUENT_API_KEY and CONFLUENT_API_SECRET for REST API deployment"
        rm -f "$TEMP_CONFIG"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ Direct CLI deployment not available in this CLI version${NC}"
    echo ""
    echo -e "${CYAN}Please deploy via Confluent Cloud Console:${NC}"
    echo "  1. Visit: https://confluent.cloud/environments/$ENV_ID/connectors"
    echo "  2. Click 'Add connector'"
    echo "  3. Select 'PostgresCdcSource'"
    echo "  4. Configure with these key settings:"
    echo "     - Table include list: $TABLE_INCLUDE_LIST"
    echo "     - Database: $DB_NAME"
    echo "     - Hostname: $DB_HOSTNAME"
    echo ""
    echo "Full config available at: $CONNECTOR_CONFIG"
    rm -f "$TEMP_CONFIG"
    exit 0
fi

# Clean up temp files
rm -f "$TEMP_CONFIG"

echo ""
echo -e "${BLUE}Step 4: Checking connector status...${NC}"
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
echo ""
