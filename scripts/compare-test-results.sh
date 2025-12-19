#!/bin/bash
# Compare PostgreSQL and DSQL test results from log file
# Usage: ./scripts/compare-test-results.sh [LOG_FILE]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE=${1:-/tmp/k6-comparison-test.log}

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ ! -f "$LOG_FILE" ]; then
    echo -e "${RED}Error: Log file not found: $LOG_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Results Comparison${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Extract PostgreSQL results
echo -e "${CYAN}Extracting PostgreSQL Results...${NC}"
PG_SECTION=$(awk '/Testing PostgreSQL Database/,/Testing DSQL Database/' "$LOG_FILE" | head -n -1)

# Extract DSQL results  
echo -e "${CYAN}Extracting DSQL Results...${NC}"
DSQL_SECTION=$(awk '/Testing DSQL Database/,/Test Summary/' "$LOG_FILE" | head -n -1)

# Function to extract metrics
extract_metric() {
    local section="$1"
    local pattern="$2"
    echo "$section" | grep -E "$pattern" | tail -1 | sed -E 's/.*: *([0-9.]+).*/\1/' || echo "N/A"
}

# Extract PostgreSQL metrics
PG_TOTAL_EVENTS=$(echo "$PG_SECTION" | grep -E "Total Events:" | tail -1 | grep -oE "[0-9]+" | head -1 || echo "N/A")
PG_DURATION=$(echo "$PG_SECTION" | grep -E "Test Duration:|duration:" | tail -1 | grep -oE "[0-9]+\.[0-9]+s" | head -1 || echo "N/A")
PG_AVG_RESPONSE=$(echo "$PG_SECTION" | grep -E "Avg:" | grep -E "response|Response" | tail -1 | grep -oE "[0-9]+\.[0-9]+ms" | head -1 || echo "N/A")
PG_P95_RESPONSE=$(echo "$PG_SECTION" | grep -E "P95:" | tail -1 | grep -oE "[0-9]+\.[0-9]+ms" | head -1 || echo "N/A")
PG_ERROR_RATE=$(echo "$PG_SECTION" | grep -E "Error Rate:" | tail -1 | grep -oE "[0-9]+\.[0-9]+%" || echo "0.00%")
PG_EVENTS_FOUND=$(echo "$PG_SECTION" | grep -E "Events Found:" | tail -1 | grep -oE "[0-9]+" | head -1 || echo "N/A")
PG_SUCCESS_RATE=$(echo "$PG_SECTION" | grep -E "Success Rate:" | tail -1 | grep -oE "[0-9]+\.[0-9]+%" || echo "N/A")

# Extract DSQL metrics
DSQL_TOTAL_EVENTS=$(echo "$DSQL_SECTION" | grep -E "Total Events:" | tail -1 | grep -oE "[0-9]+" | head -1 || echo "N/A")
DSQL_DURATION=$(echo "$DSQL_SECTION" | grep -E "Test Duration:|duration:" | tail -1 | grep -oE "[0-9]+\.[0-9]+s" | head -1 || echo "N/A")
DSQL_AVG_RESPONSE=$(echo "$DSQL_SECTION" | grep -E "Avg:" | grep -E "response|Response" | tail -1 | grep -oE "[0-9]+\.[0-9]+ms" | head -1 || echo "N/A")
DSQL_P95_RESPONSE=$(echo "$DSQL_SECTION" | grep -E "P95:" | tail -1 | grep -oE "[0-9]+\.[0-9]+ms" | head -1 || echo "N/A")
DSQL_ERROR_RATE=$(echo "$DSQL_SECTION" | grep -E "Error Rate:" | tail -1 | grep -oE "[0-9]+\.[0-9]+%" || echo "0.00%")
DSQL_EVENTS_FOUND=$(echo "$DSQL_SECTION" | grep -E "Events Found:" | tail -1 | grep -oE "[0-9]+" | head -1 || echo "N/A")
DSQL_SUCCESS_RATE=$(echo "$DSQL_SECTION" | grep -E "Success Rate:" | tail -1 | grep -oE "[0-9]+\.[0-9]+%" || echo "N/A")

# Print comparison table
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Performance Comparison${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
printf "%-30s %-20s %-20s %-15s\n" "Metric" "PostgreSQL" "DSQL" "Winner"
echo "------------------------------------------------------------------------------------------------"
printf "%-30s %-20s %-20s %-15s\n" "Total Events" "$PG_TOTAL_EVENTS" "$DSQL_TOTAL_EVENTS" "-"
printf "%-30s %-20s %-20s %-15s\n" "Test Duration" "$PG_DURATION" "$DSQL_DURATION" "$(if [ "$PG_DURATION" != "N/A" ] && [ "$DSQL_DURATION" != "N/A" ]; then echo "$PG_DURATION" | sed 's/s//' | awk -v dsql="$DSQL_DURATION" '{if ($1 < dsql) print "PG"; else print "DSQL"}'; else echo "-"; fi)"
printf "%-30s %-20s %-20s %-15s\n" "Avg Response Time" "$PG_AVG_RESPONSE" "$DSQL_AVG_RESPONSE" "$(if [ "$PG_AVG_RESPONSE" != "N/A" ] && [ "$DSQL_AVG_RESPONSE" != "N/A" ]; then echo "$PG_AVG_RESPONSE" | sed 's/ms//' | awk -v dsql="$DSQL_AVG_RESPONSE" '{if ($1 < dsql) print "PG"; else print "DSQL"}'; else echo "-"; fi)"
printf "%-30s %-20s %-20s %-15s\n" "P95 Response Time" "$PG_P95_RESPONSE" "$DSQL_P95_RESPONSE" "$(if [ "$PG_P95_RESPONSE" != "N/A" ] && [ "$DSQL_P95_RESPONSE" != "N/A" ]; then echo "$PG_P95_RESPONSE" | sed 's/ms//' | awk -v dsql="$DSQL_P95_RESPONSE" '{if ($1 < dsql) print "PG"; else print "DSQL"}'; else echo "-"; fi)"
printf "%-30s %-20s %-20s %-15s\n" "Error Rate" "$PG_ERROR_RATE" "$DSQL_ERROR_RATE" "$(if [ "$PG_ERROR_RATE" = "0.00%" ] && [ "$DSQL_ERROR_RATE" = "0.00%" ]; then echo "Tie"; elif [ "$PG_ERROR_RATE" = "0.00%" ]; then echo "PG"; else echo "DSQL"; fi)"
printf "%-30s %-20s %-20s %-15s\n" "Events Found" "$PG_EVENTS_FOUND" "$DSQL_EVENTS_FOUND" "-"
printf "%-30s %-20s %-20s %-15s\n" "Success Rate" "$PG_SUCCESS_RATE" "$DSQL_SUCCESS_RATE" "-"
echo ""

# Calculate throughput if possible
if [ "$PG_DURATION" != "N/A" ] && [ "$DSQL_DURATION" != "N/A" ] && [ "$PG_TOTAL_EVENTS" != "N/A" ] && [ "$DSQL_TOTAL_EVENTS" != "N/A" ]; then
    PG_DURATION_SEC=$(echo "$PG_DURATION" | sed 's/s//')
    DSQL_DURATION_SEC=$(echo "$DSQL_DURATION" | sed 's/s//')
    PG_THROUGHPUT=$(echo "scale=2; $PG_TOTAL_EVENTS / $PG_DURATION_SEC" | bc)
    DSQL_THROUGHPUT=$(echo "scale=2; $DSQL_TOTAL_EVENTS / $DSQL_DURATION_SEC" | bc)
    echo -e "${BLUE}Throughput (events/second):${NC}"
    echo "  PostgreSQL: $PG_THROUGHPUT events/sec"
    echo "  DSQL: $DSQL_THROUGHPUT events/sec"
    echo ""
fi

# Show detailed sections
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PostgreSQL Detailed Results${NC}"
echo -e "${BLUE}========================================${NC}"
echo "$PG_SECTION" | grep -A 20 "k6 Batch Events Test Summary" | head -30
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}DSQL Detailed Results${NC}"
echo -e "${BLUE}========================================${NC}"
echo "$DSQL_SECTION" | grep -A 20 "k6 Batch Events Test Summary" | head -30
echo ""

echo -e "${GREEN}✅ Comparison complete!${NC}"

