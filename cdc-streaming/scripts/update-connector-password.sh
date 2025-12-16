#!/bin/bash
# Update Connector Database Password
# Updates the connector with the correct database password from .env.aurora

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

CONNECTOR_ID="${1:-lcc-70rxxp}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Update Connector Database Password${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Get password from .env.aurora
if [ -f "$PROJECT_ROOT/.env.aurora" ]; then
    DB_PASSWORD=$(grep "^export DB_PASSWORD=" "$PROJECT_ROOT/.env.aurora" 2>/dev/null | cut -d'"' -f2 || echo "")
fi

if [ -z "$DB_PASSWORD" ]; then
    echo -e "${RED}✗ Database password not found in .env.aurora${NC}"
    echo "  Please ensure .env.aurora exists with DB_PASSWORD"
    exit 1
fi

echo -e "${CYAN}Connector: $CONNECTOR_ID${NC}"
echo -e "${CYAN}Password length: ${#DB_PASSWORD} characters${NC}"
echo ""

# Get current connector config
echo -e "${BLUE}Step 1: Reading current connector configuration...${NC}"
CURRENT_CONFIG=$(confluent connect cluster describe "$CONNECTOR_ID" --output json 2>/dev/null)

if [ -z "$CURRENT_CONFIG" ]; then
    echo -e "${RED}✗ Failed to read connector configuration${NC}"
    exit 1
fi

# Extract all config values
get_config_value() {
    echo "$CURRENT_CONFIG" | jq -r ".configs[] | select(.config == \"$1\") | .value // empty"
}

# Get all current values
DB_HOSTNAME=$(get_config_value "database.hostname")
DB_USER=$(get_config_value "database.user")
DB_NAME=$(get_config_value "database.dbname")
DB_PORT=$(get_config_value "database.port")
DB_SSLMODE=$(get_config_value "database.sslmode")
KAFKA_KEY=$(get_config_value "kafka.api.key")
KAFKA_SECRET=$(get_config_value "kafka.api.secret")
DB_SERVER_NAME=$(get_config_value "database.server.name")
TOPIC_PREFIX=$(get_config_value "topic.prefix")
SLOT_NAME=$(get_config_value "slot.name")
SNAPSHOT_MODE=$(get_config_value "snapshot.mode")
TABLE_INCLUDE=$(get_config_value "table.include.list")

# Create updated config
echo -e "${BLUE}Step 2: Creating updated configuration...${NC}"
TEMP_CONFIG=$(mktemp)

# Use the event_headers config as base
CONNECTOR_CONFIG_FILE="$SCRIPT_DIR/../connectors/postgres-cdc-source-v2-debezium-business-events-confluent-cloud.json"

if [ ! -f "$CONNECTOR_CONFIG_FILE" ]; then
    echo -e "${RED}✗ Connector config file not found: $CONNECTOR_CONFIG_FILE${NC}"
    exit 1
fi

# Build config using jq
cp "$CONNECTOR_CONFIG_FILE" "$TEMP_CONFIG"

jq --arg hostname "$DB_HOSTNAME" \
   --arg user "$DB_USER" \
   --arg password "$DB_PASSWORD" \
   --arg dbname "$DB_NAME" \
   --arg port "${DB_PORT:-5432}" \
   --arg sslmode "${DB_SSLMODE:-require}" \
   --arg server_name "${DB_SERVER_NAME:-aurora-postgres-cdc}" \
   --arg kafka_key "$KAFKA_KEY" \
   --arg kafka_secret "$KAFKA_SECRET" \
   --arg topic_prefix "${TOPIC_PREFIX:-aurora-postgres-cdc}" \
   --arg slot_name "${SLOT_NAME:-event_headers_v2_debezium_slot}" \
   --arg snapshot_mode "${SNAPSHOT_MODE:-when_needed}" \
   --arg table_include "${TABLE_INCLUDE:-public.event_headers}" \
   '.config."database.hostname" = $hostname |
    .config."database.user" = $user |
    .config."database.password" = $password |
    .config."database.dbname" = $dbname |
    .config."database.port" = $port |
    .config."database.sslmode" = $sslmode |
    .config."database.server.name" = $server_name |
    .config."kafka.api.key" = $kafka_key |
    .config."kafka.api.secret" = $kafka_secret |
    .config."topic.prefix" = $topic_prefix |
    .config."slot.name" = $slot_name |
    .config."snapshot.mode" = $snapshot_mode |
    .config."table.include.list" = $table_include' \
   "$TEMP_CONFIG" > "${TEMP_CONFIG}.tmp" && mv "${TEMP_CONFIG}.tmp" "$TEMP_CONFIG"

echo -e "${GREEN}✓ Configuration prepared${NC}"
echo ""

# Update connector
echo -e "${BLUE}Step 3: Updating connector with new password...${NC}"

if confluent connect cluster update "$CONNECTOR_ID" --config-file "$TEMP_CONFIG" 2>&1; then
    echo -e "${GREEN}✓ Connector updated successfully${NC}"
else
    echo -e "${RED}✗ Failed to update connector${NC}"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

rm -f "$TEMP_CONFIG"

# Wait and check status
echo ""
echo -e "${BLUE}Step 4: Waiting for connector to restart...${NC}"
sleep 10

CONNECTOR_STATUS=$(confluent connect cluster describe "$CONNECTOR_ID" --output json 2>/dev/null | jq -r '.status.connector.state // "unknown"' 2>/dev/null || echo "unknown")

echo ""
echo -e "${BLUE}Step 5: Checking connector status...${NC}"
if [ "$CONNECTOR_STATUS" = "RUNNING" ]; then
    echo -e "${GREEN}✓ Connector is RUNNING${NC}"
elif [ "$CONNECTOR_STATUS" = "FAILED" ]; then
    echo -e "${RED}✗ Connector is still FAILED${NC}"
    echo "  Check logs: confluent connect cluster logs $CONNECTOR_ID"
else
    echo -e "${YELLOW}⚠ Connector status: $CONNECTOR_STATUS${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Password Update Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
