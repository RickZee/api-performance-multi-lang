#!/bin/bash
# Pre-warm Lambda functions to avoid cold starts
# This script invokes the health endpoints multiple times to warm up both Lambdas

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get API URLs from Terraform or environment
cd "$PROJECT_ROOT/terraform"
if [ ! -d ".terraform" ]; then
    terraform init > /dev/null 2>&1
fi

PG_API_URL=$(terraform output -raw python_rest_pg_api_url 2>/dev/null || echo "")
DSQL_API_URL=$(terraform output -raw python_rest_dsql_api_url 2>/dev/null || echo "")

if [ -z "$PG_API_URL" ] || [ -z "$DSQL_API_URL" ]; then
    echo -e "${YELLOW}Warning: Could not get API URLs from Terraform. Using defaults.${NC}"
    PG_API_URL=${PG_API_URL:-"https://kkwz7ho2gg.execute-api.us-east-1.amazonaws.com"}
    DSQL_API_URL=${DSQL_API_URL:-"https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com"}
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Pre-warming Lambda Functions${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "PostgreSQL API: $PG_API_URL"
echo "DSQL API: $DSQL_API_URL"
echo ""

# Number of warm-up requests per Lambda
WARMUP_COUNT=${1:-5}

echo -e "${BLUE}Warming up each Lambda with $WARMUP_COUNT requests...${NC}"
echo ""

# Function to warm up a Lambda
warmup_lambda() {
    local api_url=$1
    local api_name=$2
    local count=$3
    
    echo -e "${BLUE}Warming up $api_name...${NC}"
    local success=0
    local failed=0
    
    for i in $(seq 1 $count); do
        response=$(curl -s -w "\nHTTP_CODE:%{http_code}\nTIME:%{time_total}" \
            --max-time 30 \
            "${api_url}/api/v1/events/health" 2>&1)
        
        http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
        time_total=$(echo "$response" | grep "TIME:" | cut -d: -f2)
        
        if [ "$http_code" = "200" ]; then
            success=$((success + 1))
            echo -e "  ${GREEN}✓${NC} Request $i/$count: HTTP $http_code (${time_total}s)"
        else
            failed=$((failed + 1))
            echo -e "  ${YELLOW}⚠${NC} Request $i/$count: HTTP ${http_code:-timeout} (${time_total:-timeout}s)"
        fi
        
        # Small delay between requests
        sleep 0.5
    done
    
    echo -e "${BLUE}  $api_name: $success/$count successful${NC}"
    echo ""
}

# Warm up both Lambdas in parallel
warmup_lambda "$PG_API_URL" "PostgreSQL Lambda" "$WARMUP_COUNT" &
PG_PID=$!

warmup_lambda "$DSQL_API_URL" "DSQL Lambda" "$WARMUP_COUNT" &
DSQL_PID=$!

# Wait for both to complete
wait $PG_PID
wait $DSQL_PID

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Pre-warming Complete${NC}"
echo -e "${GREEN}========================================${NC}"
