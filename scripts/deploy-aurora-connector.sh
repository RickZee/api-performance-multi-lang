#!/bin/bash
# Deploy Aurora PostgreSQL CDC Connector to Confluent Cloud
# Uses the connector config file and Confluent Cloud REST API

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/cdc-streaming/connectors/postgres-debezium-aurora-confluent-cloud.json"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Deploy Aurora CDC Connector${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗ Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Get connector name and config
CONNECTOR_NAME=$(jq -r '.name' "$CONFIG_FILE")
CONNECTOR_CONFIG=$(jq -r '.config' "$CONFIG_FILE")

echo -e "${BLUE}Connector Name: $CONNECTOR_NAME${NC}"
echo ""

# Check if confluent CLI is available
if ! command -v confluent &> /dev/null; then
    echo -e "${RED}✗ Confluent CLI not installed${NC}"
    exit 1
fi

# Get environment and cluster info
ENV_ID="${CONFLUENT_ENV_ID:-env-q9n81p}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"
CONNECT_CLUSTER_ID="${CONNECT_CLUSTER_ID:-lcc-om19xj}"

echo -e "${CYAN}Configuration:${NC}"
echo "  Environment ID: $ENV_ID"
echo "  Kafka Cluster ID: $CLUSTER_ID"
echo "  Connect Cluster ID: $CONNECT_CLUSTER_ID"
echo ""

# Check if connector already exists
echo -e "${BLUE}Checking if connector already exists...${NC}"

# Try to get current API key
API_KEY="${CONFLUENT_API_KEY:-}"
API_SECRET="${CONFLUENT_API_SECRET:-}"

if [ -z "$API_KEY" ] || [ -z "$API_SECRET" ]; then
    echo -e "${YELLOW}⚠ API credentials not set${NC}"
    echo "  Set CONFLUENT_API_KEY and CONFLUENT_API_SECRET"
    echo ""
    echo -e "${CYAN}Alternative: Deploy via Confluent Cloud UI${NC}"
    echo "  1. Visit: https://confluent.cloud/environments/$ENV_ID/connectors"
    echo "  2. Click 'Add connector'"
    echo "  3. Select 'PostgresCdcSource' or 'Custom connector'"
    echo "  4. Use the configuration from: $CONFIG_FILE"
    echo ""
    echo -e "${CYAN}Connector Configuration:${NC}"
    echo "$CONNECTOR_CONFIG" | jq '.' | head -30
    exit 0
fi

# Deploy using Confluent Cloud REST API
echo -e "${BLUE}Deploying connector via REST API...${NC}"

# Create base64 auth
AUTH=$(echo -n "$API_KEY:$API_SECRET" | base64)

# Create connector
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Basic $AUTH" \
    -d "{\"name\":\"$CONNECTOR_NAME\",\"config\":$CONNECTOR_CONFIG}" \
    "https://api.confluent.cloud/connect/v1/environments/$ENV_ID/clusters/$CONNECT_CLUSTER_ID/connectors" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Connector deployed successfully!${NC}"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
else
    echo -e "${RED}✗ Failed to deploy connector${NC}"
    echo "HTTP Code: $HTTP_CODE"
    echo "Response: $BODY"
    
    # Check if connector already exists
    if echo "$BODY" | grep -qi "already exists\|duplicate"; then
        echo ""
        echo -e "${YELLOW}Connector may already exist. Checking status...${NC}"
        # Try to get connector status
        STATUS_RESPONSE=$(curl -s \
            -H "Authorization: Basic $AUTH" \
            "https://api.confluent.cloud/connect/v1/environments/$ENV_ID/clusters/$CONNECT_CLUSTER_ID/connectors/$CONNECTOR_NAME/status" 2>&1)
        
        if [ $? -eq 0 ]; then
            echo "$STATUS_RESPONSE" | jq '.' 2>/dev/null || echo "$STATUS_RESPONSE"
        fi
    fi
    exit 1
fi

echo ""
echo -e "${BLUE}Waiting for connector to start...${NC}"
sleep 5

# Check connector status
echo -e "${BLUE}Checking connector status...${NC}"
STATUS_RESPONSE=$(curl -s \
    -H "Authorization: Basic $AUTH" \
    "https://api.confluent.cloud/connect/v1/environments/$ENV_ID/clusters/$CONNECT_CLUSTER_ID/connectors/$CONNECTOR_NAME/status" 2>&1)

if [ $? -eq 0 ]; then
    STATE=$(echo "$STATUS_RESPONSE" | jq -r '.connector.state' 2>/dev/null || echo "unknown")
    echo -e "${CYAN}Connector State: $STATE${NC}"
    
    if [ "$STATE" = "RUNNING" ]; then
        echo -e "${GREEN}✓ Connector is RUNNING${NC}"
    else
        echo -e "${YELLOW}⚠ Connector state: $STATE${NC}"
        echo "Check logs for details"
    fi
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deployment Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Wait a few minutes for connector to process existing data"
echo "  2. Check topics: confluent kafka topic list | grep aurora"
echo "  3. Verify messages: python3 cdc-streaming/scripts/verify-messages.py aurora-cdc.public.car_entities 10 50"
echo "  4. Check Flink processing: confluent flink statement list"
echo ""

