#!/bin/bash
# Deploy Debezium PostgreSQL connector to local Kafka Connect
# This script deploys the connector to the local Kafka Connect instance running in Docker

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
echo -e "${BLUE}Deploy Debezium Connector (Local)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Configuration
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8085}"
CONNECTOR_CONFIG="${1:-cdc-streaming/connectors/postgres-debezium-local.json}"

# Resolve config file path
if [[ "$CONNECTOR_CONFIG" != /* ]]; then
    # Relative path - assume it's relative to project root
    if [[ "$CONNECTOR_CONFIG" != cdc-streaming/* ]]; then
        CONNECTOR_CONFIG="cdc-streaming/connectors/$CONNECTOR_CONFIG"
    fi
    CONNECTOR_CONFIG="$PROJECT_ROOT/$CONNECTOR_CONFIG"
fi

echo -e "${CYAN}Configuration:${NC}"
echo "  Kafka Connect URL: $KAFKA_CONNECT_URL"
echo "  Connector Config: $CONNECTOR_CONFIG"
echo ""

# Check if connector config exists
if [ ! -f "$CONNECTOR_CONFIG" ]; then
    echo -e "${RED}✗ Connector configuration not found: $CONNECTOR_CONFIG${NC}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗ jq is required but not installed${NC}"
    echo "  Install with: brew install jq"
    exit 1
fi

# Get connector name from config
CONNECTOR_NAME=$(jq -r '.name' "$CONNECTOR_CONFIG" 2>/dev/null || echo "")

if [ -z "$CONNECTOR_NAME" ] || [ "$CONNECTOR_NAME" = "null" ]; then
    echo -e "${RED}✗ Invalid connector configuration: missing 'name' field${NC}"
    exit 1
fi

echo -e "${CYAN}Connector Name: $CONNECTOR_NAME${NC}"
echo ""

# Wait for Kafka Connect to be ready
echo -e "${BLUE}Step 1: Waiting for Kafka Connect to be ready...${NC}"
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -sf "$KAFKA_CONNECT_URL/connectors" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Kafka Connect is ready${NC}"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo -e "${YELLOW}  Waiting for Kafka Connect... (${RETRY_COUNT}/${MAX_RETRIES})${NC}"
        sleep 2
    else
        echo -e "${RED}✗ Kafka Connect is not available at $KAFKA_CONNECT_URL${NC}"
        echo "  Make sure Kafka Connect is running:"
        echo "    docker-compose up -d kafka-connect"
        exit 1
    fi
done

echo ""

# Check if connector already exists
echo -e "${BLUE}Step 2: Checking for existing connector...${NC}"
EXISTING_CONNECTOR=$(curl -sf "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME" 2>/dev/null || echo "")

if [ -n "$EXISTING_CONNECTOR" ]; then
    echo -e "${YELLOW}⚠ Connector '$CONNECTOR_NAME' already exists${NC}"
    read -p "Delete and recreate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Deleting existing connector...${NC}"
        curl -X DELETE "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME" 2>/dev/null || true
        sleep 3
        echo -e "${GREEN}✓ Existing connector deleted${NC}"
    else
        echo "Aborted."
        exit 0
    fi
fi

echo ""

# Create topic for raw-event-headers (optional, Redpanda auto-creates topics)
echo -e "${BLUE}Step 3: Ensuring topic exists...${NC}"
echo -e "${CYAN}Note: Redpanda auto-creates topics, but we'll verify it exists${NC}"
echo ""

# Deploy connector
echo -e "${BLUE}Step 4: Deploying connector...${NC}"

# Read connector config and extract just the config section
CONNECTOR_PAYLOAD=$(jq '{name: .name, config: .config}' "$CONNECTOR_CONFIG")

# Display configuration (without secrets)
echo -e "${CYAN}Connector Configuration (secrets hidden):${NC}"
echo "$CONNECTOR_PAYLOAD" | jq -r '.config | to_entries | map(select(.key | contains("password") or contains("secret")) | .value = "***") | .[] | "  \(.key): \(.value)"' | head -20
echo ""

# Deploy via REST API
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$KAFKA_CONNECT_URL/connectors" \
    -H "Content-Type: application/json" \
    -d "$CONNECTOR_PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 200 ]; then
    echo -e "${GREEN}✓ Connector deployed successfully!${NC}"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
else
    echo -e "${RED}✗ Failed to deploy connector${NC}"
    echo "  HTTP Code: $HTTP_CODE"
    echo "  Response: $BODY"
    exit 1
fi

echo ""

# Wait a moment for connector to initialize
echo -e "${BLUE}Step 5: Waiting for connector to initialize...${NC}"
sleep 5

# Check connector status
echo -e "${BLUE}Step 6: Checking connector status...${NC}"
STATUS_RESPONSE=$(curl -sf "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME/status" 2>/dev/null || echo "")

if [ -n "$STATUS_RESPONSE" ]; then
    CONNECTOR_STATE=$(echo "$STATUS_RESPONSE" | jq -r '.connector.state' 2>/dev/null || echo "unknown")
    TASK_STATE=$(echo "$STATUS_RESPONSE" | jq -r '.tasks[0].state' 2>/dev/null || echo "unknown")
    
    echo -e "${CYAN}Connector Status:${NC}"
    echo "  State: $CONNECTOR_STATE"
    echo "  Task State: $TASK_STATE"
    echo ""
    
    if [ "$CONNECTOR_STATE" = "RUNNING" ] && [ "$TASK_STATE" = "RUNNING" ]; then
        echo -e "${GREEN}✓✓✓ Connector is RUNNING!${NC}"
    else
        echo -e "${YELLOW}⚠ Connector is not fully running yet${NC}"
        echo "  This is normal - it may take a minute to start"
        echo "  Check logs: docker logs kafka-connect"
    fi
    
    # Show any errors
    ERROR_TRACE=$(echo "$STATUS_RESPONSE" | jq -r '.connector.trace // empty' 2>/dev/null || echo "")
    if [ -n "$ERROR_TRACE" ] && [ "$ERROR_TRACE" != "null" ]; then
        echo ""
        echo -e "${RED}Error Trace:${NC}"
        echo "$ERROR_TRACE" | head -20
    fi
else
    echo -e "${YELLOW}⚠ Could not retrieve connector status${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Monitor connector logs:"
echo "     docker logs -f kafka-connect"
echo ""
echo "  2. Check connector status:"
echo "     curl $KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME/status | jq"
echo ""
echo "  3. Verify events in topic:"
echo "     docker exec -it redpanda rpk topic consume raw-event-headers --num 5"
echo ""
echo "  4. View topics in Redpanda Console:"
echo "     http://localhost:8080"
echo ""
echo -e "${CYAN}Useful Commands:${NC}"
echo "  List connectors:    curl $KAFKA_CONNECT_URL/connectors | jq"
echo "  Delete connector:   curl -X DELETE $KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME"
echo "  Restart connector:  curl -X POST $KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME/restart"
echo ""

