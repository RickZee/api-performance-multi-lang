#!/bin/bash
# Validate End-to-End CDC Pipeline
# Sends events to PostgreSQL Lambda and validates they appear in filtered Kafka topics
# Uses Confluent CLI to consume and validate events
#
# Usage:
#   ./cdc-streaming/scripts/validate-pipeline-end-to-end.sh [EVENTS_PER_TYPE] [DB_TYPE] [API_URL] [WAIT_TIME]
#
# Examples:
#   # Send 10 events of each type (default), validate in filtered topics
#   ./cdc-streaming/scripts/validate-pipeline-end-to-end.sh
#
#   # Send 5 events of each type, use DSQL Lambda
#   ./cdc-streaming/scripts/validate-pipeline-end-to-end.sh 5 dsql
#
#   # Send 10 events, custom API URL, wait 90 seconds for CDC
#   ./cdc-streaming/scripts/validate-pipeline-end-to-end.sh 10 pg "https://custom-api.execute-api.us-east-1.amazonaws.com" 90
#
# This script:
#   - Reuses existing load-test/k6/send-batch-events.js to send events
#   - Uses scripts/extract-events-from-k6-output.py to extract event UUIDs
#   - Validates events appear in Confluent Kafka filtered topics (not databases)
#
# Requirements:
#   - k6 installed (brew install k6)
#   - Confluent CLI installed and logged in (confluent login)
#   - jq installed (brew install jq)
#   - CDC connector running and configured for event_headers table
#   - Flink SQL statements deployed and running
#
# Note: For database validation, use scripts/run-k6-and-validate.sh instead

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

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

# Configuration
EVENTS_PER_TYPE=${1:-10}
DB_TYPE=${2:-pg}
API_URL=${3:-""}
WAIT_TIME=${4:-60}  # Wait time for CDC propagation (seconds)

# Filtered topics mapping
declare -A TOPIC_MAP
TOPIC_MAP["CarCreated"]="filtered-car-created-events"
TOPIC_MAP["LoanCreated"]="filtered-loan-created-events"
TOPIC_MAP["LoanPaymentSubmitted"]="filtered-loan-payment-submitted-events"
TOPIC_MAP["CarServiceDone"]="filtered-service-events"

# Expected event types
EVENT_TYPES=("CarCreated" "LoanCreated" "LoanPaymentSubmitted" "CarServiceDone")

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}End-to-End CDC Pipeline Validation${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "Events per type: $EVENTS_PER_TYPE"
echo "Total events: $((EVENTS_PER_TYPE * 4))"
echo "Database type: $DB_TYPE"
echo "CDC wait time: ${WAIT_TIME}s"
echo ""

# Check prerequisites
if ! command -v k6 &> /dev/null; then
    fail "k6 not found. Install: brew install k6"
    exit 1
fi

if ! command -v confluent &> /dev/null; then
    fail "Confluent CLI not found. Install: brew install confluentinc/tap/cli"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    fail "jq not found. Install: brew install jq"
    exit 1
fi

# Check Confluent login
if ! confluent environment list &> /dev/null; then
    fail "Not logged in to Confluent Cloud. Run: confluent login"
    exit 1
fi

# Determine API URL
if [ -z "$API_URL" ]; then
    if [ "$DB_TYPE" = "pg" ]; then
        API_URL="https://kkwz7ho2gg.execute-api.us-east-1.amazonaws.com"
    elif [ "$DB_TYPE" = "dsql" ]; then
        API_URL="https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com"
    else
        fail "Unknown DB_TYPE: $DB_TYPE (use 'pg' or 'dsql')"
        exit 1
    fi
fi

echo "API URL: $API_URL"
echo ""

# Create temporary files
EVENTS_FILE="/tmp/pipeline-validation-events-$(date +%s).json"
TEMP_OUTPUT="/tmp/k6-output-$(date +%s).txt"

# Step 1: Send events using k6 (reuses existing send-batch-events.js script)
echo -e "${BLUE}[1/4] Sending events to Lambda API using k6...${NC}"
cd "$PROJECT_ROOT/load-test/k6"

# Run k6 using existing send-batch-events.js script and extract events
# This reuses the existing k6 script that sends all 4 event types
k6 run \
    --env DB_TYPE="$DB_TYPE" \
    --env API_URL="$API_URL" \
    --env EVENTS_PER_TYPE="$EVENTS_PER_TYPE" \
    --env EVENTS_FILE="$EVENTS_FILE" \
    send-batch-events.js 2>&1 | tee "$TEMP_OUTPUT" | "$PROJECT_ROOT/scripts/extract-events-from-k6-output.py" "$EVENTS_FILE" 2>&1 | grep -v "^K6_EVENT:" | tail -50

# Check if events were extracted
if [ ! -f "$EVENTS_FILE" ] || [ ! -s "$EVENTS_FILE" ]; then
    fail "Failed to extract events from k6 output"
    exit 1
fi

EVENT_COUNT=$(jq 'length' "$EVENTS_FILE" 2>/dev/null || echo "0")
if [ "$EVENT_COUNT" -eq 0 ]; then
    fail "No events extracted from k6 output"
    exit 1
fi

pass "Sent and extracted $EVENT_COUNT events"
echo ""

# Step 2: Wait for CDC propagation
echo -e "${BLUE}[2/4] Waiting for CDC propagation (${WAIT_TIME}s)...${NC}"
info "Events need time to: Database → CDC Connector → Kafka → Flink → Filtered Topics"
for i in $(seq 1 $WAIT_TIME); do
    if [ $((i % 10)) -eq 0 ]; then
        echo -n "."
    fi
    sleep 1
done
echo ""
pass "Wait complete"
echo ""

# Step 3: Extract event UUIDs by type
echo -e "${BLUE}[3/4] Extracting event UUIDs by type...${NC}"

declare -A EVENT_UUIDS
for event_type in "${EVENT_TYPES[@]}"; do
    EVENT_UUIDS["$event_type"]=$(jq -r ".[] | select(.eventType == \"$event_type\") | .uuid" "$EVENTS_FILE" 2>/dev/null | sort -u)
    COUNT=$(echo "${EVENT_UUIDS[$event_type]}" | grep -c . || echo "0")
    if [ "$COUNT" -gt 0 ]; then
        pass "Found $COUNT $event_type events"
    else
        warn "No $event_type events found"
    fi
done
echo ""

# Step 4: Validate events in filtered topics
echo -e "${BLUE}[4/4] Validating events in filtered Kafka topics...${NC}"
echo ""

TOTAL_VALIDATED=0
TOTAL_EXPECTED=0
VALIDATION_FAILED=false

for event_type in "${EVENT_TYPES[@]}"; do
    topic="${TOPIC_MAP[$event_type]}"
    uuids="${EVENT_UUIDS[$event_type]}"
    expected_count=$(echo "$uuids" | grep -c . || echo "0")
    TOTAL_EXPECTED=$((TOTAL_EXPECTED + expected_count))
    
    if [ "$expected_count" -eq 0 ]; then
        warn "Skipping $event_type (no events sent)"
        echo ""
        continue
    fi
    
    echo -e "${CYAN}Validating $event_type → $topic${NC}"
    
    # Check if topic exists
    if ! confluent kafka topic describe "$topic" &>/dev/null; then
        fail "Topic '$topic' does not exist"
        VALIDATION_FAILED=true
        echo ""
        continue
    fi
    
    # Consume messages from topic (consume more than expected to account for existing messages)
    CONSUME_COUNT=$((expected_count + 50))
    info "Consuming up to $CONSUME_COUNT messages from $topic..."
    
    # Create a temporary file for consumed messages
    CONSUMED_MSGS_FILE="/tmp/consumed-${topic}-$(date +%s).txt"
    
    # Consume messages - the output format varies, so we'll parse it flexibly
    timeout 35 confluent kafka topic consume "$topic" \
        --max-messages "$CONSUME_COUNT" \
        --timeout 30 2>&1 | \
        tee "$CONSUMED_MSGS_FILE" | \
        head -20 > /dev/null
    
    # Extract UUIDs from consumed messages
    # The message format can vary - try to extract JSON and find 'id' field
    CONSUMED_UUIDS=$(cat "$CONSUMED_MSGS_FILE" 2>/dev/null | \
        # Try to extract JSON objects
        grep -oE '\{[^}]*"id"[^}]*\}' | \
        jq -r '.id' 2>/dev/null | \
        # Also try full JSON lines
        cat - "$CONSUMED_MSGS_FILE" | \
        jq -R 'fromjson? | select(. != null) | .id // empty' 2>/dev/null | \
        # Also try nested value field
        cat - "$CONSUMED_MSGS_FILE" | \
        jq -R 'fromjson? | select(. != null) | .value // empty | fromjson? | select(. != null) | .id // empty' 2>/dev/null | \
        grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' | \
        sort -u || echo "")
    
    # Clean up temp file
    rm -f "$CONSUMED_MSGS_FILE"
    
    CONSUMED_COUNT=$(echo "$CONSUMED_UUIDS" | grep -c . || echo "0")
    
    if [ "$CONSUMED_COUNT" -eq 0 ]; then
        warn "No UUIDs extracted from $topic (may need more wait time or topic is empty)"
        info "Try manually: confluent kafka topic consume $topic --max-messages 5"
        VALIDATION_FAILED=true
        echo ""
        continue
    fi
    
    info "Extracted $CONSUMED_COUNT unique UUIDs from $topic"
    
    # Count how many of our sent UUIDs appear in consumed messages
    FOUND_COUNT=0
    MISSING_UUIDS=()
    
    while IFS= read -r uuid; do
        if [ -n "$uuid" ]; then
            if echo "$CONSUMED_UUIDS" | grep -q "^${uuid}$"; then
                FOUND_COUNT=$((FOUND_COUNT + 1))
            else
                MISSING_UUIDS+=("$uuid")
            fi
        fi
    done <<< "$uuids"
    
    TOTAL_VALIDATED=$((TOTAL_VALIDATED + FOUND_COUNT))
    
    if [ "$FOUND_COUNT" -eq "$expected_count" ]; then
        pass "All $expected_count $event_type events found in $topic"
    elif [ "$FOUND_COUNT" -gt 0 ]; then
        warn "Only $FOUND_COUNT/$expected_count $event_type events found in $topic"
        if [ ${#MISSING_UUIDS[@]} -le 5 ]; then
            info "Missing UUIDs: ${MISSING_UUIDS[*]}"
        else
            info "Missing UUIDs: ${MISSING_UUIDS[*]:0:5} ... (and $((expected_count - FOUND_COUNT - 5)) more)"
        fi
        VALIDATION_FAILED=true
    else
        fail "No $event_type events found in $topic"
        VALIDATION_FAILED=true
    fi
    
    echo ""
done

# Summary
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Validation Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

echo "Total events sent: $EVENT_COUNT"
echo "Total events validated: $TOTAL_VALIDATED/$TOTAL_EXPECTED"

if [ "$TOTAL_VALIDATED" -eq "$TOTAL_EXPECTED" ] && [ "$TOTAL_EXPECTED" -gt 0 ]; then
    echo -e "${GREEN}✅ All events validated successfully!${NC}"
    echo ""
    echo -e "${CYAN}Pipeline flow verified:${NC}"
    echo "  Lambda API → PostgreSQL/DSQL → CDC Connector → raw-event-headers → Flink → Filtered Topics"
    exit 0
elif [ "$TOTAL_VALIDATED" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Partial validation: $TOTAL_VALIDATED/$TOTAL_EXPECTED events found${NC}"
    echo ""
    echo -e "${CYAN}Troubleshooting:${NC}"
    echo "  1. Check CDC connector status: confluent connect list"
    echo "  2. Check raw-event-headers topic: confluent kafka topic consume raw-event-headers --max-messages 5"
    echo "  3. Check Flink statements: confluent flink statement list --compute-pool <pool-id>"
    echo "  4. Increase wait time: $0 $EVENTS_PER_TYPE $DB_TYPE \"$API_URL\" $((WAIT_TIME + 30))"
    echo "  5. Check connector logs for errors"
    exit 1
else
    echo -e "${RED}❌ No events validated${NC}"
    echo ""
    echo -e "${CYAN}Troubleshooting:${NC}"
    echo "  1. Verify events were sent: Check $EVENTS_FILE"
    echo "  2. Check CDC connector is running: confluent connect list"
    echo "  3. Check raw-event-headers topic has messages"
    echo "  4. Check Flink statements are running"
    echo "  5. Increase wait time significantly: $0 $EVENTS_PER_TYPE $DB_TYPE \"$API_URL\" $((WAIT_TIME * 2))"
    exit 1
fi
