#!/bin/bash
# Generate Test Data for CDC Streaming Pipeline
# This script uses k6 to send events to the Java REST API, which stores them in Postgres
# The Postgres CDC connector will then capture these changes and stream them to Kafka

set -e

# Configuration
API_HOST="${API_HOST:-producer-api-java-rest}"
API_PORT="${API_PORT:-8081}"
API_PATH="${API_PATH:-/api/v1/events}"
API_URL="http://${API_HOST}:${API_PORT}${API_PATH}"

# k6 test configuration
VUS="${VUS:-10}"              # Virtual users (concurrent requests)
DURATION="${DURATION:-30s}"   # Test duration
RATE="${RATE:-}"              # Request rate (requests per second), optional
PAYLOAD_SIZE="${PAYLOAD_SIZE:-4k}"  # Payload size (400b, 4k, 8k, 32k, 64k)

# Output
OUTPUT_DIR="${OUTPUT_DIR:-./test-results}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/cdc-test-data-${TIMESTAMP}.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}CDC Streaming Test Data Generator${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if k6 is available
if ! command -v k6 &> /dev/null; then
    echo -e "${RED}Error: k6 is not installed${NC}"
    echo "Install k6 from: https://k6.io/docs/getting-started/installation/"
    exit 1
fi

# Check if API is accessible (check if container is running)
echo -e "${YELLOW}Checking API availability...${NC}"
API_AVAILABLE=false

# Check if running in Docker and container exists
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

# Use existing k6 test script
# Get the script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
K6_SCRIPT_PATH="$PROJECT_ROOT/load-test/k6/rest-api-test.js"

# Check if k6 script exists
if [ ! -f "$K6_SCRIPT_PATH" ]; then
    echo -e "${RED}Error: k6 test script not found at $K6_SCRIPT_PATH${NC}"
    echo "Make sure the load-test directory exists in the project root"
    exit 1
fi

echo -e "${BLUE}Configuration:${NC}"
echo "  API URL: $API_URL"
echo "  Virtual Users: $VUS"
echo "  Duration: $DURATION"
if [ -n "$RATE" ]; then
    echo "  Rate: $RATE req/s"
fi
echo "  Payload Size: $PAYLOAD_SIZE"
echo "  Output: $OUTPUT_FILE"
echo ""

echo -e "${YELLOW}Starting test data generation...${NC}"
echo ""

# Run k6 test using existing script
if k6 run \
    --vus "$VUS" \
    --duration "$DURATION" \
    --env HOST="$API_HOST" \
    --env PORT="$API_PORT" \
    --env PATH="$API_PATH" \
    --env PAYLOAD_SIZE="$PAYLOAD_SIZE" \
    --out json="$OUTPUT_FILE" \
    "$K6_SCRIPT_PATH" 2>&1 | tee "${OUTPUT_DIR}/cdc-test-run-${TIMESTAMP}.log"; then
    
    echo ""
    echo -e "${GREEN}✓ Test data generation completed!${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Check raw events in Kafka:"
    echo "     docker exec -it cdc-kafka kafka-console-consumer.sh \\"
    echo "       --bootstrap-server localhost:9092 \\"
    echo "       --topic raw-business-events \\"
    echo "       --from-beginning"
    echo ""
    echo "  2. Check filtered events:"
    echo "     docker exec -it cdc-kafka kafka-console-consumer.sh \\"
    echo "       --bootstrap-server localhost:9092 \\"
    echo "       --topic filtered-loan-events \\"
    echo "       --from-beginning"
    echo ""
    echo "  3. Check consumer logs:"
    echo "     docker logs cdc-loan-consumer"
    echo "     docker logs cdc-service-consumer"
    echo ""
    echo -e "${GREEN}Test results saved to: $OUTPUT_FILE${NC}"
else
    echo ""
    echo -e "${RED}✗ Test data generation failed${NC}"
    exit 1
fi

