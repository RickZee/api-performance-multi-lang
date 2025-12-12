#!/bin/bash
# Delete Failed and Completed Flink Statements
# Removes Flink SQL statements that are in FAILED or COMPLETED state

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

COMPUTE_POOL_ID="${FLINK_COMPUTE_POOL_ID:-lfcp-2xqo0m}"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Delete Failed and Completed Flink Statements${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "Compute Pool: $COMPUTE_POOL_ID"
echo ""

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗ jq is required but not installed${NC}"
    echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

# List all statements and filter for FAILED or COMPLETED
echo -e "${BLUE}Fetching Flink statements...${NC}"
STATEMENTS_JSON=$(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null || echo "[]")

if [ -z "$STATEMENTS_JSON" ] || [ "$STATEMENTS_JSON" = "[]" ]; then
    echo -e "${YELLOW}⚠ No Flink statements found${NC}"
    exit 0
fi

# Extract statements with FAILED or COMPLETED status
FAILED_STATEMENTS=$(echo "$STATEMENTS_JSON" | jq -r '.[] | select(.status == "FAILED" or .status == "COMPLETED") | "\(.name)|\(.status)"' || echo "")

if [ -z "$FAILED_STATEMENTS" ]; then
    echo -e "${GREEN}✓ No failed or completed statements found${NC}"
    echo ""
    echo "All statements:"
    echo "$STATEMENTS_JSON" | jq -r '.[] | "  \(.name): \(.status)"'
    exit 0
fi

# Count statements to delete
COUNT=$(echo "$FAILED_STATEMENTS" | wc -l | tr -d ' ')
echo -e "${YELLOW}Found $COUNT statement(s) to delete:${NC}"
echo ""

# Display statements to be deleted
echo "$FAILED_STATEMENTS" | while IFS='|' read -r name status; do
    if [ "$status" = "FAILED" ]; then
        echo -e "  ${RED}✗ $name${NC} (FAILED)"
    elif [ "$status" = "COMPLETED" ]; then
        echo -e "  ${YELLOW}○ $name${NC} (COMPLETED)"
    fi
done

echo ""
read -p "Delete these statements? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Delete statements
echo ""
echo -e "${BLUE}Deleting statements...${NC}"

while IFS='|' read -r name status; do
    if [ -n "$name" ]; then
        echo -n "  Deleting $name... "
        if confluent flink statement delete "$name" --force 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
        fi
        sleep 1
    fi
done <<< "$FAILED_STATEMENTS"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deletion Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Show remaining statements
echo -e "${BLUE}Remaining statements:${NC}"
REMAINING_JSON=$(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null || echo "[]")
if [ -n "$REMAINING_JSON" ] && [ "$REMAINING_JSON" != "[]" ]; then
    echo "$REMAINING_JSON" | jq -r '.[] | "  \(.name): \(.status)"'
else
    echo "  (none)"
fi
echo ""


