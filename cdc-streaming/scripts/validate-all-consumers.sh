#!/bin/bash
# Validate All Consumers - Flink and Spring Boot Pipelines
# Ensures all 4 consumer types receive all 10 events for both pipelines
# Optimized for local testing with fast timeouts

set -e

# Set maximum script runtime (2 minutes)
SCRIPT_START=$(date +%s)
MAX_RUNTIME=120

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

# Check if we've exceeded max runtime
check_timeout() {
    ELAPSED=$(($(date +%s) - SCRIPT_START))
    if [ $ELAPSED -gt $MAX_RUNTIME ]; then
        fail "Script exceeded maximum runtime of ${MAX_RUNTIME}s"
        exit 1
    fi
}

section "Complete Pipeline Validation - All Consumers"

# Generate unique test ID
TEST_ID=$(date +%s)
echo "Test ID: validate-$TEST_ID"
echo ""

# Step 1: Insert 10 Events of Each Type
section "Step 1: Insert 10 Events of Each Type into Database"
info "Inserting into car_entities.event_headers..."

# Clear previous test events to avoid confusion
docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
    "DELETE FROM event_headers WHERE id LIKE 'validate-%';" > /dev/null 2>&1 || true

# Insert all events - MUST insert into business_events first due to foreign key constraint
info "Inserting events (business_events first, then event_headers due to FK constraint)..."
for event_type in LoanCreated CarCreated LoanPaymentSubmitted CarServiceDone; do
    prefix="validate-$(echo $event_type | tr '[:upper:]' '[:lower:]' | sed 's/loancreated/loan/' | sed 's/carcreated/car/' | sed 's/loanpaymentsubmitted/payment/' | sed 's/carservicedone/service/')"
    
    # Then insert into event_headers
    event_name=$(echo $event_type | sed 's/LoanCreated/Loan Created/' | sed 's/CarCreated/Car Created/' | sed 's/LoanPaymentSubmitted/Loan Payment/' | sed 's/CarServiceDone/Car Service/')
    
    # Insert into business_events first (uses event_data, not header_data, and requires event_name)
    docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
        "INSERT INTO business_events (id, event_name, event_type, created_date, saved_date, event_data) \
         SELECT '$prefix-$TEST_ID-' || s, '$event_name', '$event_type', NOW(), NOW(), \
                jsonb_build_object('id', '$prefix-$TEST_ID-' || s) \
         FROM generate_series(1, 10) s;" > /dev/null 2>&1
    docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
        "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) \
         SELECT '$prefix-$TEST_ID-' || s, '$event_name', '$event_type', NOW(), NOW(), \
                jsonb_build_object('id', '$prefix-$TEST_ID-' || s) \
         FROM generate_series(1, 10) s;" > /dev/null 2>&1
done

pass "Inserted 40 events (10 of each type)"
echo ""

# Step 2: Verify Events in Database
section "Step 2: Verify Events in Database"
check_timeout
# Check for any validate-* events with our TEST_ID (more flexible pattern)
DB_COUNT=$(docker exec cdc-local-postgres-large psql -U postgres -d car_entities -t -c \
    "SELECT COUNT(*) FROM event_headers WHERE id LIKE 'validate-%$TEST_ID-%';" 2>&1 | tr -d ' \n')

if [ -z "$DB_COUNT" ] || [ "$DB_COUNT" = "" ]; then
    DB_COUNT=0
fi

if [ "$DB_COUNT" -eq 40 ]; then
    pass "Database: $DB_COUNT/40 events found"
else
    if [ "$DB_COUNT" -eq 0 ]; then
        # Try alternative pattern
        DB_COUNT=$(docker exec cdc-local-postgres-large psql -U postgres -d car_entities -t -c \
            "SELECT COUNT(*) FROM event_headers WHERE id LIKE '%$TEST_ID%';" 2>&1 | tr -d ' \n')
        if [ -z "$DB_COUNT" ]; then
            DB_COUNT=0
        fi
    fi
    if [ "$DB_COUNT" -eq 40 ]; then
        pass "Database: $DB_COUNT/40 events found"
    elif [ "$DB_COUNT" -gt 0 ]; then
        warn "Database: $DB_COUNT/40 events found (continuing with partial count...)"
    else
        fail "No events found in database - insertion may have failed"
        exit 1
    fi
fi
echo ""

# Step 3: Wait for CDC Propagation
section "Step 3: Wait for CDC Propagation"
check_timeout
info "Waiting 10 seconds for Debezium to capture events (local should be fast)..."
sleep 10
check_timeout

# Step 4: Verify Events in Raw Topic
section "Step 4: Verify Events in Raw Kafka Topic"
check_timeout
info "Checking raw topic for test events..."
# Consume from topic and filter for our test ID (limit to recent messages for speed)
RAW_COUNT=$(docker exec cdc-local-redpanda rpk topic consume raw-event-headers \
    --offset start --num 200 --format '%v\n' 2>&1 | \
    grep -v "^$" | \
    jq -r "select(.id != null and (.id | contains(\"validate-$TEST_ID\"))) | .id" 2>&1 | \
    wc -l | tr -d ' ' 2>/dev/null || echo "0")

if [ "$RAW_COUNT" -eq 40 ]; then
    pass "Raw topic: $RAW_COUNT/40 events found"
elif [ "$RAW_COUNT" -gt 0 ]; then
    warn "Raw topic: $RAW_COUNT/40 events found (CDC may still be processing)"
else
    fail "Raw topic: $RAW_COUNT/40 events found (CDC not capturing events)"
    exit 1
fi
echo ""

# Step 5: Verify Flink Filtered Topics
section "Step 5: Verify Flink Filtered Topics"
FLINK_TOTAL=0
FLINK_PASS=0

declare -A FLINK_EXPECTED=(
    ["filtered-loan-created-events-flink"]="validate-loan-$TEST_ID"
    ["filtered-car-created-events-flink"]="validate-car-$TEST_ID"
    ["filtered-loan-payment-submitted-events-flink"]="validate-payment-$TEST_ID"
    ["filtered-service-events-flink"]="validate-service-$TEST_ID"
)

for topic in "${!FLINK_EXPECTED[@]}"; do
    PREFIX="${FLINK_EXPECTED[$topic]}"
    EVENT_TYPE=$(echo "$topic" | sed 's/filtered-//' | sed 's/-events-flink//')
    
    COUNT=$(docker exec cdc-local-redpanda rpk topic consume "$topic" \
        --offset start --num 200 --format '%v\n' 2>&1 | \
        grep -v "^$" | \
        jq -r "select(.id != null and (.id | contains(\"$PREFIX\"))) | .id" 2>&1 | \
        wc -l | tr -d ' ' 2>/dev/null || echo "0")
    
    FLINK_TOTAL=$((FLINK_TOTAL + COUNT))
    
    if [ "$COUNT" -eq 10 ]; then
        pass "Flink $EVENT_TYPE topic: $COUNT/10 events"
        FLINK_PASS=$((FLINK_PASS + 1))
    elif [ "$COUNT" -gt 0 ]; then
        warn "Flink $EVENT_TYPE topic: $COUNT/10 events (Flink may still be processing)"
    else
        fail "Flink $EVENT_TYPE topic: $COUNT/10 events (Flink not processing)"
    fi
done

if [ "$FLINK_TOTAL" -eq 40 ] && [ "$FLINK_PASS" -eq 4 ]; then
    pass "Flink filtered topics: $FLINK_TOTAL/40 events (all 4 topics have 10 events)"
else
    warn "Flink filtered topics: $FLINK_TOTAL/40 events ($FLINK_PASS/4 topics complete)"
fi
echo ""

# Step 6: Verify Spring Boot Filtered Topics
section "Step 6: Verify Spring Boot Filtered Topics"
SPRING_TOTAL=0
SPRING_PASS=0

declare -A SPRING_EXPECTED=(
    ["filtered-loan-created-events-spring"]="validate-loan-$TEST_ID"
    ["filtered-car-created-events-spring"]="validate-car-$TEST_ID"
    ["filtered-loan-payment-submitted-events-spring"]="validate-payment-$TEST_ID"
    ["filtered-service-events-spring"]="validate-service-$TEST_ID"
)

for topic in "${!SPRING_EXPECTED[@]}"; do
    PREFIX="${SPRING_EXPECTED[$topic]}"
    EVENT_TYPE=$(echo "$topic" | sed 's/filtered-//' | sed 's/-events-spring//')
    
    COUNT=$(docker exec cdc-local-redpanda rpk topic consume "$topic" \
        --offset start --num 200 --format '%v\n' 2>&1 | \
        grep -v "^$" | \
        jq -r "select(.id != null and (.id | contains(\"$PREFIX\"))) | .id" 2>&1 | \
        wc -l | tr -d ' ' 2>/dev/null || echo "0")
    
    SPRING_TOTAL=$((SPRING_TOTAL + COUNT))
    
    if [ "$COUNT" -eq 10 ]; then
        pass "Spring $EVENT_TYPE topic: $COUNT/10 events"
        SPRING_PASS=$((SPRING_PASS + 1))
    elif [ "$COUNT" -gt 0 ]; then
        warn "Spring $EVENT_TYPE topic: $COUNT/10 events (Spring may still be processing)"
    else
        fail "Spring $EVENT_TYPE topic: $COUNT/10 events (Spring not processing)"
    fi
done

if [ "$SPRING_TOTAL" -eq 40 ] && [ "$SPRING_PASS" -eq 4 ]; then
    pass "Spring filtered topics: $SPRING_TOTAL/40 events (all 4 topics have 10 events)"
else
    warn "Spring filtered topics: $SPRING_TOTAL/40 events ($SPRING_PASS/4 topics complete)"
fi
echo ""

# Step 7: Verify Flink Consumers
section "Step 7: Verify Flink Consumers"
check_timeout
info "Waiting 10 seconds for Flink consumers to process events (local should be fast)..."
sleep 10
check_timeout

FLINK_CONSUMER_TOTAL=0
FLINK_CONSUMER_PASS=0

declare -A FLINK_CONSUMER_PREFIX=(
    ["loan-consumer-flink"]="validate-loan-$TEST_ID"
    ["car-consumer-flink"]="validate-car-$TEST_ID"
    ["loan-payment-consumer-flink"]="validate-payment-$TEST_ID"
    ["service-consumer-flink"]="validate-service-$TEST_ID"
)

for consumer in "${!FLINK_CONSUMER_PREFIX[@]}"; do
    PREFIX="${FLINK_CONSUMER_PREFIX[$consumer]}"
    CONSUMER_NAME=$(echo "$consumer" | sed 's/-consumer-flink//')
    
    COUNT=$(docker logs cdc-local-$consumer 2>&1 | grep -c "$PREFIX" || echo 0)
    FLINK_CONSUMER_TOTAL=$((FLINK_CONSUMER_TOTAL + COUNT))
    
    if [ "$COUNT" -eq 10 ]; then
        pass "Flink $CONSUMER_NAME consumer: $COUNT/10 events processed"
        FLINK_CONSUMER_PASS=$((FLINK_CONSUMER_PASS + 1))
    elif [ "$COUNT" -gt 0 ]; then
        warn "Flink $CONSUMER_NAME consumer: $COUNT/10 events processed (may still be processing)"
    else
        fail "Flink $CONSUMER_NAME consumer: $COUNT/10 events processed"
    fi
done

if [ "$FLINK_CONSUMER_TOTAL" -eq 40 ] && [ "$FLINK_CONSUMER_PASS" -eq 4 ]; then
    pass "Flink consumers: $FLINK_CONSUMER_TOTAL/40 events (all 4 consumers have 10 events)"
else
    warn "Flink consumers: $FLINK_CONSUMER_TOTAL/40 events ($FLINK_CONSUMER_PASS/4 consumers complete)"
fi
echo ""

# Step 8: Verify Spring Boot Consumers
section "Step 8: Verify Spring Boot Consumers"
check_timeout
info "Waiting 10 seconds for Spring Boot consumers to process events (local should be fast)..."
sleep 10
check_timeout

SPRING_CONSUMER_TOTAL=0
SPRING_CONSUMER_PASS=0

declare -A SPRING_CONSUMER_PREFIX=(
    ["loan-consumer"]="validate-loan-$TEST_ID"
    ["car-consumer"]="validate-car-$TEST_ID"
    ["loan-payment-consumer"]="validate-payment-$TEST_ID"
    ["service-consumer"]="validate-service-$TEST_ID"
)

for consumer in "${!SPRING_CONSUMER_PREFIX[@]}"; do
    PREFIX="${SPRING_CONSUMER_PREFIX[$consumer]}"
    CONSUMER_NAME=$(echo "$consumer" | sed 's/-consumer//')
    
    COUNT=$(docker logs cdc-local-$consumer-spring 2>&1 | grep -c "$PREFIX" || echo 0)
    SPRING_CONSUMER_TOTAL=$((SPRING_CONSUMER_TOTAL + COUNT))
    
    if [ "$COUNT" -eq 10 ]; then
        pass "Spring $CONSUMER_NAME consumer: $COUNT/10 events processed"
        SPRING_CONSUMER_PASS=$((SPRING_CONSUMER_PASS + 1))
    elif [ "$COUNT" -gt 0 ]; then
        warn "Spring $CONSUMER_NAME consumer: $COUNT/10 events processed (may still be processing)"
    else
        fail "Spring $CONSUMER_NAME consumer: $COUNT/10 events processed"
    fi
done

if [ "$SPRING_CONSUMER_TOTAL" -eq 40 ] && [ "$SPRING_CONSUMER_PASS" -eq 4 ]; then
    pass "Spring consumers: $SPRING_CONSUMER_TOTAL/40 events (all 4 consumers have 10 events)"
else
    warn "Spring consumers: $SPRING_CONSUMER_TOTAL/40 events ($SPRING_CONSUMER_PASS/4 consumers complete)"
fi
echo ""

# Final Summary
section "Final Validation Summary"
echo "Test ID: validate-$TEST_ID"
echo ""
echo "Pipeline Stages:"
echo "  1. Database:              $DB_COUNT/40 events"
echo "  2. Raw Topic:             $RAW_COUNT/40 events"
echo ""
echo "Flink Pipeline:"
echo "  3. Flink Filtered Topics: $FLINK_TOTAL/40 events ($FLINK_PASS/4 topics complete)"
echo "  4. Flink Consumers:        $FLINK_CONSUMER_TOTAL/40 events ($FLINK_CONSUMER_PASS/4 consumers complete)"
echo ""
echo "Spring Boot Pipeline:"
echo "  5. Spring Filtered Topics: $SPRING_TOTAL/40 events ($SPRING_PASS/4 topics complete)"
echo "  6. Spring Consumers:       $SPRING_CONSUMER_TOTAL/40 events ($SPRING_CONSUMER_PASS/4 consumers complete)"
echo ""

# Determine overall success
SUCCESS=true

if [ "$DB_COUNT" -ne 40 ]; then
    SUCCESS=false
fi

if [ "$RAW_COUNT" -ne 40 ]; then
    SUCCESS=false
fi

if [ "$FLINK_TOTAL" -ne 40 ] || [ "$FLINK_PASS" -ne 4 ]; then
    SUCCESS=false
fi

if [ "$FLINK_CONSUMER_TOTAL" -ne 40 ] || [ "$FLINK_CONSUMER_PASS" -ne 4 ]; then
    SUCCESS=false
fi

if [ "$SPRING_TOTAL" -ne 40 ] || [ "$SPRING_PASS" -ne 4 ]; then
    SUCCESS=false
fi

if [ "$SPRING_CONSUMER_TOTAL" -ne 40 ] || [ "$SPRING_CONSUMER_PASS" -ne 4 ]; then
    SUCCESS=false
fi

if [ "$SUCCESS" = true ]; then
    pass "✅ SUCCESS: All 40 events processed through both pipelines!"
    pass "   - All 4 Flink consumers received all 10 events each"
    pass "   - All 4 Spring Boot consumers received all 10 events each"
    exit 0
else
    fail "❌ FAILED: Not all events processed correctly"
    echo ""
    echo "Issues found:"
    [ "$DB_COUNT" -ne 40 ] && echo "  - Database: $DB_COUNT/40 events"
    [ "$RAW_COUNT" -ne 40 ] && echo "  - Raw topic: $RAW_COUNT/40 events"
    [ "$FLINK_TOTAL" -ne 40 ] || [ "$FLINK_PASS" -ne 4 ] && echo "  - Flink topics: $FLINK_TOTAL/40 events ($FLINK_PASS/4 topics)"
    [ "$FLINK_CONSUMER_TOTAL" -ne 40 ] || [ "$FLINK_CONSUMER_PASS" -ne 4 ] && echo "  - Flink consumers: $FLINK_CONSUMER_TOTAL/40 events ($FLINK_CONSUMER_PASS/4 consumers)"
    [ "$SPRING_TOTAL" -ne 40 ] || [ "$SPRING_PASS" -ne 4 ] && echo "  - Spring topics: $SPRING_TOTAL/40 events ($SPRING_PASS/4 topics)"
    [ "$SPRING_CONSUMER_TOTAL" -ne 40 ] || [ "$SPRING_CONSUMER_PASS" -ne 4 ] && echo "  - Spring consumers: $SPRING_CONSUMER_TOTAL/40 events ($SPRING_CONSUMER_PASS/4 consumers)"
    exit 1
fi

