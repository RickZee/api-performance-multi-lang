#!/bin/bash
# Run k6 batch tests against FastAPI

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Running k6 Batch Tests Against FastAPI${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if k6 is installed
if ! command -v k6 &> /dev/null; then
    echo -e "${RED}✗ k6 is not installed${NC}"
    echo "  Install with: brew install k6"
    exit 1
fi

# Check if API is running
if ! curl -s http://localhost:3000/api/v1/events/health | grep -q "healthy"; then
    echo -e "${RED}✗ FastAPI is not running or not healthy${NC}"
    echo "  Start it with: ./scripts/start-local.sh"
    exit 1
fi

echo -e "${GREEN}✓ API is running and healthy${NC}"
echo ""

# Run k6 batch test
cd "$PROJECT_ROOT/load-test/k6"

echo -e "${BLUE}Running k6 batch test...${NC}"
echo -e "${BLUE}API URL: http://localhost:3000/api/v1/events${NC}"
echo -e "${YELLOW}Note: Using single event endpoint (bulk endpoint requires different payload format)${NC}"
echo ""

k6 run --env HOST=localhost --env PORT=3000 send-batch-events.js

echo ""
echo -e "${GREEN}✓ k6 batch test completed${NC}"
