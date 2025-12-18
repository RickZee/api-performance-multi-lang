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

# Helper Functions
format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    local result=""
    [ $hours -gt 0 ] && result="${hours}h "
    [ $minutes -gt 0 ] && result="${result}${minutes}m "
    [ $secs -gt 0 ] && result="${result}${secs}s"
    echo "${result:-0s}"
}

log_with_timestamp() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] $message"
}

log_progress() {
    local message="$1"
    local color="${2:-$BLUE}"
    log_with_timestamp "$(echo -e "${color}${message}${NC}")"
}

# Configuration
DB_TYPE=${1:-pg}
EVENTS_PER_TYPE=${2:-10}
VUS=${3:-1}
API_URL=${4:-""}
EVENTS_FILE="/tmp/k6-sent-events-$(date +%s).json"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}k6 Batch Test with Validation${NC}"
echo -e "${BLUE}========================================${NC}"

# Clear database if requested (default: true)
if [ "${CLEAR_DATABASE:-true}" = "true" ]; then
    if [ -f "$SCRIPT_DIR/clear-both-databases.sh" ]; then
        log_progress "Clearing database before test..." "$BLUE"
        # The clear-both-databases.sh script clears both databases
        # We'll let it run and it will handle errors gracefully
        bash "$SCRIPT_DIR/clear-both-databases.sh" 2>&1 | grep -E "(Clearing|cleared|✅|❌|⚠️)" | head -30 || {
            log_progress "Database clear had issues, continuing anyway..." "$YELLOW"
        }
        log_progress "Database clear complete" "$GREEN"
    else
        log_progress "Skipping database clear (clear-both-databases.sh not found)" "$YELLOW"
    fi
fi

# Pre-warm Lambdas if requested
if [ "${PRE_WARM_LAMBDAS:-true}" = "true" ]; then
    if [ -f "$SCRIPT_DIR/pre-warm-lambdas.sh" ]; then
        log_progress "Pre-warming Lambda functions..." "$BLUE"
        bash "$SCRIPT_DIR/pre-warm-lambdas.sh" 3 > /dev/null 2>&1 || true
        log_progress "Pre-warming complete" "$GREEN"
    else
        log_progress "Skipping Lambda pre-warming (pre-warm-lambdas.sh not found)" "$YELLOW"
    fi
fi
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

# Record script start time
SCRIPT_START_TIME=$(date +%s)

# Run k6 test and extract events
log_progress "Starting k6 batch test..." "$BLUE"
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

# Record k6 start time
K6_START_TIME=$(date +%s)
log_progress "k6 test execution started..." "$BLUE"

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
    send-batch-events.js 2>&1 | tee "$TEMP_OUTPUT" | "$SCRIPT_DIR/extract-events-from-k6-output.py" "$EVENTS_FILE" 2>&1 | grep -v "^K6_EVENT:" | tail -100

# Record k6 end time
K6_END_TIME=$(date +%s)
TEST_DURATION=$((K6_END_TIME - K6_START_TIME))
log_progress "k6 test execution completed (duration: $(format_duration $TEST_DURATION))" "$GREEN"

# Extract all events from saved output (this is the primary source)
EXTRACTION_START_TIME=$(date +%s)
log_progress "Extracting events from k6 output..." "$BLUE"
EXTRACTION_OUTPUT=$(python3 "$SCRIPT_DIR/extract-events-from-k6-output.py" "$EVENTS_FILE" --input-file "$TEMP_OUTPUT" 2>&1)
echo "$EXTRACTION_OUTPUT" | grep -E "(Extracted|events|⚠️)" || true
rm -f "$TEMP_OUTPUT"

EXTRACTION_END_TIME=$(date +%s)
EXTRACTION_DURATION=$((EXTRACTION_END_TIME - EXTRACTION_START_TIME))

if [ ! -f "$EVENTS_FILE" ]; then
    echo -e "${RED}Error: Events file not created: $EVENTS_FILE${NC}"
    exit 1
fi

EVENT_COUNT=$(python3 -c "import json; f=open('$EVENTS_FILE'); data=json.load(f); print(len(data))" 2>/dev/null || echo "0")
EXPECTED_COUNT=$((EVENTS_PER_TYPE * 4))
log_progress "Event extraction completed: $EVENT_COUNT events extracted (duration: $(format_duration $EXTRACTION_DURATION))" "$GREEN"

# Count events by status if available
STATUS_BREAKDOWN=$(python3 -c "
import json
try:
    with open('$EVENTS_FILE') as f:
        events = json.load(f)
    status_counts = {}
    for e in events:
        status = e.get('status', 'unknown')
        status_counts[status] = status_counts.get(status, 0) + 1
    if status_counts:
        print(' | '.join([f'{k}:{v}' for k, v in sorted(status_counts.items())]))
except:
    pass
" 2>/dev/null || echo "")

echo ""
if [ "$EVENT_COUNT" -gt 0 ]; then
    if [ "$EVENT_COUNT" -lt "$EXPECTED_COUNT" ]; then
        echo -e "${YELLOW}⚠️  k6 test completed. Extracted $EVENT_COUNT/$EXPECTED_COUNT successful events to: $EVENTS_FILE${NC}"
        if [ -n "$STATUS_BREAKDOWN" ]; then
            echo -e "${YELLOW}   Status breakdown: $STATUS_BREAKDOWN${NC}"
        fi
        echo -e "${YELLOW}   Some events may have failed (409 conflicts, timeouts, etc.) or were not logged.${NC}"
        echo -e "${YELLOW}   Check k6 output for error details.${NC}"
    else
        echo -e "${GREEN}✅ k6 test completed. Saved $EVENT_COUNT events to: $EVENTS_FILE${NC}"
        if [ -n "$STATUS_BREAKDOWN" ]; then
            echo -e "${BLUE}   Status breakdown: $STATUS_BREAKDOWN${NC}"
        fi
    fi
else
    echo -e "${RED}❌ k6 test completed but no successful events were extracted.${NC}"
    echo -e "${RED}   All events may have failed (409 conflicts, timeouts, etc.). Check k6 output.${NC}"
    exit 1
fi
echo ""

# Wait a bit for database propagation before validation
WAIT_START_TIME=$(date +%s)
log_progress "Waiting 2 seconds for database propagation..." "$BLUE"
sleep 2
WAIT_DURATION=2
WAIT_END_TIME=$(date +%s)

# Validate databases
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Validating Databases${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Record validation start time
VALIDATION_START=$(date +%s)
log_progress "Starting database validation..." "$BLUE"

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

# Validate only the target database (no CDC between DSQL and PostgreSQL)
if [ "$DB_TYPE" = "pg" ]; then
    # Validate Aurora PostgreSQL (target database for PG API)
    if [ -f "$PROJECT_ROOT/scripts/validate-against-sent-events.py" ]; then
        if [ -n "$AURORA_ENDPOINT" ] && [ -n "$AURORA_PASSWORD" ]; then
            echo -e "${BLUE}Validating Aurora PostgreSQL...${NC}"
            export AURORA_ENDPOINT
            export AURORA_PASSWORD
            python3 "$PROJECT_ROOT/scripts/validate-against-sent-events.py" \
                --events-file "$EVENTS_FILE" \
                --aurora \
                --aurora-endpoint "$AURORA_ENDPOINT" \
                --aurora-password "$AURORA_PASSWORD" || {
                echo -e "${YELLOW}⚠️  Aurora validation had issues${NC}"
            }
        else
            echo -e "${YELLOW}⚠️  Skipping Aurora validation (endpoint/password not found)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Skipping Aurora validation (validate-against-sent-events.py not found)${NC}"
    fi
elif [ "$DB_TYPE" = "dsql" ]; then
    # Validate DSQL (target database for DSQL API)
    # First, check if bastion host is running (required for query-dsql.sh)
    if [ -f "scripts/query-dsql.sh" ]; then
        log_progress "Checking bastion host status..." "$BLUE"
        
        # Get bastion instance ID from Terraform
        BASTION_INSTANCE_ID=$(cd terraform && terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
        AWS_REGION=$(cd terraform && terraform output -raw aws_region 2>/dev/null || aws configure get region 2>/dev/null || echo "us-east-1")
        
        if [ -n "$BASTION_INSTANCE_ID" ]; then
            # Check bastion host status
            BASTION_STATUS=$(aws ec2 describe-instances \
                --instance-ids "$BASTION_INSTANCE_ID" \
                --region "$AWS_REGION" \
                --query 'Reservations[0].Instances[0].State.Name' \
                --output text 2>/dev/null || echo "not-found")
            
            if [ "$BASTION_STATUS" = "stopped" ]; then
                log_progress "Bastion host is stopped. Starting it..." "$YELLOW"
                aws ec2 start-instances \
                    --instance-ids "$BASTION_INSTANCE_ID" \
                    --region "$AWS_REGION" \
                    > /dev/null
                
                log_progress "Waiting for bastion host to become running..." "$BLUE"
                max_wait=300  # 5 minutes
                elapsed=0
                
                while [ $elapsed -lt $max_wait ]; do
                    BASTION_STATUS=$(aws ec2 describe-instances \
                        --instance-ids "$BASTION_INSTANCE_ID" \
                        --region "$AWS_REGION" \
                        --query 'Reservations[0].Instances[0].State.Name' \
                        --output text 2>/dev/null || echo "not-found")
                    
                    if [ "$BASTION_STATUS" = "running" ]; then
                        log_progress "Bastion host is now running. Waiting for SSM to be ready..." "$BLUE"
                        # Wait a bit more for SSM agent to be ready
                        sleep 10
                        log_progress "Bastion host is ready" "$GREEN"
                        break
                    fi
                    
                    sleep 5
                    elapsed=$((elapsed + 5))
                done
                
                if [ "$BASTION_STATUS" != "running" ]; then
                    log_progress "Bastion host did not become running within $max_wait seconds" "$RED"
                    echo -e "${YELLOW}⚠️  DSQL validation may fail. Bastion host status: $BASTION_STATUS${NC}"
                fi
            elif [ "$BASTION_STATUS" = "running" ]; then
                log_progress "Bastion host is already running" "$GREEN"
            elif [ "$BASTION_STATUS" = "not-found" ]; then
                log_progress "Bastion host not found. DSQL validation may fail." "$YELLOW"
            else
                log_progress "Bastion host is in state: $BASTION_STATUS. DSQL validation may fail." "$YELLOW"
            fi
        else
            log_progress "Bastion host instance ID not found. DSQL validation may fail." "$YELLOW"
        fi
        
        echo ""
        echo -e "${BLUE}Validating DSQL...${NC}"
        if [ -f "$PROJECT_ROOT/scripts/validate-against-sent-events.py" ]; then
            # Get DSQL connection parameters from terraform
            DSQL_HOST=$(cd terraform && terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
            # IAM username is a variable, not an output - read from terraform.tfvars
            # Remove comments and extract value
            IAM_USERNAME=$(cd terraform && grep -E "^iam_database_user\s*=" terraform.tfvars 2>/dev/null | head -1 | sed 's/#.*$//' | cut -d'"' -f2 | tr -d ' ' || echo "")
            AWS_REGION=$(cd terraform && terraform output -raw aws_region 2>/dev/null || aws configure get region 2>/dev/null || echo "us-east-1")
            DSQL_PORT=$(cd terraform && terraform output -raw aurora_dsql_port 2>/dev/null || echo "5432")
            
            # Use new direct connection method (no bastion/SSM required)
            if [ -n "$DSQL_HOST" ] && [ -n "$IAM_USERNAME" ] && [ -n "$AWS_REGION" ]; then
                python3 "$PROJECT_ROOT/scripts/validate-against-sent-events.py" \
                    --events-file "$EVENTS_FILE" \
                    --dsql \
                    --dsql-host "$DSQL_HOST" \
                    --iam-username "$IAM_USERNAME" \
                    --aws-region "$AWS_REGION" \
                    --dsql-port "$DSQL_PORT" || {
                    echo -e "${YELLOW}⚠️  DSQL validation had issues${NC}"
                }
            else
                echo -e "${YELLOW}⚠️  Skipping DSQL validation (connection parameters not found in terraform)${NC}"
                echo -e "${YELLOW}   DSQL_HOST: ${DSQL_HOST:-not found}${NC}"
                echo -e "${YELLOW}   IAM_USERNAME: ${IAM_USERNAME:-not found}${NC}"
                echo -e "${YELLOW}   AWS_REGION: ${AWS_REGION:-not found}${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  Skipping DSQL validation (validate-against-sent-events.py not found)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Skipping DSQL validation (query-dsql.sh not found)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Unknown DB_TYPE: $DB_TYPE, skipping validation${NC}"
fi

VALIDATION_END=$(date +%s)
VALIDATION_DURATION=$((VALIDATION_END - VALIDATION_START))
log_progress "Validation completed (duration: $(format_duration $VALIDATION_DURATION))" "$GREEN"

# Record script end time
SCRIPT_END_TIME=$(date +%s)
TOTAL_DURATION=$((SCRIPT_END_TIME - SCRIPT_START_TIME))

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Validation Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Time Metrics:${NC}"
echo "  k6 Test Duration: $(format_duration $TEST_DURATION)"
echo "  Event Extraction Duration: $(format_duration $EXTRACTION_DURATION)"
echo "  Database Propagation Wait: $(format_duration $WAIT_DURATION)"
echo "  Validation Duration: $(format_duration $VALIDATION_DURATION)"
echo "  Total Duration: $(format_duration $TOTAL_DURATION)"
echo ""
if [ $TOTAL_DURATION -gt 0 ]; then
    echo -e "${BLUE}Time Breakdown (percentage):${NC}"
    K6_PERCENT=$(echo "scale=1; $TEST_DURATION * 100 / $TOTAL_DURATION" | bc 2>/dev/null || echo "0")
    EXTRACTION_PERCENT=$(echo "scale=1; $EXTRACTION_DURATION * 100 / $TOTAL_DURATION" | bc 2>/dev/null || echo "0")
    WAIT_PERCENT=$(echo "scale=1; $WAIT_DURATION * 100 / $TOTAL_DURATION" | bc 2>/dev/null || echo "0")
    VALIDATION_PERCENT=$(echo "scale=1; $VALIDATION_DURATION * 100 / $TOTAL_DURATION" | bc 2>/dev/null || echo "0")
    echo "  k6 Test: ${K6_PERCENT}%"
    echo "  Event Extraction: ${EXTRACTION_PERCENT}%"
    echo "  Database Propagation Wait: ${WAIT_PERCENT}%"
    echo "  Validation: ${VALIDATION_PERCENT}%"
    echo ""
fi
if [ $TEST_DURATION -gt 0 ]; then
    EVENTS_PER_SECOND=$(echo "scale=2; $TOTAL_EVENTS / $TEST_DURATION" | bc 2>/dev/null || echo "N/A")
    echo -e "${BLUE}Throughput:${NC}"
    echo "  Events per Second: $EVENTS_PER_SECOND"
fi
echo ""
echo "Events file saved at: $EVENTS_FILE"
echo "You can re-validate using:"
echo "  python3 scripts/validate-against-sent-events.py --events-file $EVENTS_FILE --aurora --dsql"
