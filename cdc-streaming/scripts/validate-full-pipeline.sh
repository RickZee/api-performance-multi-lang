#!/usr/bin/env bash
# Validate Full CDC Pipeline End-to-End
# 1. Sends 10 events of each type to Lambda API
# 2. Validates events in Aurora PostgreSQL
# 3. Validates events in raw-event-headers Kafka topic
# 4. Validates events in 4 filtered Kafka topics
#
# Usage:
#   ./cdc-streaming/scripts/validate-full-pipeline.sh [EVENTS_PER_TYPE] [DB_TYPE] [API_URL] [WAIT_TIME]
#
# Examples:
#   # Default: 10 events per type, PostgreSQL Lambda, 60s wait
#   ./cdc-streaming/scripts/validate-full-pipeline.sh
#
#   # 5 events per type, DSQL Lambda, 90s wait
#   ./cdc-streaming/scripts/validate-full-pipeline.sh 5 dsql "" 90
#
# Requirements:
#   - k6 installed
#   - Confluent CLI installed and logged in
#   - jq installed
#   - Python 3 with asyncpg (for Aurora validation)
#   - AURORA_ENDPOINT and AURORA_PASSWORD environment variables set

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

# Filtered topics mapping (using function instead of associative array for compatibility)
get_topic_for_event_type() {
    case "$1" in
        CarCreated) echo "filtered-car-created-events" ;;
        LoanCreated) echo "filtered-loan-created-events" ;;
        LoanPaymentSubmitted) echo "filtered-loan-payment-submitted-events" ;;
        CarServiceDone) echo "filtered-service-events" ;;
        *) echo "" ;;
    esac
}

EVENT_TYPES=("CarCreated" "LoanCreated" "LoanPaymentSubmitted" "CarServiceDone")
RAW_TOPIC="raw-event-headers"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Full Pipeline Validation${NC}"
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

if ! command -v python3 &> /dev/null; then
    fail "python3 not found"
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
EVENTS_FILE="/tmp/full-pipeline-validation-$(date +%s).json"
TEMP_OUTPUT="/tmp/k6-output-$(date +%s).txt"

# Step 1: Send events using k6
echo -e "${BLUE}[1/5] Sending events to Lambda API...${NC}"
cd "$PROJECT_ROOT/load-test/k6"

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

# Step 2: Wait for database and CDC propagation
echo -e "${BLUE}[2/5] Waiting for database and CDC propagation (${WAIT_TIME}s)...${NC}"
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

# Step 3: Validate Aurora PostgreSQL
echo -e "${BLUE}[3/5] Validating events in Aurora PostgreSQL...${NC}"

if [ -z "$AURORA_ENDPOINT" ] || [ -z "$AURORA_PASSWORD" ]; then
    warn "Aurora credentials not set (AURORA_ENDPOINT, AURORA_PASSWORD)"
    warn "Skipping Aurora validation"
    AURORA_VALIDATED=false
else
    if python3 "$PROJECT_ROOT/scripts/validate-against-sent-events.py" \
        --events-file "$EVENTS_FILE" \
        --aurora \
        --aurora-endpoint "$AURORA_ENDPOINT" \
        --aurora-password "$AURORA_PASSWORD" 2>&1 | tee /tmp/aurora-validation.log; then
        AURORA_RESULTS=$(grep -E "(Events Found|Success Rate)" /tmp/aurora-validation.log || echo "")
        if echo "$AURORA_RESULTS" | grep -q "100%"; then
            pass "All events found in Aurora PostgreSQL"
            AURORA_VALIDATED=true
        else
            warn "Some events missing in Aurora PostgreSQL"
            AURORA_VALIDATED=false
        fi
    else
        fail "Aurora validation failed"
        AURORA_VALIDATED=false
    fi
fi
echo ""

# Step 4: Extract event UUIDs by type
echo -e "${BLUE}[4/5] Extracting event UUIDs by type...${NC}"

# Store UUIDs in temporary files (compatible with all bash versions)
TIMESTAMP=$(date +%s)
for event_type in "${EVENT_TYPES[@]}"; do
    UUID_FILE="/tmp/uuid-${event_type}-${TIMESTAMP}.txt"
    jq -r ".[] | select(.eventType == \"$event_type\") | .uuid" "$EVENTS_FILE" 2>/dev/null | sort -u > "$UUID_FILE"
    COUNT=$(grep -c . "$UUID_FILE" 2>/dev/null || echo "0")
    if [ "$COUNT" -gt 0 ]; then
        pass "Found $COUNT $event_type events"
        # Store file path using eval for bash 3 compatibility
        eval "UUID_FILE_${event_type//-/_}=\"$UUID_FILE\""
    else
        warn "No $event_type events found"
        rm -f "$UUID_FILE"
        eval "UUID_FILE_${event_type//-/_}=\"\""
    fi
done
echo ""

# Step 5: Validate Kafka topics
echo -e "${BLUE}[5/5] Validating events in Kafka topics...${NC}"
echo ""

# 5a. Validate raw-event-headers topic
echo -e "${CYAN}5a. Validating raw-event-headers topic${NC}"

if ! confluent kafka topic describe "$RAW_TOPIC" &>/dev/null; then
    fail "Topic '$RAW_TOPIC' does not exist"
    RAW_VALIDATED=false
else
    info "Consuming messages from $RAW_TOPIC..."
    CONSUMED_MSGS_FILE="/tmp/raw-consumed-$(date +%s).jsonl"
    
    confluent kafka topic consume "$RAW_TOPIC" \
        --max-messages $((EVENT_COUNT + 50)) \
        --timeout 30 2>&1 | \
        grep -v "^Consumer group" | \
        grep -v "^Starting consumer" | \
        grep -v "^No messages" | \
        grep -v "^Waiting" | \
        grep -E '^\{|^\[|"id"' > "$CONSUMED_MSGS_FILE" || true
    
    # Extract UUIDs - try multiple parsing strategies
    RAW_UUIDS=""
    if [ -s "$CONSUMED_MSGS_FILE" ]; then
        RAW_UUIDS=$(cat "$CONSUMED_MSGS_FILE" 2>/dev/null | \
            # Strategy 1: Direct JSON with 'id' field
            jq -R 'fromjson? | select(. != null and .id != null) | .id' 2>/dev/null | \
            grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || true)
        
        # Strategy 2: Nested in 'value' field
        if [ -z "$RAW_UUIDS" ] || [ "$(echo "$RAW_UUIDS" | grep -c . || echo "0")" -eq 0 ]; then
            RAW_UUIDS=$(cat "$CONSUMED_MSGS_FILE" 2>/dev/null | \
                jq -R 'fromjson? | select(. != null and .value != null) | .value | fromjson? | select(. != null and .id != null) | .id' 2>/dev/null | \
                grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || true)
        fi
        
        # Strategy 3: Extract UUID pattern from any JSON
        if [ -z "$RAW_UUIDS" ] || [ "$(echo "$RAW_UUIDS" | grep -c . || echo "0")" -eq 0 ]; then
            RAW_UUIDS=$(cat "$CONSUMED_MSGS_FILE" 2>/dev/null | \
                grep -oE '"id"\s*:\s*"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"' | \
                sed 's/.*"id"\s*:\s*"\([^"]*\)".*/\1/' | \
                grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || true)
        fi
        
        # Sort and deduplicate
        RAW_UUIDS=$(echo "$RAW_UUIDS" | sort -u | grep -v '^$' || echo "")
    fi
    
    rm -f "$CONSUMED_MSGS_FILE"
    
    RAW_COUNT=$(echo "$RAW_UUIDS" | grep -c . 2>/dev/null || echo "0")
    RAW_COUNT=$(echo "$RAW_COUNT" | tr -d '\n' | head -1)
    
    if [ -z "$RAW_COUNT" ] || [ "$RAW_COUNT" -eq 0 ]; then
        warn "No UUIDs found in $RAW_TOPIC"
        RAW_VALIDATED=false
    else
        # Check how many of our sent UUIDs are in raw topic
        SENT_UUIDS=$(jq -r '.[].uuid' "$EVENTS_FILE" 2>/dev/null | sort -u)
        FOUND_IN_RAW=0
        while IFS= read -r uuid; do
            if [ -n "$uuid" ] && echo "$RAW_UUIDS" | grep -q "^${uuid}$"; then
                FOUND_IN_RAW=$((FOUND_IN_RAW + 1))
            fi
        done <<< "$SENT_UUIDS"
        
        if [ "$FOUND_IN_RAW" -eq "$EVENT_COUNT" ]; then
            pass "All $EVENT_COUNT events found in $RAW_TOPIC"
            RAW_VALIDATED=true
        elif [ "$FOUND_IN_RAW" -gt 0 ]; then
            warn "Only $FOUND_IN_RAW/$EVENT_COUNT events found in $RAW_TOPIC"
            RAW_VALIDATED=false
        else
            warn "No sent events found in $RAW_TOPIC (found $RAW_COUNT total UUIDs)"
            RAW_VALIDATED=false
        fi
    fi
fi
echo ""

# 5b. Validate filtered topics
echo -e "${CYAN}5b. Validating filtered topics${NC}"
echo ""

TOTAL_VALIDATED=0
TOTAL_EXPECTED=0
FILTERED_VALIDATED=true

for event_type in "${EVENT_TYPES[@]}"; do
    topic=$(get_topic_for_event_type "$event_type")
    # Convert event type to variable name (replace - with _)
    uuid_file_var="UUID_FILE_${event_type//-/_}"
    uuid_file=$(eval echo \$$uuid_file_var)
    
    if [ -z "$uuid_file" ] || [ ! -f "$uuid_file" ]; then
        expected_count=0
    else
        expected_count=$(grep -c . "$uuid_file" 2>/dev/null || echo "0")
    fi
    TOTAL_EXPECTED=$((TOTAL_EXPECTED + expected_count))
    
    if [ "$expected_count" -eq 0 ]; then
        warn "Skipping $event_type (no events sent)"
        echo ""
        continue
    fi
    
    echo -e "${CYAN}  Validating $event_type → $topic${NC}"
    
    if ! confluent kafka topic describe "$topic" &>/dev/null; then
        fail "    Topic '$topic' does not exist"
        FILTERED_VALIDATED=false
        echo ""
        continue
    fi
    
    info "    Consuming messages from $topic..."
    CONSUMED_MSGS_FILE="/tmp/filtered-${topic}-$(date +%s).jsonl"
    
    confluent kafka topic consume "$topic" \
        --max-messages $((expected_count + 50)) \
        --timeout 30 2>&1 | \
        grep -v "^Consumer group" | \
        grep -v "^Starting consumer" | \
        grep -v "^No messages" | \
        grep -v "^Waiting" | \
        grep -E '^\{|^\[|"id"' > "$CONSUMED_MSGS_FILE" || true
    
    # Extract UUIDs - try multiple parsing strategies
    CONSUMED_UUIDS=""
    if [ -s "$CONSUMED_MSGS_FILE" ]; then
        CONSUMED_UUIDS=$(cat "$CONSUMED_MSGS_FILE" 2>/dev/null | \
            # Strategy 1: Direct JSON with 'id' field
            jq -R 'fromjson? | select(. != null and .id != null) | .id' 2>/dev/null | \
            grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || true)
        
        # Strategy 2: Nested in 'value' field
        if [ -z "$CONSUMED_UUIDS" ] || [ "$(echo "$CONSUMED_UUIDS" | grep -c . || echo "0")" -eq 0 ]; then
            CONSUMED_UUIDS=$(cat "$CONSUMED_MSGS_FILE" 2>/dev/null | \
                jq -R 'fromjson? | select(. != null and .value != null) | .value | fromjson? | select(. != null and .id != null) | .id' 2>/dev/null | \
                grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || true)
        fi
        
        # Strategy 3: Extract UUID pattern from any JSON
        if [ -z "$CONSUMED_UUIDS" ] || [ "$(echo "$CONSUMED_UUIDS" | grep -c . || echo "0")" -eq 0 ]; then
            CONSUMED_UUIDS=$(cat "$CONSUMED_MSGS_FILE" 2>/dev/null | \
                grep -oE '"id"\s*:\s*"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"' | \
                sed 's/.*"id"\s*:\s*"\([^"]*\)".*/\1/' | \
                grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || true)
        fi
        
        # Sort and deduplicate
        CONSUMED_UUIDS=$(echo "$CONSUMED_UUIDS" | sort -u | grep -v '^$' || echo "")
    fi
    
    rm -f "$CONSUMED_MSGS_FILE"
    
    CONSUMED_COUNT=$(echo "$CONSUMED_UUIDS" | grep -c . 2>/dev/null || echo "0")
    CONSUMED_COUNT=$(echo "$CONSUMED_COUNT" | tr -d '\n' | head -1)
    
    if [ -z "$CONSUMED_COUNT" ] || [ "$CONSUMED_COUNT" -eq 0 ]; then
        warn "    No UUIDs extracted from $topic"
        FILTERED_VALIDATED=false
        echo ""
        continue
    fi
    
    # Count how many of our sent UUIDs appear in consumed messages
    FOUND_COUNT=0
    MISSING_UUIDS=()
    
    if [ -f "$uuid_file" ]; then
        while IFS= read -r uuid; do
            if [ -n "$uuid" ]; then
                if echo "$CONSUMED_UUIDS" | grep -q "^${uuid}$"; then
                    FOUND_COUNT=$((FOUND_COUNT + 1))
                else
                    MISSING_UUIDS+=("$uuid")
                fi
            fi
        done < "$uuid_file"
    fi
    
    TOTAL_VALIDATED=$((TOTAL_VALIDATED + FOUND_COUNT))
    
    if [ "$FOUND_COUNT" -eq "$expected_count" ]; then
        pass "    All $expected_count $event_type events found in $topic"
    elif [ "$FOUND_COUNT" -gt 0 ]; then
        warn "    Only $FOUND_COUNT/$expected_count $event_type events found in $topic"
        if [ ${#MISSING_UUIDS[@]} -le 3 ]; then
            info "    Missing UUIDs: ${MISSING_UUIDS[*]}"
        fi
        FILTERED_VALIDATED=false
    else
        fail "    No $event_type events found in $topic"
        FILTERED_VALIDATED=false
    fi
    
    echo ""
done

# Clean up temporary UUID files
for event_type in "${EVENT_TYPES[@]}"; do
    uuid_file_var="UUID_FILE_${event_type//-/_}"
    uuid_file=$(eval echo \$$uuid_file_var)
    [ -n "$uuid_file" ] && [ -f "$uuid_file" ] && rm -f "$uuid_file"
done

# Summary
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Validation Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

echo "Total events sent: $EVENT_COUNT"
echo ""

# Aurora validation summary
if [ "$AURORA_VALIDATED" = true ]; then
    echo -e "${GREEN}✓ Aurora PostgreSQL: All events found${NC}"
elif [ "$AURORA_VALIDATED" = false ] && [ -n "$AURORA_ENDPOINT" ]; then
    echo -e "${YELLOW}⚠ Aurora PostgreSQL: Some events missing${NC}"
else
    echo -e "${YELLOW}○ Aurora PostgreSQL: Skipped (credentials not set)${NC}"
fi

# Raw topic validation summary
if [ "$RAW_VALIDATED" = true ]; then
    echo -e "${GREEN}✓ raw-event-headers topic: All events found${NC}"
else
    echo -e "${YELLOW}⚠ raw-event-headers topic: Some events missing${NC}"
fi

# Filtered topics validation summary
echo "Filtered topics validation: $TOTAL_VALIDATED/$TOTAL_EXPECTED events found"
if [ "$FILTERED_VALIDATED" = true ] && [ "$TOTAL_VALIDATED" -eq "$TOTAL_EXPECTED" ] && [ "$TOTAL_EXPECTED" -gt 0 ]; then
    echo -e "${GREEN}✓ All filtered topics: All events found${NC}"
else
    echo -e "${YELLOW}⚠ Filtered topics: Some events missing${NC}"
fi

echo ""

# Overall result
ALL_VALIDATED=true
[ "$AURORA_VALIDATED" = false ] && [ -n "$AURORA_ENDPOINT" ] && ALL_VALIDATED=false
[ "$RAW_VALIDATED" = false ] && ALL_VALIDATED=false
[ "$FILTERED_VALIDATED" = false ] && ALL_VALIDATED=false
[ "$TOTAL_VALIDATED" -ne "$TOTAL_EXPECTED" ] && ALL_VALIDATED=false

if [ "$ALL_VALIDATED" = true ]; then
    echo -e "${GREEN}✅ Full pipeline validation PASSED!${NC}"
    echo ""
    echo -e "${CYAN}Pipeline flow verified:${NC}"
    echo "  Lambda API → PostgreSQL → CDC Connector → raw-event-headers → Flink → Filtered Topics"
    echo ""
    exit 0
else
    echo -e "${YELLOW}⚠️  Full pipeline validation had issues${NC}"
    echo ""
    echo -e "${CYAN}Troubleshooting:${NC}"
    echo "  1. Check CDC connector: confluent connect list"
    echo "  2. Check raw-event-headers: confluent kafka topic consume raw-event-headers --max-messages 5"
    echo "  3. Check Flink statements: confluent flink statement list --compute-pool <pool-id>"
    echo "  4. Increase wait time: $0 $EVENTS_PER_TYPE $DB_TYPE \"$API_URL\" $((WAIT_TIME + 30))"
    echo "  5. Check connector logs for errors"
    echo ""
    exit 1
fi
