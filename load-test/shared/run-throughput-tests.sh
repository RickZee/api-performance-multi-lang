#!/bin/bash

# Throughput Test Runner
# Executes throughput tests for all producer API implementations to determine max throughput and optimal parallelism

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/color-output.sh" 2>/dev/null || true

# Configuration
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_BASE_DIR="$BASE_DIR/results/throughput"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# API configurations
get_api_config() {
    local api_name=$1
    case "$api_name" in
        producer-api)
            echo "producer-throughput/producer-throughput-test.jmx:8081:http"
            ;;
        producer-api-grpc)
            echo "producer-grpc-throughput/producer-grpc-throughput-test.jmx:9090:grpc"
            ;;
        producer-api-rust)
            echo "producer-rust-throughput/producer-rust-throughput-test.jmx:8081:http"
            ;;
        producer-api-rust-grpc)
            echo "producer-rust-grpc-throughput/producer-rust-grpc-throughput-test.jmx:9090:grpc"
            ;;
        *)
            echo ""
            ;;
    esac
}

# API list
APIS="producer-api producer-api-grpc producer-api-rust producer-api-rust-grpc"

# Function to check if service is healthy
check_service_health() {
    local api_name=$1
    local port=$2
    local protocol=$3
    
    print_status "Checking health of $api_name on port $port..."
    
    if [ "$protocol" = "http" ]; then
        if curl -f -s "http://localhost:$port/api/v1/events/health" > /dev/null 2>&1; then
            print_success "$api_name is healthy"
            return 0
        else
            print_warning "$api_name health check failed, but continuing..."
            return 1
        fi
    else
        # For gRPC, just check if port is open
        if nc -z localhost "$port" 2>/dev/null; then
            print_success "$api_name port $port is open"
            return 0
        else
            print_warning "$api_name port $port is not open, but continuing..."
            return 1
        fi
    fi
}

# Function to wait for service to be ready
wait_for_service() {
    local api_name=$1
    local port=$2
    local protocol=$3
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if check_service_health "$api_name" "$port" "$protocol"; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    print_error "$api_name is not ready after $max_attempts attempts"
    return 1
}

# Function to check API logs for event count
check_api_logs() {
    local api_name=$1
    
    print_status "Checking logs for $api_name..."
    cd "$BASE_DIR"
    
    # Get container logs (try different container name patterns)
    local logs=""
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${api_name}$"; then
        logs=$(docker logs "$api_name" 2>&1 | tail -100)
    else
        # Try to find container by name pattern
        local container_name=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -i "$api_name" | head -1)
        if [ -n "$container_name" ]; then
            logs=$(docker logs "$container_name" 2>&1 | tail -100)
        else
            print_warning "Could not find container for $api_name"
            return 1
        fi
    fi
    
    # Extract event count from logs
    # Look for pattern: "*** Persisted events count: XXX ***"
    local event_count=$(echo "$logs" | grep -o "Persisted events count: [0-9]*" | tail -1 | grep -o "[0-9]*" || echo "0")
    
    if [ -n "$event_count" ] && [ "$event_count" != "0" ]; then
        print_success "Found event count in logs: $event_count events processed"
        
        # Show last few log lines with event counts
        local recent_counts=$(echo "$logs" | grep "Persisted events count" | tail -5)
        if [ -n "$recent_counts" ]; then
            print_status "Recent event count logs:"
            echo "$recent_counts" | while read -r line; do
                print_status "  $line"
            done
        fi
        return 0
    else
        print_warning "No event count found in logs for $api_name"
        print_status "Last 20 log lines:"
        echo "$logs" | tail -20 | while read -r line; do
            print_status "  $line"
        done
        return 1
    fi
}

# Function to validate smoke test results
validate_smoke_test_results() {
    local api_name=$1
    local jtl_file=$2
    
    if [ ! -f "$jtl_file" ]; then
        print_error "JTL file not found: $jtl_file"
        return 1
    fi
    
    # Extract metrics from JTL file
    local total_samples=$(awk -F',' 'NR>1 {count++} END {print count}' "$jtl_file" 2>/dev/null || echo "0")
    local success_samples=$(awk -F',' 'NR>1 && $8=="true" {count++} END {print count}' "$jtl_file" 2>/dev/null || echo "0")
    local error_samples=$(awk -F',' 'NR>1 && $8=="false" {count++} END {print count}' "$jtl_file" 2>/dev/null || echo "0")
    
    if [ "$total_samples" -eq "0" ]; then
        print_error "No samples found in test results"
        return 1
    fi
    
    # Calculate error rate
    local error_rate=$(awk -v total="$total_samples" -v errors="$error_samples" 'BEGIN {if (total > 0) printf "%.2f", (errors/total)*100; else printf "100.00"}' 2>/dev/null || echo "100.00")
    local success_rate=$(awk -v total="$total_samples" -v success="$success_samples" 'BEGIN {if (total > 0) printf "%.2f", (success/total)*100; else printf "0.00"}' 2>/dev/null || echo "0.00")
    
    print_status "Smoke test results for $api_name:"
    print_status "  Total samples: $total_samples"
    print_status "  Successful: $success_samples"
    print_status "  Errors: $error_samples"
    print_status "  Error rate: ${error_rate}%"
    print_status "  Success rate: ${success_rate}%"
    
    # Validation criteria: error rate < 5% and success rate > 95%
    local error_check=$(awk -v rate="$error_rate" 'BEGIN {if (rate < 5.0) print "pass"; else print "fail"}' 2>/dev/null || echo "fail")
    local success_check=$(awk -v rate="$success_rate" 'BEGIN {if (rate > 95.0) print "pass"; else print "fail"}' 2>/dev/null || echo "fail")
    
    if [ "$error_check" = "pass" ] && [ "$success_check" = "pass" ]; then
        print_success "Smoke test passed for $api_name"
        return 0
    else
        print_error "Smoke test failed for $api_name (error rate: ${error_rate}%, success rate: ${success_rate}%)"
        return 1
    fi
}

# Function to prepare test plan for smoke test (disable phases 2-8)
prepare_smoke_test_plan() {
    local test_file=$1
    local temp_file="${test_file}.smoke.$$"
    
    # Copy original test plan
    cp "$test_file" "$temp_file"
    
    # Disable phases 2-8, keep only phase 1 (baseline)
    # Phase 1: Baseline (10 threads, 2 min) - keep enabled
    # Phase 2-8: Ramp-up phases - disable for smoke test
    sed -i '' 's/testname="Phase 2: Ramp-up 10 threads" enabled="[^"]*"/testname="Phase 2: Ramp-up 10 threads" enabled="false"/g' "$temp_file"
    sed -i '' 's/testname="Phase 3: Ramp-up 20 threads" enabled="[^"]*"/testname="Phase 3: Ramp-up 20 threads" enabled="false"/g' "$temp_file"
    sed -i '' 's/testname="Phase 4: Ramp-up 50 threads" enabled="[^"]*"/testname="Phase 4: Ramp-up 50 threads" enabled="false"/g' "$temp_file"
    sed -i '' 's/testname="Phase 5: Ramp-up 100 threads" enabled="[^"]*"/testname="Phase 5: Ramp-up 100 threads" enabled="false"/g' "$temp_file"
    sed -i '' 's/testname="Phase 6: Ramp-up 200 threads" enabled="[^"]*"/testname="Phase 6: Ramp-up 200 threads" enabled="false"/g' "$temp_file"
    sed -i '' 's/testname="Phase 7: Ramp-up 500 threads" enabled="[^"]*"/testname="Phase 7: Ramp-up 500 threads" enabled="false"/g' "$temp_file"
    sed -i '' 's/testname="Phase 8: Breaking Point 1000 threads" enabled="[^"]*"/testname="Phase 8: Breaking Point 1000 threads" enabled="false"/g' "$temp_file"
    
    # Also reduce Phase 1 duration for smoke test (from 120s to 30s)
    sed -i '' 's/<stringProp name="ThreadGroup.duration">120<\/stringProp>/<stringProp name="ThreadGroup.duration">30<\/stringProp>/g' "$temp_file" || true
    
    echo "$temp_file"
}

# Function to run throughput test for a single API
run_api_test() {
    local api_name=$1
    local test_file=$2
    local port=$3
    local protocol=$4
    local test_mode=${5:-full}  # full or smoke
    
    print_status "=========================================="
    if [ "$test_mode" = "smoke" ]; then
        print_status "Running SMOKE throughput test for $api_name"
        print_status "=========================================="
    else
        print_status "Running throughput test for $api_name"
        print_status "=========================================="
    fi
    
    # Wait for service to be ready
    wait_for_service "$api_name" "$port" "$protocol" || true
    
    # Create results directory
    RESULT_DIR="$RESULTS_BASE_DIR/$api_name"
    mkdir -p "$RESULT_DIR"
    
    # Generate result file names
    local test_suffix="throughput"
    if [ "$test_mode" = "smoke" ]; then
        test_suffix="throughput-smoke"
    fi
    
    JTL_FILE="$RESULT_DIR/${api_name}-${test_suffix}-${TIMESTAMP}.jtl"
    LOG_FILE="$RESULT_DIR/${api_name}-${test_suffix}-${TIMESTAMP}.log"
    REPORT_DIR="$RESULT_DIR/${api_name}-${test_suffix}-${TIMESTAMP}-report"
    
    # Ensure JMeter container is built
    cd "$BASE_DIR"
    if ! docker-compose ps jmeter-throughput 2>/dev/null | grep -q "jmeter-throughput"; then
        print_status "Building JMeter throughput container..."
        docker-compose --profile throughput-test build jmeter-throughput > /dev/null 2>&1 || true
    fi
    
    # Prepare test file for smoke mode
    local actual_test_file="$BASE_DIR/$test_file"
    local temp_file=""
    if [ "$test_mode" = "smoke" ]; then
        temp_file=$(prepare_smoke_test_plan "$actual_test_file")
        actual_test_file="$temp_file"
        print_status "Smoke test mode: Only Phase 1 (baseline) will run"
    fi
    
    # Convert absolute paths to relative paths for Docker volume mounts
    local test_file_in_container="/jmeter/test-plans/$test_file"
    if [ -n "$temp_file" ]; then
        # For temp files, we need to copy them to a location accessible in the container
        local temp_dir="$BASE_DIR/load-test/temp"
        mkdir -p "$temp_dir"
        local temp_filename=$(basename "$temp_file")
        cp "$temp_file" "$temp_dir/$temp_filename"
        test_file_in_container="/jmeter/test-plans/temp/$temp_filename"
    fi
    
    # Build JMeter command to run in Docker container
    # Use Docker service name for host (accessible via Docker network) or localhost if APIs are on host
    local docker_host="localhost"
    # Try to detect if API is running in Docker
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${api_name}$"; then
        docker_host="$api_name"
    fi
    
    local jmeter_cmd="jmeter -n -t \"$test_file_in_container\""
    jmeter_cmd="$jmeter_cmd -l \"/jmeter/results/throughput/$api_name/$(basename $JTL_FILE)\""
    jmeter_cmd="$jmeter_cmd -j \"/jmeter/results/throughput/$api_name/$(basename $LOG_FILE)\""
    jmeter_cmd="$jmeter_cmd -e -o \"/jmeter/results/throughput/$api_name/$(basename $REPORT_DIR)\""
    jmeter_cmd="$jmeter_cmd -JHOST=$docker_host"
    jmeter_cmd="$jmeter_cmd -JPORT=$port"
    jmeter_cmd="$jmeter_cmd -JRESULTS_DIR=/jmeter/results/throughput"
    
    if [ "$protocol" = "http" ]; then
        jmeter_cmd="$jmeter_cmd -JPROTOCOL=http"
    fi
    
    # Run JMeter test in Docker container
    print_status "Executing JMeter in Docker container..."
    print_status "Command: $jmeter_cmd"
    if [ "$test_mode" = "smoke" ]; then
        print_status "Test duration: ~30 seconds (smoke test - baseline only)"
    else
        print_status "Test duration: ~15-20 minutes (ramp-up phases)"
    fi
    
    # Create results directory in container mount point
    mkdir -p "$BASE_DIR/load-test/results/throughput/$api_name"
    
    # Run JMeter in Docker container
    cd "$BASE_DIR"
    if docker-compose --profile throughput-test run --rm jmeter-throughput sh -c "$jmeter_cmd"; then
        # Move results from container mount to final location
        if [ -f "$BASE_DIR/load-test/results/throughput/$api_name/$(basename $JTL_FILE)" ]; then
            mv "$BASE_DIR/load-test/results/throughput/$api_name/$(basename $JTL_FILE)" "$JTL_FILE"
        fi
        if [ -f "$BASE_DIR/load-test/results/throughput/$api_name/$(basename $LOG_FILE)" ]; then
            mv "$BASE_DIR/load-test/results/throughput/$api_name/$(basename $LOG_FILE)" "$LOG_FILE"
        fi
        if [ -d "$BASE_DIR/load-test/results/throughput/$api_name/$(basename $REPORT_DIR)" ]; then
            mv "$BASE_DIR/load-test/results/throughput/$api_name/$(basename $REPORT_DIR)" "$REPORT_DIR"
        fi
        
        # Clean up temp file if smoke test
        if [ -n "$temp_file" ] && [ -f "$temp_file" ]; then
            rm -f "$temp_file"
            if [ -f "$BASE_DIR/load-test/temp/$(basename $temp_file)" ]; then
                rm -f "$BASE_DIR/load-test/temp/$(basename $temp_file)"
            fi
        fi
    else
        print_error "Test failed for $api_name"
        # Clean up temp file if smoke test
        if [ -n "$temp_file" ] && [ -f "$temp_file" ]; then
            rm -f "$temp_file"
            if [ -f "$BASE_DIR/load-test/temp/$(basename $temp_file)" ]; then
                rm -f "$BASE_DIR/load-test/temp/$(basename $temp_file)"
            fi
        fi
        return 1
    fi
    
    print_success "Test completed for $api_name"
    print_status "Results saved to: $RESULT_DIR"
    print_status "  - JTL: $JTL_FILE"
    print_status "  - Report: $REPORT_DIR"
    echo ""
    
    return 0
}

# Function to run smoke tests for all APIs
run_smoke_tests() {
    print_status "=========================================="
    print_status "Running Smoke Tests (Pre-flight Check)"
    print_status "=========================================="
    echo ""
    
    local smoke_failed_apis=""
    local smoke_timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Create results directory structure
    mkdir -p "$RESULTS_BASE_DIR"
    for api_name in $APIS; do
        mkdir -p "$RESULTS_BASE_DIR/$api_name"
    done
    
    for api_name in $APIS; do
        local api_config=$(get_api_config "$api_name")
        if [ -z "$api_config" ]; then
            print_error "Unknown API: $api_name"
            continue
        fi
        IFS=':' read -r test_file port protocol <<< "$api_config"
        
        local original_timestamp="$TIMESTAMP"
        TIMESTAMP="$smoke_timestamp"
        
        if ! run_api_test "$api_name" "$test_file" "$port" "$protocol" "smoke"; then
            smoke_failed_apis="$smoke_failed_apis $api_name"
            TIMESTAMP="$original_timestamp"
            continue
        fi
        
        # Check API logs for event count
        check_api_logs "$api_name"
        
        # Validate smoke test results
        local jtl_file="$RESULTS_BASE_DIR/$api_name/${api_name}-throughput-smoke-${smoke_timestamp}.jtl"
        if ! validate_smoke_test_results "$api_name" "$jtl_file"; then
            smoke_failed_apis="$smoke_failed_apis $api_name"
        fi
        
        TIMESTAMP="$original_timestamp"
        
        # Small delay between tests
        print_status "Waiting 5 seconds before next smoke test..."
        sleep 5
        echo ""
    done
    
    if [ -n "$smoke_failed_apis" ]; then
        print_error "Smoke tests failed for: $smoke_failed_apis"
        print_error "Cannot proceed with full tests. Please fix the issues and try again."
        return 1
    else
        print_success "All smoke tests passed! Proceeding with full tests..."
        echo ""
        return 0
    fi
}

# Function to run all throughput tests
run_all_tests() {
    local test_mode=${1:-full}  # full or smoke
    
    if [ "$test_mode" = "smoke" ]; then
        print_status "=========================================="
        print_status "Producer API Throughput SMOKE Test Runner"
        print_status "=========================================="
    else
        print_status "=========================================="
        print_status "Producer API Throughput Test Runner"
        print_status "=========================================="
    fi
    echo ""
    
    # If running full tests, run smoke tests first
    if [ "$test_mode" = "full" ]; then
        print_status "Running smoke tests before full tests..."
        if ! run_smoke_tests; then
            print_error "Smoke tests failed. Aborting full test execution."
            exit 1
        fi
        print_status "Starting full throughput tests..."
        echo ""
    fi
    
    # Create results directory structure
    mkdir -p "$RESULTS_BASE_DIR"
    for api_name in $APIS; do
        mkdir -p "$RESULTS_BASE_DIR/$api_name"
    done
    
    # Run tests for each API
    local failed_apis=""
    for api_name in $APIS; do
        local api_config=$(get_api_config "$api_name")
        if [ -z "$api_config" ]; then
            print_error "Unknown API: $api_name"
            continue
        fi
        IFS=':' read -r test_file port protocol <<< "$api_config"
        
        if ! run_api_test "$api_name" "$test_file" "$port" "$protocol" "$test_mode"; then
            failed_apis="$failed_apis $api_name"
        else
            # Check API logs for event count
            check_api_logs "$api_name"
        fi
        
        # Small delay between tests to allow system to stabilize
        if [ "$test_mode" = "smoke" ]; then
            print_status "Waiting 5 seconds before next test..."
            sleep 5
        else
            print_status "Waiting 30 seconds before next test..."
            sleep 30
        fi
    done
    
    # Summary
    echo ""
    print_status "=========================================="
    if [ "$test_mode" = "smoke" ]; then
        print_status "Throughput Smoke Test Summary"
    else
        print_status "Throughput Test Summary"
    fi
    print_status "=========================================="
    
    if [ -z "$failed_apis" ]; then
        print_success "All tests completed successfully!"
    else
        print_warning "Some tests failed:"
        for api in $failed_apis; do
            print_error "  - $api"
        done
    fi
    
    print_status "Results directory: $RESULTS_BASE_DIR"
    if [ "$test_mode" = "smoke" ]; then
        print_status "Smoke tests completed. Run full tests with:"
        print_status "  ./run-throughput-tests.sh"
    else
        print_status "Run analysis script to identify max throughput and optimal parallelism:"
        print_status "  ./analyze-throughput-results.sh"
    fi
    echo ""
}

# Main function
main() {
    local first_arg="${1:-all}"
    local test_mode="full"
    
    # Check if first argument is "smoke"
    if [ "$first_arg" = "smoke" ]; then
        test_mode="smoke"
        first_arg="${2:-all}"
    fi
    
    case "$first_arg" in
        "all")
            run_all_tests "$test_mode"
            ;;
        "producer-api"|"producer-api-grpc"|"producer-api-rust"|"producer-api-rust-grpc")
            local api_config=$(get_api_config "$first_arg")
            if [ -z "$api_config" ]; then
                print_error "Unknown API: $first_arg"
                exit 1
            fi
            IFS=':' read -r test_file port protocol <<< "$api_config"
            run_api_test "$first_arg" "$test_file" "$port" "$protocol" "$test_mode"
            ;;
        "help"|"-h"|"--help")
            echo "Throughput Test Runner"
            echo "====================="
            echo
            echo "Usage: $0 [smoke] [api_name|all|help]"
            echo
            echo "Options:"
            echo "  smoke                Run smoke tests (quick verification, baseline only)"
            echo "  all                  Run throughput tests for all APIs (default)"
            echo "  producer-api         Run test for Spring Boot REST API (port 8081)"
            echo "  producer-api-grpc    Run test for Java gRPC API (port 9090)"
            echo "  producer-api-rust    Run test for Rust REST API (port 8082)"
            echo "  producer-api-rust-grpc  Run test for Rust gRPC API (port 9091)"
            echo "  help                 Show this help message"
            echo
            echo "Examples:"
            echo "  $0                   # Run all full throughput tests (~15-20 min per API)"
            echo "  $0 smoke             # Run smoke tests for all APIs (~30 sec per API)"
            echo "  $0 producer-api      # Run full test for Spring Boot REST API only"
            echo "  $0 smoke producer-api  # Run smoke test for Spring Boot REST API only"
            echo
            echo "Results are saved to: load-test/results/throughput/<api_name>/"
            echo
            echo "After running tests, analyze results:"
            echo "  ./analyze-throughput-results.sh"
            ;;
        *)
            print_error "Unknown option: $first_arg"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"

