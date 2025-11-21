#!/bin/bash

# Complete System Test Runner
# Orchestrates testing of both containerized and Lambda APIs

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/color-output.sh" 2>/dev/null || true

# Configuration
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SYSTEM_CONFIG_FILE="$SCRIPT_DIR/system-test-config.json"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Test mode: smoke, full, or saturation
TEST_MODE="${1:-smoke}"
EXECUTION_MODE="${2:-}"  # local or aws (defaults to config file)

# Function to print section header
print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to get configuration value
get_config_value() {
    local key=$1
    python3 -c "
import json
import sys
try:
    with open('$SYSTEM_CONFIG_FILE', 'r') as f:
        config = json.load(f)
        keys = '$key'.split('.')
        value = config
        for k in keys:
            value = value.get(k)
            if value is None:
                break
        if value is not None:
            if isinstance(value, (list, dict)):
                print(json.dumps(value))
            else:
                print(value)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    local execution_mode=$1
    
    # Check for SAM CLI (required for both modes)
    if ! command -v sam >/dev/null 2>&1; then
        print_error "SAM CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check for Docker
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker ps >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check for Python 3
    if ! command -v python3 >/dev/null 2>&1; then
        print_error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    # AWS-specific checks
    if [ "$execution_mode" = "aws" ]; then
        if ! command -v aws >/dev/null 2>&1; then
            print_error "AWS CLI is not installed. Required for AWS mode."
            exit 1
        fi
        
        if ! aws sts get-caller-identity >/dev/null 2>&1; then
            print_error "AWS credentials not configured. Please configure AWS CLI."
            exit 1
        fi
    fi
    
    print_success "All prerequisites met"
}

# Function to ensure database is running
ensure_database_running() {
    print_section "Ensuring Database is Running"
    
    cd "$BASE_DIR"
    
    if docker ps | grep -qE "(postgres-large|car_entities_postgres_large)"; then
        print_success "PostgreSQL is already running"
        return 0
    fi
    
    print_status "Starting PostgreSQL..."
    docker-compose up -d postgres-large || {
        print_error "Failed to start PostgreSQL"
        return 1
    }
    
    # Wait for PostgreSQL to be ready
    print_status "Waiting for PostgreSQL to be ready..."
    local max_wait=30
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if docker exec car_entities_postgres_large pg_isready -U postgres >/dev/null 2>&1 || \
           docker exec postgres-large pg_isready -U postgres >/dev/null 2>&1; then
            print_success "PostgreSQL is ready"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    
    print_error "PostgreSQL failed to become ready"
    return 1
}

# Function to start local Lambda functions
start_local_lambdas() {
    print_section "Starting Local Lambda Functions"
    
    if [ ! -f "$SCRIPT_DIR/start-local-lambdas.sh" ]; then
        print_error "start-local-lambdas.sh not found"
        return 1
    fi
    
    bash "$SCRIPT_DIR/start-local-lambdas.sh" || {
        print_error "Failed to start local Lambda functions"
        return 1
    }
    
    return 0
}

# Function to stop local Lambda functions
stop_local_lambdas() {
    print_section "Stopping Local Lambda Functions"
    
    if [ ! -f "$SCRIPT_DIR/stop-local-lambdas.sh" ]; then
        print_warning "stop-local-lambdas.sh not found, skipping"
        return 0
    fi
    
    bash "$SCRIPT_DIR/stop-local-lambdas.sh" || {
        print_warning "Failed to stop some Lambda functions"
    }
    
    return 0
}

# Function to get Lambda API endpoints (local mode)
get_lambda_endpoints_local() {
    local endpoints_file="$SCRIPT_DIR/.lambda-endpoints.json"
    
    if [ ! -f "$endpoints_file" ]; then
        # Create endpoints file from local config
        python3 -c "
import json
import sys
try:
    with open('$SCRIPT_DIR/lambda-local-config.json', 'r') as f:
        local_config = json.load(f)
    with open('$SCRIPT_DIR/lambda-config.json', 'r') as f:
        lambda_config = json.load(f)
    
    ports = local_config['local_execution']['ports']
    endpoints = {}
    
    for api_name, port in ports.items():
        endpoints[api_name] = f'http://localhost:{port}'
    
    with open('$endpoints_file', 'w') as f:
        json.dump(endpoints, f, indent=2)
    
    print(json.dumps(endpoints))
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
    else
        cat "$endpoints_file"
    fi
}

# Function to run containerized API tests
run_containerized_tests() {
    local test_mode=$1
    local payload_size=$2
    
    print_section "Running Containerized API Tests"
    
    if [ ! -f "$SCRIPT_DIR/run-sequential-throughput-tests.sh" ]; then
        print_error "run-sequential-throughput-tests.sh not found"
        return 1
    fi
    
    # Run containerized tests
    bash "$SCRIPT_DIR/run-sequential-throughput-tests.sh" "$test_mode" "" "$payload_size" || {
        print_error "Containerized API tests failed"
        return 1
    }
    
    return 0
}

# Function to run Lambda API tests
run_lambda_tests() {
    local test_mode=$1
    local payload_size=$2
    local execution_mode=$3
    
    print_section "Running Lambda API Tests"
    
    if [ "$execution_mode" = "local" ]; then
        # Get local endpoints
        local endpoints_json=$(get_lambda_endpoints_local)
        
        # Export endpoints as environment variables
        export LAMBDA_GO_REST_API_URL=$(echo "$endpoints_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('producer-api-go-rest-lambda', 'http://localhost:9084'))")
        export LAMBDA_GO_GRPC_API_URL=$(echo "$endpoints_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('producer-api-go-grpc-lambda', 'http://localhost:9085'))")
        export LAMBDA_JAVA_REST_API_URL=$(echo "$endpoints_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('producer-api-java-rest-lambda', 'http://localhost:9086'))")
        export LAMBDA_JAVA_GRPC_API_URL=$(echo "$endpoints_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('producer-api-java-grpc-lambda', 'http://localhost:9087'))")
        
        print_status "Using local Lambda endpoints:"
        print_status "  Go REST: $LAMBDA_GO_REST_API_URL"
        print_status "  Go gRPC: $LAMBDA_GO_GRPC_API_URL"
        print_status "  Java REST: $LAMBDA_JAVA_REST_API_URL"
        print_status "  Java gRPC: $LAMBDA_JAVA_GRPC_API_URL"
    fi
    
    if [ ! -f "$SCRIPT_DIR/run-lambda-tests.sh" ]; then
        print_error "run-lambda-tests.sh not found"
        return 1
    fi
    
    # Run Lambda tests
    bash "$SCRIPT_DIR/run-lambda-tests.sh" "$test_mode" "" "$payload_size" || {
        print_error "Lambda API tests failed"
        return 1
    }
    
    return 0
}

# Function to generate unified report
generate_unified_report() {
    local test_mode=$1
    local results_dir="$BASE_DIR/load-test/results"
    local output_dir=$(get_config_value "reporting.output_directory" | tr -d '"')
    
    print_section "Generating Unified Report"
    
    if [ ! -f "$SCRIPT_DIR/generate-html-report.py" ]; then
        print_error "generate-html-report.py not found"
        return 1
    fi
    
    # Create output directory
    mkdir -p "$BASE_DIR/$output_dir"
    
    # Generate report
    python3 "$SCRIPT_DIR/generate-html-report.py" "$results_dir" "$test_mode" "$TIMESTAMP" || {
        print_error "Failed to generate unified report"
        return 1
    }
    
    print_success "Unified report generated"
    return 0
}

# Main execution
main() {
    print_section "Complete System Test Runner"
    
    # Validate test mode
    if [[ ! "$TEST_MODE" =~ ^(smoke|full|saturation)$ ]]; then
        print_error "Invalid test mode: $TEST_MODE. Must be: smoke, full, or saturation"
        exit 1
    fi
    
    # Get execution mode from config if not provided
    if [ -z "$EXECUTION_MODE" ]; then
        EXECUTION_MODE=$(get_config_value "execution_mode" | tr -d '"')
    fi
    
    if [ -z "$EXECUTION_MODE" ]; then
        EXECUTION_MODE="local"
    fi
    
    # Validate execution mode
    if [[ ! "$EXECUTION_MODE" =~ ^(local|aws)$ ]]; then
        print_error "Invalid execution mode: $EXECUTION_MODE. Must be: local or aws"
        exit 1
    fi
    
    print_status "Test mode: $TEST_MODE"
    print_status "Execution mode: $EXECUTION_MODE"
    
    # Check prerequisites
    check_prerequisites "$EXECUTION_MODE"
    
    # Get test execution mode
    local test_exec_mode=$(get_config_value "test_execution.mode" | tr -d '"')
    if [ -z "$test_exec_mode" ]; then
        test_exec_mode="sequential"
    fi
    
    # Get enabled APIs
    local lambda_enabled=$(get_config_value "lambda_apis.enabled" | tr -d '"' | tr '[:upper:]' '[:lower:]')
    local containerized_enabled=$(get_config_value "containerized_apis.enabled" | tr -d '"' | tr '[:upper:]' '[:lower:]')
    
    # Ensure database is running
    ensure_database_running
    
    # Configure Lambda for local database (local mode only)
    if [ "$EXECUTION_MODE" = "local" ] && [ "$lambda_enabled" = "true" ]; then
        if [ -f "$SCRIPT_DIR/configure-lambda-local-db.sh" ]; then
            bash "$SCRIPT_DIR/configure-lambda-local-db.sh" || {
                print_warning "Lambda database configuration had issues, continuing..."
            }
        fi
    fi
    
    # Start Lambda functions (local mode)
    if [ "$EXECUTION_MODE" = "local" ] && [ "$lambda_enabled" = "true" ]; then
        start_local_lambdas || {
            print_error "Failed to start local Lambda functions"
            exit 1
        }
    fi
    
    # Determine payload sizes to test
    # For smoke tests, use empty string (default payload)
    # For other tests, test multiple payload sizes
    local payload_sizes=("")
    if [ "$TEST_MODE" != "smoke" ]; then
        payload_sizes=("4k" "8k" "32k" "64k")
    fi
    
    local test_failed=0
    
    # Run tests based on execution mode
    if [ "$test_exec_mode" = "sequential" ]; then
        # Sequential: containerized first, then Lambda
        if [ "$containerized_enabled" = "true" ]; then
            for payload_size in "${payload_sizes[@]}"; do
                if ! run_containerized_tests "$TEST_MODE" "$payload_size"; then
                    test_failed=1
                fi
            done
        fi
        
        if [ "$lambda_enabled" = "true" ]; then
            for payload_size in "${payload_sizes[@]}"; do
                if ! run_lambda_tests "$TEST_MODE" "$payload_size" "$EXECUTION_MODE"; then
                    test_failed=1
                fi
            done
        fi
    elif [ "$test_exec_mode" = "lambda_only" ]; then
        # Lambda only
        if [ "$lambda_enabled" = "true" ]; then
            for payload_size in "${payload_sizes[@]}"; do
                if ! run_lambda_tests "$TEST_MODE" "$payload_size" "$EXECUTION_MODE"; then
                    test_failed=1
                fi
            done
        fi
    elif [ "$test_exec_mode" = "containerized_only" ]; then
        # Containerized only
        if [ "$containerized_enabled" = "true" ]; then
            for payload_size in "${payload_sizes[@]}"; do
                if ! run_containerized_tests "$TEST_MODE" "$payload_size"; then
                    test_failed=1
                fi
            done
        fi
    else
        print_error "Unsupported test execution mode: $test_exec_mode"
        exit 1
    fi
    
    # Generate unified report
    if [ "$(get_config_value "reporting.generate_html" | tr -d '"')" = "true" ]; then
        generate_unified_report "$TEST_MODE" || {
            print_warning "Report generation had issues, but continuing..."
        }
    fi
    
    # Cleanup
    if [ "$(get_config_value "cleanup.stop_services_after_test" | tr -d '"')" = "true" ]; then
        print_section "Cleanup"
        
        if [ "$EXECUTION_MODE" = "local" ] && [ "$lambda_enabled" = "true" ]; then
            stop_local_lambdas
        fi
        
        # Note: Containerized APIs are stopped by their test script
    fi
    
    # Summary
    print_section "Test Summary"
    if [ $test_failed -eq 0 ]; then
        print_success "All tests completed successfully"
        exit 0
    else
        print_error "Some tests failed"
        exit 1
    fi
}

# Run main function
main "$@"

