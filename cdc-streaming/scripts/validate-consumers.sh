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

# Step 1: Start consumers
section "Step 1: Start Dockerized Consumers"
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
    if docker ps --format '{{.Names}}' | grep -q "${consumer}"; then
        RUNNING_CONSUMERS=$((RUNNING_CONSUMERS + 1))
    fi
done

if [ $RUNNING_CONSUMERS -lt 8 ]; then
    info "Starting all 8 consumers (4 Spring + 4 Flink)..."
    
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
        docker-compose up -d $ALL_CONSUMERS
    else
        docker compose up -d $ALL_CONSUMERS
    fi
    
    info "Waiting for consumers to start (checking every 2s, max 20s)..."
    # Poll consumer status instead of fixed wait
    max_startup_wait=20
    startup_elapsed=0
    while [ $startup_elapsed -lt $max_startup_wait ]; do
        RUNNING_COUNT=$(docker ps --format '{{.Names}}' | grep -E "(car-consumer|loan-consumer|loan-payment-consumer|service-consumer)" | wc -l | tr -d ' ')
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
    info "All 8 consumers already running"
fi

# Verify consumers are running
CONSUMER_CHECK_FAILED=0
for event_type in CarCreated LoanCreated LoanPaymentSubmitted CarServiceDone; do
    consumers=$(get_consumers_for_event_type "$event_type")
    for consumer in $consumers; do
        # Check if container exists and is running (container name might have prefix)
        if docker ps --format '{{.Names}}' | grep -q "${consumer}"; then
            pass "$consumer is running"
        elif docker ps -a --format '{{.Names}}' | grep -q "${consumer}"; then
            # Container exists but not running
            CONTAINER_STATUS=$(docker ps -a --format '{{.Names}} {{.Status}}' | grep "${consumer}" | awk '{print $2}')
            warn "$consumer exists but status is: $CONTAINER_STATUS"
            CONSUMER_CHECK_FAILED=1
        else
            fail "$consumer container not found"
            CONSUMER_CHECK_FAILED=1
        fi
    done
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

# Step 2: Monitor consumer logs
section "Step 2: Monitor Consumer Logs"
echo ""

LOG_DURATION=${LOG_DURATION:-15}  # Monitor logs for 15 seconds (reduced from 30s for faster execution)
LOG_FILE="/tmp/consumer-logs-$(date +%s).txt"

info "Monitoring consumer logs for ${LOG_DURATION} seconds..."
info "Collecting logs to: $LOG_FILE"
echo ""

# Start log collection in background (all 8 consumers)
# Use --tail=0 to start from current position, then follow new logs
# This prevents reading all historical logs which can be slow
if docker-compose version &> /dev/null; then
    # Use timeout if available, otherwise use background process with kill
    if command -v timeout &> /dev/null; then
        timeout $LOG_DURATION docker-compose logs --tail=0 -f $ALL_CONSUMERS > "$LOG_FILE" 2>&1 &
    else
        # Fallback: start process and kill after duration
        docker-compose logs --tail=0 -f $ALL_CONSUMERS > "$LOG_FILE" 2>&1 &
        LOG_PID=$!
        (sleep $LOG_DURATION && kill $LOG_PID 2>/dev/null) &
    fi
else
    if command -v timeout &> /dev/null; then
        timeout $LOG_DURATION docker compose logs --tail=0 -f $ALL_CONSUMERS > "$LOG_FILE" 2>&1 &
    else
        # Fallback: start process and kill after duration
        docker compose logs --tail=0 -f $ALL_CONSUMERS > "$LOG_FILE" 2>&1 &
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

pass "Log collection complete"
echo ""

# Step 3: Extract and validate events from logs
section "Step 3: Validate Events in Consumer Logs"
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
        FOUND_UUIDS=""
        
        if [ -f "$LOG_FILE" ]; then
            # Look for UUIDs in logs - consumers may log event IDs in various formats
            # Support both standard UUID format and timestamp-hash format (e.g., 1765998679-28a1dcfd)
            FOUND_UUIDS=$(grep -i "$consumer" "$LOG_FILE" 2>/dev/null | \
                grep -oE '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9]+-[0-9a-f]+)' | \
                sort -u || echo "")
        fi
        
        # Check for each expected UUID
        FOUND_COUNT=0
        MISSING_UUIDS=()
        
        for uuid in $expected_uuids; do
            # Check if UUID appears in logs (may be in different formats)
            FOUND=false
            if [ -f "$LOG_FILE" ]; then
                if echo "$FOUND_UUIDS" | grep -q "$uuid" || \
                   grep -q "$uuid" "$LOG_FILE" 2>/dev/null || \
                   grep -qi "Event ID.*$uuid\|event.*id.*$uuid" "$LOG_FILE" 2>/dev/null; then
                    FOUND=true
                fi
            fi
            
            # If not found in log file, check Docker logs directly (with timeout and tail limit)
            if [ "$FOUND" = "false" ]; then
                if docker-compose version &> /dev/null; then
                    # Use --tail to limit output and prevent hanging
                    # Use timeout if available, otherwise just use --tail
                    if command -v timeout &> /dev/null; then
                        if timeout 5 docker-compose logs --tail=100 "$consumer" 2>&1 | grep -qi "Event ID.*$uuid\|event.*id.*$uuid"; then
                            FOUND=true
                        fi
                    else
                        # Fallback: use --tail without timeout (should be fast with --tail)
                        if docker-compose logs --tail=100 "$consumer" 2>&1 | grep -qi "Event ID.*$uuid\|event.*id.*$uuid"; then
                            FOUND=true
                        fi
                    fi
                else
                    # Use --tail to limit output and prevent hanging
                    if command -v timeout &> /dev/null; then
                        if timeout 5 docker compose logs --tail=100 "$consumer" 2>&1 | grep -qi "Event ID.*$uuid\|event.*id.*$uuid"; then
                            FOUND=true
                        fi
                    else
                        # Fallback: use --tail without timeout (should be fast with --tail)
                        if docker compose logs --tail=100 "$consumer" 2>&1 | grep -qi "Event ID.*$uuid\|event.*id.*$uuid"; then
                            FOUND=true
                        fi
                    fi
                fi
            fi
            
            if [ "$FOUND" = "true" ]; then
                FOUND_COUNT=$((FOUND_COUNT + 1))
            else
                MISSING_UUIDS+=("$uuid")
            fi
        done
        
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
    echo "  - Check consumer group offsets"
    echo "  - Verify filtered topics have messages (both -spring and -flink topics)"
    echo "  - Check if Spring Boot processor is running (for -spring topics)"
    echo "  - Check if Flink INSERT statements are RUNNING (for -flink topics)"
    echo "  - Increase log monitoring duration"
    exit 1
fi

pass "All events validated in all 8 consumer logs (4 Spring + 4 Flink)"
info "Log file saved to: $LOG_FILE"
exit 0
