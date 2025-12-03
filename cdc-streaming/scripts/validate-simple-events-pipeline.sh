#!/bin/bash

# Validate Simple Events CDC Pipeline
# This script validates the entire pipeline from API to Kafka

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
API_URL="${API_URL:-http://localhost:8080}"
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"

echo "======================================"
echo "Validating Simple Events CDC Pipeline"
echo "======================================"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        return 1
    fi
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Step 1: Check if Java API is running
echo ""
echo "Step 1: Checking Java REST API..."
if curl -sf "$API_URL/api/v1/events/health" > /dev/null 2>&1; then
    print_status 0 "Java REST API is running"
else
    print_warning "Java REST API is not running at $API_URL"
    echo "  Please start it with: cd producer-api-java-rest && ./gradlew bootRun"
    echo "  Or check if it's running on a different port"
fi

# Step 2: Check if Kafka Connect is running
echo ""
echo "Step 2: Checking Kafka Connect..."
if curl -sf "$KAFKA_CONNECT_URL" > /dev/null 2>&1; then
    print_status 0 "Kafka Connect is running"
    
    # Check if simple-events connector is deployed
    CONNECTOR_NAME="postgres-debezium-simple-events-confluent-cloud"
    if curl -sf "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME" > /dev/null 2>&1; then
        print_status 0 "Simple events connector is deployed"
        
        # Check connector status
        echo ""
        echo "Connector Status:"
        curl -s "$KAFKA_CONNECT_URL/connectors/$CONNECTOR_NAME/status" | jq -r '.connector.state, .tasks[0].state' 2>/dev/null || echo "  Could not parse connector status"
    else
        print_warning "Simple events connector is not deployed"
        echo "  Deploy it with: cd cdc-streaming/scripts && ./deploy-debezium-simple-events-connector.sh"
    fi
else
    print_warning "Kafka Connect is not running at $KAFKA_CONNECT_URL"
    echo "  Please start it with: cd cdc-streaming && docker-compose -f docker-compose.confluent-cloud.yml up -d kafka-connect-cloud"
fi

# Step 3: Test the API endpoint
echo ""
echo "Step 3: Testing POST /api/v1/events/events-simple endpoint..."
TEST_UUID="test-$(date +%s)-$(uuidgen | cut -d'-' -f1)"
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

if curl -sf "$API_URL/api/v1/events/health" > /dev/null 2>&1; then
    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$TEST_EVENT" \
        "$API_URL/api/v1/events/events-simple")
    
    HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
    BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')
    
    if [ "$HTTP_STATUS" -eq 200 ]; then
        print_status 0 "API endpoint accepted the event"
        echo "  Response: $BODY"
    else
        print_warning "API endpoint returned status $HTTP_STATUS"
        echo "  Response: $BODY"
    fi
else
    print_warning "Cannot test API endpoint - API is not running"
fi

# Step 4: Check database table exists
echo ""
echo "Step 4: Checking database table..."
CONTAINER_NAME="car_entities_postgres_large"
if docker ps | grep -q "$CONTAINER_NAME"; then
    if docker exec "$CONTAINER_NAME" psql -U postgres -d car_entities -c "\d simple_events" > /dev/null 2>&1; then
        print_status 0 "simple_events table exists in database"
    else
        print_warning "simple_events table does not exist in database"
        echo "  The table should be created when the Java API starts (via schema.sql)"
    fi
else
    print_warning "PostgreSQL container '$CONTAINER_NAME' is not running"
    echo "  Cannot check database table"
fi

# Step 5: Summary
echo ""
echo "======================================"
echo "Validation Summary"
echo "======================================"
echo ""
echo "To complete the pipeline validation:"
echo "  1. Ensure Java API is running and has created the simple_events table"
echo "  2. Ensure PostgreSQL is running with logical replication enabled"
echo "  3. Deploy the CDC connector: ./deploy-debezium-simple-events-connector.sh"
echo "  4. Send test events to: POST $API_URL/api/v1/events/events-simple"
echo "  5. Verify events appear in Kafka topic: simple-business-events"
echo ""
echo "Useful commands:"
echo "  Check connector status: curl $KAFKA_CONNECT_URL/connectors/postgres-debezium-simple-events-confluent-cloud/status | jq"
echo "  View connector logs: docker logs cdc-kafka-connect-cloud -f"
echo "  Test API endpoint: curl -X POST $API_URL/api/v1/events/events-simple -H 'Content-Type: application/json' -d '$TEST_EVENT'"
echo ""


