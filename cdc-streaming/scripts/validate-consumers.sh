#!/usr/bin/env bash
# Validate dockerized consumers receive events
# Starts consumers, monitors logs, and verifies they receive expected events
#
# Usage:
#   ./cdc-streaming/scripts/validate-consumers.sh <EVENTS_FILE>
#
# Example:
#   ./cdc-streaming/scripts/validate-consumers.sh /tmp/events.json

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT/cdc-streaming"

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
section() { echo -e "${CYAN}========================================${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}========================================${NC}"; }

EVENTS_FILE="$1"

if [ -z "$EVENTS_FILE" ]; then
    fail "Events file required"
    echo "Usage: $0 <EVENTS_FILE>"
    exit 1
fi

if [ ! -f "$EVENTS_FILE" ]; then
    fail "Events file not found: $EVENTS_FILE"
    exit 1
fi

# Check prerequisites
if ! command -v docker &> /dev/null; then
    fail "docker not found"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    fail "docker-compose not found"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    fail "jq not found"
    exit 1
fi

# Consumer mappings (using function instead of associative array)
# Returns both Spring and Flink consumers for each event type
get_consumers_for_event_type() {
    case "$1" in
        CarCreated) echo "car-consumer car-consumer-flink" ;;
        LoanCreated) echo "loan-consumer loan-consumer-flink" ;;
        LoanPaymentSubmitted) echo "loan-payment-consumer loan-payment-consumer-flink" ;;
        CarServiceDone) echo "service-consumer service-consumer-flink" ;;
        *) echo "" ;;
    esac
}

# Get Spring consumer only (for backward compatibility)
get_spring_consumer_for_event_type() {
    case "$1" in
        CarCreated) echo "car-consumer" ;;
        LoanCreated) echo "loan-consumer" ;;
        LoanPaymentSubmitted) echo "loan-payment-consumer" ;;
        CarServiceDone) echo "service-consumer" ;;
        *) echo "" ;;
    esac
}

# Get Flink consumer only
get_flink_consumer_for_event_type() {
    case "$1" in
        CarCreated) echo "car-consumer-flink" ;;
        LoanCreated) echo "loan-consumer-flink" ;;
        LoanPaymentSubmitted) echo "loan-payment-consumer-flink" ;;
        CarServiceDone) echo "service-consumer-flink" ;;
        *) echo "" ;;
    esac
}

# Get event UUIDs by type
EVENT_COUNT=$(jq 'length' "$EVENTS_FILE" 2>/dev/null || echo "0")

if [ "$EVENT_COUNT" -eq 0 ]; then
    fail "No events found in events file"
    exit 1
fi

# Create temporary files for each event type
CAR_UUIDS_FILE="/tmp/car-uuids-consumer-$(date +%s).txt"
LOAN_UUIDS_FILE="/tmp/loan-uuids-consumer-$(date +%s).txt"
PAYMENT_UUIDS_FILE="/tmp/payment-uuids-consumer-$(date +%s).txt"
SERVICE_UUIDS_FILE="/tmp/service-uuids-consumer-$(date +%s).txt"

> "$CAR_UUIDS_FILE"
> "$LOAN_UUIDS_FILE"
> "$PAYMENT_UUIDS_FILE"
> "$SERVICE_UUIDS_FILE"

for i in $(seq 0 $((EVENT_COUNT - 1))); do
    EVENT_TYPE=$(jq -r ".[$i].eventType" "$EVENTS_FILE")
    EVENT_UUID=$(jq -r ".[$i].uuid" "$EVENTS_FILE")
    case "$EVENT_TYPE" in
        CarCreated) echo "$EVENT_UUID" >> "$CAR_UUIDS_FILE" ;;
        LoanCreated) echo "$EVENT_UUID" >> "$LOAN_UUIDS_FILE" ;;
        LoanPaymentSubmitted) echo "$EVENT_UUID" >> "$PAYMENT_UUIDS_FILE" ;;
        CarServiceDone) echo "$EVENT_UUID" >> "$SERVICE_UUIDS_FILE" ;;
    esac
done

get_uuids_for_event_type() {
    case "$1" in
        CarCreated) cat "$CAR_UUIDS_FILE" 2>/dev/null || echo "" ;;
        LoanCreated) cat "$LOAN_UUIDS_FILE" 2>/dev/null || echo "" ;;
        LoanPaymentSubmitted) cat "$PAYMENT_UUIDS_FILE" 2>/dev/null || echo "" ;;
        CarServiceDone) cat "$SERVICE_UUIDS_FILE" 2>/dev/null || echo "" ;;
        *) echo "" ;;
    esac
}

section "Consumer Validation"
echo ""

# Step 10.1: Verify consumers are running (they should already be started in Step 3)
section "Step 10.1: Verify Consumers Are Running"
echo ""

# Check if docker-compose file exists
if [ ! -f "docker-compose.yml" ]; then
    fail "docker-compose.yml not found in cdc-streaming directory"
    exit 1
fi

# Check if consumers are already running
info "Checking consumer status..."
# All 8 consumers: 4 Spring + 4 Flink
ALL_CONSUMERS="car-consumer loan-consumer loan-payment-consumer service-consumer car-consumer-flink loan-consumer-flink loan-payment-consumer-flink service-consumer-flink"
RUNNING_CONSUMERS=0

for consumer in $ALL_CONSUMERS; do
    if docker ps --format '{{.Names}}' | grep -q "cdc-${consumer}"; then
        RUNNING_CONSUMERS=$((RUNNING_CONSUMERS + 1))
    fi
done

if [ $RUNNING_CONSUMERS -lt 8 ]; then
    warn "Only $RUNNING_CONSUMERS/8 consumers are running (expected to be started in Step 3)"
    info "Attempting to start missing consumers..."
    
    # Source environment files if they exist
    if [ -f "$PROJECT_ROOT/cdc-streaming/.env" ]; then
        source "$PROJECT_ROOT/cdc-streaming/.env"
    fi
    
    # Check if KAFKA environment variables are set
    if [ -z "$KAFKA_BOOTSTRAP_SERVERS" ] && [ -z "$CONFLUENT_BOOTSTRAP_SERVERS" ]; then
        fail "KAFKA_BOOTSTRAP_SERVERS or CONFLUENT_BOOTSTRAP_SERVERS environment variable not set"
        exit 1
    fi
    
    # Use CONFLUENT_BOOTSTRAP_SERVERS if KAFKA_BOOTSTRAP_SERVERS is not set
    if [ -z "$KAFKA_BOOTSTRAP_SERVERS" ] && [ -n "$CONFLUENT_BOOTSTRAP_SERVERS" ]; then
        export KAFKA_BOOTSTRAP_SERVERS="$CONFLUENT_BOOTSTRAP_SERVERS"
    fi
    
    if docker-compose version &> /dev/null; then
        docker-compose up -d $ALL_CONSUMERS 2>&1 | grep -v "level=warning" | tail -5
    else
        docker compose up -d $ALL_CONSUMERS 2>&1 | grep -v "level=warning" | tail -5
    fi
    
    info "Waiting for consumers to start (checking every 2s, max 20s)..."
    max_startup_wait=20
    startup_elapsed=0
    while [ $startup_elapsed -lt $max_startup_wait ]; do
        RUNNING_COUNT=$(docker ps --format '{{.Names}}' | grep -E "cdc-(car-consumer|loan-consumer|loan-payment-consumer|service-consumer)" | wc -l | tr -d ' ')
        if [ "$RUNNING_COUNT" -ge 8 ]; then
            pass "All 8 consumers started (after ${startup_elapsed}s)"
            break
        fi
        sleep 2
        startup_elapsed=$((startup_elapsed + 2))
    done
    
    if [ "$RUNNING_COUNT" -lt 8 ]; then
        warn "Only $RUNNING_COUNT/8 consumers started after ${startup_elapsed}s"
    fi
else
    pass "All 8 consumers are running (started in Step 3)"
fi

# Verify consumers are running
CONSUMER_CHECK_FAILED=0
for consumer in $ALL_CONSUMERS; do
    if docker ps --format '{{.Names}}' | grep -q "cdc-${consumer}"; then
        pass "cdc-${consumer} is running"
    elif docker ps -a --format '{{.Names}}' | grep -q "cdc-${consumer}"; then
        CONTAINER_STATUS=$(docker ps -a --format '{{.Names}} {{.Status}}' | grep "cdc-${consumer}" | awk '{print $2}')
        warn "cdc-${consumer} exists but status is: $CONTAINER_STATUS"
        CONSUMER_CHECK_FAILED=1
    else
        fail "cdc-${consumer} container not found"
        CONSUMER_CHECK_FAILED=1
    fi
done

if [ $CONSUMER_CHECK_FAILED -eq 1 ]; then
    warn "Some consumers are not running properly"
    info "Checking consumer logs for errors..."
    if docker-compose version &> /dev/null; then
        docker-compose logs --tail=10 2>&1 | head -20
    else
        docker compose logs --tail=10 2>&1 | head -20
    fi
    # Continue anyway - they might start soon
fi
echo ""

# Step 10.2: Monitor consumer logs
section "Step 10.2: Monitor Consumer Logs"
echo ""

LOG_DURATION=${LOG_DURATION:-15}  # Monitor logs for 15 seconds (reduced from 30s for faster execution)
LOG_FILE="/tmp/consumer-logs-$(date +%s).txt"

info "Monitoring consumer logs for ${LOG_DURATION} seconds..."
info "Collecting logs to: $LOG_FILE"
echo ""

# Debug: Check if stream processor is running and routing events
info "Debug: Checking stream processor status..."
if docker ps --format '{{.Names}}' | grep -q "cdc-stream-processor"; then
    pass "Stream processor container is running"
    # Check if filters are loaded
    if docker-compose logs stream-processor --tail=50 2>&1 | grep -q "Loading.*filter"; then
        FILTER_COUNT=$(docker-compose logs stream-processor --tail=50 2>&1 | grep -c "Configuring filter" || echo "0")
        if [ "$FILTER_COUNT" -gt 0 ]; then
            pass "Stream processor has $FILTER_COUNT filter(s) configured"
        else
            warn "Stream processor running but no filters configured"
        fi
    else
        warn "Stream processor may not have filters loaded"
    fi
    # Check if events are being routed
    ROUTED_COUNT=$(docker-compose logs stream-processor --tail=200 2>&1 | grep -c "Event sent to" || echo "0")
    if [ "$ROUTED_COUNT" -gt 0 ]; then
        info "Stream processor has routed $ROUTED_COUNT events to filtered topics"
    else
        warn "Stream processor has not routed any events yet (may need new events or reprocessing)"
    fi
else
    warn "Stream processor container is not running - Spring consumers won't receive events"
fi
echo ""

# Start log collection in background (all 8 consumers)
# Use --tail=200 to capture recent logs (events already processed) plus follow new logs
# This ensures we capture events that were processed before log collection started
if docker-compose version &> /dev/null; then
    # First, get recent logs (without -f to get existing logs)
    docker-compose logs --tail=200 $ALL_CONSUMERS > "$LOG_FILE" 2>&1 || true
    # Then follow new logs (with timeout to prevent hanging)
    if command -v timeout &> /dev/null; then
        timeout $LOG_DURATION docker-compose logs --tail=0 -f $ALL_CONSUMERS >> "$LOG_FILE" 2>&1 &
    else
        # Fallback: start process and kill after duration
        docker-compose logs --tail=0 -f $ALL_CONSUMERS >> "$LOG_FILE" 2>&1 &
        LOG_PID=$!
        (sleep $LOG_DURATION && kill $LOG_PID 2>/dev/null) &
    fi
else
    # First, get recent logs (without -f to get existing logs)
    docker compose logs --tail=200 $ALL_CONSUMERS > "$LOG_FILE" 2>&1 || true
    # Then follow new logs (with timeout to prevent hanging)
    if command -v timeout &> /dev/null; then
        timeout $LOG_DURATION docker compose logs --tail=0 -f $ALL_CONSUMERS >> "$LOG_FILE" 2>&1 &
    else
        # Fallback: start process and kill after duration
        docker compose logs --tail=0 -f $ALL_CONSUMERS >> "$LOG_FILE" 2>&1 &
        LOG_PID=$!
        (sleep $LOG_DURATION && kill $LOG_PID 2>/dev/null) &
    fi
fi

LOG_PID=$!

# Wait for log collection
sleep $LOG_DURATION

# Kill log process if still running
kill $LOG_PID 2>/dev/null || true
wait $LOG_PID 2>/dev/null || true

# Verify log file was created and has content
if [ ! -f "$LOG_FILE" ]; then
    warn "Log file was not created: $LOG_FILE"
elif [ ! -s "$LOG_FILE" ]; then
    warn "Log file is empty: $LOG_FILE"
    info "This may indicate consumers are not producing logs or log collection failed"
else
    LOG_LINES=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ' || echo "0")
    info "Collected $LOG_LINES lines of log data"
fi

pass "Log collection complete"
echo ""

# Step 10.2.5: Debug - Check topic message counts and consumer offsets
section "Step 10.2.5: Debug - Topic and Consumer Status"
echo ""

# Check if Confluent CLI is available
if command -v confluent &> /dev/null && confluent environment list &> /dev/null 2>&1; then
    info "Checking filtered topic message counts..."
    
    # Check each filtered topic
    for event_type in CarCreated LoanCreated LoanPaymentSubmitted CarServiceDone; do
        consumers=$(get_consumers_for_event_type "$event_type")
        for consumer in $consumers; do
            # Determine topic based on consumer type
            case "$consumer" in
                *-flink)
                    case "$event_type" in
                        CarCreated) topic="filtered-car-created-events-flink" ;;
                        LoanCreated) topic="filtered-loan-created-events-flink" ;;
                        LoanPaymentSubmitted) topic="filtered-loan-payment-submitted-events-flink" ;;
                        CarServiceDone) topic="filtered-service-events-flink" ;;
                        *) continue ;;
                    esac
                    consumer_group="${consumer}-group"
                    ;;
                *)
                    case "$event_type" in
                        CarCreated) topic="filtered-car-created-events-spring" ;;
                        LoanCreated) topic="filtered-loan-created-events-spring" ;;
                        LoanPaymentSubmitted) topic="filtered-loan-payment-submitted-events-spring" ;;
                        CarServiceDone) topic="filtered-service-events-spring" ;;
                        *) continue ;;
                    esac
                    consumer_group="${consumer}-spring-group"
                    ;;
            esac
            
            # Check topic message count
            if confluent kafka topic describe "$topic" &>/dev/null; then
                LATEST_OFFSET=$(confluent kafka topic describe "$topic" --output json 2>/dev/null | jq -r '.partitions[0].latest_offset // "0"' 2>/dev/null || echo "0")
                EARLIEST_OFFSET=$(confluent kafka topic describe "$topic" --output json 2>/dev/null | jq -r '.partitions[0].earliest_offset // "0"' 2>/dev/null || echo "0")
                MESSAGE_COUNT=$((LATEST_OFFSET - EARLIEST_OFFSET)) 2>/dev/null || MESSAGE_COUNT=0
                
                if [ "$MESSAGE_COUNT" -gt 0 ] 2>/dev/null; then
                    info "  Topic $topic: $MESSAGE_COUNT messages (offsets: $EARLIEST_OFFSET to $LATEST_OFFSET)"
                else
                    warn "  Topic $topic: No messages found (offsets: $EARLIEST_OFFSET to $LATEST_OFFSET)"
                fi
                
                # Check consumer group offset
                GROUP_INFO=$(confluent kafka consumer-group describe "$consumer_group" --output json 2>/dev/null || echo "")
                if [ -n "$GROUP_INFO" ] && echo "$GROUP_INFO" | jq -e '.partitions' &>/dev/null; then
                    CURRENT_OFFSET=$(echo "$GROUP_INFO" | jq -r '[.partitions[]?.current_offset // 0] | max // 0' 2>/dev/null || echo "0")
                    LAG=$(echo "$GROUP_INFO" | jq -r '[.partitions[]?.lag // 0] | max // 0' 2>/dev/null || echo "0")
                    if [ "$CURRENT_OFFSET" != "0" ] || [ "$LAG" != "0" ]; then
                        info "  Consumer group $consumer_group: offset=$CURRENT_OFFSET, lag=$LAG"
                    else
                        info "  Consumer group $consumer_group: No offset committed yet (consumer may not have started consuming)"
                    fi
                else
                    info "  Consumer group $consumer_group: Not found or no offsets committed"
                fi
            else
                warn "  Topic $topic: Does not exist"
            fi
        done
    done
    echo ""
else
    warn "Confluent CLI not available - skipping topic/offset checks"
    info "To enable: confluent login"
    echo ""
fi

# Step 10.3: Extract and validate events from logs
section "Step 10.3: Validate Events in Consumer Logs"
echo ""

TOTAL_VALIDATED=0
TOTAL_EXPECTED=0
VALIDATION_FAILED=false

for event_type in CarCreated LoanCreated LoanPaymentSubmitted CarServiceDone; do
    consumers=$(get_consumers_for_event_type "$event_type")
    expected_uuids=$(get_uuids_for_event_type "$event_type")
    expected_count=$(echo "$expected_uuids" | grep -c . || echo "0")
    
    if [ "$expected_count" -eq 0 ]; then
        warn "Skipping $event_type consumers (no $event_type events submitted)"
        echo ""
        continue
    fi
    
    # Each event should be found in BOTH Spring and Flink consumers
    # So total expected is doubled (once per consumer type)
    TOTAL_EXPECTED=$((TOTAL_EXPECTED + expected_count * 2))
    
    info "Validating $event_type events in both Spring and Flink consumers"
    
    # Validate each consumer (Spring and Flink)
    for consumer in $consumers; do
        consumer_type=""
        # Check if consumer name ends with -flink using string comparison (more reliable)
        case "$consumer" in
            *-flink)
                consumer_type="Flink"
                ;;
            *)
                consumer_type="Spring"
                ;;
        esac
        
        info "  Checking $consumer_type consumer: $consumer"
        
        # Extract event IDs from consumer logs
        # Container names in docker-compose logs are prefixed with "cdc-"
        # Spring service names: "car-consumer" → container: "cdc-car-consumer-spring"
        # Flink service names: "car-consumer-flink" → container: "cdc-car-consumer-flink"
        # Container name pattern: cdc-{service}-{spring|flink} for Spring, cdc-{service} for Flink
        if [ "$consumer_type" = "Flink" ]; then
            # Flink service name already includes "-flink", so container is just "cdc-{service}"
            CONTAINER_PATTERN="cdc-${consumer}"
        else
            # Spring service name needs "-spring" suffix
            CONTAINER_PATTERN="cdc-${consumer}-spring"
        fi
        
        # Cache Docker logs once per consumer (instead of calling for each UUID)
        # This prevents hanging and improves performance
        DOCKER_LOGS_CACHE=""
        if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
            # Extract logs for this specific container from the log file (with timeout)
            # Use timeout to prevent hanging on large log files
            if command -v timeout &> /dev/null; then
                DOCKER_LOGS_CACHE=$(timeout 5 grep -i "$CONTAINER_PATTERN" "$LOG_FILE" 2>/dev/null || echo "")
            else
                DOCKER_LOGS_CACHE=$(grep -i "$CONTAINER_PATTERN" "$LOG_FILE" 2>/dev/null | head -1000 || echo "")
            fi
        fi
        
        # If log file doesn't have this container's logs, fetch from Docker once (with timeout)
        if [ -z "$DOCKER_LOGS_CACHE" ] || [ ${#DOCKER_LOGS_CACHE} -lt 10 ]; then
            DOCKER_LOGS_TMP="/tmp/docker-logs-${consumer}-$(date +%s).txt"
            if docker-compose version &> /dev/null; then
                if command -v timeout &> /dev/null; then
                    timeout 3 docker-compose logs --tail=200 "$consumer" 2>&1 > "$DOCKER_LOGS_TMP" || true
                else
                    # Fallback: use head to limit output and prevent hanging
                    docker-compose logs --tail=200 "$consumer" 2>&1 | head -500 > "$DOCKER_LOGS_TMP" 2>/dev/null || true
                fi
            else
                if command -v timeout &> /dev/null; then
                    timeout 3 docker compose logs --tail=200 "$consumer" 2>&1 > "$DOCKER_LOGS_TMP" || true
                else
                    # Fallback: use head to limit output and prevent hanging
                    docker compose logs --tail=200 "$consumer" 2>&1 | head -500 > "$DOCKER_LOGS_TMP" 2>/dev/null || true
                fi
            fi
            if [ -f "$DOCKER_LOGS_TMP" ] && [ -s "$DOCKER_LOGS_TMP" ]; then
                DOCKER_LOGS_CACHE=$(cat "$DOCKER_LOGS_TMP" 2>/dev/null || echo "")
                rm -f "$DOCKER_LOGS_TMP"
            fi
        fi
        
        # Extract all UUIDs from cached logs once (with timeout to prevent hanging)
        FOUND_UUIDS=""
        if [ -n "$DOCKER_LOGS_CACHE" ]; then
            # Look for UUIDs in logs - consumers may log event IDs in various formats
            # Support both standard UUID format and timestamp-hash format (e.g., 1765998679-28a1dcfd)
            # Use timeout to prevent hanging on large log content
            if command -v timeout &> /dev/null; then
                FOUND_UUIDS=$(echo "$DOCKER_LOGS_CACHE" | timeout 3 grep -oE '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9]+-[0-9a-f]+)' | sort -u || echo "")
            else
                # Fallback: limit input size to prevent hanging
                FOUND_UUIDS=$(echo "$DOCKER_LOGS_CACHE" | head -2000 | grep -oE '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9]+-[0-9a-f]+)' | sort -u || echo "")
            fi
        fi
        
        # Create a simple lookup file for fast UUID checking (avoid repeated grep operations)
        FOUND_UUIDS_FILE="/tmp/found-uuids-${consumer}-$(date +%s).txt"
        echo "$FOUND_UUIDS" > "$FOUND_UUIDS_FILE"
        
        # Check for each expected UUID (fast lookup using file)
        FOUND_COUNT=0
        MISSING_UUIDS=()
        
        for uuid in $expected_uuids; do
            # Fast check: use grep on the UUID file (much faster than repeated string operations)
            if grep -q "^${uuid}$" "$FOUND_UUIDS_FILE" 2>/dev/null; then
                FOUND_COUNT=$((FOUND_COUNT + 1))
            else
                # Also check for UUID in various log formats (with timeout)
                # Look for patterns like "Event ID: uuid", "UUID: uuid", "id=uuid", etc.
                FOUND=false
                if [ -n "$DOCKER_LOGS_CACHE" ]; then
                    if command -v timeout &> /dev/null; then
                        if echo "$DOCKER_LOGS_CACHE" | timeout 1 grep -qiE "(Event ID|event.*id|UUID|uuid|id=).*${uuid}"; then
                            FOUND=true
                        fi
                    else
                        # Fallback: limit search to prevent hanging
                        if echo "$DOCKER_LOGS_CACHE" | head -1000 | grep -qiE "(Event ID|event.*id|UUID|uuid|id=).*${uuid}"; then
                            FOUND=true
                        fi
                    fi
                fi
                
                if [ "$FOUND" = "true" ]; then
                    FOUND_COUNT=$((FOUND_COUNT + 1))
                else
                    MISSING_UUIDS+=("$uuid")
                fi
            fi
        done
        
        # Cleanup temporary file
        rm -f "$FOUND_UUIDS_FILE"
        
        if [ "$FOUND_COUNT" -eq "$expected_count" ]; then
            pass "    All $expected_count $event_type events found in $consumer ($consumer_type) logs"
            TOTAL_VALIDATED=$((TOTAL_VALIDATED + FOUND_COUNT))
        elif [ "$FOUND_COUNT" -gt 0 ]; then
            warn "    Only $FOUND_COUNT/$expected_count $event_type events found in $consumer ($consumer_type) logs"
            if [ ${#MISSING_UUIDS[@]} -le 3 ]; then
                info "    Missing UUIDs: ${MISSING_UUIDS[*]}"
            fi
            TOTAL_VALIDATED=$((TOTAL_VALIDATED + FOUND_COUNT))
            VALIDATION_FAILED=true
        else
            fail "    No $event_type events found in $consumer ($consumer_type) logs"
            info "    Checking recent logs for $consumer:"
            if docker-compose version &> /dev/null; then
                if command -v timeout &> /dev/null; then
                    timeout 5 docker-compose logs --tail=20 "$consumer" 2>&1 | head -10 || echo "    (Could not retrieve logs - container may not be running)"
                else
                    docker-compose logs --tail=20 "$consumer" 2>&1 | head -10 || echo "    (Could not retrieve logs - container may not be running)"
                fi
            else
                if command -v timeout &> /dev/null; then
                    timeout 5 docker compose logs --tail=20 "$consumer" 2>&1 | head -10 || echo "    (Could not retrieve logs - container may not be running)"
                else
                    docker compose logs --tail=20 "$consumer" 2>&1 | head -10 || echo "    (Could not retrieve logs - container may not be running)"
                fi
            fi
            VALIDATION_FAILED=true
        fi
    done
    
    echo ""
done

# Summary
section "Validation Summary"
echo ""
echo "Total events expected (across all 8 consumers): $TOTAL_EXPECTED"
echo "Total events validated: $TOTAL_VALIDATED"
echo ""
echo "Consumers validated:"
echo "  - 4 Spring consumers (filtered-*-events-spring topics)"
echo "  - 4 Flink consumers (filtered-*-events-flink topics)"
echo ""

if [ "$VALIDATION_FAILED" = true ]; then
    fail "Some events not found in consumer logs"
    echo ""
    echo "Troubleshooting:"
    echo "  - Check consumer logs: docker-compose -f cdc-streaming/docker-compose.yml logs <consumer-name>"
    echo "  - Verify consumers are connected to Kafka"
    echo "  - Check consumer group offsets (see debug output above)"
    echo "  - Verify filtered topics have messages (both -spring and -flink topics)"
    echo "  - Check if Spring Boot processor is running (for -spring topics)"
    echo "  - Check if Flink INSERT statements are RUNNING (for -flink topics)"
    echo "  - Increase log monitoring duration"
    echo ""
    echo "Common Issues:"
    echo "  1. Stream processor started AFTER events were already in raw-event-headers topic"
    echo "     → Kafka Streams only processes NEW events, not historical ones"
    echo "     → Solution: Submit new events OR reset consumer group: confluent kafka consumer-group delete event-stream-processor"
    echo "  2. Consumers reading from wrong offset"
    echo "     → Check: confluent kafka consumer-group describe <group-name>"
    echo "     → Solution: Reset consumer group or ensure auto.offset.reset=earliest"
    echo "  3. Filters not loaded in stream processor"
    echo "     → Check: docker-compose logs stream-processor | grep 'Loading.*filter'"
    echo "     → Solution: Ensure filters.yml is mounted (see docker-compose.yml volumes)"
    exit 1
fi

pass "All events validated in all 8 consumer logs (4 Spring + 4 Flink)"
info "Log file saved to: $LOG_FILE"
exit 0
