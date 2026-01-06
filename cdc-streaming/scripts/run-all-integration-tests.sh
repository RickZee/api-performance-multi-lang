#!/usr/bin/env bash
# Run all new integration tests
# This script starts Docker infrastructure and runs all local and schema tests
#
# Usage:
#   ./scripts/run-all-integration-tests.sh [--confluent-cloud]
#
# Options:
#   --confluent-cloud    Use Confluent Cloud instead of local Docker Kafka
#                        Requires: CONFLUENT_BOOTSTRAP_SERVERS, CONFLUENT_API_KEY, CONFLUENT_API_SECRET
#                        Or: confluent login

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDC_STREAMING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$CDC_STREAMING_DIR"

# Source environment files if they exist (same pattern as test-e2e-pipeline.sh)
PROJECT_ROOT="$(cd "$CDC_STREAMING_DIR/.." && pwd)"
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

COMPOSE_FILE="docker-compose.integration-test.yml"
USE_CONFLUENT_CLOUD=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --confluent-cloud)
      USE_CONFLUENT_CLOUD=true
      shift
      ;;
    *)
      warn "Unknown argument: $1"
      shift
      ;;
  esac
done

# Confluent login function (from test-e2e-pipeline.sh)
# Note: We check for API keys first - if they exist, we can use them directly
# without needing CLI login for Kafka operations
ensure_confluent_login() {
  # Check if we have API keys - if so, we can proceed without CLI login
  local api_key="${CONFLUENT_CLOUD_API_KEY:-${KAFKA_API_KEY:-${CONFLUENT_API_KEY:-}}}"
  local api_secret="${CONFLUENT_CLOUD_API_SECRET:-${KAFKA_API_SECRET:-${CONFLUENT_API_SECRET:-}}}"
  
  if [ -n "$api_key" ] && [ -n "$api_secret" ]; then
    info "API keys found - can proceed with Kafka operations"
    # Try CLI login for topic management, but don't fail if it doesn't work
    if confluent environment list &>/dev/null; then
      pass "Confluent Cloud authenticated via CLI"
      return 0
    else
      warn "CLI not logged in, but API keys available - will use API keys for Kafka connections"
      warn "Topic creation may be skipped - ensure topics exist in Confluent Cloud"
      return 0  # Allow to proceed with API keys
    fi
  fi
  
  # Try CLI login if no API keys
  if confluent environment list &>/dev/null; then
    pass "Confluent Cloud authenticated"
    CURRENT_ENV=$(confluent environment list --output json 2>/dev/null | jq -r '.[] | select(.is_current==true) | .name // .id' | head -1 || echo "unknown")
    if [ -n "$CURRENT_ENV" ] && [ "$CURRENT_ENV" != "unknown" ]; then
      info "Current environment: $CURRENT_ENV"
    fi
    return 0
  fi
  
  # Fall back to interactive
  warn "Not logged in - attempting interactive login..."
  if confluent login; then
    if confluent environment list &>/dev/null; then
      pass "Confluent Cloud authenticated via interactive login"
      return 0
    fi
  fi
  
  warn "Login failed or was cancelled"
  info "To enable Confluent Cloud testing, run: confluent login"
  info "Or set: export CONFLUENT_CLOUD_API_KEY=key && export CONFLUENT_CLOUD_API_SECRET=secret"
  return 1
}

# Default to local Docker (Redpanda + local Postgres)
# Use --confluent-cloud flag to use Confluent Cloud instead
if [ "$USE_CONFLUENT_CLOUD" = "true" ]; then
    section "Confluent Cloud Configuration"
    info "Using Confluent Cloud Kafka (--confluent-cloud flag provided)"
    
    # Check for Confluent CLI
    if ! command -v confluent &>/dev/null; then
        fail "Confluent CLI not found. Install it: https://docs.confluent.io/confluent-cli/current/install.html"
        exit 1
    fi
    
    # Ensure login
    if ! ensure_confluent_login; then
        fail "Confluent Cloud authentication required"
        exit 1
    fi
    
    # Check for required environment variables
    if [ -z "$KAFKA_BOOTSTRAP_SERVERS" ] && [ -z "$CONFLUENT_BOOTSTRAP_SERVERS" ]; then
        fail "KAFKA_BOOTSTRAP_SERVERS or CONFLUENT_BOOTSTRAP_SERVERS environment variable not set"
        fail "Set it in cdc-streaming/.env or export it before running tests"
        exit 1
    fi
    
    # Use CONFLUENT_BOOTSTRAP_SERVERS if KAFKA_BOOTSTRAP_SERVERS is not set
    if [ -z "$KAFKA_BOOTSTRAP_SERVERS" ] && [ -n "$CONFLUENT_BOOTSTRAP_SERVERS" ]; then
        export KAFKA_BOOTSTRAP_SERVERS="$CONFLUENT_BOOTSTRAP_SERVERS"
    fi
    
    # Check for API credentials
    if [ -z "$KAFKA_API_KEY" ] && [ -z "$CONFLUENT_API_KEY" ] && [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
        fail "KAFKA_API_KEY, CONFLUENT_API_KEY, or CONFLUENT_CLOUD_API_KEY environment variable not set"
        fail "Set it in cdc-streaming/.env or export it before running tests"
        exit 1
    fi
    
    if [ -z "$KAFKA_API_SECRET" ] && [ -z "$CONFLUENT_API_SECRET" ] && [ -z "$CONFLUENT_CLOUD_API_SECRET" ]; then
        fail "KAFKA_API_SECRET, CONFLUENT_API_SECRET, or CONFLUENT_CLOUD_API_SECRET environment variable not set"
        fail "Set it in cdc-streaming/.env or export it before running tests"
        exit 1
    fi
    
    # Set bootstrap servers and credentials
    BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-${CONFLUENT_BOOTSTRAP_SERVERS}}"
    API_KEY="${KAFKA_API_KEY:-${CONFLUENT_API_KEY:-${CONFLUENT_CLOUD_API_KEY}}}"
    API_SECRET="${KAFKA_API_SECRET:-${CONFLUENT_API_SECRET:-${CONFLUENT_CLOUD_API_SECRET}}}"
    
    pass "Using Confluent Cloud: $BOOTSTRAP_SERVERS"
    
    # Export for services
    export KAFKA_BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS"
    export KAFKA_API_KEY="$API_KEY"
    export KAFKA_API_SECRET="$API_SECRET"
    export KAFKA_SECURITY_PROTOCOL="SASL_SSL"
    export CONFLUENT_API_KEY="$API_KEY"
    export CONFLUENT_API_SECRET="$API_SECRET"
    
    # Ensure topics exist in Confluent Cloud
    info "Ensuring topics exist in Confluent Cloud..."
    if command -v confluent &>/dev/null && confluent environment list &>/dev/null; then
        # Get current cluster/resource ID
        CLUSTER_ID=$(confluent kafka cluster list -o json 2>/dev/null | jq -r '.[0].id' | head -1 || echo "")
        if [ -z "$CLUSTER_ID" ]; then
            warn "Could not get Kafka cluster ID - topics must exist in Confluent Cloud"
        else
            info "Using Kafka cluster: $CLUSTER_ID"
            # Create topics if they don't exist
            info "Creating topics in Confluent Cloud if needed..."
            for topic in raw-event-headers raw-event-headers-v2 filtered-car-created-events-spring filtered-car-created-events-v2-spring filtered-loan-created-events-spring filtered-loan-created-events-v2-spring filtered-loan-payment-submitted-events-spring filtered-loan-payment-submitted-events-v2-spring filtered-service-events-spring filtered-service-events-v2-spring; do
                if ! confluent kafka topic describe "$topic" --cluster "$CLUSTER_ID" &>/dev/null 2>&1; then
                    info "Creating topic: $topic"
                    confluent kafka topic create "$topic" --cluster "$CLUSTER_ID" --partitions 3 2>&1 | grep -v "already exists\|Topic.*already exists" || true
                else
                    info "Topic $topic already exists"
                fi
            done
            pass "Topics verified in Confluent Cloud"
        fi
    else
        warn "Confluent CLI not available - topics must exist in Confluent Cloud"
        info "Make sure these topics exist: raw-event-headers, filtered-car-created-events-spring, filtered-loan-created-events-spring, filtered-loan-payment-submitted-events-spring, filtered-service-events-spring"
    fi
else
    section "Local Docker Configuration"
    info "Using local Docker (Redpanda + local Postgres) - default mode"
    pass "No credentials required for local mode"
    
    # Unset any Confluent Cloud credentials to ensure we use local Redpanda
    # For Docker containers, use internal hostname; for tests, use localhost with external port
    # Set this for Docker containers (they use redpanda:9092 internally)
    export KAFKA_BOOTSTRAP_SERVERS="redpanda:9092"
    export KAFKA_SECURITY_PROTOCOL="PLAINTEXT"
    export KAFKA_API_KEY=""
    export KAFKA_API_SECRET=""
    
    # Store the test bootstrap servers separately (for tests running on host)
    export TEST_KAFKA_BOOTSTRAP_SERVERS="localhost:29092"
fi

# Start infrastructure
section "Starting Test Infrastructure"

# Start Mock API
info "Starting Mock Confluent API..."
docker-compose -f "$COMPOSE_FILE" up -d mock-confluent-api

# Start local services if not using Confluent Cloud
if [ "$USE_CONFLUENT_CLOUD" != "true" ]; then
    # Start Redpanda
    info "Starting Redpanda..."
    docker-compose -f "$COMPOSE_FILE" up -d redpanda
    info "Waiting for Redpanda to be healthy..."
    # Wait for Redpanda health check (up to 30 seconds)
    max_wait=30
    elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if docker exec int-test-redpanda rpk cluster health &>/dev/null 2>&1; then
            pass "Redpanda is healthy"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    if [ $elapsed -ge $max_wait ]; then
        warn "Redpanda may not be fully healthy, but continuing..."
    fi
    
    # Create topics in Redpanda
    info "Creating topics in Redpanda..."
    TOPICS=(
        "raw-event-headers"
        "raw-event-headers-v2"
        "filtered-car-created-events-spring"
        "filtered-car-created-events-v2-spring"
        "filtered-loan-created-events-spring"
        "filtered-loan-created-events-v2-spring"
        "filtered-loan-payment-submitted-events-spring"
        "filtered-loan-payment-submitted-events-v2-spring"
        "filtered-service-events-spring"
        "filtered-service-events-v2-spring"
    )
    
    for topic in "${TOPICS[@]}"; do
        if docker exec int-test-redpanda rpk topic describe "$topic" &>/dev/null; then
            info "Topic $topic already exists"
        else
            info "Creating topic: $topic"
            docker exec int-test-redpanda rpk topic create "$topic" --partitions 3 --replicas 1 || true
        fi
    done
    
    # Wait for topics to be fully available (metadata propagation)
    info "Waiting for topics to be fully available..."
    sleep 3
    
    # Verify topics are accessible
    for topic in "${TOPICS[@]}"; do
        if docker exec int-test-redpanda rpk topic describe "$topic" &>/dev/null; then
            pass "Topic $topic is available"
        else
            warn "Topic $topic may not be fully available"
        fi
    done
    pass "Topics verified in Redpanda"
    
    # In local Docker mode, always use local postgres (ignore USE_AURORA)
    # USE_AURORA is only relevant for Confluent Cloud mode
    info "Starting local PostgreSQL for local Docker mode..."
    docker-compose -f "$COMPOSE_FILE" up -d postgres
    info "Waiting for local PostgreSQL to be healthy..."
    # Wait for PostgreSQL health check (up to 30 seconds)
    max_wait=30
    elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if docker exec int-test-postgres pg_isready -U postgres &>/dev/null 2>&1; then
            pass "Local PostgreSQL is healthy"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    if [ $elapsed -ge $max_wait ]; then
        warn "PostgreSQL may not be fully healthy, but continuing..."
    fi
else
    # Confluent Cloud mode - check for Aurora database
    if [ "$USE_AURORA" = "true" ]; then
        info "Using Aurora PostgreSQL - skipping local postgres container"
        # Ensure local postgres is down if it was running
        docker-compose -f "$COMPOSE_FILE" down postgres 2>/dev/null || true
        # Set DATABASE_URL for metadata-service to Aurora endpoint
        export DATABASE_URL="jdbc:postgresql://${AURORA_ENDPOINT}:5432/${DB_NAME}"
        export DATABASE_USERNAME="${AURORA_USERNAME}"
        export DATABASE_PASSWORD="${AURORA_PASSWORD}"
    else
        info "Starting local PostgreSQL..."
        docker-compose -f "$COMPOSE_FILE" up -d postgres
        info "Waiting for local PostgreSQL to be healthy..."
        # Wait for PostgreSQL health check (up to 30 seconds)
        max_wait=30
        elapsed=0
        while [ $elapsed -lt $max_wait ]; do
            if docker exec int-test-postgres pg_isready -U postgres &>/dev/null 2>&1; then
                pass "Local PostgreSQL is healthy"
                break
            fi
            sleep 2
            elapsed=$((elapsed + 2))
        done
        if [ $elapsed -ge $max_wait ]; then
            warn "PostgreSQL may not be fully healthy, but continuing..."
        fi
    fi
fi

# Cleanup function
cleanup() {
    info "Cleaning up Docker containers..."
    docker-compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    docker-compose -f "$COMPOSE_FILE" --profile v2 down 2>/dev/null || true
}

trap cleanup EXIT

if [ "$USE_CONFLUENT_CLOUD" = "true" ]; then
    info "Starting Metadata Service and Stream Processor (connecting to Confluent Cloud)..."
else
    info "Starting Metadata Service and Stream Processor (connecting to local Redpanda)..."
    # Ensure Docker containers use internal hostname (redpanda:9092)
    # Don't let test environment variables affect Docker containers
    export KAFKA_BOOTSTRAP_SERVERS="redpanda:9092"
fi
docker-compose -f "$COMPOSE_FILE" build metadata-service stream-processor stream-processor-v2
docker-compose -f "$COMPOSE_FILE" up -d metadata-service stream-processor

# Start V2 stream processor for breaking schema change tests
info "Starting V2 Stream Processor for parallel deployment tests..."
docker-compose -f "$COMPOSE_FILE" --profile v2 up -d stream-processor-v2

info "Waiting for services to be healthy..."
max_wait=60
elapsed=0
while [ $elapsed -lt $max_wait ]; do
    if curl -sf http://localhost:8080/api/v1/health &>/dev/null && \
       curl -sf http://localhost:8083/actuator/health &>/dev/null; then
        pass "All services are healthy"
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

if [ $elapsed -ge $max_wait ]; then
    warn "Some services may not be fully healthy, but continuing with tests..."
fi

# Seed V1 filters into Metadata Service (needed for stream processor)
info "Seeding V1 filters into Metadata Service..."
if [ -f "$CDC_STREAMING_DIR/scripts/seed-v1-filters.sh" ]; then
    "$CDC_STREAMING_DIR/scripts/seed-v1-filters.sh" || warn "Failed to seed V1 filters - stream processor may not route events correctly"
else
    warn "seed-v1-filters.sh not found - V1 filters may not be available"
fi

# Seed V2 filters into Metadata Service if V2 tests will run
info "Seeding V2 filters into Metadata Service..."
if [ -f "$CDC_STREAMING_DIR/scripts/seed-v2-filters.sh" ]; then
    "$CDC_STREAMING_DIR/scripts/seed-v2-filters.sh" || warn "Failed to seed V2 filters - V2 tests may fail"
else
    warn "seed-v2-filters.sh not found - V2 filters may not be available"
fi

# Continue with test execution

section "Running Local Integration Tests"

cd "$CDC_STREAMING_DIR/e2e-tests"

# Export environment variables for tests
if [ "$USE_CONFLUENT_CLOUD" = "true" ]; then
    export KAFKA_BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS"
    export CONFLUENT_BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS"
    if [ -n "$API_KEY" ] && [ -n "$API_SECRET" ]; then
        export CONFLUENT_API_KEY="$API_KEY"
        export CONFLUENT_API_SECRET="$API_SECRET"
        export CONFLUENT_CLOUD_API_KEY="$API_KEY"
        export CONFLUENT_CLOUD_API_SECRET="$API_SECRET"
        export KAFKA_API_KEY="$API_KEY"
        export KAFKA_API_SECRET="$API_SECRET"
    fi
else
    # Local mode - use Redpanda
    # Tests run on host, so use localhost with external port
    export KAFKA_BOOTSTRAP_SERVERS="${TEST_KAFKA_BOOTSTRAP_SERVERS:-localhost:29092}"
    export CONFLUENT_BOOTSTRAP_SERVERS="${TEST_KAFKA_BOOTSTRAP_SERVERS:-localhost:29092}"
    # No API keys needed for local Redpanda
    export KAFKA_API_KEY=""
    export KAFKA_API_SECRET=""
fi

info "Running LocalKafkaIntegrationTest..."
info "Bootstrap servers for tests: $KAFKA_BOOTSTRAP_SERVERS"
./gradlew test --tests "com.example.e2e.local.LocalKafkaIntegrationTest" --no-daemon 2>&1 | tee /tmp/test-local-kafka.log || warn "Some LocalKafkaIntegrationTest tests failed"

info "Running FilterLifecycleLocalTest..."
./gradlew test --tests "com.example.e2e.local.FilterLifecycleLocalTest" --no-daemon --info 2>&1 | tee /tmp/test-filter-lifecycle.log || warn "Some FilterLifecycleLocalTest tests failed"

info "Running StreamProcessorLocalTest..."
./gradlew test --tests "com.example.e2e.local.StreamProcessorLocalTest" --no-daemon --info 2>&1 | tee /tmp/test-stream-processor.log || warn "Some StreamProcessorLocalTest tests failed"

section "Running Schema Evolution Tests"

info "Running NonBreakingSchemaTest..."
./gradlew test --tests "com.example.e2e.schema.NonBreakingSchemaTest" --no-daemon --info 2>&1 | tee /tmp/test-non-breaking-schema.log || warn "Some NonBreakingSchemaTest tests failed"

info "Running V2SystemDiagnosticsTest (diagnostic tests)..."
./gradlew test --tests "com.example.e2e.schema.V2SystemDiagnosticsTest" --no-daemon --info 2>&1 | tee /tmp/test-v2-diagnostics.log || warn "Some V2SystemDiagnosticsTest tests failed"

info "Running BreakingSchemaChangeTest (V2 system)..."
# Create V2 topics in Confluent Cloud
info "Creating V2 topics in Confluent Cloud..."
if command -v confluent &>/dev/null && confluent environment list &>/dev/null; then
    CLUSTER_ID=$(confluent kafka cluster list -o json 2>/dev/null | jq -r '.[0].id' | head -1 || echo "")
    if [ -n "$CLUSTER_ID" ]; then
        for topic in raw-event-headers-v2 filtered-car-created-events-v2-spring filtered-loan-created-events-v2-spring filtered-loan-payment-submitted-events-v2-spring filtered-service-events-v2-spring; do
            if ! confluent kafka topic describe "$topic" --cluster "$CLUSTER_ID" &>/dev/null 2>&1; then
                info "Creating topic: $topic"
                confluent kafka topic create "$topic" --cluster "$CLUSTER_ID" --partitions 3 2>&1 | grep -v "already exists\|Topic.*already exists" || true
            else
                info "Topic $topic already exists"
            fi
        done
        pass "V2 topics verified in Confluent Cloud"
    else
        warn "Could not get Kafka cluster ID - V2 topics must exist in Confluent Cloud"
    fi
fi

# Start V2 stream processor
cd "$CDC_STREAMING_DIR"
docker-compose -f "$COMPOSE_FILE" --profile v2 up -d stream-processor-v2

cd "$CDC_STREAMING_DIR/e2e-tests"
./gradlew test --tests "com.example.e2e.schema.BreakingSchemaChangeTest" --no-daemon --info 2>&1 | tee /tmp/test-breaking-schema.log || warn "Some BreakingSchemaChangeTest tests failed"

section "Test Summary"

info "All tests completed. Check output above for results."
info "To see detailed test results, check: cdc-streaming/e2e-tests/build/reports/tests/test/index.html"

