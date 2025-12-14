#!/bin/bash
# Test filter API directly without Docker
# Starts the metadata service locally and tests it

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

METADATA_URL="http://localhost:8080"
DATA_PATH=$(cd "$PROJECT_ROOT/data" && pwd)

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Testing Filter API (Direct - No Docker)${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Check if service is already running
if curl -s -f "${METADATA_URL}/api/v1/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Metadata service is already running${NC}"
else
    echo -e "${BLUE}Starting metadata service in background...${NC}"
    echo -e "${YELLOW}Note: Make sure the service is running on port 8080${NC}"
    echo -e "${YELLOW}Start it with:${NC}"
    echo "  cd metadata-service"
    echo "  GIT_REPOSITORY=file://${DATA_PATH} LOCAL_CACHE_DIR=${DATA_PATH} go run cmd/server/main.go"
    echo ""
    echo -e "${YELLOW}Or run the Go tests instead:${NC}"
    echo "  cd metadata-service && go test -run TestFilterE2E -v"
    echo ""
    read -p "Press Enter to continue with API tests (or Ctrl+C to exit)..."
fi

# Wait a bit for service to be ready
sleep 2

# Check health
echo -e "${BLUE}Checking service health...${NC}"
if ! curl -s -f "${METADATA_URL}/api/v1/health" > /dev/null; then
    echo -e "${RED}✗ Service is not responding at ${METADATA_URL}${NC}"
    echo -e "${YELLOW}Starting service for you...${NC}"
    
    # Start service in background
    cd metadata-service
    GIT_REPOSITORY="file://${DATA_PATH}" \
    LOCAL_CACHE_DIR="${DATA_PATH}" \
    SERVER_PORT=8080 \
    DEFAULT_VERSION=v1 \
    go run cmd/server/main.go &
    
    SERVICE_PID=$!
    echo -e "${BLUE}Service started with PID: ${SERVICE_PID}${NC}"
    
    # Wait for service to start
    echo -e "${BLUE}Waiting for service to be ready...${NC}"
    for i in {1..30}; do
        if curl -s -f "${METADATA_URL}/api/v1/health" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Service is ready${NC}"
            break
        fi
        sleep 1
        echo -n "."
    done
    echo ""
    
    if ! curl -s -f "${METADATA_URL}/api/v1/health" > /dev/null; then
        echo -e "${RED}✗ Service failed to start${NC}"
        kill $SERVICE_PID 2>/dev/null || true
        exit 1
    fi
    
    # Cleanup function
    trap "echo ''; echo 'Stopping service...'; kill $SERVICE_PID 2>/dev/null || true; exit" INT TERM
fi

cd "$PROJECT_ROOT"

# Run the test script
echo ""
echo -e "${BLUE}Running filter API tests...${NC}"
echo ""
./scripts/test-filter-api.sh

# Cleanup
if [ ! -z "$SERVICE_PID" ]; then
    echo ""
    echo -e "${BLUE}Stopping service (PID: ${SERVICE_PID})...${NC}"
    kill $SERVICE_PID 2>/dev/null || true
fi
