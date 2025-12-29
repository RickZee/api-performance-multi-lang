#!/usr/bin/env bash
# Local Jenkins Pipeline Simulation
# Simulates Jenkins CI/CD pipeline stages locally for testing
#
# Usage:
#   ./cdc-streaming/scripts/jenkins-local-simulate.sh [OPTIONS]
#
# Options:
#   --stage STAGE        Run specific stage only (checkout, build, test, etc.)
#   --test-suite SUITE   Run specific test suite (all, local, schema, breaking)
#   --skip-build         Skip Docker image builds
#   --no-cleanup         Don't clean up containers after tests
#   --verbose            Enable verbose output

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDC_STREAMING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$CDC_STREAMING_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors for Jenkins-like output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Jenkins-like logging functions
jenkins_log() {
    echo -e "${BLUE}[Jenkins]${NC} $1"
}

jenkins_stage() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${BOLD}${CYAN}Stage: $1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

jenkins_step() {
    echo -e "${BLUE}[Step]${NC} $1"
}

jenkins_success() {
    echo -e "${GREEN}✓${NC} $1"
}

jenkins_error() {
    echo -e "${RED}✗${NC} $1"
}

jenkins_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Configuration
STAGE=""
TEST_SUITE="all"
SKIP_BUILD=false
CLEANUP=true
VERBOSE=false
COMPOSE_FILE="$CDC_STREAMING_DIR/docker-compose.integration-test.yml"
E2E_TESTS_DIR="$CDC_STREAMING_DIR/e2e-tests"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%s)}"
WORKSPACE="${WORKSPACE:-$PROJECT_ROOT}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --stage)
            STAGE="$2"
            shift 2
            ;;
        --test-suite)
            TEST_SUITE="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --no-cleanup)
            CLEANUP=false
            shift
            ;;
        --verbose)
            VERBOSE=true
            set -x
            shift
            ;;
        *)
            jenkins_warn "Unknown option: $1"
            shift
            ;;
    esac
done

# Cleanup function
cleanup() {
    if [ "$CLEANUP" = true ]; then
        jenkins_log "Cleaning up Docker containers..."
        cd "$CDC_STREAMING_DIR"
        docker-compose -f "$COMPOSE_FILE" down 2>/dev/null || true
        docker-compose -f "$COMPOSE_FILE" --profile v2 down 2>/dev/null || true
        docker ps -a --filter "name=int-test-" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Stage: Checkout
stage_checkout() {
    jenkins_stage "Checkout"
    jenkins_step "Checking out source code..."
    
    if [ -d "$WORKSPACE/.git" ]; then
        jenkins_success "Source code available at $WORKSPACE"
        GIT_COMMIT=$(cd "$WORKSPACE" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        GIT_BRANCH=$(cd "$WORKSPACE" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        jenkins_log "Commit: $GIT_COMMIT | Branch: $GIT_BRANCH"
    else
        jenkins_warn "Not a git repository, continuing anyway..."
    fi
}

# Stage: Prerequisites
stage_prerequisites() {
    jenkins_stage "Prerequisites"
    jenkins_step "Checking prerequisites..."
    
    MISSING=0
    
    if command -v docker &>/dev/null; then
        DOCKER_VERSION=$(docker --version)
        jenkins_success "Docker: $DOCKER_VERSION"
    else
        jenkins_error "Docker not found"
        MISSING=1
    fi
    
    if command -v docker-compose &>/dev/null || docker compose version &>/dev/null; then
        jenkins_success "Docker Compose: available"
    else
        jenkins_error "Docker Compose not found"
        MISSING=1
    fi
    
    if command -v java &>/dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | head -1)
        jenkins_success "Java: $JAVA_VERSION"
    else
        jenkins_error "Java not found"
        MISSING=1
    fi
    
    if [ -f "$E2E_TESTS_DIR/gradlew" ]; then
        jenkins_success "Gradle wrapper: available"
    else
        jenkins_error "Gradle wrapper not found"
        MISSING=1
    fi
    
    if [ $MISSING -eq 1 ]; then
        jenkins_error "Missing required prerequisites"
        exit 1
    fi
    
    # Check Docker is running
    if ! docker ps &>/dev/null; then
        jenkins_error "Docker daemon is not running"
        exit 1
    fi
    jenkins_success "Docker daemon is running"
}

# Stage: Build Docker Images
stage_build() {
    if [ "$SKIP_BUILD" = true ]; then
        jenkins_stage "Build Docker Images (SKIPPED)"
        jenkins_warn "Skipping Docker image builds (--skip-build)"
        return
    fi
    
    jenkins_stage "Build Docker Images"
    jenkins_step "Building test infrastructure images..."
    
    cd "$CDC_STREAMING_DIR"
    
    jenkins_step "Building mock-confluent-api..."
    docker-compose -f "$COMPOSE_FILE" build mock-confluent-api || {
        jenkins_error "Failed to build mock-confluent-api"
        exit 1
    }
    
    jenkins_step "Building metadata-service..."
    docker-compose -f "$COMPOSE_FILE" build metadata-service || {
        jenkins_error "Failed to build metadata-service"
        exit 1
    }
    
    jenkins_step "Building stream-processor..."
    docker-compose -f "$COMPOSE_FILE" build stream-processor || {
        jenkins_error "Failed to build stream-processor"
        exit 1
    }
    
    jenkins_success "All Docker images built successfully"
}

# Stage: Start Test Infrastructure
stage_start_infrastructure() {
    jenkins_stage "Start Test Infrastructure"
    
    cd "$CDC_STREAMING_DIR"
    
    jenkins_step "Starting Kafka, Schema Registry, and Mock API..."
    docker-compose -f "$COMPOSE_FILE" up -d kafka schema-registry mock-confluent-api || {
        jenkins_error "Failed to start infrastructure services"
        exit 1
    }
    
    jenkins_step "Waiting for Kafka to be healthy..."
    max_wait=60
    elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if docker exec int-test-kafka kafka-topics --bootstrap-server localhost:9092 --list &>/dev/null 2>&1; then
            jenkins_success "Kafka is healthy"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    if [ $elapsed -ge $max_wait ]; then
        jenkins_error "Kafka did not become healthy within ${max_wait}s"
        exit 1
    fi
    
    jenkins_step "Initializing V1 topics..."
    docker-compose -f "$COMPOSE_FILE" up init-topics || {
        jenkins_warn "Topic initialization had issues (continuing anyway)"
    }
    
    jenkins_success "Test infrastructure started successfully"
}

# Stage: Start Services
stage_start_services() {
    jenkins_stage "Start Services"
    
    cd "$CDC_STREAMING_DIR"
    
    jenkins_step "Starting Metadata Service and Stream Processor..."
    docker-compose -f "$COMPOSE_FILE" up -d metadata-service stream-processor || {
        jenkins_error "Failed to start services"
        exit 1
    }
    
    jenkins_step "Waiting for services to be healthy..."
    max_wait=60
    elapsed=0
    metadata_healthy=false
    processor_healthy=false
    
    while [ $elapsed -lt $max_wait ]; do
        if curl -sf http://localhost:8080/api/v1/health &>/dev/null; then
            metadata_healthy=true
        fi
        if curl -sf http://localhost:8083/actuator/health &>/dev/null; then
            processor_healthy=true
        fi
        
        if [ "$metadata_healthy" = true ] && [ "$processor_healthy" = true ]; then
            jenkins_success "All services are healthy"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    if [ "$metadata_healthy" = false ] || [ "$processor_healthy" = false ]; then
        jenkins_warn "Some services may not be fully healthy (continuing anyway)"
    fi
}

# Stage: Run Local Integration Tests
stage_test_local() {
    if [ "$TEST_SUITE" != "all" ] && [ "$TEST_SUITE" != "local" ]; then
        jenkins_stage "Run Local Integration Tests (SKIPPED)"
        jenkins_warn "Skipping local tests (test-suite=$TEST_SUITE)"
        return
    fi
    
    jenkins_stage "Run Local Integration Tests"
    
    cd "$E2E_TESTS_DIR"
    
    jenkins_step "Running LocalKafkaIntegrationTest..."
    ./gradlew test --tests "com.example.e2e.local.LocalKafkaIntegrationTest" --no-daemon || {
        jenkins_warn "LocalKafkaIntegrationTest had failures"
    }
    
    jenkins_step "Running FilterLifecycleLocalTest..."
    ./gradlew test --tests "com.example.e2e.local.FilterLifecycleLocalTest" --no-daemon || {
        jenkins_warn "FilterLifecycleLocalTest had failures"
    }
    
    jenkins_step "Running StreamProcessorLocalTest..."
    ./gradlew test --tests "com.example.e2e.local.StreamProcessorLocalTest" --no-daemon || {
        jenkins_warn "StreamProcessorLocalTest had failures"
    }
    
    jenkins_success "Local integration tests completed"
}

# Stage: Run Schema Evolution Tests
stage_test_schema() {
    if [ "$TEST_SUITE" != "all" ] && [ "$TEST_SUITE" != "schema" ]; then
        jenkins_stage "Run Schema Evolution Tests (SKIPPED)"
        jenkins_warn "Skipping schema tests (test-suite=$TEST_SUITE)"
        return
    fi
    
    jenkins_stage "Run Schema Evolution Tests"
    
    cd "$E2E_TESTS_DIR"
    
    jenkins_step "Running NonBreakingSchemaTest..."
    ./gradlew test --tests "com.example.e2e.schema.NonBreakingSchemaTest" --no-daemon || {
        jenkins_warn "NonBreakingSchemaTest had failures"
    }
    
    jenkins_success "Schema evolution tests completed"
}

# Stage: Run Breaking Schema Tests
stage_test_breaking() {
    if [ "$TEST_SUITE" != "all" ] && [ "$TEST_SUITE" != "breaking" ]; then
        jenkins_stage "Run Breaking Schema Tests (SKIPPED)"
        jenkins_warn "Skipping breaking schema tests (test-suite=$TEST_SUITE)"
        return
    fi
    
    jenkins_stage "Run Breaking Schema Tests (V2)"
    
    cd "$CDC_STREAMING_DIR"
    
    jenkins_step "Starting V2 system..."
    docker-compose -f "$COMPOSE_FILE" --profile v2 build stream-processor-v2 2>/dev/null || true
    docker-compose -f "$COMPOSE_FILE" --profile v2 up -d stream-processor-v2 || {
        jenkins_warn "Failed to start V2 system (continuing anyway)"
    }
    
    jenkins_step "Initializing V2 topics..."
    docker-compose -f "$COMPOSE_FILE" --profile v2 up init-topics-v2 || {
        jenkins_warn "V2 topic initialization had issues (continuing anyway)"
    }
    
    jenkins_step "Waiting for V2 system to be ready..."
    sleep 15
    
    cd "$E2E_TESTS_DIR"
    
    jenkins_step "Running BreakingSchemaChangeTest..."
    ./gradlew test --tests "com.example.e2e.schema.BreakingSchemaChangeTest" --no-daemon || {
        jenkins_warn "BreakingSchemaChangeTest had failures"
    }
    
    jenkins_success "Breaking schema tests completed"
}

# Stage: Generate Test Reports
stage_reports() {
    jenkins_stage "Generate Test Reports"
    
    cd "$E2E_TESTS_DIR"
    
    jenkins_step "Generating test reports..."
    ./gradlew test --no-daemon || true
    
    if [ -f "build/reports/tests/test/index.html" ]; then
        jenkins_success "Test reports generated"
        jenkins_log "Test report: $E2E_TESTS_DIR/build/reports/tests/test/index.html"
    else
        jenkins_warn "Test reports not found"
    fi
    
    # Count test results
    if [ -d "build/test-results/test" ]; then
        TEST_COUNT=$(find build/test-results/test -name "*.xml" | wc -l | tr -d ' ')
        jenkins_log "Found $TEST_COUNT test result files"
    fi
}

# Main execution
main() {
    jenkins_log "=========================================="
    jenkins_log "Jenkins Pipeline Simulation"
    jenkins_log "Build #$BUILD_NUMBER"
    jenkins_log "Workspace: $WORKSPACE"
    jenkins_log "Test Suite: $TEST_SUITE"
    jenkins_log "=========================================="
    echo ""
    
    # Run all stages or specific stage
    if [ -z "$STAGE" ]; then
        stage_checkout
        stage_prerequisites
        stage_build
        stage_start_infrastructure
        stage_start_services
        stage_test_local
        stage_test_schema
        stage_test_breaking
        stage_reports
    else
        case "$STAGE" in
            checkout)
                stage_checkout
                ;;
            prerequisites)
                stage_prerequisites
                ;;
            build)
                stage_build
                ;;
            infrastructure)
                stage_start_infrastructure
                ;;
            services)
                stage_start_services
                ;;
            test-local)
                stage_test_local
                ;;
            test-schema)
                stage_test_schema
                ;;
            test-breaking)
                stage_test_breaking
                ;;
            reports)
                stage_reports
                ;;
            *)
                jenkins_error "Unknown stage: $STAGE"
                echo "Available stages: checkout, prerequisites, build, infrastructure, services, test-local, test-schema, test-breaking, reports"
                exit 1
                ;;
        esac
    fi
    
    echo ""
    jenkins_log "=========================================="
    jenkins_log "Pipeline Simulation Complete"
    jenkins_log "Build #$BUILD_NUMBER"
    jenkins_log "=========================================="
}

# Run main
main

