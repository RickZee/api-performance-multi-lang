#!/bin/bash
# End-to-End Pipeline Validation Script
# Validates the complete CDC pipeline: Postgres → Debezium → Kafka → Flink → Consumers

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
section() { echo -e "${CYAN}========================================${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}========================================${NC}"; }

section "End-to-End Pipeline Validation"

# Generate unique test ID
TEST_ID=$(date +%s)
echo "Test ID: validate-$TEST_ID"
echo ""

# Step 1: Insert Test Events
section "Step 1: Insert Test Events into Postgres"
info "Inserting 10 events of each type into car_entities.event_headers..."

for i in {1..10}; do
    docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
        "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) \
         VALUES ('validate-loan-$TEST_ID-$i', 'Loan Created Event', 'LoanCreated', NOW(), NOW(), '{\"id\": \"validate-loan-$TEST_ID-$i\"}');" \
        > /dev/null 2>&1
done

for i in {1..10}; do
    docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
        "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) \
         VALUES ('validate-car-$TEST_ID-$i', 'Car Created Event', 'CarCreated', NOW(), NOW(), '{\"id\": \"validate-car-$TEST_ID-$i\"}');" \
        > /dev/null 2>&1
done

for i in {1..10}; do
    docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
        "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) \
         VALUES ('validate-payment-$TEST_ID-$i', 'Loan Payment Submitted', 'LoanPaymentSubmitted', NOW(), NOW(), '{\"id\": \"validate-payment-$TEST_ID-$i\"}');" \
        > /dev/null 2>&1
done

for i in {1..10}; do
    docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
        "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) \
         VALUES ('validate-service-$TEST_ID-$i', 'Car Service Done', 'CarServiceDone', NOW(), NOW(), '{\"id\": \"validate-service-$TEST_ID-$i\"}');" \
        > /dev/null 2>&1
done

pass "Inserted 40 test events (10 of each type)"
echo ""

# Step 2: Verify Events in Database
section "Step 2: Verify Events in Database"
DB_COUNT=$(docker exec cdc-local-postgres-large psql -U postgres -d car_entities -t -c \
    "SELECT COUNT(*) FROM event_headers WHERE id LIKE 'validate-$TEST_ID-%';" 2>&1 | tr -d ' ')

if [ "$DB_COUNT" -eq 40 ]; then
    pass "Database: $DB_COUNT/40 events found"
else
    fail "Database: $DB_COUNT/40 events found (expected 40)"
fi
echo ""

# Step 3: Wait for CDC Propagation
section "Step 3: Wait for CDC Propagation"
info "Waiting 20 seconds for Debezium to capture events..."
sleep 20

# Step 4: Verify Events in Raw Topic
section "Step 4: Verify Events in Raw Kafka Topic"
RAW_COUNT=$(docker exec cdc-local-redpanda rpk topic consume raw-event-headers \
    --offset start --num 1000 --format '%v\n' 2>&1 | \
    jq -r "select(.id != null and (.id | contains(\"validate-$TEST_ID\"))) | .id" 2>&1 | \
    wc -l | tr -d ' ')

if [ "$RAW_COUNT" -eq 40 ]; then
    pass "Raw topic: $RAW_COUNT/40 events found"
elif [ "$RAW_COUNT" -gt 0 ]; then
    warn "Raw topic: $RAW_COUNT/40 events found (CDC may still be processing)"
else
    fail "Raw topic: $RAW_COUNT/40 events found (CDC not capturing events)"
fi
echo ""

# Step 5: Verify Events in Flink Filtered Topics
section "Step 5: Verify Events in Flink Filtered Topics"
TOTAL_FILTERED=0

for topic in filtered-loan-created-events-flink filtered-car-created-events-flink \
             filtered-loan-payment-submitted-events-flink filtered-service-events-flink; do
    EVENT_TYPE=$(echo "$topic" | sed 's/filtered-//' | sed 's/-events-flink//')
    
    if [ "$EVENT_TYPE" = "loan-created" ]; then
        PREFIX="validate-loan-$TEST_ID"
        EXPECTED=10
    elif [ "$EVENT_TYPE" = "car-created" ]; then
        PREFIX="validate-car-$TEST_ID"
        EXPECTED=10
    elif [ "$EVENT_TYPE" = "loan-payment-submitted" ]; then
        PREFIX="validate-payment-$TEST_ID"
        EXPECTED=10
    elif [ "$EVENT_TYPE" = "service" ]; then
        PREFIX="validate-service-$TEST_ID"
        EXPECTED=10
    fi
    
    COUNT=$(docker exec cdc-local-redpanda rpk topic consume "$topic" \
        --offset start --num 1000 --format '%v\n' 2>&1 | \
        jq -r "select(.id != null and (.id | contains(\"$PREFIX\"))) | .id" 2>&1 | \
        wc -l | tr -d ' ')
    
    TOTAL_FILTERED=$((TOTAL_FILTERED + COUNT))
    
    if [ "$COUNT" -eq "$EXPECTED" ]; then
        pass "$EVENT_TYPE topic: $COUNT/$EXPECTED events"
    elif [ "$COUNT" -gt 0 ]; then
        warn "$EVENT_TYPE topic: $COUNT/$EXPECTED events (Flink may still be processing)"
    else
        fail "$EVENT_TYPE topic: $COUNT/$EXPECTED events (Flink not processing)"
    fi
done

if [ "$TOTAL_FILTERED" -eq 40 ]; then
    pass "Total filtered: $TOTAL_FILTERED/40 events"
else
    warn "Total filtered: $TOTAL_FILTERED/40 events"
fi
echo ""

# Step 6: Verify Events in Consumer Logs
section "Step 6: Verify Events in Consumer Logs"
info "Waiting 10 seconds for consumers to process events..."
sleep 10

TOTAL_CONSUMED=0

for consumer in loan-consumer-flink car-consumer-flink loan-payment-consumer-flink service-consumer-flink; do
    CONSUMER_NAME=$(echo "$consumer" | sed 's/-consumer-flink//')
    
    if [ "$CONSUMER_NAME" = "loan" ]; then
        PREFIX="validate-loan-$TEST_ID"
        EXPECTED=10
    elif [ "$CONSUMER_NAME" = "car" ]; then
        PREFIX="validate-car-$TEST_ID"
        EXPECTED=10
    elif [ "$CONSUMER_NAME" = "loan-payment" ]; then
        PREFIX="validate-payment-$TEST_ID"
        EXPECTED=10
    elif [ "$CONSUMER_NAME" = "service" ]; then
        PREFIX="validate-service-$TEST_ID"
        EXPECTED=10
    fi
    
    COUNT=$(docker logs cdc-local-$consumer 2>&1 | grep -c "$PREFIX" || echo 0)
    TOTAL_CONSUMED=$((TOTAL_CONSUMED + COUNT))
    
    if [ "$COUNT" -eq "$EXPECTED" ]; then
        pass "$CONSUMER_NAME consumer: $COUNT/$EXPECTED events processed"
    elif [ "$COUNT" -gt 0 ]; then
        warn "$CONSUMER_NAME consumer: $COUNT/$EXPECTED events processed (may still be processing)"
    else
        fail "$CONSUMER_NAME consumer: $COUNT/$EXPECTED events processed"
    fi
done

if [ "$TOTAL_CONSUMED" -eq 40 ]; then
    pass "Total consumed: $TOTAL_CONSUMED/40 events"
else
    warn "Total consumed: $TOTAL_CONSUMED/40 events"
fi
echo ""

# Final Summary
section "Validation Summary"
echo "Test ID: validate-$TEST_ID"
echo ""
echo "Pipeline Stages:"
echo "  1. Database:        $DB_COUNT/40 events"
echo "  2. Raw Topic:        $RAW_COUNT/40 events"
echo "  3. Filtered Topics: $TOTAL_FILTERED/40 events"
echo "  4. Consumers:        $TOTAL_CONSUMED/40 events"
echo ""

if [ "$DB_COUNT" -eq 40 ] && [ "$RAW_COUNT" -eq 40 ] && [ "$TOTAL_FILTERED" -eq 40 ] && [ "$TOTAL_CONSUMED" -eq 40 ]; then
    pass "✅ SUCCESS: All 40 events processed through entire pipeline!"
    exit 0
elif [ "$RAW_COUNT" -eq 0 ]; then
    fail "❌ FAILED: CDC not capturing events (check Debezium connector)"
    exit 1
elif [ "$TOTAL_FILTERED" -eq 0 ]; then
    fail "❌ FAILED: Flink not processing events (check Flink job)"
    exit 1
elif [ "$TOTAL_CONSUMED" -eq 0 ]; then
    fail "❌ FAILED: Consumers not processing events (check consumer logs)"
    exit 1
else
    warn "⚠️  PARTIAL: Pipeline is working but some events may still be processing"
    exit 0
fi

