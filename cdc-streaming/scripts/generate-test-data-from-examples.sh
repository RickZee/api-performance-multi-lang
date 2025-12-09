#!/bin/bash
# Generate Test Data for CDC Streaming Pipeline using Example Structures
# This script generates test data for three event types using example files from the data folder
#
# Based on:
# - data/schemas/event/samples/car-created-event.json
# - data/schemas/event/samples/loan-created-event.json
# - data/schemas/event/samples/loan-payment-submitted-event.json

set -e

# Configuration
API_HOST="${API_HOST:-producer-api-java-rest}"
API_PORT="${API_PORT:-8081}"
API_PATH="${API_PATH:-/api/v1/events}"
API_URL="http://${API_HOST}:${API_PORT}${API_PATH}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$PROJECT_ROOT/data"
CAR_CREATED_FILE="$DATA_DIR/schemas/event/samples/car-created-event.json"
LOAN_CREATED_FILE="$DATA_DIR/schemas/event/samples/loan-created-event.json"
LOAN_PAYMENT_FILE="$DATA_DIR/schemas/event/samples/loan-payment-submitted-event.json"

# Output
OUTPUT_DIR="${OUTPUT_DIR:-./test-results}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/cdc-test-data-from-examples-${TIMESTAMP}.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}CDC Streaming Test Data Generator${NC}"
echo -e "${BLUE}Generating: Car Created, Loan Created, Loan Payment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if example files exist
if [ ! -f "$CAR_CREATED_FILE" ]; then
    echo -e "${RED}Error: Car created event file not found at $CAR_CREATED_FILE${NC}"
    exit 1
fi

if [ ! -f "$LOAN_CREATED_FILE" ]; then
    echo -e "${RED}Error: Loan created event file not found at $LOAN_CREATED_FILE${NC}"
    exit 1
fi

if [ ! -f "$LOAN_PAYMENT_FILE" ]; then
    echo -e "${RED}Error: Loan payment event file not found at $LOAN_PAYMENT_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found car-created-event.json${NC}"
echo -e "${GREEN}✓ Found loan-created-event.json${NC}"
echo -e "${GREEN}✓ Found loan-payment-submitted-event.json${NC}"
echo ""

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    echo "Install jq from: https://stedolan.github.io/jq/download/"
    exit 1
fi

# Check if API is accessible
echo -e "${YELLOW}Checking API availability...${NC}"
API_AVAILABLE=false

if command -v docker &> /dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^producer-api-java-rest$"; then
    API_AVAILABLE=true
    echo -e "${GREEN}✓ Java REST API container is running${NC}"
else
    echo -e "${YELLOW}Warning: Java REST API container not found${NC}"
    echo -e "${YELLOW}Make sure the Java REST API is running:${NC}"
    echo -e "  docker-compose --profile producer-java-rest up -d producer-api-java-rest"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate test events based on examples
echo -e "${BLUE}Generating test events from examples...${NC}"

# Read the example files
CAR_EVENT_TEMPLATE=$(cat "$CAR_CREATED_FILE")
LOAN_EVENT_TEMPLATE=$(cat "$LOAN_CREATED_FILE")
LOAN_PAYMENT_TEMPLATE=$(cat "$LOAN_PAYMENT_FILE")

# Generate timestamps with proper sequencing
# Car Created: T0 (base timestamp)
# Loan Created: T0 + 5 days
# Loan Payment: T0 + 35 days (30 days after loan)
BASE_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Calculate timestamps using Python for cross-platform compatibility
LOAN_TIMESTAMP=$(python3 -c "
from datetime import datetime, timedelta
base = datetime.fromisoformat('$BASE_TIMESTAMP'.replace('Z', '+00:00'))
loan = base + timedelta(days=5)
print(loan.strftime('%Y-%m-%dT%H:%M:%SZ'))
" 2>/dev/null || echo "$BASE_TIMESTAMP")

PAYMENT_TIMESTAMP=$(python3 -c "
from datetime import datetime, timedelta
base = datetime.fromisoformat('$BASE_TIMESTAMP'.replace('Z', '+00:00'))
payment = base + timedelta(days=35)
print(payment.strftime('%Y-%m-%dT%H:%M:%SZ'))
" 2>/dev/null || echo "$BASE_TIMESTAMP")

CAR_TIMESTAMP="$BASE_TIMESTAMP"

# Generate unique IDs
CAR_ID="CAR-$(date +%Y%m%d)-$(printf "%03d" $((RANDOM % 1000)))"
LOAN_ID="LOAN-$(date +%Y%m%d)-$(printf "%03d" $((RANDOM % 1000)))"
PAYMENT_ID="PAYMENT-$(date +%Y%m%d)-$(printf "%03d" $((RANDOM % 1000)))"

# Generate UUIDs
CAR_UUID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "550e8400-e29b-41d4-a716-446655440001")
LOAN_UUID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "550e8400-e29b-41d4-a716-446655440002")
PAYMENT_UUID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "550e8400-e29b-41d4-a716-446655440003")

# Generate car created event
CAR_EVENT=$(echo "$CAR_EVENT_TEMPLATE" | jq \
    --arg uuid "$CAR_UUID" \
    --arg timestamp "$CAR_TIMESTAMP" \
    --arg carId "$CAR_ID" \
    '.eventHeader.uuid = $uuid |
     .eventHeader.createdDate = $timestamp |
     .eventHeader.savedDate = $timestamp |
     .entities[0].entityHeader.entityId = $carId |
     .entities[0].entityHeader.createdAt = $timestamp |
     .entities[0].entityHeader.updatedAt = $timestamp |
     .entities[0].id = $carId')

# Generate loan created event (linked to car)
LOAN_EVENT_GENERATED=$(echo "$LOAN_EVENT_TEMPLATE" | jq \
    --arg uuid "$LOAN_UUID" \
    --arg timestamp "$LOAN_TIMESTAMP" \
    --arg loanId "$LOAN_ID" \
    --arg carId "$CAR_ID" \
    '.eventHeader.uuid = $uuid |
     .eventHeader.createdDate = $timestamp |
     .eventHeader.savedDate = $timestamp |
     .entities[0].entityHeader.entityId = $loanId |
     .entities[0].entityHeader.createdAt = $timestamp |
     .entities[0].entityHeader.updatedAt = $timestamp |
     .entities[0].id = $loanId |
     .entities[0].carId = $carId |
     .entities[0].lastPaidDate = $timestamp |
     .entities[0].startDate = $timestamp')

# Extract monthly payment amount from loan event for payment amount
MONTHLY_PAYMENT=$(echo "$LOAN_EVENT_GENERATED" | jq -r '.entities[0].monthlyPayment')

# Generate loan payment event (linked to loan)
LOAN_PAYMENT_EVENT=$(echo "$LOAN_PAYMENT_TEMPLATE" | jq \
    --arg uuid "$PAYMENT_UUID" \
    --arg timestamp "$PAYMENT_TIMESTAMP" \
    --arg paymentId "$PAYMENT_ID" \
    --arg loanId "$LOAN_ID" \
    --arg amount "$MONTHLY_PAYMENT" \
    '.eventHeader.uuid = $uuid |
     .eventHeader.createdDate = $timestamp |
     .eventHeader.savedDate = $timestamp |
     .entities[0].entityHeader.entityId = $paymentId |
     .entities[0].entityHeader.createdAt = $timestamp |
     .entities[0].entityHeader.updatedAt = $timestamp |
     .entities[0].id = $paymentId |
     .entities[0].loanId = $loanId |
     .entities[0].amount = ($amount | tonumber) |
     .entities[0].paymentDate = $timestamp')

echo -e "${GREEN}✓ Generated car created event${NC}"
echo -e "${GREEN}✓ Generated loan created event${NC}"
echo -e "${GREEN}✓ Generated loan payment submitted event${NC}"
echo ""

# Display sample events
echo -e "${BLUE}Sample Car Created Event:${NC}"
echo "$CAR_EVENT" | jq '.' | head -20
echo ""
echo -e "${BLUE}Sample Loan Created Event:${NC}"
echo "$LOAN_EVENT_GENERATED" | jq '.' | head -20
echo ""
echo -e "${BLUE}Sample Loan Payment Submitted Event:${NC}"
echo "$LOAN_PAYMENT_EVENT" | jq '.' | head -20
echo ""

# Save events to file
echo "$CAR_EVENT" > "${OUTPUT_DIR}/car-created-event-${TIMESTAMP}.json"
echo "$LOAN_EVENT_GENERATED" > "${OUTPUT_DIR}/loan-created-event-${TIMESTAMP}.json"
echo "$LOAN_PAYMENT_EVENT" > "${OUTPUT_DIR}/loan-payment-submitted-event-${TIMESTAMP}.json"

echo -e "${GREEN}✓ Events saved to:${NC}"
echo "  - ${OUTPUT_DIR}/car-created-event-${TIMESTAMP}.json"
echo "  - ${OUTPUT_DIR}/loan-created-event-${TIMESTAMP}.json"
echo "  - ${OUTPUT_DIR}/loan-payment-submitted-event-${TIMESTAMP}.json"
echo ""

# If API is available, send events in sequence
if [ "$API_AVAILABLE" = true ]; then
    echo -e "${YELLOW}Sending events to API (in sequence: Car → Loan → Payment)...${NC}"
    
    # Send car created event (first)
    CAR_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "$CAR_EVENT")
    CAR_HTTP_CODE=$(echo "$CAR_RESPONSE" | tail -n1)
    CAR_BODY=$(echo "$CAR_RESPONSE" | sed '$d')
    
    if [ "$CAR_HTTP_CODE" -eq 200 ] || [ "$CAR_HTTP_CODE" -eq 201 ]; then
        echo -e "${GREEN}✓ Car created event sent successfully${NC}"
    else
        echo -e "${RED}✗ Failed to send car created event (HTTP $CAR_HTTP_CODE)${NC}"
        echo "$CAR_BODY" | jq '.' 2>/dev/null || echo "$CAR_BODY"
    fi
    
    # Small delay to ensure car is created before loan
    sleep 1
    
    # Send loan created event (second)
    LOAN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "$LOAN_EVENT_GENERATED")
    LOAN_HTTP_CODE=$(echo "$LOAN_RESPONSE" | tail -n1)
    LOAN_BODY=$(echo "$LOAN_RESPONSE" | sed '$d')
    
    if [ "$LOAN_HTTP_CODE" -eq 200 ] || [ "$LOAN_HTTP_CODE" -eq 201 ]; then
        echo -e "${GREEN}✓ Loan created event sent successfully${NC}"
    else
        echo -e "${RED}✗ Failed to send loan created event (HTTP $LOAN_HTTP_CODE)${NC}"
        echo "$LOAN_BODY" | jq '.' 2>/dev/null || echo "$LOAN_BODY"
    fi
    
    # Small delay to ensure loan is created before payment
    sleep 1
    
    # Send loan payment event (third)
    PAYMENT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "$LOAN_PAYMENT_EVENT")
    PAYMENT_HTTP_CODE=$(echo "$PAYMENT_RESPONSE" | tail -n1)
    PAYMENT_BODY=$(echo "$PAYMENT_RESPONSE" | sed '$d')
    
    if [ "$PAYMENT_HTTP_CODE" -eq 200 ] || [ "$PAYMENT_HTTP_CODE" -eq 201 ]; then
        echo -e "${GREEN}✓ Loan payment submitted event sent successfully${NC}"
    else
        echo -e "${RED}✗ Failed to send loan payment event (HTTP $PAYMENT_HTTP_CODE)${NC}"
        echo "$PAYMENT_BODY" | jq '.' 2>/dev/null || echo "$PAYMENT_BODY"
    fi
    echo ""
fi

echo -e "${BLUE}Next steps:${NC}"
echo "  1. Check raw events in Kafka:"
echo "     docker exec -it cdc-kafka kafka-console-consumer.sh \\"
echo "       --bootstrap-server localhost:9092 \\"
echo "       --topic raw-business-events \\"
echo "       --from-beginning"
echo ""
echo "  2. Check filtered loan created events:"
echo "     docker exec -it cdc-kafka kafka-console-consumer.sh \\"
echo "       --bootstrap-server localhost:9092 \\"
echo "       --topic filtered-loan-events \\"
echo "       --from-beginning"
echo ""
echo "  3. Check filtered loan payment events:"
echo "     docker exec -it cdc-kafka kafka-console-consumer.sh \\"
echo "       --bootstrap-server localhost:9092 \\"
echo "       --topic filtered-loan-payment-events \\"
echo "       --from-beginning"
echo ""
echo "  4. Check consumer logs:"
echo "     docker logs cdc-loan-consumer"
echo ""
echo -e "${GREEN}Test data generation completed!${NC}"
echo -e "${BLUE}Generated 3 events: Car Created → Loan Created → Loan Payment Submitted${NC}"

