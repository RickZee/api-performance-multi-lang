#!/bin/bash
# Complete local test runner - sets up and runs the filter API tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Local Filter API Test Runner${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Step 1: Setup local environment
echo -e "${BLUE}Step 1: Setting up local test environment...${NC}"
./scripts/setup-local-test.sh
echo ""

# Step 2: Get absolute path for git repository
DATA_ABS_PATH=$(cd "$PROJECT_ROOT/data" && pwd)
GIT_REPO_URL="file://${DATA_ABS_PATH}"

echo -e "${BLUE}Step 2: Starting metadata service...${NC}"
echo -e "${YELLOW}Using git repository: ${GIT_REPO_URL}${NC}"

# Stop existing service if running
docker-compose --profile metadata-service down 2>/dev/null || true

# Start service
GIT_REPOSITORY="${GIT_REPO_URL}" docker-compose --profile metadata-service up -d

echo -e "${GREEN}✓ Service starting...${NC}"
echo ""

# Step 3: Wait for service to be healthy
echo -e "${BLUE}Step 3: Waiting for service to be healthy...${NC}"
MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if curl -s -f http://localhost:8080/api/v1/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Service is healthy${NC}"
        break
    fi
    echo -n "."
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    echo -e "${RED}✗ Service failed to become healthy${NC}"
    echo "Check logs: docker-compose logs metadata-service"
    exit 1
fi

echo ""

# Step 4: Run tests
echo -e "${BLUE}Step 4: Running filter API tests...${NC}"
echo ""
./scripts/test-filter-api.sh

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${GREEN}✓ Test run completed${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "To view service logs: docker-compose logs -f metadata-service"
echo "To stop service: docker-compose --profile metadata-service down"
