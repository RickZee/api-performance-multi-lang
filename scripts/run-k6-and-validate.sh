#!/bin/bash
# Run k6 batch test and validate databases against sent events
# Usage: ./scripts/run-k6-and-validate.sh [DB_TYPE] [EVENTS_PER_TYPE] [API_URL]

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
DB_TYPE=${1:-pg}
EVENTS_PER_TYPE=${2:-10}
VUS=${3:-1}
API_URL=${4:-""}
EVENTS_FILE="/tmp/k6-sent-events-$(date +%s).json"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}k6 Batch Test with Validation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Database Type: $DB_TYPE"
echo "Events per Type: $EVENTS_PER_TYPE"
echo "Virtual Users (VUs): $VUS"
echo "Total Events: $((EVENTS_PER_TYPE * 4))"
echo "Events File: $EVENTS_FILE"
echo ""

# Determine API URL
if [ -z "$API_URL" ]; then
    if [ "$DB_TYPE" = "pg" ]; then
        API_URL="https://kkwz7ho2gg.execute-api.us-east-1.amazonaws.com"
    elif [ "$DB_TYPE" = "dsql" ]; then
        API_URL="https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com"
    else
        echo -e "${RED}Error: Unknown DB_TYPE: $DB_TYPE${NC}"
        exit 1
    fi
fi

echo "API URL: $API_URL"
echo ""

# Run k6 test and extract events
echo -e "${BLUE}Running k6 batch test...${NC}"
cd "$PROJECT_ROOT/load-test/k6"

# Calculate iterations: using per-vu-iterations executor
# Each VU processes EVENTS_PER_TYPE * NUM_EVENT_TYPES / VUS iterations
# Total events = EVENTS_PER_TYPE * NUM_EVENT_TYPES (e.g., 50 * 4 = 200)
TOTAL_EVENTS=$((EVENTS_PER_TYPE * 4))
ITERATIONS_PER_VU=$(( (EVENTS_PER_TYPE * 4 + VUS - 1) / VUS ))  # Ceiling division
# With per-vu-iterations, each VU runs ITERATIONS_PER_VU iterations
# Total iterations across all VUs = ITERATIONS_PER_VU * VUS

echo "Test Configuration:"
echo "  Total Events Expected: $TOTAL_EVENTS"
echo "  VUs: $VUS"
echo "  Iterations per VU: $ITERATIONS_PER_VU"
echo "  Total Iterations (across all VUs): $((ITERATIONS_PER_VU * VUS))"
echo ""

# Record start time
START_TIME=$(date +%s)

# Run k6 and extract events from output
# With scenario-based per-vu-iterations, we don't pass --iterations or --vus
# The script's export const options handles the configuration
TEMP_OUTPUT="/tmp/k6-output-$$.log"
k6 run \
    --env DB_TYPE=$DB_TYPE \
    --env EVENTS_PER_TYPE=$EVENTS_PER_TYPE \
    --env TOTAL_VUS=$VUS \
    --env EVENTS_FILE="$EVENTS_FILE" \
    --env API_URL="$API_URL" \
    send-batch-events.js 2>&1 | tee "$TEMP_OUTPUT" | "$SCRIPT_DIR/extract-events-from-k6-output.py" "$EVENTS_FILE" 2>&1 | tail -50

# Record end time
END_TIME=$(date +%s)
TEST_DURATION=$((END_TIME - START_TIME))

# Also try extracting from saved output
python3 "$SCRIPT_DIR/extract-events-from-k6-output.py" "$EVENTS_FILE" --input-file "$TEMP_OUTPUT" 2>&1 | grep -E "(Extracted|events)" || true
rm -f "$TEMP_OUTPUT"

echo ""
echo -e "${BLUE}Test Duration: ${TEST_DURATION}s${NC}"

if [ ! -f "$EVENTS_FILE" ]; then
    echo -e "${RED}Error: Events file not created: $EVENTS_FILE${NC}"
    exit 1
fi

EVENT_COUNT=$(python3 -c "import json; f=open('$EVENTS_FILE'); data=json.load(f); print(len(data))" 2>/dev/null || echo "0")
echo ""
if [ "$EVENT_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ k6 test completed. Saved $EVENT_COUNT events to: $EVENTS_FILE${NC}"
else
    echo -e "${YELLOW}⚠️  k6 test completed but no events were extracted. Check k6 output.${NC}"
fi
echo ""

# Validate databases
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Validating Databases${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Record validation start time
VALIDATION_START=$(date +%s)

cd "$PROJECT_ROOT"

# Get Aurora credentials from terraform
AURORA_ENDPOINT=""
AURORA_PASSWORD=""
if [ -f "terraform/terraform.tfvars" ]; then
    AURORA_ENDPOINT=$(cd terraform && terraform output -raw aurora_endpoint 2>/dev/null || echo "")
    # Extract password and clean it (remove newlines, take first 32 chars)
    RAW_PASSWORD=$(grep database_password terraform/terraform.tfvars | cut -d'"' -f2 || echo "")
    AURORA_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\n\r' | head -c 32)
fi

# Validate Aurora
if [ -n "$AURORA_ENDPOINT" ] && [ -n "$AURORA_PASSWORD" ]; then
    echo -e "${BLUE}Validating Aurora PostgreSQL...${NC}"
    export AURORA_ENDPOINT
    export AURORA_PASSWORD
    python3 scripts/validate-against-sent-events.py \
        --events-file "$EVENTS_FILE" \
        --aurora \
        --aurora-endpoint "$AURORA_ENDPOINT" \
        --aurora-password "$AURORA_PASSWORD" || {
        echo -e "${YELLOW}⚠️  Aurora validation had issues${NC}"
    }
else
    echo -e "${YELLOW}⚠️  Skipping Aurora validation (endpoint/password not found)${NC}"
fi

echo ""

# Validate DSQL
if [ -f "scripts/query-dsql.sh" ]; then
    echo -e "${BLUE}Validating DSQL...${NC}"
    python3 scripts/validate-against-sent-events.py \
        --events-file "$EVENTS_FILE" \
        --dsql \
        --query-dsql-script scripts/query-dsql.sh || {
        echo -e "${YELLOW}⚠️  DSQL validation had issues${NC}"
    }
else
    echo -e "${YELLOW}⚠️  Skipping DSQL validation (query-dsql.sh not found)${NC}"
fi

VALIDATION_END=$(date +%s)
VALIDATION_DURATION=$((VALIDATION_END - VALIDATION_START))

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Validation Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Time Metrics:${NC}"
echo "  k6 Test Duration: ${TEST_DURATION}s"
echo "  Validation Duration: ${VALIDATION_DURATION}s"
echo "  Total Duration: $((TEST_DURATION + VALIDATION_DURATION))s"
if [ $TEST_DURATION -gt 0 ]; then
    EVENTS_PER_SECOND=$(echo "scale=2; $TOTAL_EVENTS / $TEST_DURATION" | bc 2>/dev/null || echo "N/A")
    echo "  Events per Second: $EVENTS_PER_SECOND"
fi
echo ""
echo "Events file saved at: $EVENTS_FILE"
echo "You can re-validate using:"
echo "  python3 scripts/validate-against-sent-events.py --events-file $EVENTS_FILE --aurora --dsql"
