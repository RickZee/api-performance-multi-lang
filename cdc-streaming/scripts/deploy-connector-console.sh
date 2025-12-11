#!/bin/bash
# Guide for deploying connector via Confluent Cloud Console
# Since managed connectors require Console access

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

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Deploy Connector via Console${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

echo -e "${YELLOW}Since managed connectors require Console access, please follow these steps:${NC}"
echo ""

echo -e "${BLUE}Step 1: Open Confluent Cloud Console${NC}"
echo "  https://confluent.cloud/environments/$ENV_ID/connectors"
echo ""

echo -e "${BLUE}Step 2: Click 'Add connector'${NC}"
echo ""

echo -e "${BLUE}Step 3: Select 'PostgresCdcSource'${NC}"
echo "  (This is the managed PostgreSQL CDC connector)"
echo ""

echo -e "${BLUE}Step 4: Configure the connector with these settings:${NC}"
echo ""

CONFIG_FILE="$PROJECT_ROOT/cdc-streaming/connectors/postgres-cdc-source-business-events-confluent-cloud.json"
CONFIG=$(cat "$CONFIG_FILE" | jq -r '.config')

echo "$CONFIG" | jq -r 'to_entries | .[] | "  \(.key): \(.value)"' | grep -v "password\|secret" | head -20
echo "  ... (see config file for complete settings)"
echo ""

echo -e "${BLUE}Step 5: Key Configuration Values:${NC}"
echo "  Database hostname: $(echo "$CONFIG" | jq -r '.database.hostname')"
echo "  Database name: $(echo "$CONFIG" | jq -r '.database.dbname')"
echo "  Table include list: $(echo "$CONFIG" | jq -r '.table.include.list')"
echo "  Output format: $(echo "$CONFIG" | jq -r '.output.data.format')"
echo "  Topic prefix: $(echo "$CONFIG" | jq -r '.topic.prefix')"
echo ""

echo -e "${BLUE}Step 6: Important Transform Configuration${NC}"
echo "  Add transform: RegexRouter"
echo "  Regex: aurora-cdc.public.business_events"
echo "  Replacement: raw-business-events"
echo "  This routes the CDC output to the raw-business-events topic"
echo ""

echo -e "${BLUE}Step 7: After deployment, verify:${NC}"
echo "  confluent connect cluster list"
echo "  confluent connect cluster describe <connector-name>"
echo ""

echo -e "${CYAN}Alternative: View full config file${NC}"
echo "  cat $CONFIG_FILE | jq"
echo ""
