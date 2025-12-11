#!/bin/bash
# Send 3 sample events using k6 to Java REST API for Confluent integration
# Events: Car Created → Loan Created → Loan Payment Submitted
# Based on samples in data/schemas/event/samples/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
K6_SCRIPT="$REPO_ROOT/load-test/k6/send-sample-events.js"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default configuration
# If API_URL is set, use it directly (for Lambda API Gateway)
# Otherwise construct from HOST and PORT
if [ -n "$API_URL" ]; then
    # API_URL already set, use as-is
    :
elif [ -n "$HOST" ] && [ -n "$PORT" ]; then
    API_URL="http://${HOST}:${PORT}"
else
    # Default to localhost for local testing
    API_HOST="${HOST:-localhost}"
    API_PORT="${PORT:-8081}"
    API_URL="http://${API_HOST}:${API_PORT}"
fi
VERIFY_EVENTS="${VERIFY_EVENTS:-false}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            API_HOST="$2"
            API_URL="http://${API_HOST}:${API_PORT}"
            shift 2
            ;;
        --port)
            API_PORT="$2"
            API_URL="http://${API_HOST}:${API_PORT}"
            shift 2
            ;;
        --verify)
            VERIFY_EVENTS="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Send 3 sample events to Java REST API using k6:"
            echo "  1. Car Created"
            echo "  2. Loan Created (linked to car)"
            echo "  3. Loan Payment Submitted (linked to loan)"
            echo ""
            echo "Options:"
            echo "  --host HOST          API host (default: localhost)"
            echo "  --port PORT          API port (default: 8081)"
            echo "  --verify             Verify events in Confluent after sending"
            echo "  --help               Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  HOST                 API host"
            echo "  PORT                 API port"
            echo "  VERIFY_EVENTS        Set to 'true' to verify events (default: false)"
            echo ""
            echo "Examples:"
            echo "  $0"
            echo "  $0 --host producer-api-java-rest --port 8081"
            echo "  $0 --verify"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Send Sample Events with k6${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Configuration:${NC}"
echo "  API URL:      $API_URL"
echo "  Events:       Car Created → Loan Created → Loan Payment Submitted"
echo "  Verify:       $VERIFY_EVENTS"
echo ""

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"
echo ""

# Check k6 is installed
if ! command -v k6 &> /dev/null; then
    echo -e "${RED}✗ k6 is not installed${NC}"
    echo "  Install with: brew install k6"
    echo "  Or: npm install -g k6"
    exit 1
fi
echo -e "${GREEN}✓ k6 is installed${NC}"

# Check k6 script exists
if [ ! -f "$K6_SCRIPT" ]; then
    echo -e "${RED}✗ k6 test script not found: $K6_SCRIPT${NC}"
    exit 1
fi
echo -e "${GREEN}✓ k6 test script found${NC}"

# Check API is running
echo -e "${YELLOW}  Checking API health...${NC}"
if curl -sf "${API_URL}/api/v1/events/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ API is running and responding${NC}"
else
    echo -e "${RED}✗ API is not running at $API_URL${NC}"
    echo "  Start with: cd producer-api-java-rest && ./gradlew bootRun"
    echo "  Or ensure the API is accessible at $API_URL"
    exit 1
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Sending Sample Events${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Set environment variables for k6
export HOST="$API_HOST"
export PORT="$API_PORT"

# Add authentication if provided
if [ -n "$AUTH_ENABLED" ]; then
    export AUTH_ENABLED="$AUTH_ENABLED"
fi
if [ -n "$JWT_TOKEN" ]; then
    export JWT_TOKEN="$JWT_TOKEN"
fi

# Run k6 test
echo -e "${CYAN}Executing: k6 run $K6_SCRIPT${NC}"
echo -e "${CYAN}Environment:${NC}"
echo "  HOST=$HOST"
echo "  PORT=$PORT"
echo ""

if k6 run "$K6_SCRIPT"; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Sample Events Sent Successfully${NC}"
    echo -e "${GREEN}========================================${NC}"
    TEST_SUCCESS=true
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Failed to Send Events${NC}"
    echo -e "${RED}========================================${NC}"
    TEST_SUCCESS=false
fi

# Verify events if requested
if [ "$VERIFY_EVENTS" = "true" ]; then
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Verifying Events${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    if [ -f "$SCRIPT_DIR/verify-k6-events-in-confluent.sh" ]; then
        echo -e "${CYAN}Running verification script...${NC}"
        ENDPOINT="/api/v1/events" "$SCRIPT_DIR/verify-k6-events-in-confluent.sh" || {
            echo -e "${YELLOW}⚠ Verification script encountered issues${NC}"
        }
    else
        echo -e "${YELLOW}⚠ Verification script not found${NC}"
        echo "  Expected: $SCRIPT_DIR/verify-k6-events-in-confluent.sh"
    fi
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "  API URL:      $API_URL"
echo "  Events Sent:  Car Created → Loan Created → Loan Payment Submitted"
echo "  Status:       $([ "$TEST_SUCCESS" = "true" ] && echo -e "${GREEN}SUCCESS${NC}" || echo -e "${RED}FAILED${NC}")"
echo ""

if [ "$TEST_SUCCESS" = "true" ]; then
    echo -e "${GREEN}Next Steps:${NC}"
    echo "  1. Review k6 metrics above"
    echo "  2. Verify events in PostgreSQL database"
    echo "  3. Check Debezium CDC connector status"
    echo "  4. Verify events in Confluent Cloud topics"
    echo "  5. Monitor Flink SQL job processing (if deployed)"
    exit 0
else
    echo -e "${RED}Failed to send events. Check the output above for details.${NC}"
    exit 1
fi
