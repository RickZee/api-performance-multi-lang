#!/bin/bash

# Lambda API Test Runner
# Runs performance tests against Lambda APIs and collects CloudWatch metrics

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/color-output.sh" 2>/dev/null || true

# Configuration
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAMBDA_CONFIG_FILE="$SCRIPT_DIR/lambda-config.json"
RESULTS_BASE_DIR="$BASE_DIR/load-test/results/lambda-tests"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Test mode: smoke, full, or saturation
TEST_MODE="${1:-smoke}"
API_NAME="${2:-}"  # Optional: specific API to test
PAYLOAD_SIZE="${3:-}"  # Optional: specific payload size
EXECUTION_MODE="${4:-local}"  # local or aws (default: local)

# Function to print section header
print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to collect local Lambda metrics
collect_lambda_local_metrics() {
    local api_name=$1
    local start_time=$2
    local end_time=$3
    
    print_section "Collecting Local Lambda Metrics: $api_name"
    
    # Set up results directory
    local api_results_dir="$RESULTS_BASE_DIR/$api_name"
    mkdir -p "$api_results_dir"
    
    # SAM Local logs are in the log directory
    local log_file="$SCRIPT_DIR/.lambda-logs/${api_name}.log"
    
    if [ ! -f "$log_file" ]; then
        print_warning "Lambda log file not found: $log_file"
        return 1
    fi
    
    # Extract metrics from SAM Local logs
    # SAM Local outputs Lambda REPORT lines similar to CloudWatch
    print_status "Extracting metrics from SAM Local logs..."
    
    # Use analyze-lambda-metrics.py if available
    if [ -f "$SCRIPT_DIR/analyze-lambda-metrics.py" ]; then
        local metrics_file="$api_results_dir/${api_name}-lambda-metrics-${TIMESTAMP}.json"
        
        python3 "$SCRIPT_DIR/analyze-lambda-metrics.py" "$log_file" > "$metrics_file" 2>&1 || {
            print_warning "Failed to analyze Lambda metrics from local logs"
            return 1
        }
        
        print_success "Local Lambda metrics analyzed and saved to: $metrics_file"
    else
        print_warning "analyze-lambda-metrics.py not found, skipping metrics analysis"
    fi
    
    return 0
}

# Function to check prerequisites
check_prerequisites() {
    local execution_mode=$1
    print_section "Checking Prerequisites"
    
    # Check for SAM CLI (required for both modes)
    if ! command -v sam >/dev/null 2>&1; then
        print_error "SAM CLI is not installed. Please install it first."
        exit 1
    fi
    
    # AWS CLI only required for AWS mode
    if [ "$execution_mode" = "aws" ]; then
        if ! command -v aws >/dev/null 2>&1; then
            print_error "AWS CLI is not installed. Required for AWS mode."
            exit 1
        fi
    fi
    
    # Check for k6
    if ! command -v k6 >/dev/null 2>&1 && ! docker ps >/dev/null 2>&1; then
        print_error "k6 is not installed and Docker is not available. Please install k6 or Docker."
        exit 1
    fi
    
    # Check for Python 3
    if ! command -v python3 >/dev/null 2>&1; then
        print_error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check for Lambda config file
    if [ ! -f "$LAMBDA_CONFIG_FILE" ]; then
        print_error "Lambda config file not found: $LAMBDA_CONFIG_FILE"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Function to get Lambda API configuration
get_lambda_config() {
    local api_name=$1
    python3 -c "
import json
import sys
try:
    with open('$LAMBDA_CONFIG_FILE', 'r') as f:
        config = json.load(f)
        api_config = config['apis'].get('$api_name')
        if api_config:
            print(json.dumps(api_config))
        else:
            sys.exit(1)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
}

# Function to get all Lambda API names
get_all_lambda_apis() {
    python3 -c "
import json
import sys
try:
    with open('$LAMBDA_CONFIG_FILE', 'r') as f:
        config = json.load(f)
        apis = list(config['apis'].keys())
        print(' '.join(apis))
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
}

# Function to get API Gateway endpoint
get_api_gateway_endpoint() {
    local env_var=$1
    local api_name=$2
    local execution_mode=$3
    local endpoint=""
    
    if [ "$execution_mode" = "local" ]; then
        # Local mode: get from local config
        local local_config_file="$SCRIPT_DIR/lambda-local-config.json"
        if [ -f "$local_config_file" ]; then
            local port=$(python3 -c "
import json
import sys
try:
    with open('$local_config_file', 'r') as f:
        config = json.load(f)
        print(config['local_execution']['ports'].get('$api_name', 9084))
except:
    print('9084')
")
            # On macOS, Docker can't access localhost via --network host
            # Use host.docker.internal instead
            if [[ "$OSTYPE" == "darwin"* ]]; then
                endpoint="http://host.docker.internal:$port"
            else
                endpoint="http://localhost:$port"
            fi
        else
            # Fallback to default port
            if [[ "$OSTYPE" == "darwin"* ]]; then
                endpoint="http://host.docker.internal:9084"
            else
                endpoint="http://localhost:9084"
            fi
        fi
    else
        # AWS mode: get from environment variable
        endpoint="${!env_var}"
        
        if [ -z "$endpoint" ]; then
            print_warning "API Gateway endpoint not set in environment variable: $env_var"
            print_warning "Please set it before running tests: export $env_var=https://your-api.execute-api.region.amazonaws.com"
            return 1
        fi
    fi
    
    echo "$endpoint"
}

# Function to run k6 test for Lambda API
run_k6_test() {
    local api_name=$1
    local api_config_json=$2
    local api_url=$3
    local test_mode=$4
    local payload_size=$5
    
    print_section "Running k6 Test: $api_name"
    
    # Parse API config
    local test_script=$(echo "$api_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['test_script'])")
    local protocol=$(echo "$api_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['protocol'])")
    
    # Set up results directory
    local api_results_dir="$RESULTS_BASE_DIR/$api_name"
    if [ -n "$payload_size" ] && [ "$payload_size" != "default" ]; then
        api_results_dir="$api_results_dir/$payload_size"
    fi
    mkdir -p "$api_results_dir"
    
    # Set up k6 environment variables
    export TEST_MODE="$test_mode"
    export API_URL="$api_url"
    export LAMBDA_API_URL="$api_url"
    if [ -n "$payload_size" ] && [ "$payload_size" != "default" ]; then
        export PAYLOAD_SIZE="$payload_size"
    fi
    
    # Determine k6 command
    local k6_cmd=""
    if command -v k6 >/dev/null 2>&1; then
        k6_cmd="k6"
    elif docker ps >/dev/null 2>&1; then
        # Use Docker k6
        k6_cmd="docker run --rm -i --network host -v $BASE_DIR:/k6 grafana/k6:latest"
    else
        print_error "k6 is not available"
        return 1
    fi
    
    # Run k6 test
    local json_output_file="$api_results_dir/${api_name}-throughput-${test_mode}-${TIMESTAMP}.json"
    local summary_output_file="$api_results_dir/${api_name}-throughput-${test_mode}-${TIMESTAMP}-summary.txt"
    
    print_status "Running k6 test script: $test_script"
    print_status "API URL: $api_url"
    print_status "Test mode: $test_mode"
    print_status "Payload size: ${payload_size:-default}"
    
    if [ -n "$k6_cmd" ] && [ "$k6_cmd" = "k6" ]; then
        # Local k6
        "$k6_cmd" run \
            --out json="$json_output_file" \
            --env TEST_MODE="$test_mode" \
            --env API_URL="$api_url" \
            --env LAMBDA_API_URL="$api_url" \
            ${payload_size:+--env PAYLOAD_SIZE="$payload_size"} \
            "$BASE_DIR/load-test/k6/$test_script" > "$summary_output_file" 2>&1
    else
        # Docker k6
        # Convert relative paths to absolute paths for Docker mount
        local json_output_file_abs="$BASE_DIR/$json_output_file"
        local test_script_abs="$BASE_DIR/load-test/k6/$test_script"
        
        # Ensure results directory exists
        mkdir -p "$(dirname "$json_output_file_abs")"
        
        # Calculate relative path from BASE_DIR for Docker mount
        local json_output_file_rel="${json_output_file#$BASE_DIR/}"
        if [ "$json_output_file_rel" = "$json_output_file" ]; then
            # If json_output_file doesn't start with BASE_DIR, it's already relative
            json_output_file_rel="$json_output_file"
        fi
        
        # On macOS, use host.docker.internal instead of --network host
        # The api_url already contains the correct hostname (host.docker.internal on macOS, localhost on Linux)
        docker run --rm -i \
            -v "$BASE_DIR:/k6" \
            -e TEST_MODE="$test_mode" \
            -e API_URL="$api_url" \
            -e LAMBDA_API_URL="$api_url" \
            ${payload_size:+-e PAYLOAD_SIZE="$payload_size"} \
            grafana/k6:latest run \
            --out json="/k6/$json_output_file_rel" \
            "/k6/load-test/k6/$test_script" > "$summary_output_file" 2>&1
        local k6_exit_code=$?
        
        # Check if JSON output file was created (indicates test ran successfully)
        # k6 may return non-zero exit code for thresholds, but test still completed
        if [ -f "$json_output_file_abs" ]; then
            k6_exit_code=0
        fi
    fi
    
    if [ ${k6_exit_code:-1} -eq 0 ]; then
        print_success "k6 test completed successfully"
        print_status "Results saved to: $json_output_file"
        return 0
    else
        print_error "k6 test failed"
        return 1
    fi
}

# Function to collect CloudWatch metrics
collect_cloudwatch_metrics() {
    local api_name=$1
    local function_name=$2
    local start_time=$3
    local end_time=$4
    local region="${AWS_REGION:-us-east-1}"
    
    print_section "Collecting CloudWatch Metrics: $function_name"
    
    # Set up results directory
    local api_results_dir="$RESULTS_BASE_DIR/$api_name"
    mkdir -p "$api_results_dir"
    
    # Log group name
    local log_group="/aws/lambda/$function_name"
    
    # Export logs
    local log_file="$api_results_dir/${api_name}-cloudwatch-logs-${TIMESTAMP}.log"
    print_status "Exporting CloudWatch Logs from $log_group..."
    
    aws logs filter-log-events \
        --log-group-name "$log_group" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --region "$region" \
        --output json > "$log_file" 2>&1 || {
        print_warning "Failed to export CloudWatch Logs. Function may not exist or logs may not be available."
        return 1
    }
    
    print_success "CloudWatch Logs exported to: $log_file"
    
    # Analyze Lambda metrics from logs
    if [ -f "$SCRIPT_DIR/analyze-lambda-metrics.py" ]; then
        print_status "Analyzing Lambda metrics from CloudWatch Logs..."
        local metrics_file="$api_results_dir/${api_name}-lambda-metrics-${TIMESTAMP}.json"
        
        python3 "$SCRIPT_DIR/analyze-lambda-metrics.py" "$log_file" > "$metrics_file" 2>&1 || {
            print_warning "Failed to analyze Lambda metrics"
            return 1
        }
        
        print_success "Lambda metrics analyzed and saved to: $metrics_file"
    fi
    
    return 0
}

# Function to run test for a single Lambda API
run_lambda_api_test() {
    local api_name=$1
    local test_mode=$2
    local payload_size=$3
    local execution_mode=$4
    
    print_section "Testing Lambda API: $api_name (Mode: $execution_mode)"
    
    # Get API configuration
    local api_config_json=$(get_lambda_config "$api_name")
    if [ $? -ne 0 ]; then
        print_error "Failed to get configuration for API: $api_name"
        return 1
    fi
    
    # Parse API config
    local protocol=$(echo "$api_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['protocol'])")
    
    # Get API Gateway endpoint
    local endpoint_env_var=$(echo "$api_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['api_gateway_endpoint_env_var'])")
    local api_url=$(get_api_gateway_endpoint "$endpoint_env_var" "$api_name" "$execution_mode")
    if [ $? -ne 0 ]; then
        print_error "API Gateway endpoint not configured for: $api_name"
        return 1
    fi
    
    # Database integration setup
    local db_script_dir="$SCRIPT_DIR"
    local test_run_id=""
    local db_client_path="$db_script_dir/db_client.py"
    
    # Check if database is available and create test run
    if [ -f "$db_client_path" ]; then
        local db_test_output=$(python3 "$db_client_path" test 2>&1)
        if [ $? -eq 0 ]; then
            # Reset pg_stat_statements before test (for full/saturation tests)
            if [ "$test_mode" != "smoke" ]; then
                local db_metrics_script="$db_script_dir/collect-db-metrics.py"
                if [ -f "$db_metrics_script" ]; then
                    print_status "Resetting pg_stat_statements for clean metrics collection..."
                    python3 "$db_metrics_script" reset >/dev/null 2>&1 || print_warning "Failed to reset pg_stat_statements"
                fi
            fi
            
            # Normalize payload_size for database (use 'default' if empty)
            local db_payload_size="${payload_size:-default}"
            
            # Create test run in database
            local create_output=$(python3 "$db_client_path" create_test_run \
                "$api_name" "$test_mode" "$db_payload_size" "$protocol" 2>&1)
            if [ $? -eq 0 ]; then
                test_run_id=$(echo "$create_output" | tail -1)
                print_success "Created test run in database (ID: $test_run_id)"
            else
                print_warning "Failed to create test run record (output: $create_output), continuing without database storage..."
                test_run_id=""
            fi
        else
            print_warning "Database not available (test output: $db_test_output), continuing without database storage..."
            test_run_id=""
        fi
    else
        print_warning "Database client script not found at $db_client_path, continuing without database storage..."
        test_run_id=""
    fi
    
    # Record start time (Unix timestamp in milliseconds)
    local start_time=$(($(date +%s) * 1000))
    
    # Run k6 test
    run_k6_test "$api_name" "$api_config_json" "$api_url" "$test_mode" "$payload_size"
    local test_result=$?
    
    # Record end time
    local end_time=$(($(date +%s) * 1000))
    
    # Get k6 JSON file path for database storage
    local api_results_dir="$RESULTS_BASE_DIR/$api_name"
    if [ -n "$payload_size" ] && [ "$payload_size" != "default" ]; then
        api_results_dir="$api_results_dir/$payload_size"
    fi
    local json_output_file="$api_results_dir/${api_name}-throughput-${test_mode}-${TIMESTAMP}.json"
    
    # Store performance metrics in database
    if [ -n "$test_run_id" ] && [ -f "$json_output_file" ]; then
        print_status "Storing performance metrics in database..."
        local metrics_output=$(python3 "$db_script_dir/extract_k6_metrics.py" "$json_output_file" 2>/dev/null || echo "")
        if [ -n "$metrics_output" ]; then
            IFS='|' read -r total_samples success_samples error_samples duration_seconds throughput avg_response min_response max_response <<< "$metrics_output"
            
            # Calculate error rate
            local error_rate=0.0
            if [ "$total_samples" -gt 0 ] 2>/dev/null; then
                error_rate=$(awk "BEGIN {printf \"%.2f\", ($error_samples / $total_samples) * 100}" 2>/dev/null || echo "0.0")
            fi
            
            # Extract percentiles from JSON if available
            local p50_response="" p90_response="" p95_response="" p99_response=""
            if command -v python3 >/dev/null 2>&1; then
                local percentiles=$(python3 -c "
import json
import sys
try:
    with open('$json_output_file', 'r') as f:
        data = json.load(f)
        metrics = data.get('metrics', {})
        duration_metric = metrics.get('http_req_duration') or metrics.get('grpc_req_duration')
        if duration_metric:
            values = duration_metric.get('values', {})
            p50 = values.get('med', values.get('p(50)', ''))
            p90 = values.get('p(90)', '')
            p95 = values.get('p(95)', '')
            p99 = values.get('p(99)', '')
            print(f'{p50}|{p90}|{p95}|{p99}')
except:
    pass
" 2>/dev/null || echo "|||")
                IFS='|' read -r p50_response p90_response p95_response p99_response <<< "$percentiles"
            fi
            
            # Insert performance metrics directly to database
            if [ -n "$p50_response" ] && [ "$p50_response" != "" ]; then
                python3 "$db_script_dir/db_client.py" insert_performance_metrics \
                    "$test_run_id" \
                    "$total_samples" "$success_samples" "$error_samples" \
                    "$throughput" "$avg_response" "$min_response" "$max_response" \
                    "$p50_response" "$p90_response" "$p95_response" "$p99_response" \
                    "$error_rate" >/dev/null 2>&1 || print_warning "Failed to store performance metrics"
            else
                python3 "$db_script_dir/db_client.py" insert_performance_metrics \
                    "$test_run_id" \
                    "$total_samples" "$success_samples" "$error_samples" \
                    "$throughput" "$avg_response" "$min_response" "$max_response" \
                    "$error_rate" >/dev/null 2>&1 || print_warning "Failed to store performance metrics"
            fi
            
            # Update test run completion
            python3 "$db_script_dir/db_client.py" update_test_run_completion \
                "$test_run_id" "completed" "$duration_seconds" "$json_output_file" >/dev/null 2>&1 || print_warning "Failed to update test run completion"
            
            print_success "Performance metrics stored in database"
        else
            print_warning "Could not extract metrics from JSON file"
        fi
    fi
    
    # Collect and store DB query metrics (for full and saturation tests)
    if [ -n "$test_run_id" ] && [ "$test_mode" != "smoke" ]; then
        print_status "Collecting database query metrics..."
        local db_metrics_script="$db_script_dir/collect-db-metrics.py"
        if [ -f "$db_metrics_script" ]; then
            # Collect DB metrics snapshot
            local db_metrics_file=$(mktemp)
            if python3 "$db_metrics_script" snapshot "$test_run_id" > "$db_metrics_file" 2>/dev/null; then
                # Store in database
                if python3 "$db_script_dir/db_client.py" insert_db_query_metrics "$test_run_id" "$db_metrics_file" >/dev/null 2>&1; then
                    print_success "DB query metrics collected and stored"
                else
                    print_warning "Failed to store DB query metrics in database"
                fi
            else
                print_warning "Failed to collect DB query metrics (pg_stat_statements may not be enabled)"
            fi
            rm -f "$db_metrics_file"
        fi
    fi
    
    # Collect metrics (CloudWatch for AWS, local metrics for local)
    if [ "$execution_mode" = "aws" ]; then
        collect_cloudwatch_metrics "$api_name" "$api_name" "$start_time" "$end_time" || true
    else
        # Local mode: collect from SAM Local logs
        collect_lambda_local_metrics "$api_name" "$start_time" "$end_time" || true
    fi
    
    return $test_result
}

# Main execution
main() {
    print_section "Lambda API Performance Test Runner"
    
    # Determine execution mode
    if [ -z "$EXECUTION_MODE" ]; then
        EXECUTION_MODE="local"
    fi
    
    # Check prerequisites
    check_prerequisites "$EXECUTION_MODE"
    
    # Validate test mode
    if [[ ! "$TEST_MODE" =~ ^(smoke|full|saturation)$ ]]; then
        print_error "Invalid test mode: $TEST_MODE. Must be: smoke, full, or saturation"
        exit 1
    fi
    
    # Get list of APIs to test
    if [ -n "$API_NAME" ]; then
        # Test specific API
        apis=("$API_NAME")
    else
        # Test all APIs
        apis=($(get_all_lambda_apis))
    fi
    
    if [ ${#apis[@]} -eq 0 ]; then
        print_error "No Lambda APIs found to test"
        exit 1
    fi
    
    print_status "Test mode: $TEST_MODE"
    print_status "APIs to test: ${apis[*]}"
    print_status "Payload size: ${payload_size:-all sizes}"
    
    # Determine payload sizes to test
    local payload_sizes=("default")
    if [ -n "$PAYLOAD_SIZE" ]; then
        payload_sizes=("$PAYLOAD_SIZE")
    elif [ "$TEST_MODE" != "smoke" ]; then
        # For full/saturation tests, test multiple payload sizes
        payload_sizes=("4k" "8k" "32k" "64k")
    fi
    
    # Run tests
    local total_tests=$((${#apis[@]} * ${#payload_sizes[@]}))
    local current_test=0
    local failed_tests=0
    
    for api_name in "${apis[@]}"; do
        for payload_size in "${payload_sizes[@]}"; do
            current_test=$((current_test + 1))
            print_progress "$current_test" "$total_tests" "Testing $api_name (${payload_size:-default})"
            
            if ! run_lambda_api_test "$api_name" "$TEST_MODE" "$payload_size" "$EXECUTION_MODE"; then
                failed_tests=$((failed_tests + 1))
                print_error "Test failed for $api_name (${payload_size:-default})"
            fi
        done
    done
    
    # Summary
    print_section "Test Summary"
    print_status "Total tests: $total_tests"
    print_status "Passed: $((total_tests - failed_tests))"
    print_status "Failed: $failed_tests"
    print_status "Results directory: $RESULTS_BASE_DIR"
    
    if [ $failed_tests -gt 0 ]; then
        print_error "Some tests failed"
        exit 1
    else
        print_success "All tests completed successfully"
        exit 0
    fi
}

# Run main function
main "$@"
