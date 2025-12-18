#!/usr/bin/env bash
# Validate events in Kafka topics
# Checks raw-event-headers topic and filtered topics for Flink or Spring Boot
#
# Usage:
#   ./cdc-streaming/scripts/validate-kafka-topics.sh <EVENTS_FILE> [PROCESSOR]
#
# Example:
#   ./cdc-streaming/scripts/validate-kafka-topics.sh /tmp/events.json flink
#   ./cdc-streaming/scripts/validate-kafka-topics.sh /tmp/events.json spring
#
# PROCESSOR can be: flink, spring, or both (default: both)
#   - flink: Validates only -flink suffixed topics
#   - spring: Validates only -spring suffixed topics
#   - both: Validates both (for testing/validation)

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

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

EVENTS_FILE="$1"
PROCESSOR="${2:-both}"  # Default to both if not specified

if [ -z "$EVENTS_FILE" ]; then
    fail "Events file required"
    echo "Usage: $0 <EVENTS_FILE> [PROCESSOR]"
    echo "  PROCESSOR: flink, spring, or both (default: both)"
    exit 1
fi

if [ ! -f "$EVENTS_FILE" ]; then
    fail "Events file not found: $EVENTS_FILE"
    exit 1
fi

# Validate processor option
if [ "$PROCESSOR" != "flink" ] && [ "$PROCESSOR" != "spring" ] && [ "$PROCESSOR" != "both" ]; then
    fail "Invalid processor: $PROCESSOR (must be: flink, spring, or both)"
    exit 1
fi

info "Validating for processor: $PROCESSOR"

# Check prerequisites
if ! command -v confluent &> /dev/null; then
    fail "Confluent CLI not found"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    fail "jq not found"
    exit 1
fi

# Check Confluent Cloud login
# Source environment files if they exist
if [ -f "$PROJECT_ROOT/cdc-streaming/.env" ]; then
    source "$PROJECT_ROOT/cdc-streaming/.env"
fi

# Check if logged in to Confluent Cloud
if ! confluent environment list &> /dev/null; then
    fail "Not logged in to Confluent Cloud. Run: confluent login"
    exit 1
fi

pass "Confluent Cloud authenticated"

# Topic mappings (using function instead of associative array for compatibility)
# Returns topic name based on event type and processor
get_topic_for_event_type() {
    local event_type="$1"
    local processor="${2:-$PROCESSOR}"
    
    case "$event_type" in
        CarCreated)
            if [ "$processor" = "flink" ]; then
                echo "filtered-car-created-events-flink"
            elif [ "$processor" = "spring" ]; then
                echo "filtered-car-created-events-spring"
            else
                # For "both", return base name and let caller handle it
                echo "filtered-car-created-events"
            fi
            ;;
        LoanCreated)
            if [ "$processor" = "flink" ]; then
                echo "filtered-loan-created-events-flink"
            elif [ "$processor" = "spring" ]; then
                echo "filtered-loan-created-events-spring"
            else
                echo "filtered-loan-created-events"
            fi
            ;;
        LoanPaymentSubmitted)
            if [ "$processor" = "flink" ]; then
                echo "filtered-loan-payment-submitted-events-flink"
            elif [ "$processor" = "spring" ]; then
                echo "filtered-loan-payment-submitted-events-spring"
            else
                echo "filtered-loan-payment-submitted-events"
            fi
            ;;
        CarServiceDone)
            if [ "$processor" = "flink" ]; then
                echo "filtered-service-events-flink"
            elif [ "$processor" = "spring" ]; then
                echo "filtered-service-events-spring"
            else
                echo "filtered-service-events"
            fi
            ;;
        *) echo "" ;;
    esac
}

# Get UUIDs for event type from events file
get_uuids_for_event_type() {
    local event_type="$1"
    jq -r ".[] | select(.eventType == \"$event_type\") | .uuid" "$EVENTS_FILE" 2>/dev/null | grep -v "^null$" || echo ""
}

RAW_TOPIC="raw-event-headers"

# Get event UUIDs
EVENT_COUNT=$(jq 'length' "$EVENTS_FILE" 2>/dev/null || echo "0")

if [ "$EVENT_COUNT" -eq 0 ]; then
    fail "No events found in events file"
    exit 1
fi

info "Validating $EVENT_COUNT events in Kafka topics..."
echo ""

# Extract event UUIDs by type (already done above, this is a duplicate - removing)

# Step 1: Validate raw-event-headers topic
echo -e "${CYAN}Step 1: Validate raw-event-headers Topic${NC}"
echo ""

if ! confluent kafka topic describe "$RAW_TOPIC" &>/dev/null; then
    fail "Topic '$RAW_TOPIC' does not exist or Confluent CLI not authenticated"
    warn "To fix: confluent login"
    warn "Or verify topic exists: confluent kafka topic list"
    # Continue anyway - might be a permission issue
fi

info "Consuming messages from $RAW_TOPIC..."
CONSUMED_RAW_FILE="/tmp/raw-events-$(date +%s).jsonl"

# Use a unique consumer group to avoid conflicts with other consumers
CONSUMER_GROUP="validation-group-$(date +%s)"

# Check topic offsets first to see if messages are present
info "Checking topic offsets..."
LATEST_OFFSET=$(confluent kafka topic describe "$RAW_TOPIC" --output json 2>/dev/null | jq -r '.partitions[0].latest_offset // "0"' 2>/dev/null || echo "0")
EARLIEST_OFFSET=$(confluent kafka topic describe "$RAW_TOPIC" --output json 2>/dev/null | jq -r '.partitions[0].earliest_offset // "0"' 2>/dev/null || echo "0")
MESSAGE_COUNT=$((LATEST_OFFSET - EARLIEST_OFFSET))

if [ "$MESSAGE_COUNT" -gt 0 ] 2>/dev/null; then
    info "Topic has approximately $MESSAGE_COUNT messages (offset range: $EARLIEST_OFFSET to $LATEST_OFFSET)"
else
    warn "Could not determine message count from offsets"
fi
echo ""

# Polling function to check if enough messages consumed
poll_consume_complete() {
  local file="$1"
  local expected="$2"
  local max_wait="${3:-15}"
  local elapsed=0
  
  while [ $elapsed -lt $max_wait ]; do
    local count=$(wc -l < "$file" 2>/dev/null | tr -d ' ' || echo "0")
    if [ "$count" -ge "$expected" ] 2>/dev/null; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}

# Consume messages - use a background process
# Note: confluent CLI doesn't support --max-messages, so we limit with head and poll
# Try --from-beginning first to get all messages
info "Consuming messages from beginning of topic..."
(confluent kafka topic consume "$RAW_TOPIC" \
    --from-beginning \
    --group "$CONSUMER_GROUP" 2>&1 | \
    grep -v "^Consumer group" | \
    grep -v "^Starting consumer" | \
    grep -v "^No messages" | \
    grep -v "^Waiting" | \
    grep -E '^\{|^\[|"id"' | \
    head -$((EVENT_COUNT + 20)) > "$CONSUMED_RAW_FILE" 2>&1 &)
CONSUME_PID=$!
# Poll instead of fixed wait
if poll_consume_complete "$CONSUMED_RAW_FILE" "$EVENT_COUNT" 15; then
  info "Consumed enough messages (early exit)"
fi
kill $CONSUME_PID 2>/dev/null || true
wait $CONSUME_PID 2>/dev/null || true

# If no messages found from beginning, try reading from latest offset as fallback
if [ ! -s "$CONSUMED_RAW_FILE" ] || [ "$(wc -l < "$CONSUMED_RAW_FILE" 2>/dev/null | tr -d ' ')" -eq 0 ]; then
    warn "No messages found from beginning, trying latest offset..."
    LATEST_CONSUMER_GROUP="validation-group-latest-$(date +%s)"
    (confluent kafka topic consume "$RAW_TOPIC" \
        --group "$LATEST_CONSUMER_GROUP" 2>&1 | \
        grep -v "^Consumer group" | \
        grep -v "^Starting consumer" | \
        grep -v "^No messages" | \
        grep -v "^Waiting" | \
        grep -E '^\{|^\[|"id"' | \
        head -$((EVENT_COUNT + 20)) > "$CONSUMED_RAW_FILE" 2>&1 &)
    LATEST_CONSUME_PID=$!
    # Poll instead of fixed wait
    if poll_consume_complete "$CONSUMED_RAW_FILE" "$EVENT_COUNT" 10; then
      info "Consumed enough messages from latest (early exit)"
    fi
    kill $LATEST_CONSUME_PID 2>/dev/null || true
    wait $LATEST_CONSUME_PID 2>/dev/null || true
fi

# Extract UUIDs from raw topic
RAW_FOUND_UUIDS=""
if [ -s "$CONSUMED_RAW_FILE" ]; then
    RAW_FOUND_UUIDS=$(cat "$CONSUMED_RAW_FILE" 2>/dev/null | \
        jq -r 'if type == "object" then .id // empty elif type == "array" then .[].id // empty else empty end' 2>/dev/null | \
        grep -v "^null$" | sort -u)
fi

# Count UUIDs found, handling empty case
if [ -z "$RAW_FOUND_UUIDS" ] || [ "$RAW_FOUND_UUIDS" = "" ]; then
    RAW_FOUND_COUNT=0
else
    RAW_FOUND_COUNT=$(echo "$RAW_FOUND_UUIDS" | wc -l | tr -d '[:space:]')
    # Ensure it's a number
    if ! [[ "$RAW_FOUND_COUNT" =~ ^[0-9]+$ ]]; then
        RAW_FOUND_COUNT=0
    fi
fi

if [ "$RAW_FOUND_COUNT" -ge "$EVENT_COUNT" ] 2>/dev/null; then
    pass "Found at least $EVENT_COUNT events in $RAW_TOPIC"
else
    warn "Found $RAW_FOUND_COUNT events in $RAW_TOPIC (expected at least $EVENT_COUNT)"
fi
echo ""

# Step 2: Validate filtered topics for each event type
echo -e "${CYAN}Step 2: Validate Filtered Topics${NC}"
echo ""

TOTAL_VALIDATED=0
TOTAL_EXPECTED=0
VALIDATION_FAILED=false

for event_type in CarCreated LoanCreated LoanPaymentSubmitted CarServiceDone; do
    expected_uuids=$(get_uuids_for_event_type "$event_type")
    expected_count=$(echo "$expected_uuids" | grep -c . || echo "0")
    
    if [ "$expected_count" -eq 0 ]; then
        warn "Skipping $event_type (no events of this type submitted)"
        echo ""
        continue
    fi
    
    # Determine which topics to validate based on processor setting
    if [ "$PROCESSOR" = "both" ]; then
        # Validate both Flink and Spring Boot topics
        topics=("$(get_topic_for_event_type "$event_type" flink)" "$(get_topic_for_event_type "$event_type" spring)")
    else
        # Validate single processor topic
        topics=("$(get_topic_for_event_type "$event_type" "$PROCESSOR")")
    fi
    
    for topic in "${topics[@]}"; do
        if [ -z "$topic" ]; then
            continue
        fi
        
        TOTAL_EXPECTED=$((TOTAL_EXPECTED + expected_count))
        
        info "Validating $event_type → $topic"
        
        # Check if topic exists
        if ! confluent kafka topic describe "$topic" &>/dev/null; then
            fail "  Topic '$topic' does not exist"
            VALIDATION_FAILED=true
            echo ""
            continue
        fi
        
        # Consume messages from filtered topic
        CONSUMED_FILE="/tmp/filtered-${topic}-$(date +%s).jsonl"
        
        # Use a unique consumer group for each topic to avoid conflicts
        FILTERED_CONSUMER_GROUP="validation-filtered-${topic}-$(date +%s)"
        
        info "  Consuming messages from $topic..."
    
        # Check topic offsets first
        LATEST_OFFSET=$(confluent kafka topic describe "$topic" --output json 2>/dev/null | jq -r '.partitions[0].latest_offset // "0"' 2>/dev/null || echo "0")
        EARLIEST_OFFSET=$(confluent kafka topic describe "$topic" --output json 2>/dev/null | jq -r '.partitions[0].earliest_offset // "0"' 2>/dev/null || echo "0")
        TOPIC_MESSAGE_COUNT=$((LATEST_OFFSET - EARLIEST_OFFSET))
        
        if [ "$TOPIC_MESSAGE_COUNT" -gt 0 ] 2>/dev/null; then
            info "  Topic has approximately $TOPIC_MESSAGE_COUNT messages"
        fi
        
        # Consume messages - use a background process
        # Try --from-beginning first to get all messages
        (confluent kafka topic consume "$topic" \
            --from-beginning \
            --group "$FILTERED_CONSUMER_GROUP" 2>&1 | \
            grep -v "^Consumer group" | \
            grep -v "^Starting consumer" | \
            grep -v "^No messages" | \
            grep -v "^Waiting" | \
            grep -E '^\{|^\[|"id"' | \
            head -$((expected_count + 10)) > "$CONSUMED_FILE" 2>&1 &)
        CONSUME_PID=$!
        # Poll instead of fixed wait
        if poll_consume_complete "$CONSUMED_FILE" "$expected_count" 15; then
          info "  Consumed enough messages (early exit)"
        fi
        kill $CONSUME_PID 2>/dev/null || true
        wait $CONSUME_PID 2>/dev/null || true
        
        # If no messages found from beginning, try reading from latest offset as fallback
        if [ ! -s "$CONSUMED_FILE" ] || [ "$(wc -l < "$CONSUMED_FILE" 2>/dev/null | tr -d ' ')" -eq 0 ]; then
            warn "  No messages found from beginning, trying latest offset..."
            LATEST_FILTERED_GROUP="validation-filtered-latest-${topic}-$(date +%s)"
            (confluent kafka topic consume "$topic" \
                --group "$LATEST_FILTERED_GROUP" 2>&1 | \
                grep -v "^Consumer group" | \
                grep -v "^Starting consumer" | \
                grep -v "^No messages" | \
                grep -v "^Waiting" | \
                grep -E '^\{|^\[|"id"' | \
                head -$((expected_count + 10)) > "$CONSUMED_FILE" 2>&1 &)
            LATEST_CONSUME_PID=$!
            # Poll instead of fixed wait
            if poll_consume_complete "$CONSUMED_FILE" "$expected_count" 10; then
              info "  Consumed enough messages from latest (early exit)"
            fi
            kill $LATEST_CONSUME_PID 2>/dev/null || true
            wait $LATEST_CONSUME_PID 2>/dev/null || true
        fi
        
        # Extract UUIDs from consumed messages
        FOUND_UUIDS=""
        if [ -s "$CONSUMED_FILE" ]; then
            FOUND_UUIDS=$(cat "$CONSUMED_FILE" 2>/dev/null | \
                jq -r 'if type == "object" then .id // empty elif type == "array" then .[].id // empty else empty end' 2>/dev/null | \
                grep -v "^null$" | sort -u)
        fi
        
        # Check for each expected UUID
        FOUND_COUNT=0
        MISSING_UUIDS=()
        
        for uuid in $expected_uuids; do
            if echo "$FOUND_UUIDS" | grep -q "^${uuid}$"; then
                FOUND_COUNT=$((FOUND_COUNT + 1))
            else
                MISSING_UUIDS+=("$uuid")
            fi
        done
        
        if [ "$FOUND_COUNT" -eq "$expected_count" ]; then
            pass "  All $expected_count $event_type events found in $topic"
            TOTAL_VALIDATED=$((TOTAL_VALIDATED + FOUND_COUNT))
        elif [ "$FOUND_COUNT" -gt 0 ]; then
            warn "  Only $FOUND_COUNT/$expected_count $event_type events found in $topic"
            if [ ${#MISSING_UUIDS[@]} -le 3 ]; then
                info "  Missing UUIDs: ${MISSING_UUIDS[*]}"
            fi
            TOTAL_VALIDATED=$((TOTAL_VALIDATED + FOUND_COUNT))
            VALIDATION_FAILED=true
        else
            fail "  No $event_type events found in $topic"
            VALIDATION_FAILED=true
        fi
        
        # Cleanup
        rm -f "$CONSUMED_FILE"
        echo ""
    done
done

# Summary
echo -e "${CYAN}Validation Summary${NC}"
echo ""
echo "Total events expected: $TOTAL_EXPECTED"
echo "Total events validated: $TOTAL_VALIDATED"
echo ""

if [ "$VALIDATION_FAILED" = true ]; then
    fail "Some events not found in filtered topics"
    echo ""
    echo "Troubleshooting:"
    echo "  - Check CDC connector status: confluent connect list"
    echo "  - Check Flink statements: confluent flink statement list"
    echo "  - Check Spring Boot service: docker-compose -f cdc-streaming/docker-compose.yml ps"
    echo "  - Increase wait time for CDC propagation"
    exit 1
fi

pass "All events validated in Kafka topics"
exit 0
