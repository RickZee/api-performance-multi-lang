#!/bin/bash
# Cleanup Flink Statements - Remove COMPLETED and FAILED statements

set -e

COMPUTE_POOL_ID="${FLINK_COMPUTE_POOL_ID:-lfcp-2xqo0m}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Cleanup Flink Statements${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Compute Pool: $COMPUTE_POOL_ID"
echo ""

# Get statements to delete
STATEMENTS_TO_DELETE=$(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null | \
    python3 -c "import sys, json; data = json.load(sys.stdin); to_delete = [s['name'] for s in data if s.get('status') in ['COMPLETED', 'FAILED']]; print('\n'.join(to_delete))" 2>/dev/null)

if [ -z "$STATEMENTS_TO_DELETE" ]; then
    echo -e "${GREEN}✓ No COMPLETED or FAILED statements to delete${NC}"
    exit 0
fi

echo -e "${YELLOW}Found statements to delete:${NC}"
echo "$STATEMENTS_TO_DELETE" | while read -r name; do
    if [ -n "$name" ]; then
        echo "  - $name"
    fi
done
echo ""

# Delete each statement (without --compute-pool flag)
echo "$STATEMENTS_TO_DELETE" | while read -r name; do
    if [ -n "$name" ]; then
        echo -e "${BLUE}Deleting: $name${NC}"
        if confluent flink statement delete "$name" --force 2>&1; then
            echo -e "${GREEN}✓ Deleted: $name${NC}"
        else
            echo -e "${RED}✗ Failed to delete: $name${NC}"
        fi
        sleep 1
    fi
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
