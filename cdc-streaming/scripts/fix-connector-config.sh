#!/bin/bash
# Fix Connector Configuration - Add ExtractNewRecordState Transform
# Based on CONFLUENT_CLOUD_SETUP_GUIDE.md Issue 7

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

CONNECTOR_NAME="postgres-cdc-source-business-events"
FIXED_CONFIG="$PROJECT_ROOT/cdc-streaming/connectors/postgres-cdc-source-business-events-confluent-cloud-fixed.json"
ENV_ID="${CONFLUENT_ENV_ID:-env-q9n81p}"

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Fix Connector Configuration - Add ExtractNewRecordState Transform${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Based on: CONFLUENT_CLOUD_SETUP_GUIDE.md - Issue 7${NC}"
echo ""

# Step 1: Show the problem
echo -e "${BLUE}Step 1: Understanding the Issue${NC}"
echo ""
echo "The Flink statement requires CDC metadata fields (__op, __table, __ts_ms)"
echo "that are added by the ExtractNewRecordState transform."
echo ""
echo "If connector only has 'route' transform (not 'unwrap,route'):"
echo "  ✗ Flink filter WHERE __op = 'c' will fail"
echo "  ✗ No events will match the filter"
echo "  ✗ Filtered topics will be empty"
echo ""

# Step 2: Show required configuration
echo -e "${BLUE}Step 2: Required Configuration${NC}"
echo ""
echo "The connector MUST have these settings:"
echo ""
echo -e "${GREEN}✓ transforms: unwrap,route${NC}"
echo -e "${GREEN}✓ transforms.unwrap.type: io.debezium.transforms.ExtractNewRecordState${NC}"
echo -e "${GREEN}✓ transforms.unwrap.drop.tombstones: false${NC}"
echo -e "${GREEN}✓ transforms.unwrap.add.fields: op,table,ts_ms${NC}"
echo -e "${GREEN}✓ transforms.unwrap.add.fields.prefix: __${NC}"
echo ""

# Step 3: Instructions for fixing
echo -e "${BLUE}Step 3: How to Fix${NC}"
echo ""
echo -e "${CYAN}Option 1: Update via Confluent Cloud Console (Recommended)${NC}"
echo ""
echo "1. Open Confluent Cloud Console:"
echo "   https://confluent.cloud/environments/$ENV_ID/connectors"
echo ""
echo "2. Find connector: $CONNECTOR_NAME"
echo ""
echo "3. Click 'Edit configuration'"
echo ""
echo "4. Add/update these settings:"
echo ""
if command -v jq &> /dev/null && [ -f "$FIXED_CONFIG" ]; then
    echo "   transforms: $(jq -r '.config.transforms' "$FIXED_CONFIG")"
    echo "   transforms.unwrap.type: $(jq -r '.config."transforms.unwrap.type"' "$FIXED_CONFIG")"
    echo "   transforms.unwrap.drop.tombstones: $(jq -r '.config."transforms.unwrap.drop.tombstones"' "$FIXED_CONFIG")"
    echo "   transforms.unwrap.add.fields: $(jq -r '.config."transforms.unwrap.add.fields"' "$FIXED_CONFIG")"
    echo "   transforms.unwrap.add.fields.prefix: $(jq -r '.config."transforms.unwrap.add.fields.prefix"' "$FIXED_CONFIG")"
    echo "   transforms.route.type: $(jq -r '.config."transforms.route.type"' "$FIXED_CONFIG")"
    echo "   transforms.route.regex: $(jq -r '.config."transforms.route.regex"' "$FIXED_CONFIG")"
    echo "   transforms.route.replacement: $(jq -r '.config."transforms.route.replacement"' "$FIXED_CONFIG")"
else
    echo "   transforms: unwrap,route"
    echo "   transforms.unwrap.type: io.debezium.transforms.ExtractNewRecordState"
    echo "   transforms.unwrap.drop.tombstones: false"
    echo "   transforms.unwrap.add.fields: op,table,ts_ms"
    echo "   transforms.unwrap.add.fields.prefix: __"
    echo "   transforms.route.type: io.confluent.connect.cloud.transforms.TopicRegexRouter"
    echo "   transforms.route.regex: aurora-postgres-cdc\\.public\\.business_events"
    echo "   transforms.route.replacement: raw-business-events"
fi
echo ""
echo "5. Save and restart the connector"
echo ""
echo "6. Wait for connector to reach RUNNING state"
echo ""

echo -e "${CYAN}Option 2: Reference Config File${NC}"
echo ""
echo "Use the fixed configuration file as reference:"
echo "  $FIXED_CONFIG"
echo ""
if [ -f "$FIXED_CONFIG" ]; then
    echo "Key settings from config file:"
    if command -v jq &> /dev/null; then
        jq '.config | {
            transforms: .transforms,
            unwrap_type: ."transforms.unwrap.type",
            add_fields: ."transforms.unwrap.add.fields",
            prefix: ."transforms.unwrap.add.fields.prefix"
        }' "$FIXED_CONFIG" 2>/dev/null | head -10
    else
        echo "  (Install jq to see formatted output)"
    fi
fi
echo ""

# Step 4: Verification
echo -e "${BLUE}Step 4: Verify Fix${NC}"
echo ""
echo "After updating, verify:"
echo ""
echo "1. Connector status is RUNNING"
echo ""
echo "2. Flink statements start processing events:"
echo "   confluent flink statement list --compute-pool lfcp-2xqo0m"
echo "   # Check that offsets are advancing"
echo ""
echo "3. Filtered topics receive events:"
echo "   # Check consumer logs for processed events"
echo ""
echo "4. Test with k6:"
echo "   cd cdc-streaming"
echo "   k6 run scripts/send-5-events-k6.js"
echo "   # Then check consumer logs"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Fix Instructions Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Reference:${NC}"
echo "  - CONFLUENT_CLOUD_SETUP_GUIDE.md - Issue 7: Flink Filter Not Matching Events"
echo "  - RECOMMENDED_APPROACH.md - Detailed recommendation guide"
echo "  - DATA_STRUCTURE_COMPARISON.md - Structure comparison"
echo ""
