#!/usr/bin/env bash
# Local Integration Test Pipeline
# Mirrors structure of test-e2e-pipeline.sh for consistency
# Tests filtering and routing services using local Docker Compose with Confluent Kafka
#
# Usage:
#   ./cdc-streaming/scripts/run-local-integration-tests.sh [FLAGS]
#
# Examples:
#   ./cdc-streaming/scripts/run-local-integration-tests.sh
#   ./cdc-streaming/scripts/run-local-integration-tests.sh --fast
#   ./cdc-streaming/scripts/run-local-integration-tests.sh --profile v2
#   ./cdc-streaming/scripts/run-local-integration-tests.sh --cleanup
#
# Flags:
#   --fast              Skip builds (use existing images)
#   --profile v2        Run with V2 breaking change system
#   --skip-build        Skip Docker image builds
#   --cleanup           Clean up containers after tests
#   --skip-to-step N    Resume from step N (1-9)
#   --debug             Enable verbose output with timing
#   --wait-time N       Wait time for event processing (default: 15s)

set +e
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDC_STREAMING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$CDC_STREAMING_DIR"

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
SKIP_BUILD=false
CLEANUP=false
SKIP_TO_STEP=0
DEBUG=false
FAST_MODE=false
WAIT_TIME=15
V2_PROFILE=false
COMPOSE_FILE="docker-compose.integration-test.yml"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --fast)
      FAST_MODE=true
      SKIP_BUILD=true
      shift
      ;;
    --profile)
      if [ "$2" = "v2" ]; then
        V2_PROFILE=true
      fi
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --cleanup)
      CLEANUP=true
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
    --wait-time)
      WAIT_TIME="$2"
      shift 2
      ;;
    *)
      warn "Unknown argument: $1"
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

# Configuration
EVENTS_FILE="/tmp/local-int-test-events-$(date +%s).json"
RESULTS_FILE="/tmp/local-int-test-results-$(date +%s).json"

# Initialize results
echo "{}" > "$RESULTS_FILE"

section "Local Integration Test Pipeline"
echo ""
echo "Testing filtering and routing services with local Docker Compose"
echo "Wait time for event processing: ${WAIT_TIME}s"
[ "$FAST_MODE" = true ] && info "Fast mode enabled (skipping builds)"
[ "$V2_PROFILE" = true ] && info "V2 profile enabled (breaking schema changes)"
[ "$DEBUG" = true ] && info "Debug mode enabled (verbose timing output)"
echo ""

# Cleanup function
cleanup() {
  if [ "$CLEANUP" = true ]; then
    info "Cleaning up containers..."
    if [ "$V2_PROFILE" = true ]; then
      docker-compose -f "$COMPOSE_FILE" --profile v2 down
    else
      docker-compose -f "$COMPOSE_FILE" down
    fi
  fi
}

trap cleanup EXIT

# Step 1: Check Prerequisites
if [ "$SKIP_TO_STEP" -le 1 ]; then
  step_start "Prerequisites Check"
  section "Step 1: Prerequisites Check"
  echo ""

  MISSING_DEPS=0

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

  if [ $MISSING_DEPS -eq 1 ]; then
    fail "Missing required dependencies"
    exit 1
  fi

  step_end
  echo ""
fi

# Step 2: Start Confluent Stack
if [ "$SKIP_TO_STEP" -le 2 ]; then
  step_start "Start Confluent Stack"
  section "Step 2: Start Confluent Stack"
  echo ""

  info "Starting Kafka and Schema Registry..."
  if [ "$V2_PROFILE" = true ]; then
    docker-compose -f "$COMPOSE_FILE" --profile v2 up -d kafka schema-registry mock-confluent-api
  else
    docker-compose -f "$COMPOSE_FILE" up -d kafka schema-registry mock-confluent-api
  fi

  # Wait for Kafka to be healthy
  info "Waiting for Kafka to be healthy..."
  max_wait=60
  elapsed=0
  while [ $elapsed -lt $max_wait ]; do
    if docker exec int-test-kafka kafka-topics --bootstrap-server localhost:9092 --list &>/dev/null; then
      pass "Kafka is healthy"
      break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  if [ $elapsed -ge $max_wait ]; then
    fail "Kafka did not become healthy within ${max_wait}s"
    exit 1
  fi

  # Initialize topics
  info "Initializing topics..."
  docker-compose -f "$COMPOSE_FILE" up init-topics

  step_end
  echo ""
fi

# Step 3: Start Consumers
if [ "$SKIP_TO_STEP" -le 3 ]; then
  step_start "Start Consumers"
  section "Step 3: Start Consumers"
  echo ""

  info "Starting consumers..."
  if [ "$V2_PROFILE" = true ]; then
    docker-compose -f "$COMPOSE_FILE" --profile v2 up -d car-consumer loan-consumer loan-payment-consumer service-consumer
  else
    docker-compose -f "$COMPOSE_FILE" up -d car-consumer loan-consumer loan-payment-consumer service-consumer
  fi

  # Wait for consumers to start
  sleep 5
  RUNNING_COUNT=$(docker ps --format '{{.Names}}' | grep -E "int-test-(car-consumer|loan-consumer|loan-payment-consumer|service-consumer)" | wc -l | tr -d ' ')
  if [ "$RUNNING_COUNT" -eq 4 ]; then
    pass "All 4 consumers started"
  else
    warn "Only $RUNNING_COUNT/4 consumers started"
  fi

  step_end
  echo ""
fi

# Step 4: Start Services
if [ "$SKIP_TO_STEP" -le 4 ]; then
  step_start "Start Services"
  section "Step 4: Start Services"
  echo ""

  # Build images if needed
  if [ "$SKIP_BUILD" = false ]; then
    info "Building images (this may take a few minutes)..."
    docker-compose -f "$COMPOSE_FILE" build metadata-service stream-processor
    if [ "$V2_PROFILE" = true ]; then
      docker-compose -f "$COMPOSE_FILE" build stream-processor-v2
    fi
  fi

  # Start metadata service
  info "Starting metadata service..."
  if [ "$V2_PROFILE" = true ]; then
    docker-compose -f "$COMPOSE_FILE" --profile v2 up -d metadata-service
  else
    docker-compose -f "$COMPOSE_FILE" up -d metadata-service
  fi

  # Wait for metadata service to be healthy
  max_wait=30
  elapsed=0
  while [ $elapsed -lt $max_wait ]; do
    if curl -sf http://localhost:8080/api/v1/health &>/dev/null; then
      pass "Metadata service is healthy"
      break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  # Start stream processor
  info "Starting stream processor..."
  if [ "$V2_PROFILE" = true ]; then
    docker-compose -f "$COMPOSE_FILE" --profile v2 up -d stream-processor stream-processor-v2
  else
    docker-compose -f "$COMPOSE_FILE" up -d stream-processor
  fi

  # Wait for stream processor to be healthy
  max_wait=30
  elapsed=0
  while [ $elapsed -lt $max_wait ]; do
    if curl -sf http://localhost:8083/actuator/health &>/dev/null; then
      pass "Stream processor is healthy"
      break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  step_end
  echo ""
fi

# Step 5: Submit Test Events
if [ "$SKIP_TO_STEP" -le 5 ]; then
  step_start "Submit Test Events"
  section "Step 5: Submit Test Events"
  echo ""

  info "Generating test events..."
  # Generate test events (simplified - in real scenario, use test event generator)
  cat > "$EVENTS_FILE" <<EOF
[
  {"id": "test-car-1", "event_type": "CarCreated", "event_name": "CarCreated", "__op": "c", "__table": "event_headers"},
  {"id": "test-loan-1", "event_type": "LoanCreated", "event_name": "LoanCreated", "__op": "c", "__table": "event_headers"},
  {"id": "test-payment-1", "event_type": "LoanPaymentSubmitted", "event_name": "LoanPaymentSubmitted", "__op": "c", "__table": "event_headers"},
  {"id": "test-service-1", "event_type": "CarServiceDone", "event_name": "CarServiceDone", "__op": "c", "__table": "event_headers"}
]
EOF

  info "Publishing events to raw-event-headers topic..."
  # Use kafka-console-producer to publish events
  for event in $(jq -c '.[]' "$EVENTS_FILE"); do
    echo "$event" | docker exec -i int-test-kafka kafka-console-producer --bootstrap-server localhost:9092 --topic raw-event-headers
  done

  EVENT_COUNT=$(jq 'length' "$EVENTS_FILE")
  pass "Published $EVENT_COUNT events"
  jq ".events_submitted = $EVENT_COUNT" "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"

  step_end
  echo ""
fi

# Step 6: Wait for Processing
if [ "$SKIP_TO_STEP" -le 6 ]; then
  step_start "Wait for Processing"
  section "Step 6: Wait for Processing"
  echo ""

  info "Waiting ${WAIT_TIME}s for event processing..."
  sleep $WAIT_TIME
  pass "Wait complete"

  step_end
  echo ""
fi

# Step 7: Validate Topics
if [ "$SKIP_TO_STEP" -le 7 ]; then
  step_start "Validate Topics"
  section "Step 7: Validate Topics"
  echo ""

  TOPICS_VALIDATED=0
  TOPICS_TOTAL=4

  # Check each filtered topic
  for topic in filtered-car-created-events-spring filtered-loan-created-events-spring filtered-loan-payment-submitted-events-spring filtered-service-events-spring; do
    info "Checking topic: $topic"
    COUNT=$(docker exec int-test-kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic "$topic" --from-beginning --max-messages 10 --timeout-ms 5000 2>/dev/null | wc -l | tr -d ' ')
    if [ "$COUNT" -gt 0 ]; then
      pass "Topic $topic has $COUNT messages"
      TOPICS_VALIDATED=$((TOPICS_VALIDATED + 1))
    else
      warn "Topic $topic has no messages"
    fi
  done

  if [ $TOPICS_VALIDATED -eq $TOPICS_TOTAL ]; then
    pass "All topics validated"
    jq '.topics_validated = true' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
  else
    warn "Only $TOPICS_VALIDATED/$TOPICS_TOTAL topics validated"
    jq ".topics_validated = $TOPICS_VALIDATED" "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
  fi

  step_end
  echo ""
fi

# Step 8: Validate Consumers
if [ "$SKIP_TO_STEP" -le 8 ]; then
  step_start "Validate Consumers"
  section "Step 8: Validate Consumers"
  echo ""

  CONSUMERS_VALIDATED=0
  CONSUMERS_TOTAL=4

  for consumer in int-test-car-consumer int-test-loan-consumer int-test-loan-payment-consumer int-test-service-consumer; do
    info "Checking consumer: $consumer"
    LOG_COUNT=$(docker logs "$consumer" 2>&1 | grep -cE "(Event|Processing|Consumed)" || echo "0")
    if [ "$LOG_COUNT" -gt 0 ]; then
      pass "$consumer processed events (found $LOG_COUNT event references)"
      CONSUMERS_VALIDATED=$((CONSUMERS_VALIDATED + 1))
    else
      warn "$consumer has no event processing logs"
    fi
  done

  if [ $CONSUMERS_VALIDATED -eq $CONSUMERS_TOTAL ]; then
    pass "All consumers validated"
    jq '.consumers_validated = true' "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
  else
    warn "Only $CONSUMERS_VALIDATED/$CONSUMERS_TOTAL consumers validated"
    jq ".consumers_validated = $CONSUMERS_VALIDATED" "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
  fi

  step_end
  echo ""
fi

# Step 9: Generate Report
step_start "Generate Report"
section "Step 9: Test Report"
echo ""

EVENTS_SUBMITTED=$(jq -r '.events_submitted // 0' "$RESULTS_FILE")
TOPICS_VALIDATED=$(jq -r '.topics_validated // false' "$RESULTS_FILE")
CONSUMERS_VALIDATED=$(jq -r '.consumers_validated // false' "$RESULTS_FILE")

echo "Test Results Summary:"
echo "  Events Submitted: $EVENTS_SUBMITTED"
echo "  Topics Validated: $TOPICS_VALIDATED"
echo "  Consumers Validated: $CONSUMERS_VALIDATED"
echo ""

if [ "$TOPICS_VALIDATED" = "true" ] && [ "$CONSUMERS_VALIDATED" = "true" ]; then
  pass "All validations passed!"
  echo ""
  echo "Pipeline flow verified:"
  echo "  Events → raw-event-headers → Stream Processor → Filtered Topics → Consumers"
  exit 0
else
  fail "Some validations failed"
  exit 1
fi

step_end

