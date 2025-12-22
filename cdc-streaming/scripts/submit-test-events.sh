#!/usr/bin/env bash
# Submit test events to Lambda API
# Submits 10 events of each type (CarCreated, LoanCreated, LoanPaymentSubmitted, CarServiceDone)
# Total: 40 events (10 × 4 types)
#
# Usage:
#   ./cdc-streaming/scripts/submit-test-events.sh <API_URL> <OUTPUT_FILE> [EVENTS_PER_TYPE]
#
# Example:
#   ./cdc-streaming/scripts/submit-test-events.sh https://api.example.com /tmp/events.json
#   ./cdc-streaming/scripts/submit-test-events.sh https://api.example.com /tmp/events.json 10

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

API_URL="$1"
OUTPUT_FILE="$2"
EVENTS_PER_TYPE="${3:-10}"  # Default to 10 events per type

if [ -z "$API_URL" ]; then
    fail "API URL required"
    echo "Usage: $0 <API_URL> <OUTPUT_FILE> [EVENTS_PER_TYPE]"
    exit 1
fi

if [ -z "$OUTPUT_FILE" ]; then
    fail "Output file required"
    echo "Usage: $0 <API_URL> <OUTPUT_FILE> [EVENTS_PER_TYPE]"
    exit 1
fi

# Validate EVENTS_PER_TYPE is a positive integer
if ! [[ "$EVENTS_PER_TYPE" =~ ^[1-9][0-9]*$ ]]; then
    fail "EVENTS_PER_TYPE must be a positive integer"
    exit 1
fi

info "Will submit $EVENTS_PER_TYPE events of each type (total: $((EVENTS_PER_TYPE * 4)) events)"

# Remove trailing slash from API URL
API_URL="${API_URL%/}"

# Sample event files
CAR_EVENT="$PROJECT_ROOT/data/schemas/event/samples/car-created-event.json"
LOAN_EVENT="$PROJECT_ROOT/data/schemas/event/samples/loan-created-event.json"
PAYMENT_EVENT="$PROJECT_ROOT/data/schemas/event/samples/loan-payment-submitted-event.json"
SERVICE_EVENT="$PROJECT_ROOT/data/schemas/event/samples/car-service-done-event.json"

# Verify sample files exist
for file in "$CAR_EVENT" "$LOAN_EVENT" "$PAYMENT_EVENT" "$SERVICE_EVENT"; do
    if [ ! -f "$file" ]; then
        fail "Sample event file not found: $file"
        exit 1
    fi
done

# Initialize output array
echo "[]" > "$OUTPUT_FILE"

# Function to submit event
submit_event() {
    local event_file="$1"
    local event_type="$2"
    local quiet_mode="${3:-}"
    
    # Only show detailed info for first event of each type
    if [ "$quiet_mode" != "quiet" ]; then
        info "Submitting $event_type event..."
    fi
    
    # Generate unique UUID for this test run
    local timestamp=$(date +%s)
    local unique_id="${timestamp}-$(openssl rand -hex 4)"
    
    # Generate unique entity ID suffix for this event (to ensure each event creates a new entity)
    local entity_suffix=$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]')
    
    # Generate realistic dates: createdDate = now, savedDate = now + 2-5 seconds
    local created_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local saved_delay=$((2 + RANDOM % 4))  # Random delay between 2-5 seconds
    
    # Calculate saved_date (works on both macOS and Linux)
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS date command
        local saved_date=$(date -u -v+${saved_delay}S +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    else
        # Linux date command
        local saved_date=$(date -u -d "+${saved_delay} seconds" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    fi
    
    # Fallback to created_date + 3 seconds if date calculation fails
    if [ -z "$saved_date" ]; then
        local created_timestamp=$(date -u +%s)
        local saved_timestamp=$((created_timestamp + 3))
        saved_date=$(date -u -r "$saved_timestamp" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "@$saved_timestamp" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "$created_date")
    fi
    
    # Load event and update UUID, dates, and entity IDs
    # First, update event header UUID and dates
    local event_json=$(jq --arg uuid "$unique_id" \
        --arg created "$created_date" \
        --arg saved "$saved_date" \
        '.eventHeader.uuid = $uuid | 
         .eventHeader.createdDate = $created | 
         .eventHeader.savedDate = $saved' "$event_file")
    
    # Update entity IDs in all entities (both entityHeader.entityId and id field)
    # Extract entity type from first entity to determine prefix
    local entity_type=$(echo "$event_json" | jq -r '.entities[0].entityHeader.entityType // ""')
    if [ -n "$entity_type" ] && [ "$entity_type" != "null" ]; then
        # Determine entity ID prefix based on entity type
        local entity_prefix=""
        case "$entity_type" in
            "Car") entity_prefix="CAR" ;;
            "Loan") entity_prefix="LOAN" ;;
            "LoanPayment") entity_prefix="PAYMENT" ;;
            "ServiceRecord") entity_prefix="SERVICE" ;;
            *) entity_prefix="ENTITY" ;;
        esac
        
        # Generate new entity ID with unique suffix
        local new_entity_id="${entity_prefix}-2025-${entity_suffix}"
        
        # Update entityHeader.entityId, id field, and entity dates for all entities
        # Entity dates should match event createdDate (entities are created when event is created)
        event_json=$(echo "$event_json" | jq --arg new_id "$new_entity_id" \
            --arg created "$created_date" \
            --arg updated "$created_date" '
            .entities = (.entities | map(
                .entityHeader.entityId = $new_id |
                .id = $new_id |
                .entityHeader.createdAt = $created |
                .entityHeader.updatedAt = $updated
            ))
        ')
    fi
    
    # Submit to API
    local response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$event_json" \
        "${API_URL}/api/v1/events" 2>&1)
    
    local http_code=$(echo "$response" | tail -n1 | tr -d '[:space:]')
    local body=$(echo "$response" | sed '$d')
    
    # Validate http_code is numeric
    if ! [[ "$http_code" =~ ^[0-9]+$ ]]; then
        fail "$event_type event submission failed: Invalid HTTP response"
        echo "Response: $response"
        return 1
    fi
    
    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
        # Only show pass message for first event of each type
        if [ "$quiet_mode" != "quiet" ]; then
            pass "$event_type event submitted (HTTP $http_code)"
        fi
        
        # Extract UUID from response or use the one we set
        local event_uuid=$(echo "$event_json" | jq -r '.eventHeader.uuid')
        local event_name=$(echo "$event_json" | jq -r '.eventHeader.eventName')
        local event_type_val=$(echo "$event_json" | jq -r '.eventHeader.eventType')
        
        # Add to output file
        jq --arg uuid "$event_uuid" \
           --arg name "$event_name" \
           --arg type "$event_type_val" \
           '. += [{"uuid": $uuid, "eventName": $name, "eventType": $type}]' \
           "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
        
        return 0
    else
        fail "$event_type event submission failed (HTTP $http_code)"
        echo "Response: $body"
        return 1
    fi
}

# Submit all events (10 of each type)
SUCCESS_COUNT=0
FAIL_COUNT=0

# Submit CarCreated events
info "Submitting $EVENTS_PER_TYPE CarCreated events..."
for i in $(seq 1 $EVENTS_PER_TYPE); do
    if [ $i -eq 1 ]; then
        # Show detailed info for first event
        if submit_event "$CAR_EVENT" "CarCreated"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        # Quiet mode for subsequent events
        if submit_event "$CAR_EVENT" "CarCreated" "quiet"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    fi
    sleep 0.1  # Minimal delay between requests
done

# Submit LoanCreated events
info "Submitting $EVENTS_PER_TYPE LoanCreated events..."
for i in $(seq 1 $EVENTS_PER_TYPE); do
    if [ $i -eq 1 ]; then
        if submit_event "$LOAN_EVENT" "LoanCreated"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        if submit_event "$LOAN_EVENT" "LoanCreated" "quiet"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    fi
    sleep 0.1
done

# Submit LoanPaymentSubmitted events
info "Submitting $EVENTS_PER_TYPE LoanPaymentSubmitted events..."
for i in $(seq 1 $EVENTS_PER_TYPE); do
    if [ $i -eq 1 ]; then
        if submit_event "$PAYMENT_EVENT" "LoanPaymentSubmitted"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        if submit_event "$PAYMENT_EVENT" "LoanPaymentSubmitted" "quiet"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    fi
    sleep 0.1
done

# Submit CarServiceDone events
info "Submitting $EVENTS_PER_TYPE CarServiceDone events..."
for i in $(seq 1 $EVENTS_PER_TYPE); do
    if [ $i -eq 1 ]; then
        if submit_event "$SERVICE_EVENT" "CarServiceDone"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        if submit_event "$SERVICE_EVENT" "CarServiceDone" "quiet"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    fi
    sleep 0.1
done

echo ""
info "Submission Summary: $SUCCESS_COUNT successful, $FAIL_COUNT failed"

if [ $FAIL_COUNT -gt 0 ]; then
    fail "Some events failed to submit"
    exit 1
fi

pass "All events submitted successfully"
info "Event UUIDs saved to: $OUTPUT_FILE"
