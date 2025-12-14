#!/bin/bash
# Run all metadata service Java tests in Docker

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Metadata Service Java - Docker Test Runner${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Build the test image
echo -e "${BLUE}Building test Docker image...${NC}"
docker build -f Dockerfile.test -t metadata-service-java-test:latest .

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to build test image${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Test image built successfully${NC}"
echo ""

# Run tests
echo -e "${BLUE}Running all tests...${NC}"
echo ""

docker run --rm \
    -v "$SCRIPT_DIR:/app" \
    -w /app \
    metadata-service-java-test:latest \
    ./gradlew test --no-daemon --info

TEST_EXIT_CODE=$?

echo ""
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo -e "${GREEN}========================================${NC}"
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ Some tests failed (exit code: $TEST_EXIT_CODE)${NC}"
    echo -e "${RED}========================================${NC}"
fi

exit $TEST_EXIT_CODE
