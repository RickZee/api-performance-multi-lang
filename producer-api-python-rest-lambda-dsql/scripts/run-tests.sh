#!/bin/bash
# Run test suite for Producer API Python REST Lambda DSQL

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Running Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

cd "$PROJECT_ROOT"

# Check if pytest is installed
if ! python3 -m pytest --version &> /dev/null; then
    echo -e "${YELLOW}⚠ pytest not found, installing dependencies...${NC}"
    pip install -r requirements.txt
fi

# Run tests
echo -e "${BLUE}Running all tests...${NC}"
echo ""

if [ "$1" == "--unit" ]; then
    echo -e "${BLUE}Running unit tests only...${NC}"
    python3 -m pytest tests/unit/ -v
elif [ "$1" == "--integration" ]; then
    echo -e "${BLUE}Running integration tests only...${NC}"
    python3 -m pytest tests/integration/ -v
elif [ "$1" == "--coverage" ]; then
    echo -e "${BLUE}Running tests with coverage...${NC}"
    python3 -m pytest --cov=. --cov-report=term-missing --cov-report=html
    echo ""
    echo -e "${GREEN}Coverage report generated in htmlcov/index.html${NC}"
else
    python3 -m pytest tests/ -v
fi

echo ""
echo -e "${GREEN}✓ Tests completed${NC}"
