#!/bin/bash
# Monitor Business Events CDC Pipeline
# Checks connector status, Flink statements, topics, and message flow

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ENV_ID="${CONFLUENT_ENV_ID:-env-q9n81p}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"
COMPUTE_POOL_ID="${FLINK_COMPUTE_POOL_ID:-lfcp-2xqo0m}"
CONNECTOR_NAME="${CONNECTOR_NAME:-postgres-debezium-business-events-confluent-cloud}"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Business Events Pipeline Monitor${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# 1. Check Connector Status
echo -e "${BLUE}1. CDC Connector Status${NC}"
echo "----------------------------------------"
if confluent connect cluster describe "$CONNECTOR_NAME" &>/dev/null; then
    CONNECTOR_STATE=$(confluent connect cluster describe "$CONNECTOR_NAME" --output json | jq -r '.status.connector.state' 2>/dev/null || echo "unknown")
    TASKS=$(confluent connect cluster describe "$CONNECTOR_NAME" --output json | jq -r '.status.tasks[]?.state' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    
    if [ "$CONNECTOR_STATE" = "RUNNING" ]; then
        echo -e "${GREEN}✓ Connector: $CONNECTOR_STATE${NC}"
    else
        echo -e "${RED}✗ Connector: $CONNECTOR_STATE${NC}"
    fi
    
    if [ -n "$TASKS" ]; then
        echo "  Tasks: $TASKS"
    fi
    
    # Show error if any
    ERROR=$(confluent connect cluster describe "$CONNECTOR_NAME" --output json | jq -r '.status.connector.trace' 2>/dev/null || echo "")
    if [ -n "$ERROR" ] && [ "$ERROR" != "null" ]; then
        echo -e "${YELLOW}  Error: $ERROR${NC}"
    fi
else
    echo -e "${RED}✗ Connector not found: $CONNECTOR_NAME${NC}"
fi
echo ""

# 2. Check Topics
echo -e "${BLUE}2. Kafka Topics${NC}"
echo "----------------------------------------"
echo "Raw topic:"
if confluent kafka topic describe raw-business-events &>/dev/null; then
    MSG_COUNT=$(confluent kafka topic describe raw-business-events --output json | jq '[.partitions[].offset] | add' 2>/dev/null || echo "0")
    echo -e "${GREEN}✓ raw-business-events exists${NC} (messages: $MSG_COUNT)"
else
    echo -e "${RED}✗ raw-business-events does not exist${NC}"
fi

echo ""
echo "Filtered topics:"
for topic in filtered-car-created-events filtered-loan-created-events filtered-loan-payment-submitted-events filtered-service-events; do
    if confluent kafka topic describe "$topic" &>/dev/null; then
        MSG_COUNT=$(confluent kafka topic describe "$topic" --output json | jq '[.partitions[].offset] | add' 2>/dev/null || echo "0")
        echo -e "${GREEN}✓ $topic${NC} (messages: $MSG_COUNT)"
    else
        echo -e "${YELLOW}○ $topic${NC} (not created yet - will be created by Flink)"
    fi
done
echo ""

# 3. Check Flink Statements
echo -e "${BLUE}3. Flink SQL Statements${NC}"
echo "----------------------------------------"
STATEMENTS=$(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null | jq -r '.[] | "\(.name)|\(.status)"' || echo "")

if [ -z "$STATEMENTS" ]; then
    echo -e "${RED}✗ No Flink statements found${NC}"
else
    echo "$STATEMENTS" | while IFS='|' read -r name status; do
        if [ "$status" = "RUNNING" ]; then
            echo -e "${GREEN}✓ $name: $status${NC}"
        else
            echo -e "${YELLOW}⚠ $name: $status${NC}"
        fi
    done
fi
echo ""

# 4. Check Message Flow
echo -e "${BLUE}4. Message Flow Check${NC}"
echo "----------------------------------------"
echo "Checking for recent messages in raw-business-events..."
LATEST_MSG=$(confluent kafka topic consume raw-business-events --max-messages 1 --timeout 5 2>&1 | head -5 || echo "")
if [ -n "$LATEST_MSG" ] && ! echo "$LATEST_MSG" | grep -q "No messages"; then
    echo -e "${GREEN}✓ Messages found in raw-business-events${NC}"
else
    echo -e "${YELLOW}⚠ No recent messages in raw-business-events${NC}"
    echo "  This is normal if no events have been sent recently"
fi
echo ""

# 5. Summary
echo -e "${BLUE}5. Pipeline Summary${NC}"
echo "----------------------------------------"
CONNECTOR_OK=false
TOPIC_OK=false
FLINK_OK=false

if confluent connect cluster describe "$CONNECTOR_NAME" &>/dev/null; then
    CONNECTOR_STATE=$(confluent connect cluster describe "$CONNECTOR_NAME" --output json | jq -r '.status.connector.state' 2>/dev/null || echo "unknown")
    [ "$CONNECTOR_STATE" = "RUNNING" ] && CONNECTOR_OK=true
fi

confluent kafka topic describe raw-business-events &>/dev/null && TOPIC_OK=true

STATEMENT_COUNT=$(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null | jq 'length' || echo "0")
[ "$STATEMENT_COUNT" -gt 0 ] && FLINK_OK=true

if [ "$CONNECTOR_OK" = true ] && [ "$TOPIC_OK" = true ] && [ "$FLINK_OK" = true ]; then
    echo -e "${GREEN}✓ Pipeline is operational${NC}"
else
    echo -e "${YELLOW}⚠ Pipeline has issues:${NC}"
    [ "$CONNECTOR_OK" = false ] && echo "  - Connector not running"
    [ "$TOPIC_OK" = false ] && echo "  - Topic missing"
    [ "$FLINK_OK" = false ] && echo "  - Flink statements not deployed"
fi
echo ""

# 6. Troubleshooting Commands
echo -e "${BLUE}6. Troubleshooting Commands${NC}"
echo "----------------------------------------"
echo "View connector logs:"
echo "  confluent connect cluster logs $CONNECTOR_NAME"
echo ""
echo "View connector details:"
echo "  confluent connect cluster describe $CONNECTOR_NAME"
echo ""
echo "List Flink statements:"
echo "  confluent flink statement list --compute-pool $COMPUTE_POOL_ID"
echo ""
echo "Consume messages:"
echo "  confluent kafka topic consume raw-business-events --max-messages 5"
echo "  confluent kafka topic consume filtered-car-created-events --max-messages 5"
echo ""
