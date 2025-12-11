#!/bin/bash
# Verify and Update CDC Connector Configuration
# Checks if connector has ExtractNewRecordState transform and updates if needed

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

# Configuration
RECOMMENDED_CONFIG="$PROJECT_ROOT/cdc-streaming/connectors/postgres-cdc-source-business-events-confluent-cloud-fixed.json"
BASIC_CONFIG="$PROJECT_ROOT/cdc-streaming/connectors/postgres-cdc-source-business-events-confluent-cloud.json"
CONNECTOR_NAME="postgres-cdc-source-business-events"

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Verify and Update CDC Connector Configuration${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Step 1: Check if connector exists via topics
echo -e "${BLUE}Step 1: Checking for existing connector...${NC}"

# Check if raw-business-events topic exists (indicates connector may exist)
TOPIC_EXISTS=$(confluent kafka topic list 2>/dev/null | grep -c "raw-business-events" || echo "0")

if [ "$TOPIC_EXISTS" -gt 0 ]; then
    echo -e "${GREEN}✓ Found raw-business-events topic (connector likely exists)${NC}"
else
    echo -e "${YELLOW}⚠ raw-business-events topic not found${NC}"
    echo "  Connector may not be deployed yet"
fi
echo ""

# Step 2: Check connector via Confluent Cloud Console
echo -e "${BLUE}Step 2: Connector Status Check${NC}"
echo ""
echo -e "${CYAN}Please check connector status via Confluent Cloud Console:${NC}"
echo "  https://confluent.cloud/environments/${CONFLUENT_ENV_ID:-env-q9n81p}/connectors"
echo ""
echo -e "${YELLOW}Look for connector named: ${CONNECTOR_NAME}${NC}"
echo ""
read -p "Does the connector exist? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Connector does not exist. Deploying recommended configuration...${NC}"
    echo ""
    echo -e "${CYAN}To deploy the connector:${NC}"
    echo "  1. Use the deployment script:"
    echo "     ./cdc-streaming/scripts/deploy-connector-with-unwrap.sh"
    echo ""
    echo "  2. Or deploy via Confluent Cloud Console using:"
    echo "     $RECOMMENDED_CONFIG"
    echo ""
    exit 0
fi

# Step 3: Verify configuration
echo -e "${BLUE}Step 3: Verifying connector configuration...${NC}"
echo ""
echo -e "${CYAN}In Confluent Cloud Console, check the connector configuration:${NC}"
echo "  1. Navigate to the connector"
echo "  2. Click 'Edit configuration'"
echo "  3. Check for these settings:"
echo ""
echo -e "${YELLOW}Required Configuration:${NC}"
echo "  ✓ transforms: \"unwrap,route\""
echo "  ✓ transforms.unwrap.type: \"io.debezium.transforms.ExtractNewRecordState\""
echo "  ✓ transforms.unwrap.add.fields: \"op,table,ts_ms\""
echo "  ✓ transforms.unwrap.add.fields.prefix: \"__\""
echo ""
read -p "Does the connector have the ExtractNewRecordState transform? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}✓ Connector has correct configuration${NC}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Verify Flink statements are processing events"
    echo "  2. Check filtered topics for events"
    echo "  3. Monitor consumer logs"
    exit 0
else
    echo -e "${YELLOW}⚠ Connector needs to be updated${NC}"
    echo ""
    echo -e "${BLUE}Step 4: Update Connector Configuration${NC}"
    echo ""
    echo -e "${CYAN}Option 1: Update via Confluent Cloud Console (Recommended)${NC}"
    echo "  1. Navigate to the connector"
    echo "  2. Click 'Edit configuration'"
    echo "  3. Add/update these settings:"
    echo ""
    echo "     transforms: unwrap,route"
    echo "     transforms.unwrap.type: io.debezium.transforms.ExtractNewRecordState"
    echo "     transforms.unwrap.drop.tombstones: false"
    echo "     transforms.unwrap.add.fields: op,table,ts_ms"
    echo "     transforms.unwrap.add.fields.prefix: __"
    echo "     transforms.route.type: io.confluent.connect.cloud.transforms.TopicRegexRouter"
    echo "     transforms.route.regex: aurora-postgres-cdc\\.public\\.business_events"
    echo "     transforms.route.replacement: raw-business-events"
    echo ""
    echo "  4. Save and restart the connector"
    echo ""
    echo -e "${CYAN}Option 2: Reference the recommended config file:${NC}"
    echo "  $RECOMMENDED_CONFIG"
    echo ""
    echo -e "${YELLOW}⚠ Important: After updating, the connector will restart and may reprocess events${NC}"
    echo ""
    read -p "Press Enter after updating the connector configuration..."
    echo ""
    echo -e "${GREEN}✓ Connector configuration updated${NC}"
    echo ""
    echo -e "${CYAN}Step 5: Verify Update${NC}"
    echo "  1. Check connector status is RUNNING"
    echo "  2. Verify Flink statements start processing events"
    echo "  3. Check filtered topics receive events"
    echo ""
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Verification Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Useful Commands:${NC}"
echo "  Check Flink statements: confluent flink statement list"
echo "  Check topics: confluent kafka topic list"
echo "  View connector logs: (via Confluent Cloud Console)"
echo ""
