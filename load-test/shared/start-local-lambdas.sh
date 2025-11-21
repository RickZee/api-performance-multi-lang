#!/bin/bash

# Start Local Lambda Functions
# Starts all Lambda functions locally using SAM Local for testing

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/color-output.sh" 2>/dev/null || true

# Configuration
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAMBDA_CONFIG_FILE="$SCRIPT_DIR/lambda-config.json"
LAMBDA_LOCAL_CONFIG_FILE="$SCRIPT_DIR/lambda-local-config.json"
PID_FILE_DIR="$SCRIPT_DIR/.lambda-pids"
LOG_DIR="$SCRIPT_DIR/.lambda-logs"

# Create directories
mkdir -p "$PID_FILE_DIR"
mkdir -p "$LOG_DIR"

# Function to print section header
print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    # Check for SAM CLI
    if ! command -v sam >/dev/null 2>&1; then
        print_error "SAM CLI is not installed. Please install it first: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html"
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
    
    # Check if Docker network exists
    if ! docker network inspect car_network >/dev/null 2>&1; then
        print_warning "Docker network 'car_network' does not exist. Creating it..."
        docker network create car_network || {
            print_error "Failed to create Docker network"
            exit 1
        }
    fi
    
    # Check if PostgreSQL is running
    if ! docker ps | grep -qE "(postgres-large|car_entities_postgres_large)"; then
        print_warning "PostgreSQL container is not running."
        print_warning "Lambda functions need the database to be running. Starting it..."
        cd "$BASE_DIR"
        docker-compose up -d postgres-large || {
            print_error "Failed to start PostgreSQL"
            exit 1
        }
        # Wait for PostgreSQL to be ready
        echo "Waiting for PostgreSQL to be ready..."
        sleep 5
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

# Function to get local configuration
get_local_config() {
    python3 -c "
import json
import sys
try:
    with open('$LAMBDA_LOCAL_CONFIG_FILE', 'r') as f:
        config = json.load(f)
        print(json.dumps(config))
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
}

# Function to build Lambda function
build_lambda() {
    local api_name=$1
    local api_dir="$BASE_DIR/$api_name"
    
    if [ ! -d "$api_dir" ]; then
        print_error "Lambda API directory not found: $api_dir"
        return 1
    fi
    
    print_status "Building $api_name..."
    
    # Check if build artifacts already exist
    if [ -f "$api_dir/build/bootstrap" ]; then
        print_status "Using existing build artifact for $api_name"
        return 0
    fi
    
    # Check if SAM build artifacts exist
    if [ -d "$api_dir/.aws-sam" ] && [ -f "$api_dir/.aws-sam/build"/*/bootstrap ] 2>/dev/null; then
        print_status "Using existing SAM build for $api_name"
        return 0
    fi
    
    # Try to use SAM build with Docker (no local Go needed)
    print_status "Building $api_name using SAM build (Docker-based, no local Go required)..."
    cd "$api_dir"
    
    # Use SAM build with Docker container - handles Go builds automatically
    sam build --use-container --template sam-template.yaml || {
        # Fallback: Try native build if Go is available
        local go_cmd=""
        if command -v go >/dev/null 2>&1; then
            go_cmd="go"
        elif [ -f "/opt/homebrew/bin/go" ]; then
            go_cmd="/opt/homebrew/bin/go"
            export PATH="/opt/homebrew/bin:$PATH"
        elif [ -f "/usr/local/go/bin/go" ]; then
            go_cmd="/usr/local/go/bin/go"
            export PATH="/usr/local/go/bin:$PATH"
        fi
        
        if [ -n "$go_cmd" ] && [ -f "$api_dir/scripts/build-lambda.sh" ]; then
            print_status "SAM build failed, falling back to native Go build..."
            export PATH="/opt/homebrew/bin:/usr/local/go/bin:$PATH"
            bash scripts/build-lambda.sh || {
                print_error "Failed to build $api_name"
                return 1
            }
        else
            print_error "Failed to build $api_name (SAM build failed and Go not available)"
            return 1
        fi
    }
    
    print_success "Built $api_name successfully"
    
    return 0
}

# Function to start a Lambda function locally
start_lambda_local() {
    local api_name=$1
    local api_config_json=$2
    local local_config_json=$3
    
    print_section "Starting Lambda: $api_name"
    
    # Parse configurations
    local api_dir="$BASE_DIR/$api_name"
    local port=$(echo "$local_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['local_execution']['ports'].get('$api_name', 9084))")
    local db_host=$(echo "$local_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['local_execution']['database_host'])")
    local db_port=$(echo "$local_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['local_execution']['database_port'])")
    local db_name=$(echo "$local_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['local_execution']['database_name'])")
    local db_user=$(echo "$local_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['local_execution']['database_user'])")
    local db_password=$(echo "$local_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['local_execution']['database_password'])")
    local memory_mb=$(echo "$local_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['local_execution']['memory_mb'])")
    local timeout_sec=$(echo "$local_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['local_execution']['timeout_seconds'])")
    local log_level=$(echo "$local_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin)['local_execution']['log_level'])")
    
    # Build database URL
    local database_url="postgresql://${db_user}:${db_password}@${db_host}:${db_port}/${db_name}"
    
    # Check if already running
    local pid_file="$PID_FILE_DIR/${api_name}.pid"
    if [ -f "$pid_file" ]; then
        local old_pid=$(cat "$pid_file")
        if ps -p "$old_pid" > /dev/null 2>&1; then
            print_warning "$api_name is already running (PID: $old_pid)"
            return 0
        else
            rm -f "$pid_file"
        fi
    fi
    
    # Build Lambda function
    if ! build_lambda "$api_name"; then
        print_error "Failed to build $api_name"
        return 1
    fi
    
    # Check if sam-template.yaml exists
    if [ ! -f "$api_dir/sam-template.yaml" ]; then
        print_error "sam-template.yaml not found in $api_dir"
        return 1
    fi
    
    # Start SAM Local
    print_status "Starting SAM Local for $api_name on port $port..."
    print_status "Database URL: postgresql://${db_user}:***@${db_host}:${db_port}/${db_name}"
    
    local log_file="$LOG_DIR/${api_name}.log"
    
    cd "$api_dir"
    
    # Create environment variables file for SAM Local
    local env_file="$SCRIPT_DIR/.lambda-env-${api_name}.json"
    cat > "$env_file" <<EOF
{
  "Parameters": {
    "DatabaseURL": "$database_url",
    "AuroraEndpoint": "",
    "DatabaseName": "$db_name",
    "DatabaseUser": "$db_user",
    "DatabasePassword": "$db_password",
    "LogLevel": "$log_level",
    "VpcId": "",
    "SubnetIds": ""
  }
}
EOF
    
    # Start SAM Local in background
    # Use --parameter-overrides to pass parameters, which will set environment variables via template
    sam local start-api \
        --template sam-template.yaml \
        --port "$port" \
        --host 0.0.0.0 \
        --docker-network car_network \
        --parameter-overrides "DatabaseURL=$database_url" "DatabaseName=$db_name" "DatabaseUser=$db_user" "DatabasePassword=$db_password" "LogLevel=$log_level" \
        --warm-containers EAGER \
        > "$log_file" 2>&1 &
    
    local sam_pid=$!
    echo "$sam_pid" > "$pid_file"
    
    # Wait for SAM Local to start
    print_status "Waiting for $api_name to be ready..."
    local max_wait=30
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if curl -s "http://localhost:$port/api/v1/events/health" > /dev/null 2>&1 || \
           curl -s "http://localhost:$port/health" > /dev/null 2>&1; then
            print_success "$api_name is ready on port $port"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    
    # Check if process is still running
    if ! ps -p "$sam_pid" > /dev/null 2>&1; then
        print_error "$api_name failed to start. Check logs: $log_file"
        rm -f "$pid_file"
        return 1
    fi
    
    print_warning "$api_name may not be fully ready yet, but process is running"
    print_status "Check logs: $log_file"
    return 0
}

# Function to get all Lambda API names
get_all_lambda_apis() {
    # Try to get from system-test-config.json first (respects enabled/disabled)
    local system_config="$SCRIPT_DIR/system-test-config.json"
    if [ -f "$system_config" ]; then
        python3 -c "
import json
import sys
try:
    with open('$system_config', 'r') as f:
        config = json.load(f)
        if config.get('lambda_apis', {}).get('enabled', False):
            apis = config.get('lambda_apis', {}).get('apis', [])
            print(' '.join(apis))
        else:
            print('')
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" && return 0
    fi
    
    # Fallback to lambda-config.json
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

# Main execution
main() {
    print_section "Starting Local Lambda Functions"
    
    # Check prerequisites
    check_prerequisites
    
    # Get local configuration
    local_config_json=$(get_local_config)
    if [ $? -ne 0 ]; then
        print_error "Failed to load local configuration"
        exit 1
    fi
    
    # Get list of APIs to start
    if [ $# -gt 0 ]; then
        # Start specific APIs
        apis=("$@")
    else
        # Start all APIs
        apis=($(get_all_lambda_apis))
    fi
    
    if [ ${#apis[@]} -eq 0 ]; then
        print_error "No Lambda APIs found to start"
        exit 1
    fi
    
    print_status "APIs to start: ${apis[*]}"
    
    # Start each Lambda function
    local started=0
    local failed=0
    
    for api_name in "${apis[@]}"; do
        # Get API configuration
        api_config_json=$(get_lambda_config "$api_name")
        if [ $? -ne 0 ]; then
            print_error "Failed to get configuration for: $api_name"
            failed=$((failed + 1))
            continue
        fi
        
        if start_lambda_local "$api_name" "$api_config_json" "$local_config_json"; then
            started=$((started + 1))
        else
            failed=$((failed + 1))
        fi
    done
    
    # Summary
    print_section "Startup Summary"
    print_status "Started: $started"
    print_status "Failed: $failed"
    print_status "PID files: $PID_FILE_DIR"
    print_status "Log files: $LOG_DIR"
    
    if [ $failed -gt 0 ]; then
        print_error "Some Lambda functions failed to start"
        exit 1
    else
        print_success "All Lambda functions started successfully"
        exit 0
    fi
}

# Run main function
main "$@"

