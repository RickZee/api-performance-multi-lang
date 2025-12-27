#!/usr/bin/env bash
# Run all new integration tests
# This script starts Docker infrastructure and runs all local and schema tests

set -e

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

COMPOSE_FILE="docker-compose.integration-test.yml"

# Check if Docker is running
if ! docker ps &>/dev/null; then
    fail "Docker is not running. Please start Docker Desktop and try again."
    exit 1
fi

pass "Docker is running"

# Cleanup function
cleanup() {
    info "Cleaning up Docker containers..."
    docker-compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    docker-compose -f "$COMPOSE_FILE" --profile v2 down 2>/dev/null || true
}

trap cleanup EXIT

section "Starting Test Infrastructure"

info "Starting Kafka, Schema Registry, and Mock API..."
docker-compose -f "$COMPOSE_FILE" up -d kafka schema-registry mock-confluent-api

info "Waiting for Kafka to be healthy..."
max_wait=60
elapsed=0
while [ $elapsed -lt $max_wait ]; do
    if docker exec int-test-kafka kafka-topics --bootstrap-server localhost:9092 --list &>/dev/null 2>&1; then
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

info "Initializing topics..."
docker-compose -f "$COMPOSE_FILE" up init-topics

info "Starting Metadata Service and Stream Processor..."
docker-compose -f "$COMPOSE_FILE" build metadata-service stream-processor
docker-compose -f "$COMPOSE_FILE" up -d metadata-service stream-processor

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

section "Running Local Integration Tests"

cd "$CDC_STREAMING_DIR/e2e-tests"

info "Running LocalKafkaIntegrationTest..."
./gradlew test --tests "com.example.e2e.local.LocalKafkaIntegrationTest" --no-daemon || warn "Some LocalKafkaIntegrationTest tests failed"

info "Running FilterLifecycleLocalTest..."
./gradlew test --tests "com.example.e2e.local.FilterLifecycleLocalTest" --no-daemon || warn "Some FilterLifecycleLocalTest tests failed"

info "Running StreamProcessorLocalTest..."
./gradlew test --tests "com.example.e2e.local.StreamProcessorLocalTest" --no-daemon || warn "Some StreamProcessorLocalTest tests failed"

section "Running Schema Evolution Tests"

info "Running NonBreakingSchemaTest..."
./gradlew test --tests "com.example.e2e.schema.NonBreakingSchemaTest" --no-daemon || warn "Some NonBreakingSchemaTest tests failed"

info "Running BreakingSchemaChangeTest (V2 system)..."
# Start V2 system
cd "$CDC_STREAMING_DIR"
docker-compose -f "$COMPOSE_FILE" --profile v2 up -d stream-processor-v2
docker-compose -f "$COMPOSE_FILE" --profile v2 up init-topics-v2

cd "$CDC_STREAMING_DIR/e2e-tests"
./gradlew test --tests "com.example.e2e.schema.BreakingSchemaChangeTest" --no-daemon || warn "Some BreakingSchemaChangeTest tests failed"

section "Test Summary"

info "All tests completed. Check output above for results."
info "To see detailed test results, check: cdc-streaming/e2e-tests/build/reports/tests/test/index.html"

