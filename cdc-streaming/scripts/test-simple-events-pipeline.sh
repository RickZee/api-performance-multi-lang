#!/bin/bash

# End-to-End Test Script for Simple Events Pipeline
# This script tests the complete pipeline from API to Kafka

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
API_URL="${API_URL:-http://localhost:8081}"
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"
DB_CONTAINER="car_entities_postgres_large"

echo "======================================"
echo "Testing Simple Events CDC Pipeline"
echo "======================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++))
}

test_info() {
    echo -e "${BLUE}ℹ INFO${NC}: $1"
}

# Test 1: Check API is running
echo "Test 1: Checking Java REST API health..."
if curl -sf "$API_URL/api/v1/events/health" > /dev/null 2>&1; then
    test_pass "API is running and responding"
else
    test_fail "API is not running at $API_URL"
    echo "  Start with: cd producer-api-java-rest && ./gradlew bootRun"
    exit 1
fi

# Test 2: Check database table exists
echo ""
echo "Test 2: Checking simple_events table exists..."
if docker ps | grep -q "$DB_CONTAINER"; then
    if docker exec "$DB_CONTAINER" psql -U postgres -d car_entities -c "\d simple_events" > /dev/null 2>&1; then
        test_pass "simple_events table exists"
    else
        test_fail "simple_events table does not exist"
        test_info "Table should be created automatically when API starts"
    fi
else
    test_fail "PostgreSQL container '$DB_CONTAINER' is not running"
fi

# Test 3: Send a test event
echo ""
echo "Test 3: Sending test event to API..."
TEST_UUID="test-$(date +%s)-$(uuidgen 2>/dev/null | cut -d'-' -f1 || echo "manual")"
TEST_EVENT=$(cat <<EOF
{
  "uuid": "$TEST_UUID",
  "eventName": "LoanPaymentSubmitted",
  "createdDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "savedDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "eventType": "LoanPaymentSubmitted"
}
EOF
)

RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$TEST_EVENT" \
    "$API_URL/api/v1/events/events-simple" 2>&1)

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

if [ "$HTTP_STATUS" -eq 200 ]; then
    test_pass "Event accepted by API (HTTP $HTTP_STATUS)"
    test_info "Response: $BODY"
else
    test_fail "Event rejected by API (HTTP $HTTP_STATUS)"
    test_info "Response: $BODY"
fi

# Test 4: Verify event in database
echo ""
echo "Test 4: Verifying event in database..."
if docker ps | grep -q "$DB_CONTAINER"; then
    sleep 1  # Give DB a moment to commit
    DB_RESULT=$(docker exec "$DB_CONTAINER" psql -U postgres -d car_entities -t -c "SELECT COUNT(*) FROM simple_events WHERE id = '$TEST_UUID';" 2>/dev/null | tr -d ' ')
    if [ "$DB_RESULT" = "1" ]; then
        test_pass "Event found in database"
        
        # Get event details
        EVENT_DATA=$(docker exec "$DB_CONTAINER" psql -U postgres -d car_entities -t -A -F',' -c "SELECT id, event_name, event_type FROM simple_events WHERE id = '$TEST_UUID';" 2>/dev/null)
        test_info "Event data: $EVENT_DATA"
    else
        test_fail "Event not found in database (count: $DB_RESULT)"
    fi
else
    test_info "Skipping database verification - container not running"
fi

# Test 5: Check CDC connector is deployed
echo ""
echo "Test 5: Checking CDC connector status..."
CONNECTOR_NAME="postgres-debezium-simple-events-confluent-cloud"
if curl -sf "$KAFKA_CONNECT_URL" > /dev/null 2>&1; then
    if curl -sf "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME" > /dev/null 2>&1; then
        CONNECTOR_STATE=$(curl -s "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME/status" | jq -r '.connector.state' 2>/dev/null || echo "unknown")
        TASK_STATE=$(curl -s "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME/status" | jq -r '.tasks[0].state' 2>/dev/null || echo "unknown")
        
        if [ "$CONNECTOR_STATE" = "RUNNING" ] && [ "$TASK_STATE" = "RUNNING" ]; then
            test_pass "CDC connector is running (connector: $CONNECTOR_STATE, task: $TASK_STATE)"
        else
            test_fail "CDC connector not fully running (connector: $CONNECTOR_STATE, task: $TASK_STATE)"
        fi
    else
        test_fail "CDC connector '$CONNECTOR_NAME' is not deployed"
        test_info "Deploy with: cd cdc-streaming/scripts && ./deploy-debezium-simple-events-connector.sh"
    fi
else
    test_fail "Kafka Connect is not running at $KAFKA_CONNECT_URL"
    test_info "Start with: cd cdc-streaming && docker-compose -f docker-compose.confluent-cloud.yml up -d kafka-connect-cloud"
fi

# Test 6: Check for CDC events (if connector is running)
echo ""
echo "Test 6: Checking for CDC events in Kafka..."
if curl -sf "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME" > /dev/null 2>&1; then
    test_info "Note: To verify events in Kafka topic 'simple-business-events', use:"
    test_info "  kafka-console-consumer --bootstrap-server <broker> --topic simple-business-events --from-beginning"
    test_info "  Or check Confluent Cloud UI for the topic"
else
    test_info "Skipping Kafka verification - connector not deployed"
fi

# Summary
echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi



