#!/bin/bash
# Update existing connector to capture from event_headers table
# Fixes WAL issue and updates table configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Parse arguments
AUTO_YES=false
if [[ "$1" == "--yes" ]] || [[ "$1" == "-y" ]]; then
    AUTO_YES=true
fi

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Update Connector to Event Headers${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Existing connector ID
EXISTING_CONNECTOR_ID="lcc-70rxxp"
EXISTING_CONNECTOR_NAME="postgres-cdc-source-v2-debezium-business-events"

# Check if connector exists
if ! confluent connect cluster describe "$EXISTING_CONNECTOR_ID" &>/dev/null; then
    echo -e "${RED}✗ Connector $EXISTING_CONNECTOR_ID not found${NC}"
    echo "Listing available connectors..."
    confluent connect cluster list
    exit 1
fi

echo -e "${CYAN}Current Connector:${NC}"
echo "  ID: $EXISTING_CONNECTOR_ID"
echo "  Name: $EXISTING_CONNECTOR_NAME"
echo ""

# Get current connector config
echo -e "${BLUE}Step 1: Reading current connector configuration...${NC}"
CURRENT_CONFIG=$(confluent connect cluster describe "$EXISTING_CONNECTOR_ID" --output json 2>/dev/null)

if [ -z "$CURRENT_CONFIG" ]; then
    echo -e "${RED}✗ Failed to read connector configuration${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Configuration loaded${NC}"
echo ""

# Note: We'll extract current config values, so env vars are optional
# But we'll check if we have the minimum needed
echo -e "${CYAN}Note: Will use current connector config values if env vars not set${NC}"

# Set defaults for event_headers
export TABLE_INCLUDE_LIST="${TABLE_INCLUDE_LIST:-public.event_headers}"
export SLOT_NAME="${SLOT_NAME:-event_headers_v2_debezium_slot}"
export TOPIC_PREFIX="${TOPIC_PREFIX:-aurora-postgres-cdc}"
export DB_SERVER_NAME="${DB_SERVER_NAME:-aurora-postgres-cdc}"
export DB_PORT="${DB_PORT:-5432}"
export DB_SSLMODE="${DB_SSLMODE:-require}"

# Create updated config file
echo -e "${BLUE}Step 2: Creating updated configuration...${NC}"
TEMP_CONFIG=$(mktemp)

# Extract ALL current config values to preserve secrets and connection info
# Note: configs is an array of {config: "key", value: "value"} objects
echo -e "${CYAN}Extracting current connector configuration values...${NC}"
get_config_value() {
    echo "$CURRENT_CONFIG" | jq -r ".configs[] | select(.config == \"$1\") | .value // empty"
}

CURRENT_DB_HOSTNAME=$(get_config_value "database.hostname")
CURRENT_DB_USER=$(get_config_value "database.user")
CURRENT_DB_PASSWORD=$(get_config_value "database.password")
CURRENT_DB_NAME=$(get_config_value "database.dbname")
CURRENT_DB_PORT=$(get_config_value "database.port")
CURRENT_DB_SSLMODE=$(get_config_value "database.sslmode")
CURRENT_KAFKA_KEY=$(get_config_value "kafka.api.key")
CURRENT_KAFKA_SECRET=$(get_config_value "kafka.api.secret")
CURRENT_DB_SERVER_NAME=$(get_config_value "database.server.name")
CURRENT_TOPIC_PREFIX=$(get_config_value "topic.prefix")

# Set defaults if empty
CURRENT_DB_PORT="${CURRENT_DB_PORT:-5432}"
CURRENT_DB_SSLMODE="${CURRENT_DB_SSLMODE:-require}"
CURRENT_DB_SERVER_NAME="${CURRENT_DB_SERVER_NAME:-aurora-postgres-cdc}"
CURRENT_TOPIC_PREFIX="${CURRENT_TOPIC_PREFIX:-aurora-postgres-cdc}"

# Use current values if env vars not set
export DB_HOSTNAME="${DB_HOSTNAME:-$CURRENT_DB_HOSTNAME}"
export DB_USERNAME="${DB_USERNAME:-$CURRENT_DB_USER}"
export DB_PASSWORD="${DB_PASSWORD:-$CURRENT_DB_PASSWORD}"
export DB_NAME="${DB_NAME:-$CURRENT_DB_NAME}"
export DB_PORT="${DB_PORT:-$CURRENT_DB_PORT}"
export DB_SSLMODE="${DB_SSLMODE:-$CURRENT_DB_SSLMODE}"
export KAFKA_API_KEY="${KAFKA_API_KEY:-$CURRENT_KAFKA_KEY}"
export KAFKA_API_SECRET="${KAFKA_API_SECRET:-$CURRENT_KAFKA_SECRET}"
export DB_SERVER_NAME="${DB_SERVER_NAME:-$CURRENT_DB_SERVER_NAME}"
export TOPIC_PREFIX="${TOPIC_PREFIX:-$CURRENT_TOPIC_PREFIX}"

# Verify we have required values
if [ -z "$DB_HOSTNAME" ] || [ -z "$DB_PASSWORD" ] || [ -z "$KAFKA_API_KEY" ] || [ -z "$KAFKA_API_SECRET" ]; then
    echo -e "${RED}✗ Failed to extract required configuration values from current connector${NC}"
    echo "Please set environment variables:"
    echo "  DB_HOSTNAME, DB_PASSWORD, KAFKA_API_KEY, KAFKA_API_SECRET"
    exit 1
fi

# Use the event_headers config as base
CONNECTOR_CONFIG_FILE="$SCRIPT_DIR/../connectors/postgres-cdc-source-v2-debezium-business-events-confluent-cloud.json"

if [ ! -f "$CONNECTOR_CONFIG_FILE" ]; then
    echo -e "${RED}✗ Connector config file not found: $CONNECTOR_CONFIG_FILE${NC}"
    exit 1
fi

# Build config using jq to avoid envsubst issues with ${VAR:-default} syntax
cp "$CONNECTOR_CONFIG_FILE" "$TEMP_CONFIG"

# Update all config values using jq
jq --arg hostname "$DB_HOSTNAME" \
   --arg user "$DB_USERNAME" \
   --arg password "$DB_PASSWORD" \
   --arg dbname "$DB_NAME" \
   --arg port "$DB_PORT" \
   --arg sslmode "$DB_SSLMODE" \
   --arg server_name "$DB_SERVER_NAME" \
   --arg kafka_key "$KAFKA_API_KEY" \
   --arg kafka_secret "$KAFKA_API_SECRET" \
   --arg topic_prefix "$TOPIC_PREFIX" \
   '.config."database.hostname" = $hostname |
    .config."database.user" = $user |
    .config."database.password" = $password |
    .config."database.dbname" = $dbname |
    .config."database.port" = $port |
    .config."database.sslmode" = $sslmode |
    .config."database.server.name" = $server_name |
    .config."kafka.api.key" = $kafka_key |
    .config."kafka.api.secret" = $kafka_secret |
    .config."topic.prefix" = $topic_prefix' \
   "$TEMP_CONFIG" > "${TEMP_CONFIG}.tmp" && mv "${TEMP_CONFIG}.tmp" "$TEMP_CONFIG"

# Override snapshot.mode to when_needed to fix WAL issue
jq '.config."snapshot.mode" = "when_needed"' "$TEMP_CONFIG" > "${TEMP_CONFIG}.tmp" && mv "${TEMP_CONFIG}.tmp" "$TEMP_CONFIG"

# Ensure table.include.list is set correctly
jq '.config."table.include.list" = "public.event_headers"' "$TEMP_CONFIG" > "${TEMP_CONFIG}.tmp" && mv "${TEMP_CONFIG}.tmp" "$TEMP_CONFIG"

# Ensure slot.name is set correctly
jq ".config.\"slot.name\" = \"$SLOT_NAME\"" "$TEMP_CONFIG" > "${TEMP_CONFIG}.tmp" && mv "${TEMP_CONFIG}.tmp" "$TEMP_CONFIG"

# Ensure route regex matches event_headers
jq '.config."transforms.route.regex" = "aurora-postgres-cdc\\.public\\.event_headers"' "$TEMP_CONFIG" > "${TEMP_CONFIG}.tmp" && mv "${TEMP_CONFIG}.tmp" "$TEMP_CONFIG"

echo -e "${GREEN}✓ Configuration prepared${NC}"
echo ""

# Display key changes
echo -e "${CYAN}Key Configuration Changes:${NC}"
echo "  table.include.list: public.event_headers"
echo "  slot.name: $SLOT_NAME"
echo "  snapshot.mode: when_needed (fixes WAL issue)"
echo "  transforms.route.regex: aurora-postgres-cdc\\.public\\.event_headers"
echo "  transforms.route.replacement: raw-event-headers"
echo ""

# Confirm update
if [ "$AUTO_YES" = false ]; then
    read -p "Update connector with this configuration? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        rm -f "$TEMP_CONFIG"
        exit 0
    fi
else
    echo -e "${CYAN}Auto-confirming update (--yes flag)${NC}"
fi

# Update connector
echo ""
echo -e "${BLUE}Step 3: Updating connector...${NC}"

if confluent connect cluster update "$EXISTING_CONNECTOR_ID" --config-file "$TEMP_CONFIG" 2>&1; then
    echo -e "${GREEN}✓ Connector updated successfully${NC}"
else
    echo -e "${RED}✗ Failed to update connector${NC}"
    echo "You may need to update via Confluent Cloud Console:"
    echo "  1. Navigate to the connector"
    echo "  2. Edit configuration"
    echo "  3. Update these key settings:"
    echo "     - table.include.list: public.event_headers"
    echo "     - slot.name: $SLOT_NAME"
    echo "     - snapshot.mode: when_needed"
    echo "     - transforms.route.regex: aurora-postgres-cdc\\.public\\.event_headers"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

rm -f "$TEMP_CONFIG"

# Wait for connector to restart
echo ""
echo -e "${BLUE}Step 4: Waiting for connector to restart...${NC}"
sleep 10

# Check connector status
echo ""
echo -e "${BLUE}Step 5: Checking connector status...${NC}"
CONNECTOR_STATUS=$(confluent connect cluster describe "$EXISTING_CONNECTOR_ID" --output json 2>/dev/null | jq -r '.status.connector.state' 2>/dev/null || echo "unknown")

if [ "$CONNECTOR_STATUS" = "RUNNING" ]; then
    echo -e "${GREEN}✓ Connector is RUNNING${NC}"
elif [ "$CONNECTOR_STATUS" = "FAILED" ]; then
    echo -e "${RED}✗ Connector is FAILED${NC}"
    echo ""
    echo "Check connector logs:"
    echo "  confluent connect cluster logs $EXISTING_CONNECTOR_ID"
    echo ""
    echo "View connector details:"
    echo "  confluent connect cluster describe $EXISTING_CONNECTOR_ID"
else
    echo -e "${YELLOW}⚠ Connector status: $CONNECTOR_STATUS${NC}"
    echo "  Check logs: confluent connect cluster logs $EXISTING_CONNECTOR_ID"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Update Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Monitor connector: confluent connect cluster describe $EXISTING_CONNECTOR_ID"
echo "  2. Check logs: confluent connect cluster logs $EXISTING_CONNECTOR_ID"
echo "  3. Verify events in raw-event-headers topic"
echo "  4. Update Flink source table to use raw-event-headers"
echo ""
