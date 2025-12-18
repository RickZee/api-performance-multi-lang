#!/bin/bash
# Run k6 batch test for both PostgreSQL and DSQL databases
# Usage: ./scripts/run-k6-both-databases.sh [EVENTS_PER_TYPE] [VUS] [PG_API_URL] [DSQL_API_URL]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
EVENTS_PER_TYPE=${1:-1000}
VUS=${2:-10}
PG_API_URL=${3:-""}
DSQL_API_URL=${4:-""}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}k6 Batch Test for Both Databases${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Configuration:"
echo "  Events per Type: $EVENTS_PER_TYPE"
echo "  Virtual Users (VUs): $VUS"
echo "  Total Events per Database: $((EVENTS_PER_TYPE * 4))"
echo ""

# Determine API URLs if not provided
if [ -z "$PG_API_URL" ]; then
    PG_API_URL="https://kkwz7ho2gg.execute-api.us-east-1.amazonaws.com"
fi

if [ -z "$DSQL_API_URL" ]; then
    DSQL_API_URL="https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com"
fi

echo "PostgreSQL API URL: $PG_API_URL"
echo "DSQL API URL: $DSQL_API_URL"
echo ""

# Run PostgreSQL test
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Testing PostgreSQL Database${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

cd "$PROJECT_ROOT"
bash "$SCRIPT_DIR/run-k6-and-validate.sh" pg "$EVENTS_PER_TYPE" "$VUS" "$PG_API_URL"

PG_RESULT=$?

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Testing DSQL Database${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Run DSQL test
bash "$SCRIPT_DIR/run-k6-and-validate.sh" dsql "$EVENTS_PER_TYPE" "$VUS" "$DSQL_API_URL"

DSQL_RESULT=$?

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ $PG_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ PostgreSQL test completed successfully${NC}"
else
    echo -e "${RED}❌ PostgreSQL test failed${NC}"
fi

if [ $DSQL_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ DSQL test completed successfully${NC}"
else
    echo -e "${RED}❌ DSQL test failed${NC}"
fi

echo ""

# Exit with error if either test failed
if [ $PG_RESULT -ne 0 ] || [ $DSQL_RESULT -ne 0 ]; then
    exit 1
fi

exit 0
