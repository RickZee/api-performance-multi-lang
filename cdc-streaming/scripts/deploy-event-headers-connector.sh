#!/bin/bash
# Deploy PostgreSQL CDC Source V2 (Debezium) Connector for event_headers table
# Following CONFLUENT_CLOUD_SETUP_GUIDE.md instructions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

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
    echo -e "${RED}✗ Confluent CLI not installed${NC}"
    echo "  Install with: brew install confluentinc/tap/cli"
    exit 1
fi

# Source environment variables
if [ -f "$PROJECT_ROOT/.env.aurora" ]; then
    source "$PROJECT_ROOT/.env.aurora"
fi

# Get environment and cluster
ENV_ID="${CONFLUENT_ENV_ID:-$(confluent environment list --output json 2>/dev/null | jq -r '.[0].id' 2>/dev/null || echo 'env-q9n81p')}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-$(confluent kafka cluster list --output json 2>/dev/null | jq -r '.[0].id' 2>/dev/null || echo 'lkc-rno3vp')}"

echo -e "${CYAN}Configuration:${NC}"
echo "  Environment ID: $ENV_ID"
echo "  Cluster ID: $CLUSTER_ID"
echo ""

# Check required environment variables
REQUIRED_VARS=("DB_HOSTNAME" "DB_PASSWORD" "DB_NAME")
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
    echo -e "${CYAN}Source .env.aurora file:${NC}"
    echo "  source .env.aurora"
    exit 1
fi

# Set defaults
export TABLE_INCLUDE_LIST="${TABLE_INCLUDE_LIST:-public.event_headers}"
export SLOT_NAME="${SLOT_NAME:-event_headers_v2_debezium_slot}"
export TOPIC_PREFIX="${TOPIC_PREFIX:-aurora-postgres-cdc}"
export DB_SERVER_NAME="${DB_SERVER_NAME:-aurora-postgres-cdc}"
export DB_PORT="${DB_PORT:-5432}"
export DB_SSLMODE="${DB_SSLMODE:-require}"
export DB_USERNAME="${DB_USERNAME:-postgres}"
export SNAPSHOT_MODE="${SNAPSHOT_MODE:-when_needed}"

# Get Kafka API keys from existing connector or prompt
echo -e "${BLUE}Step 1: Getting Kafka API credentials...${NC}"
if [ -z "$KAFKA_API_KEY" ] || [ -z "$KAFKA_API_SECRET" ]; then
    # Try to get from existing connector
    EXISTING_CONNECTOR=$(confluent connect cluster list --output json 2>/dev/null | jq -r '.[0].id' 2>/dev/null || echo "")
    if [ -n "$EXISTING_CONNECTOR" ]; then
        echo -e "${CYAN}  Attempting to extract from existing connector...${NC}"
        # Note: API keys are masked, so we'll need to use Confluent Cloud Console
        echo -e "${YELLOW}  ⚠ API keys are masked in connector config${NC}"
        echo -e "${CYAN}  You'll need to enter them in the Confluent Cloud Console${NC}"
    else
        echo -e "${YELLOW}  ⚠ No existing connector found to extract credentials${NC}"
    fi
    echo ""
    echo -e "${CYAN}Please get your Kafka API key and secret:${NC}"
    echo "  1. Go to: https://confluent.cloud/environments/$ENV_ID/api-keys"
    echo "  2. Find or create a Kafka API key for cluster $CLUSTER_ID"
    echo "  3. Copy the key and secret"
    echo ""
    read -p "Press Enter after you have the API key and secret..."
    echo ""
    read -sp "Enter Kafka API Key: " KAFKA_API_KEY
    echo ""
    read -sp "Enter Kafka API Secret: " KAFKA_API_SECRET
    echo ""
    export KAFKA_API_KEY
    export KAFKA_API_SECRET
else
    echo -e "${GREEN}✓ Kafka API credentials found in environment${NC}"
fi

# Create connector config
echo ""
echo -e "${BLUE}Step 2: Creating connector configuration...${NC}"
TEMP_CONFIG=$(mktemp)

python3 << 'PYEOF' > "$TEMP_CONFIG"
import json
import os
import sys

# Read template
with open('cdc-streaming/connectors/postgres-cdc-source-v2-debezium-business-events-confluent-cloud.json') as f:
    template = json.load(f)

# Get all env vars
env_vars = {
    'KAFKA_API_KEY': os.getenv('KAFKA_API_KEY', ''),
    'KAFKA_API_SECRET': os.getenv('KAFKA_API_SECRET', ''),
    'DB_HOSTNAME': os.getenv('DB_HOSTNAME', ''),
    'DB_USERNAME': os.getenv('DB_USERNAME', 'postgres'),
    'DB_PASSWORD': os.getenv('DB_PASSWORD', ''),
    'DB_NAME': os.getenv('DB_NAME', 'car_entities'),
    'TABLE_INCLUDE_LIST': os.getenv('TABLE_INCLUDE_LIST', 'public.event_headers'),
    'SLOT_NAME': os.getenv('SLOT_NAME', 'event_headers_v2_debezium_slot'),
    'TOPIC_PREFIX': os.getenv('TOPIC_PREFIX', 'aurora-postgres-cdc'),
    'DB_SERVER_NAME': os.getenv('DB_SERVER_NAME', 'aurora-postgres-cdc'),
    'DB_PORT': os.getenv('DB_PORT', '5432'),
    'DB_SSLMODE': os.getenv('DB_SSLMODE', 'require'),
    'SNAPSHOT_MODE': os.getenv('SNAPSHOT_MODE', 'when_needed'),
}

# Build config
config = template['config'].copy()
config['name'] = 'postgres-cdc-source-v2-debezium-event-headers'
config['table.include.list'] = env_vars['TABLE_INCLUDE_LIST']
config['slot.name'] = env_vars['SLOT_NAME']
config['snapshot.mode'] = env_vars['SNAPSHOT_MODE']
config['topic.prefix'] = env_vars['TOPIC_PREFIX']
config['database.server.name'] = env_vars['DB_SERVER_NAME']
config['database.hostname'] = env_vars['DB_HOSTNAME']
config['database.user'] = env_vars['DB_USERNAME']
config['database.password'] = env_vars['DB_PASSWORD']
config['database.dbname'] = env_vars['DB_NAME']
config['database.port'] = env_vars['DB_PORT']
config['database.sslmode'] = env_vars['DB_SSLMODE']
config['kafka.api.key'] = env_vars['KAFKA_API_KEY']
config['kafka.api.secret'] = env_vars['KAFKA_API_SECRET']
config['transforms.route.regex'] = f"{env_vars['TOPIC_PREFIX']}\\.public\\.event_headers"

# Write config
json.dump({'config': config}, sys.stdout, indent=2)
PYEOF

echo -e "${GREEN}✓ Configuration prepared${NC}"
echo ""

# Display key settings (without secrets)
echo -e "${CYAN}Key Configuration Settings:${NC}"
cat "$TEMP_CONFIG" | jq -r '.config | to_entries | map(select(.key | contains("password") or contains("secret") or contains("key")) | .value = "***") | .[] | "  \(.key): \(.value)"' 2>/dev/null | grep -E "(name|table|slot|snapshot|route)" | head -10
echo ""

# Check if connector already exists
CONNECTOR_NAME="postgres-cdc-source-v2-debezium-event-headers"
EXISTING_CONNECTOR=$(confluent connect cluster list --output json 2>/dev/null | jq -r ".[] | select(.name == \"$CONNECTOR_NAME\") | .id" 2>/dev/null | head -1 || echo "")

if [ -n "$EXISTING_CONNECTOR" ]; then
    echo -e "${YELLOW}⚠ Connector '$CONNECTOR_NAME' already exists (ID: $EXISTING_CONNECTOR)${NC}"
    read -p "Delete and recreate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Deleting existing connector...${NC}"
        confluent connect cluster pause "$EXISTING_CONNECTOR" 2>/dev/null || true
        sleep 3
        confluent connect cluster delete "$EXISTING_CONNECTOR" --force 2>/dev/null || true
        echo -e "${GREEN}✓ Existing connector deleted${NC}"
        EXISTING_CONNECTOR=""
    else
        echo "Aborted."
        rm -f "$TEMP_CONFIG"
        exit 0
    fi
fi

echo ""
echo -e "${BLUE}Step 3: Deploying connector via Confluent Cloud Console${NC}"
echo ""
echo -e "${YELLOW}Note: PostgreSQL CDC Source V2 (Debezium) must be deployed via Console${NC}"
echo ""
echo -e "${CYAN}Instructions:${NC}"
echo "  1. Open: https://confluent.cloud/environments/$ENV_ID/connectors"
echo "  2. Click 'Add connector'"
echo "  3. Search for: 'PostgreSQL CDC Source V2 (Debezium)'"
echo "  4. Select it and click 'Continue'"
echo ""
echo -e "${CYAN}Configuration Values:${NC}"
echo ""
cat "$TEMP_CONFIG" | jq -r '.config | to_entries | .[] | "  \(.key): \(.value)"' 2>/dev/null | grep -v "password\|secret\|key" | head -20
echo ""
echo -e "${CYAN}Critical Settings:${NC}"
echo "  - Connector class: PostgresCdcSourceV2"
echo "  - Table include list: $TABLE_INCLUDE_LIST"
echo "  - Slot name: $SLOT_NAME"
echo "  - Snapshot mode: $SNAPSHOT_MODE"
echo "  - Transforms: unwrap,route"
echo "  - Transform route regex: ${TOPIC_PREFIX}\\.public\\.event_headers"
echo "  - Transform route replacement: raw-event-headers"
echo ""
echo -e "${CYAN}Full configuration saved to:${NC}"
echo "  $TEMP_CONFIG"
echo ""
read -p "Press Enter after deploying the connector in the Console..."
echo ""

# Clean up temp file
rm -f "$TEMP_CONFIG"

# Verify connector
echo -e "${BLUE}Step 4: Verifying connector deployment...${NC}"
sleep 10

NEW_CONNECTOR_ID=$(confluent connect cluster list --output json 2>/dev/null | jq -r ".[] | select(.name == \"$CONNECTOR_NAME\") | .id" 2>/dev/null | head -1 || echo "")

if [ -n "$NEW_CONNECTOR_ID" ]; then
    echo -e "${GREEN}✓ Connector found: $NEW_CONNECTOR_ID${NC}"
    echo ""
    
    # Check status
    CONNECTOR_STATUS=$(confluent connect cluster describe "$NEW_CONNECTOR_ID" --output json 2>/dev/null | jq -r '.connector.status // "unknown"' 2>/dev/null || echo "unknown")
    
    echo -e "${CYAN}Connector Status: $CONNECTOR_STATUS${NC}"
    
    if [ "$CONNECTOR_STATUS" = "RUNNING" ]; then
        echo -e "${GREEN}✓✓✓ Connector is RUNNING!${NC}"
    else
        echo -e "${YELLOW}⚠ Connector status: $CONNECTOR_STATUS${NC}"
        echo "  Check logs: confluent connect cluster logs $NEW_CONNECTOR_ID"
    fi
    
    echo ""
    echo -e "${CYAN}Connector Details:${NC}"
    confluent connect cluster describe "$NEW_CONNECTOR_ID" 2>&1 | head -25
    
else
    echo -e "${YELLOW}⚠ Connector not found via CLI${NC}"
    echo "  Please verify in Console: https://confluent.cloud/environments/$ENV_ID/connectors"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Wait for connector to reach RUNNING state (may take 1-2 minutes)"
echo "  2. Verify replication slot was created:"
echo "     python3 cdc-streaming/scripts/fix-postgres-replication-privileges.py"
echo "  3. Check events in topic:"
echo "     confluent kafka topic consume raw-event-headers --max-messages 5"
echo "  4. Verify events have __op, __table, __ts_ms fields"
echo ""
