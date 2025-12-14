#!/bin/bash
# Test script for metadata service filter API
# Tests the full filter workflow: create -> generate -> approve -> deploy

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

METADATA_URL="${METADATA_SERVICE_URL:-http://localhost:8080}"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Testing Metadata Service Filter API${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Check if metadata service is running
echo -e "${BLUE}Checking metadata service health...${NC}"
if ! curl -s -f "${METADATA_URL}/api/v1/health" > /dev/null; then
    echo -e "${RED}✗ Metadata service is not running at ${METADATA_URL}${NC}"
    echo -e "${YELLOW}Start it with: docker-compose --profile metadata-service up -d${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Metadata service is running${NC}"
echo ""

# Step 1: Create a filter
echo -e "${BLUE}Step 1: Creating filter...${NC}"
FILTER_RESPONSE=$(curl -s -X POST "${METADATA_URL}/api/v1/filters?version=v1" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Service Events for Dealer 001",
        "description": "Routes service events from Tesla Service Center SF to dedicated topic",
        "consumerId": "dealer-001-service-consumer",
        "outputTopic": "filtered-service-events-dealer-001",
        "conditions": [
            {
                "field": "event_type",
                "operator": "equals",
                "value": "CarServiceDone",
                "valueType": "string",
                "logicalOperator": "AND"
            },
            {
                "field": "header_data.dealerId",
                "operator": "equals",
                "value": "DEALER-001",
                "valueType": "string",
                "logicalOperator": "AND"
            }
        ],
        "enabled": true,
        "conditionLogic": "AND"
    }')

FILTER_ID=$(echo "$FILTER_RESPONSE" | jq -r '.id // empty')
if [ -z "$FILTER_ID" ]; then
    echo -e "${RED}✗ Failed to create filter${NC}"
    echo "$FILTER_RESPONSE" | jq '.'
    exit 1
fi

echo -e "${GREEN}✓ Filter created: ${FILTER_ID}${NC}"
echo "$FILTER_RESPONSE" | jq '.'
echo ""

# Step 2: Get the filter
echo -e "${BLUE}Step 2: Retrieving filter...${NC}"
GET_RESPONSE=$(curl -s "${METADATA_URL}/api/v1/filters/${FILTER_ID}?version=v1")
echo "$GET_RESPONSE" | jq '.'
echo ""

# Step 3: Generate SQL
echo -e "${BLUE}Step 3: Generating Flink SQL...${NC}"
SQL_RESPONSE=$(curl -s -X POST "${METADATA_URL}/api/v1/filters/${FILTER_ID}/generate?version=v1")
VALID=$(echo "$SQL_RESPONSE" | jq -r '.valid // false')

if [ "$VALID" != "true" ]; then
    echo -e "${RED}✗ SQL generation failed${NC}"
    echo "$SQL_RESPONSE" | jq '.'
    exit 1
fi

echo -e "${GREEN}✓ SQL generated successfully${NC}"
echo "$SQL_RESPONSE" | jq -r '.sql'
echo ""

# Step 4: Validate SQL
echo -e "${BLUE}Step 4: Validating SQL...${NC}"
SQL_TEXT=$(echo "$SQL_RESPONSE" | jq -r '.sql')
VALIDATE_RESPONSE=$(curl -s -X POST "${METADATA_URL}/api/v1/filters/${FILTER_ID}/validate?version=v1" \
    -H "Content-Type: application/json" \
    -d "{\"sql\": $(echo "$SQL_TEXT" | jq -Rs '.')}")

VALID=$(echo "$VALIDATE_RESPONSE" | jq -r '.valid // false')
if [ "$VALID" != "true" ]; then
    echo -e "${YELLOW}⚠ SQL validation warnings${NC}"
    echo "$VALIDATE_RESPONSE" | jq '.'
else
    echo -e "${GREEN}✓ SQL validation passed${NC}"
fi
echo ""

# Step 5: Approve filter
echo -e "${BLUE}Step 5: Approving filter...${NC}"
APPROVE_RESPONSE=$(curl -s -X POST "${METADATA_URL}/api/v1/filters/${FILTER_ID}/approve?version=v1" \
    -H "Content-Type: application/json" \
    -d '{
        "approvedBy": "test-user"
    }')

STATUS=$(echo "$APPROVE_RESPONSE" | jq -r '.status // empty')
if [ "$STATUS" != "approved" ]; then
    echo -e "${RED}✗ Failed to approve filter${NC}"
    echo "$APPROVE_RESPONSE" | jq '.'
    exit 1
fi

echo -e "${GREEN}✓ Filter approved${NC}"
echo "$APPROVE_RESPONSE" | jq '.'
echo ""

# Step 6: Get filter status
echo -e "${BLUE}Step 6: Getting filter status...${NC}"
STATUS_RESPONSE=$(curl -s "${METADATA_URL}/api/v1/filters/${FILTER_ID}/status?version=v1")
echo "$STATUS_RESPONSE" | jq '.'
echo ""

# Step 7: List all filters
echo -e "${BLUE}Step 7: Listing all filters...${NC}"
LIST_RESPONSE=$(curl -s "${METADATA_URL}/api/v1/filters?version=v1")
TOTAL=$(echo "$LIST_RESPONSE" | jq -r '.total // 0')
echo -e "${GREEN}✓ Found ${TOTAL} filter(s)${NC}"
echo "$LIST_RESPONSE" | jq '.filters[] | {id, name, status}'
echo ""

# Step 8: Deploy filter (will skip if Confluent Cloud not configured)
echo -e "${BLUE}Step 8: Attempting to deploy filter...${NC}"
if [ -z "$CONFLUENT_CLOUD_API_KEY" ] || [ -z "$CONFLUENT_FLINK_COMPUTE_POOL_ID" ]; then
    echo -e "${YELLOW}⚠ Skipping deployment - Confluent Cloud credentials not configured${NC}"
    echo "Set CONFLUENT_CLOUD_API_KEY and CONFLUENT_FLINK_COMPUTE_POOL_ID to test deployment"
else
    DEPLOY_RESPONSE=$(curl -s -X POST "${METADATA_URL}/api/v1/filters/${FILTER_ID}/deploy?version=v1" \
        -H "Content-Type: application/json" \
        -d '{"force": false}')
    
    DEPLOY_STATUS=$(echo "$DEPLOY_RESPONSE" | jq -r '.status // empty')
    if [ "$DEPLOY_STATUS" = "deployed" ]; then
        echo -e "${GREEN}✓ Filter deployed successfully${NC}"
        echo "$DEPLOY_RESPONSE" | jq '.'
    else
        echo -e "${YELLOW}⚠ Deployment may have failed or is in progress${NC}"
        echo "$DEPLOY_RESPONSE" | jq '.'
    fi
fi
echo ""

echo -e "${CYAN}========================================${NC}"
echo -e "${GREEN}✓ Filter API test completed${NC}"
echo -e "${CYAN}========================================${NC}"
