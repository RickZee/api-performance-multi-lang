#!/usr/bin/env bash
# End-to-End Functional Test Pipeline
# Tests both Flink SQL and Spring Boot Kafka Streams filtering/routing pipelines
#
# Usage:
#   ./cdc-streaming/scripts/test-e2e-pipeline.sh [WAIT_TIME] [FLAGS]
#
# Examples:
#   ./cdc-streaming/scripts/test-e2e-pipeline.sh 90
#   ./cdc-streaming/scripts/test-e2e-pipeline.sh --fast
#   ./cdc-streaming/scripts/test-e2e-pipeline.sh --skip-to-step 5
#   ./cdc-streaming/scripts/test-e2e-pipeline.sh --fast --skip-aurora 30
#
# Note: Submits 10 events of each type (40 total) by default
#
# Flags:
#   --fast              Skip prerequisites and Docker builds (fastest iteration)
#   --skip-prereqs      Skip dependency and login checks
#   --skip-aurora       Skip Aurora cluster status check
#   --skip-build        Skip Docker image builds
#   --skip-clear-logs   Skip clearing consumer logs before validation
#   --skip-to-step N    Resume from step N (1-11)
#   --debug             Enable verbose output with timing
#
# Requirements:
#   - Terraform outputs available (Aurora endpoint, Lambda API URL, credentials)
#   - Confluent CLI installed and logged in
#   - Docker and Docker Compose
#   - jq installed

# Don't use set -e here - we want to continue even if some validations fail
# Use set -u but allow unset variables with ${VAR:-} syntax
set +e
set +u
#   - Python 3 with psycopg2 or asyncpg

# Don't set -e - we want to continue even if some validations fail
# Individual critical operations will check exit codes explicitly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Source environment files if they exist
if [ -f "$PROJECT_ROOT/.env.aurora" ]; then
    source "$PROJECT_ROOT/.env.aurora"
fi

if [ -f "$PROJECT_ROOT/cdc-streaming/.env" ]; then
    source "$PROJECT_ROOT/cdc-streaming/.env"
fi

if [ -f "$PROJECT_ROOT/cdc-streaming/.env.aurora" ]; then
    source "$PROJECT_ROOT/cdc-streaming/.env.aurora"
fi

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
section() { echo -e "${CYAN}========================================${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}========================================${NC}"; }

# Configuration flags
SKIP_PREREQUISITES=false
SKIP_AURORA_CHECK=false
SKIP_BUILD=false
SKIP_CLEAR_LOGS=false
SKIP_TO_STEP=0
DEBUG=false
FAST_MODE=false
WAIT_TIME=15

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --fast)
      FAST_MODE=true
      SKIP_PREREQUISITES=true
      SKIP_BUILD=true
      shift
      ;;
    --skip-prereqs)
      SKIP_PREREQUISITES=true
      shift
      ;;
    --skip-aurora)
      SKIP_AURORA_CHECK=true
      shift
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --skip-clear-logs)
      SKIP_CLEAR_LOGS=true
      shift
      ;;
    --skip-to-step)
      SKIP_TO_STEP="$2"
      shift 2
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    *)
      # Assume it's a numeric wait time
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        WAIT_TIME="$1"
      else
        warn "Unknown argument: $1 (assuming wait time)"
        WAIT_TIME="$1"
      fi
      shift
      ;;
  esac
done

# Step timing functions
step_start() {
  STEP_START_TIME=$(date +%s)
  [ "$DEBUG" = true ] && info "Starting step: $1"
}

step_end() {
  local elapsed=$(($(date +%s) - STEP_START_TIME))
  [ "$DEBUG" = true ] && info "Step completed in ${elapsed}s"
}

# Checkpoint support
CHECKPOINT_FILE="/tmp/e2e-test-checkpoint-$(date +%Y%m%d).json"
if [ ! -f "$CHECKPOINT_FILE" ]; then
  echo "{}" > "$CHECKPOINT_FILE"
fi

save_checkpoint() {
  local step="$1"
  jq --arg step "$step" '.last_completed_step = $step' "$CHECKPOINT_FILE" > "$CHECKPOINT_FILE.tmp" 2>/dev/null && mv "$CHECKPOINT_FILE.tmp" "$CHECKPOINT_FILE" || true
}

# Configuration
EVENTS_FILE="/tmp/e2e-test-events-$(date +%s).json"
RESULTS_FILE="/tmp/e2e-test-results-$(date +%s).json"

# Initialize results
echo "{}" > "$RESULTS_FILE"

section "E2E Functional Test Pipeline"
echo ""
echo "Testing both Flink SQL and Spring Boot Kafka Streams variants"
echo "Wait time for CDC propagation: ${WAIT_TIME}s"
[ "$FAST_MODE" = true ] && info "Fast mode enabled (skipping prereqs and builds)"
[ "$DEBUG" = true ] && info "Debug mode enabled (verbose timing output)"
echo ""

# Simplified Confluent login function
ensure_confluent_login() {
  if confluent environment list &>/dev/null; then
    pass "Confluent Cloud authenticated"
    CURRENT_ENV=$(confluent environment list --output json 2>/dev/null | jq -r '.[] | select(.is_current==true) | .name // .id' | head -1 || echo "unknown")
    if [ -n "$CURRENT_ENV" ] && [ "$CURRENT_ENV" != "unknown" ]; then
      info "Current environment: $CURRENT_ENV"
    fi
    return 0
  fi
  
  # Try API key auth first
  if [ -n "${CONFLUENT_CLOUD_API_KEY:-}" ] && [ -n "${CONFLUENT_CLOUD_API_SECRET:-}" ]; then
    info "Attempting Confluent Cloud login with API keys..."
    if confluent login --api-key "${CONFLUENT_CLOUD_API_KEY}" --api-secret "${CONFLUENT_CLOUD_API_SECRET}" &>/dev/null; then
      if confluent environment list &>/dev/null; then
        pass "Confluent Cloud authenticated via API keys"
        return 0
      fi
    fi
  fi
  
  # Fall back to interactive
  warn "Not logged in - attempting interactive login..."
  if confluent login; then
    if confluent environment list &>/dev/null; then
      pass "Confluent Cloud authenticated via interactive login"
      return 0
    fi
  fi
  
  warn "Login failed or was cancelled - Kafka validation will be skipped"
  info "To enable Kafka validation, run: confluent login"
  info "Or set: export CONFLUENT_CLOUD_API_KEY=key && export CONFLUENT_CLOUD_API_SECRET=secret"
  return 1
}

# Step 1: Check Prerequisites
if [ "$SKIP_TO_STEP" -le 1 ] && [ "$SKIP_PREREQUISITES" = false ]; then
  step_start "Prerequisites Check"
  section "Step 1: Prerequisites Check"
  echo ""

  MISSING_DEPS=0

  if ! command -v terraform &> /dev/null; then
    fail "terraform not found"
    MISSING_DEPS=1
  else
    pass "terraform found"
  fi

  if ! command -v confluent &> /dev/null; then
    fail "Confluent CLI not found"
    MISSING_DEPS=1
  else
    pass "Confluent CLI found"
  fi

  if ! command -v docker &> /dev/null; then
    fail "docker not found"
    MISSING_DEPS=1
  else
    pass "docker found"
  fi

  if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    fail "docker-compose not found"
    MISSING_DEPS=1
  else
    pass "docker-compose found"
  fi

  if ! command -v jq &> /dev/null; then
    fail "jq not found"
    MISSING_DEPS=1
  else
    pass "jq found"
  fi

  if ! command -v python3 &> /dev/null; then
    fail "python3 not found"
    MISSING_DEPS=1
  else
    pass "python3 found"
  fi

  if [ $MISSING_DEPS -eq 1 ]; then
    fail "Missing required dependencies"
    exit 1
  fi

  # Check Confluent Cloud login (optional - only needed for Kafka validation)
  ensure_confluent_login || true

  step_end
  save_checkpoint "1"
  echo ""
elif [ "$SKIP_PREREQUISITES" = true ]; then
  info "Skipping prerequisites check (--skip-prereqs flag)"
  ensure_confluent_login || true
fi

# Step 2: Start Aurora Cluster
if [ "$SKIP_TO_STEP" -le 2 ] && [ "$SKIP_AURORA_CHECK" = false ]; then
  step_start "Start Aurora Cluster"
  section "Step 2: Start Aurora Cluster"
  echo ""

  cd "$PROJECT_ROOT/terraform"
  if [ ! -f "terraform.tfstate" ]; then
    fail "Terraform state not found. Run terraform apply first"
    exit 1
  fi

  info "Checking Aurora cluster status..."
  # Get actual status from AWS
  cd "$PROJECT_ROOT/terraform"
  CLUSTER_ID=$(terraform output -raw aurora_cluster_id 2>/dev/null || echo "producer-api-aurora-cluster")
  AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

  if [ -z "$CLUSTER_ID" ]; then
    # Try to get from terraform state
    CLUSTER_ID="producer-api-aurora-cluster"
  fi

  AURORA_STATUS=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --region "$AWS_REGION" \
    --query 'DBClusters[0].Status' \
    --output text 2>/dev/null || echo "unknown")

  if [ "$AURORA_STATUS" = "available" ]; then
    pass "Aurora cluster is already running"
    jq '.aurora_started = true' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
  elif [ "$AURORA_STATUS" = "stopped" ]; then
    info "Starting Aurora cluster..."
    cd "$PROJECT_ROOT"
    if "$PROJECT_ROOT/terraform/scripts/aurora-start-stop.sh" start --wait; then
      pass "Aurora cluster started successfully"
      jq '.aurora_started = true' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
    else
      fail "Failed to start Aurora cluster"
      exit 1
    fi
  else
    # Cluster is in transitional state (backing-up, starting, etc.)
    warn "Aurora cluster is in state: $AURORA_STATUS"
    info "Waiting for cluster to become available..."
    
    max_wait=600  # 10 minutes
    elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
      AURORA_STATUS=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_ID" \
        --region "$AWS_REGION" \
        --query 'DBClusters[0].Status' \
        --output text 2>/dev/null || echo "unknown")
      
      if [ "$AURORA_STATUS" = "available" ]; then
        pass "Aurora cluster is now available"
        jq '.aurora_started = true' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
        break
      fi
      if [ $((elapsed % 30)) -eq 0 ]; then
        info "Cluster status: $AURORA_STATUS (waiting...)"
      fi
      sleep 10
      elapsed=$((elapsed + 10))
    done
    
    if [ "$AURORA_STATUS" != "available" ]; then
      fail "Aurora cluster did not become available within $max_wait seconds (current status: $AURORA_STATUS)"
      exit 1
    fi
  fi

  cd "$PROJECT_ROOT"

  # Get Aurora details (need to be in terraform directory)
  cd "$PROJECT_ROOT/terraform"
  AURORA_ENDPOINT=$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")
  DB_NAME=$(terraform output -raw database_name 2>/dev/null || echo "car_entities")
  DB_USER=$(terraform output -raw database_user 2>/dev/null || echo "postgres")
  TERRAFORM_DB_PASSWORD=$(terraform output -raw database_password 2>/dev/null || echo "")
  cd "$PROJECT_ROOT"

  if [ -z "$AURORA_ENDPOINT" ]; then
    fail "Aurora endpoint not found in Terraform outputs"
    exit 1
  fi

  # Get password from terraform.tfvars (like run-k6-and-validate.sh does)
  # This is the most reliable method and matches the working pattern
  DB_PASSWORD=""
  if [ -f "$PROJECT_ROOT/terraform/terraform.tfvars" ]; then
    # Extract password and clean it (remove newlines, take first 32 chars)
    # This matches exactly how run-k6-and-validate.sh does it
    RAW_PASSWORD=$(grep database_password "$PROJECT_ROOT/terraform/terraform.tfvars" | cut -d'"' -f2 || echo "")
    DB_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\n\r' | head -c 32)
  fi

  # Fallback to .env.aurora file if terraform.tfvars not found
  if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "" ]; then
    if [ -f "$PROJECT_ROOT/.env.aurora" ]; then
      RAW_PASSWORD=$(grep -E "^export[[:space:]]+AURORA_PASSWORD=|^AURORA_PASSWORD=|^export[[:space:]]+DB_PASSWORD=|^DB_PASSWORD=|^export[[:space:]]+DATABASE_PASSWORD=|^DATABASE_PASSWORD=" "$PROJECT_ROOT/.env.aurora" 2>/dev/null | head -1 | sed 's/^export[[:space:]]*//' | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs || echo "")
      if [ -n "$RAW_PASSWORD" ]; then
        DB_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\n\r' | head -c 32)
      fi
    elif [ -f "$PROJECT_ROOT/cdc-streaming/.env.aurora" ]; then
      RAW_PASSWORD=$(grep -E "^export[[:space:]]+AURORA_PASSWORD=|^AURORA_PASSWORD=|^export[[:space:]]+DB_PASSWORD=|^DB_PASSWORD=|^export[[:space:]]+DATABASE_PASSWORD=|^DATABASE_PASSWORD=" "$PROJECT_ROOT/cdc-streaming/.env.aurora" 2>/dev/null | head -1 | sed 's/^export[[:space:]]*//' | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs || echo "")
      if [ -n "$RAW_PASSWORD" ]; then
        DB_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\n\r' | head -c 32)
      fi
    fi
  fi

  # Final fallback to Terraform output or environment variables
  if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "" ]; then
    if [ -n "$TERRAFORM_DB_PASSWORD" ] && [ "$TERRAFORM_DB_PASSWORD" != "" ]; then
      DB_PASSWORD=$(echo "$TERRAFORM_DB_PASSWORD" | tr -d '\n\r' | head -c 32)
    elif [ -n "${DATABASE_PASSWORD:-}" ]; then
      DB_PASSWORD=$(echo "$DATABASE_PASSWORD" | tr -d '\n\r' | head -c 32)
    elif [ -n "${AURORA_PASSWORD:-}" ]; then
      DB_PASSWORD=$(echo "$AURORA_PASSWORD" | tr -d '\n\r' | head -c 32)
    else
      fail "Database password not found. Expected in terraform/terraform.tfvars as database_password"
      fail "Or set in .env.aurora file as AURORA_PASSWORD, DB_PASSWORD, or DATABASE_PASSWORD"
      fail "Or set DATABASE_PASSWORD, DB_PASSWORD, or AURORA_PASSWORD environment variable"
      exit 1
    fi
  fi

  # Verify password is set
  if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "" ]; then
    fail "Database password is empty after checking all sources"
    exit 1
  fi

  pass "Aurora endpoint: $AURORA_ENDPOINT"
  step_end
  save_checkpoint "2"
  echo ""
elif [ "$SKIP_AURORA_CHECK" = true ]; then
  info "Skipping Aurora check (--skip-aurora flag)"
  # Still need to get Aurora details for later steps
  cd "$PROJECT_ROOT/terraform"
  AURORA_ENDPOINT=$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")
  DB_NAME=$(terraform output -raw database_name 2>/dev/null || echo "car_entities")
  DB_USER=$(terraform output -raw database_user 2>/dev/null || echo "postgres")
  TERRAFORM_DB_PASSWORD=$(terraform output -raw database_password 2>/dev/null || echo "")
  cd "$PROJECT_ROOT"
  
  # Get password
  DB_PASSWORD=""
  if [ -f "$PROJECT_ROOT/terraform/terraform.tfvars" ]; then
    RAW_PASSWORD=$(grep database_password "$PROJECT_ROOT/terraform/terraform.tfvars" | cut -d'"' -f2 || echo "")
    DB_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\n\r' | head -c 32)
  fi
  if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "" ]; then
    if [ -f "$PROJECT_ROOT/.env.aurora" ]; then
      RAW_PASSWORD=$(grep -E "^export[[:space:]]+AURORA_PASSWORD=|^AURORA_PASSWORD=|^export[[:space:]]+DB_PASSWORD=|^DB_PASSWORD=|^export[[:space:]]+DATABASE_PASSWORD=|^DATABASE_PASSWORD=" "$PROJECT_ROOT/.env.aurora" 2>/dev/null | head -1 | sed 's/^export[[:space:]]*//' | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs || echo "")
      if [ -n "$RAW_PASSWORD" ]; then
        DB_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\n\r' | head -c 32)
      fi
    elif [ -f "$PROJECT_ROOT/cdc-streaming/.env.aurora" ]; then
      RAW_PASSWORD=$(grep -E "^export[[:space:]]+AURORA_PASSWORD=|^AURORA_PASSWORD=|^export[[:space:]]+DB_PASSWORD=|^DB_PASSWORD=|^export[[:space:]]+DATABASE_PASSWORD=|^DATABASE_PASSWORD=" "$PROJECT_ROOT/cdc-streaming/.env.aurora" 2>/dev/null | head -1 | sed 's/^export[[:space:]]*//' | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs || echo "")
      if [ -n "$RAW_PASSWORD" ]; then
        DB_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\n\r' | head -c 32)
      fi
    fi
  fi
  if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "" ]; then
    if [ -n "$TERRAFORM_DB_PASSWORD" ] && [ "$TERRAFORM_DB_PASSWORD" != "" ]; then
      DB_PASSWORD=$(echo "$TERRAFORM_DB_PASSWORD" | tr -d '\n\r' | head -c 32)
    elif [ -n "${DATABASE_PASSWORD:-}" ]; then
      DB_PASSWORD=$(echo "$DATABASE_PASSWORD" | tr -d '\n\r' | head -c 32)
    elif [ -n "${AURORA_PASSWORD:-}" ]; then
      DB_PASSWORD=$(echo "$AURORA_PASSWORD" | tr -d '\n\r' | head -c 32)
    fi
  fi
fi

# Step 3: Start Dockerized Consumers
if [ "$SKIP_TO_STEP" -le 3 ]; then
  step_start "Start Dockerized Consumers"
  section "Step 3: Start Dockerized Consumers"
  echo ""
  
  cd "$PROJECT_ROOT/cdc-streaming"
  
  # Check if docker-compose file exists
  if [ ! -f "docker-compose.yml" ]; then
    fail "docker-compose.yml not found in cdc-streaming directory"
    exit 1
  fi
  
  # Check if consumers are already running
  info "Checking consumer status..."
  # All 8 consumers: 4 Spring + 4 Flink
  ALL_CONSUMERS="car-consumer loan-consumer loan-payment-consumer service-consumer car-consumer-flink loan-consumer-flink loan-payment-consumer-flink service-consumer-flink"
  RUNNING_CONSUMERS=0
  
  for consumer in $ALL_CONSUMERS; do
    if docker ps --format '{{.Names}}' | grep -q "cdc-${consumer}"; then
      RUNNING_CONSUMERS=$((RUNNING_CONSUMERS + 1))
    fi
  done
  
  if [ $RUNNING_CONSUMERS -lt 8 ]; then
    info "Starting all 8 consumers (4 Spring + 4 Flink)..."
    
    # Source environment files if they exist
    if [ -f "$PROJECT_ROOT/cdc-streaming/.env" ]; then
      source "$PROJECT_ROOT/cdc-streaming/.env"
    fi
    
    # Check if KAFKA environment variables are set
    if [ -z "$KAFKA_BOOTSTRAP_SERVERS" ] && [ -z "$CONFLUENT_BOOTSTRAP_SERVERS" ]; then
      fail "KAFKA_BOOTSTRAP_SERVERS or CONFLUENT_BOOTSTRAP_SERVERS environment variable not set"
      exit 1
    fi
    
    # Use CONFLUENT_BOOTSTRAP_SERVERS if KAFKA_BOOTSTRAP_SERVERS is not set
    if [ -z "$KAFKA_BOOTSTRAP_SERVERS" ] && [ -n "$CONFLUENT_BOOTSTRAP_SERVERS" ]; then
      export KAFKA_BOOTSTRAP_SERVERS="$CONFLUENT_BOOTSTRAP_SERVERS"
    fi
    
    if docker-compose version &> /dev/null; then
      docker-compose up -d $ALL_CONSUMERS 2>&1 | grep -v "level=warning" | tail -5
    else
      docker compose up -d $ALL_CONSUMERS 2>&1 | grep -v "level=warning" | tail -5
    fi
    
    info "Waiting for consumers to start (checking every 2s, max 20s)..."
    # Poll consumer status instead of fixed wait
    max_startup_wait=20
    startup_elapsed=0
    while [ $startup_elapsed -lt $max_startup_wait ]; do
      RUNNING_COUNT=$(docker ps --format '{{.Names}}' | grep -E "cdc-(car-consumer|loan-consumer|loan-payment-consumer|service-consumer)" | wc -l | tr -d ' ')
      if [ "$RUNNING_COUNT" -ge 8 ]; then
        pass "All 8 consumers started (after ${startup_elapsed}s)"
        break
      fi
      sleep 2
      startup_elapsed=$((startup_elapsed + 2))
    done
    
    if [ "$RUNNING_COUNT" -lt 8 ]; then
      warn "Only $RUNNING_COUNT/8 consumers started after ${startup_elapsed}s"
    fi
  else
    pass "All 8 consumers already running"
  fi
  
  # Verify consumers are running
  CONSUMER_CHECK_FAILED=0
  for consumer in $ALL_CONSUMERS; do
    if docker ps --format '{{.Names}}' | grep -q "cdc-${consumer}"; then
      pass "cdc-${consumer} is running"
    elif docker ps -a --format '{{.Names}}' | grep -q "cdc-${consumer}"; then
      CONTAINER_STATUS=$(docker ps -a --format '{{.Names}} {{.Status}}' | grep "cdc-${consumer}" | awk '{print $2}')
      warn "cdc-${consumer} exists but status is: $CONTAINER_STATUS"
      CONSUMER_CHECK_FAILED=1
    else
      fail "cdc-${consumer} container not found"
      CONSUMER_CHECK_FAILED=1
    fi
  done
  
  if [ $CONSUMER_CHECK_FAILED -eq 1 ]; then
    warn "Some consumers are not running properly"
  fi
  
  cd "$PROJECT_ROOT"
  step_end
  save_checkpoint "3"
  echo ""
fi

# Step 4: Get Lambda API URL
if [ "$SKIP_TO_STEP" -le 4 ]; then
  step_start "Get Lambda API URL"
  section "Step 4: Get Lambda API URL"
  echo ""

cd "$PROJECT_ROOT/terraform"
# Try multiple possible output names
LAMBDA_API_URL=$(terraform output -raw lambda_api_url 2>/dev/null || echo "")

if [ -z "$LAMBDA_API_URL" ]; then
    # Try PostgreSQL Lambda API URL (for producer-api-python-rest-lambda-pg)
    LAMBDA_API_URL=$(terraform output -raw python_rest_pg_api_url 2>/dev/null || echo "")
fi

if [ -z "$LAMBDA_API_URL" ]; then
    # Try alternative output names
    LAMBDA_API_URL=$(terraform output -json 2>/dev/null | jq -r '.api_url.value // .python_rest_pg_api_url.value // empty' || echo "")
fi

if [ -z "$LAMBDA_API_URL" ]; then
    fail "Lambda API URL not found in Terraform outputs"
    info "Available outputs:"
    terraform output | grep -i "api\|lambda\|url"
    exit 1
fi
cd "$PROJECT_ROOT"

  pass "Lambda API URL: $LAMBDA_API_URL"
  jq ".lambda_api_url = \"$LAMBDA_API_URL\"" "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
  step_end
  save_checkpoint "4"
  echo ""
fi

# Clear database and consumer logs BEFORE submitting events for accurate timing measurement
if [ "$SKIP_TO_STEP" -le 5 ] && [ "$SKIP_CLEAR_LOGS" = false ]; then
  section "Pre-Test Cleanup"
  echo ""
  
  # Clear database test events
  info "Clearing previous test events from database..."
  if [ -n "$DB_PASSWORD" ] && [ -n "$AURORA_ENDPOINT" ]; then
    # Count events before clearing
    BEFORE_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM business_events" 2>/dev/null | tr -d ' \n' || echo "0")
    
    # Delete all events (for clean test)
    if PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -c "DELETE FROM business_events" 2>/dev/null; then
      AFTER_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM business_events" 2>/dev/null | tr -d ' \n' || echo "0")
      pass "Database cleared: $BEFORE_COUNT events deleted, $AFTER_COUNT remaining"
    else
      warn "Could not clear database (continuing anyway)"
    fi
  else
    warn "Database credentials not available, skipping database clear"
  fi
  echo ""
  
  # Clear consumer logs (consumers already started in Step 3)
  info "Clearing consumer logs..."
  if "$SCRIPT_DIR/clear-consumer-logs.sh" 2>&1 | tail -10; then
    pass "Consumer logs cleared"
  else
    warn "Some consumer logs could not be cleared (continuing anyway)"
  fi
  
  # Wait for consumers to warm up (based on our delay analysis)
  info "Waiting 10s for consumers to reconnect to Kafka..."
  sleep 10
  pass "Consumer warm-up complete"
  echo ""
fi

# Step 5: Submit Events
if [ "$SKIP_TO_STEP" -le 5 ]; then
  step_start "Submit Events"
  section "Step 5: Submit Events to Lambda API"
  echo ""
  info "Submitting 10 events of each type (40 total: CarCreated, LoanCreated, LoanPaymentSubmitted, CarServiceDone)"
  echo ""

  cd "$PROJECT_ROOT"
  if "$SCRIPT_DIR/submit-test-events.sh" "$LAMBDA_API_URL" "$EVENTS_FILE"; then
    pass "Events submitted successfully"
    jq '.events_submitted = true' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
  else
    fail "Failed to submit events"
    exit 1
  fi

  SUBMITTED_EVENTS=$(jq 'length' "$EVENTS_FILE" 2>/dev/null || echo "0")
  info "Submitted $SUBMITTED_EVENTS events (expected: 40 events - 10 of each type)"
  step_end
  save_checkpoint "5"
  echo ""
fi

# Step 6: Validate Database
if [ "$SKIP_TO_STEP" -le 6 ]; then
  step_start "Validate Database"
  section "Step 6: Validate Events in Database"
  echo ""

# Run database validation and capture output
# Password is now read from .env.aurora in validate-database-events.sh, but we still pass it for compatibility
DB_VALIDATION_TMP="/tmp/db-validation-$(date +%s).log"
if "$SCRIPT_DIR/validate-database-events.sh" "$AURORA_ENDPOINT" "$DB_NAME" "$DB_USER" "$DB_PASSWORD" "$EVENTS_FILE" > "$DB_VALIDATION_TMP" 2>&1; then
    cat "$DB_VALIDATION_TMP"
    pass "Database validation successful"
    jq '.database_validated = true' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
    rm -f "$DB_VALIDATION_TMP"
else
    DB_VALIDATION_EXIT=$?
    cat "$DB_VALIDATION_TMP"
    fail "Database validation failed (exit code: $DB_VALIDATION_EXIT)"
    jq '.database_validated = false' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
    rm -f "$DB_VALIDATION_TMP"
    # Don't exit - continue with other validations
  fi
  step_end
  save_checkpoint "6"
  echo ""
fi

# Step 7: Start Stream Processor
if [ "$SKIP_TO_STEP" -le 7 ]; then
  step_start "Start Stream Processor"
  section "Step 7: Start Stream Processor"
  echo ""

  info "Starting Spring Boot stream processor..."
  cd "$PROJECT_ROOT/cdc-streaming"

  # Check if stream processor is already running
  if docker-compose ps stream-processor 2>/dev/null | grep -q "Up"; then
    pass "Stream processor is already running"
  elif [ "$SKIP_BUILD" = true ]; then
    info "Skipping build (--skip-build flag), checking if image exists..."
    if docker images | grep -q stream-processor; then
      info "Image exists, starting container..."
      if docker-compose up -d stream-processor 2>&1 | grep -v "level=warning" | tail -3; then
        pass "Stream processor started (skipped build)"
      else
        warn "Failed to start stream processor"
      fi
    else
      warn "Image not found but --skip-build specified. Attempting to start anyway..."
      docker-compose up -d stream-processor 2>&1 | grep -v "level=warning" | tail -3 || true
    fi
  else
    info "Building stream processor image (this may take a few minutes)..."
    # Build the image first
    if docker-compose build stream-processor 2>&1 | tail -5; then
      info "Starting stream processor container..."
      if docker-compose up -d stream-processor 2>&1 | grep -v "level=warning" | tail -3; then
        info "Waiting for stream processor to become healthy..."
        # Poll health endpoint instead of fixed wait
        max_health_wait=30
        health_elapsed=0
        while [ $health_elapsed -lt $max_health_wait ]; do
          if curl -sf http://localhost:8083/actuator/health > /dev/null 2>&1; then
            pass "Stream processor started and healthy (after ${health_elapsed}s)"
            break
          fi
          sleep 2
          health_elapsed=$((health_elapsed + 2))
        done
        
        if [ $health_elapsed -ge $max_health_wait ]; then
          if docker-compose ps stream-processor 2>/dev/null | grep -q "Up"; then
            warn "Stream processor is running but health check not responding after ${max_health_wait}s"
            info "Check logs: docker-compose -f cdc-streaming/docker-compose.yml logs stream-processor"
          else
            warn "Stream processor container may not be fully started"
            info "Check logs: docker-compose -f cdc-streaming/docker-compose.yml logs stream-processor"
          fi
        fi
      else
        warn "Failed to start stream processor"
        info "Check logs: docker-compose -f cdc-streaming/docker-compose.yml logs stream-processor"
      fi
    else
      warn "Failed to build stream processor image"
      info "You may need to build it manually: cd cdc-streaming && docker-compose build stream-processor"
    fi
  fi
  cd "$PROJECT_ROOT"
  step_end
  save_checkpoint "7"
  echo ""
fi

# Step 8: Wait for CDC Propagation
if [ "$SKIP_TO_STEP" -le 8 ]; then
  step_start "Wait for CDC Propagation"
  section "Step 8: Wait for CDC Propagation"
  echo ""

  info "Waiting up to ${WAIT_TIME}s for CDC to propagate events..."
  info "Events flow: Database → CDC Connector → Kafka → Stream Processors → Filtered Topics"
  # Use a single sleep instead of loop for faster execution
  sleep $WAIT_TIME
  pass "Wait complete"
  step_end
  save_checkpoint "8"
  echo ""
fi

# Step 9: Validate Kafka Topics
if [ "$SKIP_TO_STEP" -le 9 ]; then
  step_start "Validate Kafka Topics"
  section "Step 9: Validate Kafka Topics"
  echo ""

  # Check if Confluent is logged in before attempting Kafka validation
  if confluent environment list &> /dev/null; then
    # Determine which processor to validate based on which is running
    # Check if Spring Boot stream processor is running
    PROCESSOR_TO_VALIDATE="both"  # Default to both for comprehensive testing
    if docker-compose ps stream-processor 2>/dev/null | grep -q "Up"; then
      # Spring Boot is running, validate spring topics
      # Also check for Flink (both might be running in test scenarios)
      info "Spring Boot processor detected, validating spring topics"
      PROCESSOR_TO_VALIDATE="spring"
    else
      # Only Flink is likely running
      info "Validating Flink topics (Spring Boot not running)"
      PROCESSOR_TO_VALIDATE="flink"
    fi
    
    if "$SCRIPT_DIR/validate-kafka-topics.sh" "$EVENTS_FILE" "$PROCESSOR_TO_VALIDATE"; then
      pass "Kafka topic validation successful ($PROCESSOR_TO_VALIDATE)"
      jq '.kafka_validated = true' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
    else
      fail "Kafka topic validation failed ($PROCESSOR_TO_VALIDATE)"
      jq '.kafka_validated = false' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
    fi
  else
    warn "Skipping Kafka validation - Confluent Cloud not logged in"
    info "To enable Kafka validation, run: confluent login"
      jq '.kafka_validated = "skipped"' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
  fi
  step_end
  save_checkpoint "9"
  echo ""
fi

# Step 10: Validate Consumers
if [ "$SKIP_TO_STEP" -le 10 ]; then
  step_start "Validate Consumers"
  section "Step 10: Validate All 8 Consumers (4 Spring + 4 Flink)"
  echo ""
  info "Validating all 8 consumers:"
  info "  - 4 Spring consumers (from filtered-*-events-spring topics)"
  info "  - 4 Flink consumers (from filtered-*-events-flink topics)"
  echo ""

  if "$SCRIPT_DIR/validate-consumers.sh" "$EVENTS_FILE"; then
    pass "All 8 consumers validated successfully"
    jq '.consumers_validated = true' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
  else
    fail "Consumer validation failed"
    jq '.consumers_validated = false' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
  fi
  step_end
  save_checkpoint "10"
  echo ""
fi

# Step 11: Generate Report
step_start "Generate Report"
section "Step 11: Test Report"
echo ""

DB_VALIDATED=$(jq -r '.database_validated // false' "$RESULTS_FILE")
KAFKA_VALIDATED=$(jq -r '.kafka_validated // false' "$RESULTS_FILE")
CONSUMERS_VALIDATED=$(jq -r '.consumers_validated // false' "$RESULTS_FILE")

echo "Test Results Summary:"
echo "  Events Submitted: $SUBMITTED_EVENTS"
echo "  Database Validated: $DB_VALIDATED"
echo "  Kafka Topics Validated: $KAFKA_VALIDATED"
echo "  Consumers Validated: $CONSUMERS_VALIDATED"
echo ""

if [ "$DB_VALIDATED" = "true" ] && [ "$KAFKA_VALIDATED" = "true" ] && [ "$CONSUMERS_VALIDATED" = "true" ]; then
    pass "All validations passed!"
    echo ""
    echo "Pipeline flow verified:"
    echo "  Lambda API → PostgreSQL → CDC → raw-event-headers → Stream Processor → Filtered Topics → Consumers"
    echo ""
    echo "Note: Topics are processor-specific:"
    echo "  - Flink: filtered-*-events-flink"
    echo "  - Spring Boot: filtered-*-events-spring"
    exit 0
else
    fail "Some validations failed"
    echo ""
    echo "Troubleshooting:"
    if [ "$DB_VALIDATED" != "true" ]; then
        echo "  - Check database connection and event_headers table"
    fi
    if [ "$KAFKA_VALIDATED" != "true" ]; then
        echo "  - Check CDC connector status: confluent connect list"
        echo "  - Check raw-event-headers topic: confluent kafka topic consume raw-event-headers --max-messages 5"
        echo "  - Check Flink statements: confluent flink statement list"
        echo "  - Check Spring Boot service: docker-compose -f cdc-streaming/docker-compose.yml ps"
    fi
    if [ "$CONSUMERS_VALIDATED" != "true" ]; then
        echo "  - Check consumer logs: docker-compose -f cdc-streaming/docker-compose.yml logs"
        echo "  - Verify consumers are running: docker-compose -f cdc-streaming/docker-compose.yml ps"
    fi
  step_end
  save_checkpoint "11"
  exit 1
fi

step_end
save_checkpoint "11"
