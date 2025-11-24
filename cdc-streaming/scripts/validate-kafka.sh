#!/bin/bash
# Validate Data in Kafka Topics
# This script checks Kafka topics for messages and validates event structure

set -e

# Configuration
KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-localhost:9092}"
TOPIC="${1:-raw-business-events}"
LIMIT="${LIMIT:-10}"
FORMAT="${FORMAT:-json}"  # json or avro

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Kafka Topic Validation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Kafka is accessible
if ! docker exec cdc-kafka /usr/bin/kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1; then
    echo -e "${RED}Error: Kafka is not accessible${NC}"
    exit 1
fi

# Check if topic exists
if ! docker exec cdc-kafka /usr/bin/kafka-topics --bootstrap-server localhost:9092 --list | grep -q "^${TOPIC}$"; then
    echo -e "${RED}Error: Topic '${TOPIC}' does not exist${NC}"
    echo "Available topics:"
    docker exec cdc-kafka kafka-topics.sh --bootstrap-server localhost:9092 --list
    exit 1
fi

echo -e "${BLUE}Topic: ${TOPIC}${NC}"
echo -e "${BLUE}Bootstrap Servers: ${KAFKA_BOOTSTRAP_SERVERS}${NC}"
echo -e "${BLUE}Limit: ${LIMIT} messages${NC}"
echo ""

# Get topic information
echo -e "${YELLOW}Topic Information:${NC}"
docker exec cdc-kafka /usr/bin/kafka-topics \
    --bootstrap-server localhost:9092 \
    --describe \
    --topic "${TOPIC}" 2>/dev/null | head -5 || echo "  (Topic info unavailable)"

echo ""

# Get consumer group information
echo -e "${YELLOW}Consumer Groups:${NC}"
docker exec cdc-kafka /usr/bin/kafka-consumer-groups \
    --bootstrap-server localhost:9092 \
    --list 2>/dev/null | head -5 || echo "  No consumer groups found"

echo ""

# Get message count (approximate)
echo -e "${YELLOW}Message Count (approximate):${NC}"
LOW_WATERMARK=$(docker exec cdc-kafka /usr/bin/kafka-run-class kafka.tools.GetOffsetShell \
    --broker-list localhost:9092 \
    --topic "${TOPIC}" \
    --time -2 2>/dev/null | awk -F: '{sum+=$3} END {print sum}' || echo "0")

HIGH_WATERMARK=$(docker exec cdc-kafka /usr/bin/kafka-run-class kafka.tools.GetOffsetShell \
    --broker-list localhost:9092 \
    --topic "${TOPIC}" \
    --time -1 2>/dev/null | awk -F: '{sum+=$3} END {print sum}' || echo "0")

MESSAGE_COUNT=$((HIGH_WATERMARK - LOW_WATERMARK))
echo "  Messages: ${MESSAGE_COUNT}"

if [ "$MESSAGE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}  No messages found in topic${NC}"
    echo ""
    echo "To generate test data, run:"
    echo "  ./scripts/generate-test-data.sh"
    exit 0
fi

echo ""

# Sample messages
echo -e "${YELLOW}Sample Messages (last ${LIMIT}):${NC}"
echo ""

# Use kafka-console-consumer to get sample messages
docker exec cdc-kafka /usr/bin/kafka-console-consumer \
    --bootstrap-server localhost:9092 \
    --topic "${TOPIC}" \
    --from-beginning \
    --max-messages "${LIMIT}" \
    --timeout-ms 5000 2>/dev/null | while IFS= read -r line; do
    if [ -n "$line" ]; then
        echo -e "${GREEN}Message:${NC}"
        # Try to format as JSON if possible
        if command -v jq &> /dev/null && echo "$line" | jq . > /dev/null 2>&1; then
            echo "$line" | jq .
        else
            echo "$line"
        fi
        echo ""
    fi
done || echo -e "${YELLOW}No messages retrieved (topic may be empty or consumer timed out)${NC}"

echo ""

# Validate message structure (if JSON)
if [ "$FORMAT" = "json" ]; then
    echo -e "${YELLOW}Validating Message Structure:${NC}"
    
    SAMPLE_MSG=$(docker exec cdc-kafka /usr/bin/kafka-console-consumer \
        --bootstrap-server localhost:9092 \
        --topic "${TOPIC}" \
        --from-beginning \
        --max-messages 1 \
        --timeout-ms 5000 2>/dev/null | head -1)
    
    if [ -n "$SAMPLE_MSG" ] && command -v jq &> /dev/null; then
        # Check for required fields
        if echo "$SAMPLE_MSG" | jq -e '.eventHeader' > /dev/null 2>&1; then
            echo -e "${GREEN}  ✓ eventHeader field present${NC}"
        else
            echo -e "${RED}  ✗ eventHeader field missing${NC}"
        fi
        
        if echo "$SAMPLE_MSG" | jq -e '.eventBody' > /dev/null 2>&1; then
            echo -e "${GREEN}  ✓ eventBody field present${NC}"
        else
            echo -e "${RED}  ✗ eventBody field missing${NC}"
        fi
        
        if echo "$SAMPLE_MSG" | jq -e '.eventHeader.eventName' > /dev/null 2>&1; then
            EVENT_NAME=$(echo "$SAMPLE_MSG" | jq -r '.eventHeader.eventName')
            echo -e "${GREEN}  ✓ eventName: ${EVENT_NAME}${NC}"
        else
            echo -e "${RED}  ✗ eventName field missing${NC}"
        fi
        
        if echo "$SAMPLE_MSG" | jq -e '.eventBody.entities' > /dev/null 2>&1; then
            ENTITY_COUNT=$(echo "$SAMPLE_MSG" | jq '.eventBody.entities | length')
            echo -e "${GREEN}  ✓ entities array with ${ENTITY_COUNT} entity(ies)${NC}"
        else
            echo -e "${RED}  ✗ entities array missing${NC}"
        fi
    else
        echo -e "${YELLOW}  (Skipping validation - jq not available or no messages)${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Validation complete!${NC}"

