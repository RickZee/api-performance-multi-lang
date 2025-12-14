#!/bin/bash
# Setup script for local testing
# Initializes a local git repository in the data directory for metadata service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Setting up local test environment${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Check if data directory exists
if [ ! -d "data" ]; then
    echo -e "${YELLOW}⚠ Data directory not found, creating...${NC}"
    mkdir -p data/schemas/v1/{event,entity,filters}
fi

# Initialize git repository in data directory if not already a git repo
if [ ! -d "data/.git" ]; then
    echo -e "${BLUE}Initializing git repository in data directory...${NC}"
    cd data
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -m "Initial commit: schemas and filters" || true
    cd ..
    echo -e "${GREEN}✓ Git repository initialized${NC}"
else
    echo -e "${GREEN}✓ Git repository already exists${NC}"
    # Make sure all files are committed
    cd data
    git add -A 2>/dev/null || true
    git commit -m "Update schemas and filters" 2>/dev/null || true
    cd ..
fi

# Get absolute path for docker-compose
DATA_ABS_PATH=$(cd "$PROJECT_ROOT/data" && pwd)
echo ""
echo -e "${BLUE}Data directory: ${DATA_ABS_PATH}${NC}"
echo -e "${YELLOW}Note: For docker-compose, use file://${DATA_ABS_PATH} as GIT_REPOSITORY${NC}"
echo ""

echo -e "${CYAN}========================================${NC}"
echo -e "${GREEN}✓ Local test environment ready${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Start services:"
echo "   GIT_REPOSITORY=file://${DATA_ABS_PATH} docker-compose --profile metadata-service up -d"
echo "2. Wait for service to be healthy (check logs: docker-compose logs metadata-service)"
echo "3. Run tests: ./scripts/test-filter-api.sh"
