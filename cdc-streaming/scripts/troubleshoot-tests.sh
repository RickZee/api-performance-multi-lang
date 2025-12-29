#!/usr/bin/env bash
# Test Troubleshooting Script
# Diagnoses common issues when running integration tests

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDC_STREAMING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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

section "Integration Test Troubleshooting"

ISSUES_FOUND=0

# Check Docker
section "Docker Status"
if command -v docker &>/dev/null; then
    if docker ps &>/dev/null; then
        pass "Docker is running"
        CONTAINER_COUNT=$(docker ps --format '{{.Names}}' | grep -c "int-test-" || echo "0")
        if [ "$CONTAINER_COUNT" -gt 0 ]; then
            info "Found $CONTAINER_COUNT test containers running:"
            docker ps --format '  {{.Names}} - {{.Status}}' | grep "int-test-"
        else
            warn "No test containers running"
            info "Start containers with: docker-compose -f docker-compose.integration-test.yml up -d"
        fi
    else
        fail "Docker daemon is not running"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    fail "Docker not installed"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check services
section "Service Health"
SERVICES=(
    "http://localhost:8080/api/v1/health:Metadata Service"
    "http://localhost:8083/actuator/health:Stream Processor"
    "http://localhost:8081/subjects:Schema Registry"
    "http://localhost:8082/health:Mock Confluent API"
)

for service_check in "${SERVICES[@]}"; do
    URL="${service_check%%:*}"
    NAME="${service_check##*:}"
    if curl -sf "$URL" &>/dev/null; then
        pass "$NAME is healthy"
    else
        fail "$NAME is not responding"
        info "  Check: curl $URL"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
done

# Check Kafka
section "Kafka Status"
if docker ps --format '{{.Names}}' | grep -q "int-test-kafka"; then
    pass "Kafka container is running"
    
    if docker exec int-test-kafka kafka-topics --bootstrap-server localhost:9092 --list &>/dev/null 2>&1; then
        pass "Kafka is accessible"
        
        TOPIC_COUNT=$(docker exec int-test-kafka kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | wc -l | tr -d ' ')
        if [ "$TOPIC_COUNT" -gt 0 ]; then
            info "Found $TOPIC_COUNT topics"
            REQUIRED_TOPICS=("raw-event-headers" "filtered-car-created-events-spring" "filtered-loan-created-events-spring")
            for topic in "${REQUIRED_TOPICS[@]}"; do
                if docker exec int-test-kafka kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | grep -q "$topic"; then
                    pass "Topic '$topic' exists"
                else
                    fail "Topic '$topic' not found"
                    info "  Create with: docker-compose -f docker-compose.integration-test.yml up init-topics"
                    ISSUES_FOUND=$((ISSUES_FOUND + 1))
                fi
            done
        else
            warn "No topics found"
            info "Initialize topics: docker-compose -f docker-compose.integration-test.yml up init-topics"
        fi
    else
        fail "Kafka is not accessible"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    fail "Kafka container is not running"
    info "Start with: docker-compose -f docker-compose.integration-test.yml up -d kafka"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check ports
section "Port Availability"
PORTS=(8080 8081 8082 8083 9092)
for port in "${PORTS[@]}"; do
    if lsof -Pi :$port -sTCP:LISTEN -t &>/dev/null; then
        PROCESS=$(lsof -Pi :$port -sTCP:LISTEN -t | head -1 | xargs ps -p 2>/dev/null | tail -1 || echo "unknown")
        if echo "$PROCESS" | grep -q "docker\|kafka\|java"; then
            pass "Port $port is in use (expected)"
        else
            warn "Port $port is in use by: $PROCESS"
        fi
    else
        warn "Port $port is not in use (services may not be running)"
    fi
done

# Check test compilation
section "Test Compilation"
cd "$CDC_STREAMING_DIR/e2e-tests"
if ./gradlew compileTestJava --no-daemon &>/dev/null; then
    pass "Tests compile successfully"
else
    fail "Tests have compilation errors"
    info "Run: cd e2e-tests && ./gradlew compileTestJava --no-daemon"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check test files
section "Test Files"
TEST_CLASSES=(
    "local/LocalKafkaIntegrationTest.java"
    "local/FilterLifecycleLocalTest.java"
    "local/StreamProcessorLocalTest.java"
    "schema/NonBreakingSchemaTest.java"
    "schema/BreakingSchemaChangeTest.java"
)

for test_class in "${TEST_CLASSES[@]}"; do
    if [ -f "src/test/java/com/example/e2e/$test_class" ]; then
        pass "Found: $test_class"
    else
        fail "Missing: $test_class"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
done

# Summary
echo ""
section "Troubleshooting Summary"

if [ $ISSUES_FOUND -eq 0 ]; then
    pass "No issues found! Tests should run successfully."
    echo ""
    info "To run tests:"
    echo "  cd $CDC_STREAMING_DIR/e2e-tests"
    echo "  ./gradlew test --tests 'com.example.e2e.local.*' --tests 'com.example.e2e.schema.*'"
else
    fail "Found $ISSUES_FOUND issue(s)"
    echo ""
    info "Common fixes:"
    echo ""
    echo "1. Start Docker infrastructure:"
    echo "   cd $CDC_STREAMING_DIR"
    echo "   docker-compose -f docker-compose.integration-test.yml up -d kafka schema-registry mock-confluent-api"
    echo ""
    echo "2. Initialize topics:"
    echo "   docker-compose -f docker-compose.integration-test.yml up init-topics"
    echo ""
    echo "3. Start services:"
    echo "   docker-compose -f docker-compose.integration-test.yml up -d metadata-service stream-processor"
    echo ""
    echo "4. Wait for services to be healthy:"
    echo "   sleep 15"
    echo "   curl http://localhost:8080/api/v1/health"
    echo "   curl http://localhost:8083/actuator/health"
    echo ""
    echo "5. Check container logs if issues persist:"
    echo "   docker-compose -f docker-compose.integration-test.yml logs"
fi

exit $ISSUES_FOUND

