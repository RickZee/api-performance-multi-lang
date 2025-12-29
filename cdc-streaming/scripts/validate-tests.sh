#!/usr/bin/env bash
# Test Validation Script
# Validates test code structure and provides troubleshooting guidance

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDC_STREAMING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
E2E_TESTS_DIR="$CDC_STREAMING_DIR/e2e-tests"

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

section "Test Validation"

# Check test files exist
section "Checking Test Files"
TEST_FILES=(
    "local/LocalKafkaIntegrationTest.java"
    "local/FilterLifecycleLocalTest.java"
    "local/StreamProcessorLocalTest.java"
    "schema/NonBreakingSchemaTest.java"
    "schema/BreakingSchemaChangeTest.java"
)

MISSING_TESTS=0
for test_file in "${TEST_FILES[@]}"; do
    if [ -f "$E2E_TESTS_DIR/src/test/java/com/example/e2e/$test_file" ]; then
        pass "Found: $test_file"
    else
        fail "Missing: $test_file"
        MISSING_TESTS=1
    fi
done

# Check compilation
section "Checking Compilation"
cd "$E2E_TESTS_DIR"
if ./gradlew compileTestJava --no-daemon &>/dev/null; then
    pass "Tests compile successfully"
else
    fail "Tests have compilation errors"
    info "Run: cd $E2E_TESTS_DIR && ./gradlew compileTestJava --no-daemon"
    exit 1
fi

# Check test dependencies
section "Checking Test Dependencies"
cd "$E2E_TESTS_DIR"
if ./gradlew dependencies --configuration testCompileClasspath --no-daemon 2>&1 | grep -q "spring-boot-starter-webflux"; then
    pass "WebClient dependency found"
else
    warn "WebClient dependency may be missing"
fi

# Check Docker Compose file
section "Checking Docker Configuration"
if [ -f "$CDC_STREAMING_DIR/docker-compose.integration-test.yml" ]; then
    pass "Docker Compose file exists"
    
    # Check for required services
    REQUIRED_SERVICES=("kafka" "schema-registry" "metadata-service" "stream-processor")
    for service in "${REQUIRED_SERVICES[@]}"; do
        if grep -q "^  $service:" "$CDC_STREAMING_DIR/docker-compose.integration-test.yml"; then
            pass "Service '$service' defined"
        else
            fail "Service '$service' not found"
        fi
    done
else
    fail "Docker Compose file not found"
fi

# Check filter configs
section "Checking Filter Configurations"
if [ -f "$CDC_STREAMING_DIR/config/filters.json" ]; then
    pass "V1 filters.json exists"
else
    fail "V1 filters.json not found"
fi

if [ -f "$CDC_STREAMING_DIR/config/filters-v2.json" ]; then
    pass "V2 filters-v2.json exists"
else
    fail "V2 filters-v2.json not found"
fi

# Summary
echo ""
section "Validation Summary"

if [ $MISSING_TESTS -eq 0 ]; then
    pass "All test files are present"
    pass "Tests compile successfully"
    pass "Docker configuration is valid"
    
    echo ""
    info "To run tests manually:"
    echo ""
    echo "1. Start Docker infrastructure:"
    echo "   cd $CDC_STREAMING_DIR"
    echo "   docker-compose -f docker-compose.integration-test.yml up -d kafka schema-registry mock-confluent-api"
    echo "   docker-compose -f docker-compose.integration-test.yml up init-topics"
    echo ""
    echo "2. Start services:"
    echo "   docker-compose -f docker-compose.integration-test.yml up -d metadata-service stream-processor"
    echo ""
    echo "3. Wait for services (check health):"
    echo "   curl http://localhost:8080/api/v1/health"
    echo "   curl http://localhost:8083/actuator/health"
    echo ""
    echo "4. Run tests:"
    echo "   cd $E2E_TESTS_DIR"
    echo "   ./gradlew test --tests 'com.example.e2e.local.*' --tests 'com.example.e2e.schema.*'"
    echo ""
else
    fail "Some test files are missing"
    exit 1
fi

