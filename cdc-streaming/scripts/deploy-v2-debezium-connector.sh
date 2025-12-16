#!/bin/bash
# Deploy PostgreSQL CDC Source V2 (Debezium) Connector
# Based on "Newest Fix" recommendations in archive/fix-flink.md

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ENV_ID="${CONFLUENT_ENV_ID:-env-q9n81p}"
CONFIG_FILE="$PROJECT_ROOT/cdc-streaming/connectors/postgres-cdc-source-v2-debezium-business-events-confluent-cloud.json"

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Deploy PostgreSQL CDC Source V2 (Debezium) Connector${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Note: V2 Debezium connector is a Confluent Cloud managed connector type${NC}"
echo -e "${YELLOW}and must be deployed via the Confluent Cloud Console.${NC}"
echo ""

echo -e "${BLUE}Step 1: Open Confluent Cloud Console${NC}"
echo "  https://confluent.cloud/environments/$ENV_ID/connectors"
echo ""
read -p "Press Enter after opening the Console..."
echo ""

echo -e "${BLUE}Step 2: Add New Connector${NC}"
echo "  1. Click 'Add connector' button"
echo "  2. Search for: PostgreSQL CDC Source V2 (Debezium)"
echo "  3. Select it and click 'Continue'"
echo ""
read -p "Press Enter after selecting the connector type..."
echo ""

echo -e "${BLUE}Step 3: Configure Connector${NC}"
echo ""
echo -e "${CYAN}Key Configuration Values (from config file):${NC}"
echo ""

# Extract config values (without secrets)
if [ -f "$CONFIG_FILE" ]; then
    cat "$CONFIG_FILE" | jq -r '.config | to_entries | .[] | select(.key | test("password|secret|key") | not) | "  \(.key): \(.value)"' | head -20
    echo ""
    echo -e "${CYAN}  ... (see config file for complete settings)${NC}"
else
    echo -e "${RED}  ✗ Config file not found: $CONFIG_FILE${NC}"
fi

echo ""
echo -e "${YELLOW}Critical Settings:${NC}"
echo "  - Database hostname: \${DB_HOSTNAME}"
echo "  - Database port: \${DB_PORT:-5432}"
echo "  - Database user: \${DB_USERNAME}"
echo "  - Database password: \${DB_PASSWORD}"
echo "  - Database name: \${DB_NAME}"
echo "  - Table include list: public.business_events"
echo "  - Plugin name: pgoutput"
echo "  - Replication slot name: business_events_v2_debezium_slot"
echo "  - Snapshot mode: initial"
echo "  - Output format: JSON"
echo ""

echo -e "${YELLOW}Transform Configuration (CRITICAL):${NC}"
echo "  - Transforms: unwrap,route"
echo "  - Transform unwrap type: io.debezium.transforms.ExtractNewRecordState"
echo "  - Transform unwrap add fields: op,table,ts_ms"
echo "  - Transform unwrap add fields prefix: __"
echo "  - Transform unwrap delete tombstone handling mode: rewrite"
echo "  - Transform route type: io.confluent.connect.cloud.transforms.TopicRegexRouter"
echo "  - Transform route regex: aurora-postgres-cdc\\.public\\.business_events"
echo "  - Transform route replacement: raw-business-events"
echo ""

read -p "Press Enter after configuring the connector..."
echo ""

echo -e "${BLUE}Step 4: Deploy and Verify${NC}"
echo "  1. Review all settings"
echo "  2. Click 'Launch' or 'Deploy'"
echo "  3. Wait for connector to reach RUNNING state"
echo ""
read -p "Press Enter after connector is deployed..."
echo ""

echo -e "${BLUE}Step 5: Verify Connector Status${NC}"
echo ""
echo "Checking connector status..."
if confluent connect cluster list 2>&1 | grep -q "postgres-cdc-source-v2-debezium-business-events"; then
    echo -e "${GREEN}✓ Connector found${NC}"
    confluent connect cluster list 2>&1 | grep "postgres-cdc-source-v2-debezium-business-events"
else
    echo -e "${YELLOW}⚠ Connector not found via CLI (may need to check Console)${NC}"
    echo "  Please verify in Console: https://confluent.cloud/environments/$ENV_ID/connectors"
fi

echo ""
echo -e "${BLUE}Step 6: Verify Output Format${NC}"
echo ""
echo "After connector is RUNNING, verify it outputs events with metadata fields:"
echo "  - __op (operation: 'c', 'u', 'd')"
echo "  - __table (source table name)"
echo "  - __ts_ms (timestamp)"
echo "  - __deleted (for delete events)"
echo ""
echo "To verify, consume a test message:"
echo "  confluent kafka topic consume raw-business-events --max-messages 1"
echo ""

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Deployment Guide Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Verify connector is RUNNING"
echo "  2. Check connector logs for any errors"
echo "  3. Verify events in raw-business-events topic have __op, __table, __ts_ms fields"
echo "  4. Proceed with Flink statement deployment"
echo ""


