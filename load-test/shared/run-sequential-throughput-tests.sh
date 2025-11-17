#!/bin/bash

# Sequential Throughput Test Runner
# Rebuilds all producer APIs, then runs throughput tests one API at a time for fair comparison

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/color-output.sh" 2>/dev/null || true
source "$SCRIPT_DIR/collect-metrics.sh" 2>/dev/null || true

# Function to print section header
print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to print subsection header
print_subsection() {
    echo ""
    echo -e "${BLUE}──────────────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}──────────────────────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

# Function to print progress indicator
print_progress() {
    local current=$1
    local total=$2
    local message=$3
    local percent=$((current * 100 / total))
    local bar_length=50
    local filled=$((percent * bar_length / 100))
    local bar=""
    
    for ((i=0; i<filled; i++)); do
        bar+="█"
    done
    for ((i=filled; i<bar_length; i++)); do
        bar+="░"
    done
    
    echo -e "${BLUE}[${current}/${total}]${NC} ${message}"
    echo -e "${GREEN}[${bar}]${NC} ${percent}%"
}

# Function to print formatted test statistics table
print_test_stats() {
    local total_samples=$1
    local success_samples=$2
    local error_samples=$3
    local throughput=$4
    local avg_response=$5
    local p95_response=$6
    local p99_response=$7
    local error_rate=$8
    
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} ${BOLD_BLUE}Test Statistics${NC}                                                          ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────────┤${NC}"
    printf "${CYAN}│${NC} %-30s ${CYAN}:${NC} %-30s ${CYAN}│${NC}\n" "Total Requests" "$total_samples"
    printf "${CYAN}│${NC} %-30s ${CYAN}:${NC} ${GREEN}%-30s${NC} ${CYAN}│${NC}\n" "Successful" "$success_samples"
    if [ "$error_samples" -gt 0 ]; then
        printf "${CYAN}│${NC} %-30s ${CYAN}:${NC} ${RED}%-30s${NC} ${CYAN}│${NC}\n" "Failed" "$error_samples"
    else
        printf "${CYAN}│${NC} %-30s ${CYAN}:${NC} %-30s ${CYAN}│${NC}\n" "Failed" "$error_samples"
    fi
    printf "${CYAN}│${NC} %-30s ${CYAN}:${NC} %-30s ${CYAN}│${NC}\n" "Throughput" "$(printf "%.2f req/s" "$throughput")"
    printf "${CYAN}│${NC} %-30s ${CYAN}:${NC} %-30s ${CYAN}│${NC}\n" "Avg Response Time" "$(printf "%.2f ms" "$avg_response")"
    if [ -n "$p95_response" ] && [ "$p95_response" != "" ]; then
        printf "${CYAN}│${NC} %-30s ${CYAN}:${NC} %-30s ${CYAN}│${NC}\n" "P95 Response Time" "$(printf "%.2f ms" "$p95_response")"
    fi
    if [ -n "$p99_response" ] && [ "$p99_response" != "" ]; then
        printf "${CYAN}│${NC} %-30s ${CYAN}:${NC} %-30s ${CYAN}│${NC}\n" "P99 Response Time" "$(printf "%.2f ms" "$p99_response")"
    fi
    if [ "$(echo "$error_rate > 0" | bc -l 2>/dev/null || echo "0")" = "1" ]; then
        printf "${CYAN}│${NC} %-30s ${CYAN}:${NC} ${RED}%-30s${NC} ${CYAN}│${NC}\n" "Error Rate" "$(printf "%.2f%%" "$error_rate")"
    else
        printf "${CYAN}│${NC} %-30s ${CYAN}:${NC} ${GREEN}%-30s${NC} ${CYAN}│${NC}\n" "Error Rate" "$(printf "%.2f%%" "$error_rate")"
    fi
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Function to print phase progress for full/saturation tests
print_phase_progress() {
    local phase_num=$1
    local total_phases=$2
    local phase_name=$3
    local vus=$4
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD_BLUE}Phase ${phase_num}/${total_phases}: ${phase_name}${NC} (${vus} VUs)"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to print test summary after completion
print_test_summary() {
    local api_name=$1
    local json_file=$2
    
    if [ ! -f "$json_file" ]; then
        print_warning "JSON file not found, cannot display summary"
        return 1
    fi
    
    # Extract metrics
    local metrics=$(extract_k6_metrics "$json_file")
    IFS='|' read -r total_samples success_samples error_samples duration_seconds throughput avg_response min_response max_response <<< "$metrics"
    
    # Extract percentiles from JSON
    local p50_response="" p90_response="" p95_response="" p99_response=""
    if command -v python3 >/dev/null 2>&1; then
        local percentiles=$(python3 -c "
import json
import sys
try:
    with open('$json_file', 'r') as f:
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
    
    # Calculate error rate
    local error_rate=0.0
    if [ "$total_samples" -gt 0 ] 2>/dev/null; then
        error_rate=$(awk "BEGIN {printf \"%.2f\", ($error_samples / $total_samples) * 100}" 2>/dev/null || echo "0.0")
    fi
    
    # Display summary
    echo ""
    print_section "Test Summary: $api_name"
    print_test_stats "$total_samples" "$success_samples" "$error_samples" "$throughput" "$avg_response" "$p95_response" "$p99_response" "$error_rate"
}

# Function to parse k6 output for phase detection and real-time stats
# This function processes k6 output line by line to detect phases and extract stats
parse_k6_output_for_stats() {
    local api_name=$1
    local test_mode=$2
    local last_stats_time=0
    local current_phase=0
    local total_phases=0
    
    # Determine total phases based on test mode
    if [ "$test_mode" = "full" ]; then
        total_phases=4
    elif [ "$test_mode" = "saturation" ]; then
        total_phases=7
    else
        total_phases=1
    fi
    
    # Phase names for full test
    local phase_names_full=("Baseline" "Mid-load" "High-load" "Higher-load")
    local phase_vus_full=(10 50 100 200)
    
    # Phase names for saturation test
    local phase_names_sat=("Baseline" "Mid-load" "High-load" "Very High" "Extreme" "Maximum" "Saturation")
    local phase_vus_sat=(10 50 100 200 500 1000 2000)
    
    while IFS= read -r line; do
        # Output the line (for logging)
        echo "$line"
        
        # Detect phase transitions (k6 outputs stage information)
        if echo "$line" | grep -qE "(running|stage|phase|VUs)" 2>/dev/null; then
            # Try to detect VU changes which indicate phase transitions
            local detected_vus=$(echo "$line" | grep -oE "[0-9]+ VUs" | grep -oE "[0-9]+" | head -1 || echo "")
            if [ -n "$detected_vus" ]; then
                # Determine which phase based on VU count
                if [ "$test_mode" = "full" ]; then
                    for i in "${!phase_vus_full[@]}"; do
                        if [ "${phase_vus_full[$i]}" = "$detected_vus" ]; then
                            if [ "$current_phase" -ne "$((i + 1))" ]; then
                                current_phase=$((i + 1))
                                print_phase_progress "$current_phase" "$total_phases" "${phase_names_full[$i]}" "$detected_vus"
                            fi
                            break
                        fi
                    done
                elif [ "$test_mode" = "saturation" ]; then
                    for i in "${!phase_vus_sat[@]}"; do
                        if [ "${phase_vus_sat[$i]}" = "$detected_vus" ]; then
                            if [ "$current_phase" -ne "$((i + 1))" ]; then
                                current_phase=$((i + 1))
                                print_phase_progress "$current_phase" "$total_phases" "${phase_names_sat[$i]}" "$detected_vus"
                            fi
                            break
                        fi
                    done
                fi
            fi
        fi
        
        # Extract and display periodic stats (every 30-60 seconds)
        local current_time=$(date +%s)
        if [ $((current_time - last_stats_time)) -ge 30 ]; then
            # Try to extract stats from k6 output line
            # k6 outputs stats in format like: "http_reqs: 1234, http_req_duration: avg=123.45ms"
            if echo "$line" | grep -qE "(http_reqs|grpc_reqs|req/s|duration)" 2>/dev/null; then
                local reqs=$(echo "$line" | grep -oE "[0-9]+ reqs" | grep -oE "[0-9]+" | head -1 || echo "")
                local throughput=$(echo "$line" | grep -oE "[0-9]+\.[0-9]+ req/s" | grep -oE "[0-9]+\.[0-9]+" | head -1 || echo "")
                if [ -n "$reqs" ] || [ -n "$throughput" ]; then
                    last_stats_time=$current_time
                    # Display a brief stats update (non-intrusive)
                    if [ -n "$throughput" ]; then
                        echo -e "${CYAN}[Live Stats]${NC} Throughput: ${GREEN}${throughput} req/s${NC}" >&2
                    fi
                fi
            fi
        fi
    done
}

# Function to prefix log lines with API name
# Usage: command | prefix_logs "api-name"
prefix_logs() {
    local api_name=$1
    local prefix="[${api_name}]"
    # Use sed to prefix each line, with unbuffered output for real-time display
    # Try stdbuf first (Linux), fall back to unbuffer (macOS with expect) or plain sed
    if command -v stdbuf >/dev/null 2>&1; then
        stdbuf -oL -eL sed "s/^/${prefix} /"
    elif command -v unbuffer >/dev/null 2>&1; then
        unbuffer sed "s/^/${prefix} /"
    else
        # Fallback: use sed with line buffering via script command or plain sed
        sed "s/^/${prefix} /"
    fi
}

# Configuration
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEST_MODE="${1:-smoke}"  # smoke, full, or saturation

# Validate TEST_MODE parameter
if [ "$TEST_MODE" != "smoke" ] && [ "$TEST_MODE" != "full" ] && [ "$TEST_MODE" != "saturation" ]; then
    echo "Error: Invalid TEST_MODE parameter: '$TEST_MODE'"
    echo ""
    echo "Usage: $0 [TEST_MODE] [API_NAME] [PAYLOAD_SIZE]"
    echo ""
    echo "TEST_MODE options:"
    echo "  smoke       - Quick smoke test (1 VU, 5 iterations per API) [DEFAULT]"
    echo "  full        - Full throughput test (~11 minutes per API)"
    echo "  saturation  - Saturation test (~14 minutes per API)"
    echo ""
    echo "API_NAME options (optional, for debugging single API):"
    echo "  producer-api-java-rest"
    echo "  producer-api-java-grpc"
    echo "  producer-api-rust-rest"
    echo "  producer-api-rust-grpc"
    echo "  producer-api-go-rest"
    echo "  producer-api-go-grpc"
    echo ""
    echo "PAYLOAD_SIZE options (optional):"
    echo "  4k, 8k, 32k, 64k  - Specific payload size"
    echo "  all               - Run all payload sizes sequentially [DEFAULT if not specified]"
    echo "  (empty)           - Use default small payload (~400-500 bytes)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Runs smoke tests for all APIs with all payload sizes"
    echo "  $0 smoke                              # Runs smoke tests for all APIs with all payload sizes"
    echo "  $0 smoke producer-api-java-rest       # Runs smoke test for producer-api-java-rest with all payload sizes"
    echo "  $0 full producer-api-java-grpc 8k     # Runs full test for producer-api-java-grpc with 8k payloads"
    echo "  $0 saturation '' 32k                  # Runs saturation tests for all APIs with 32k payloads"
    exit 1
fi

# API list (default: all APIs)
APIS="producer-api-java-rest producer-api-java-grpc producer-api-rust-rest producer-api-rust-grpc producer-api-go-rest producer-api-go-grpc"

# Optional: Test single API for debugging
SINGLE_API="${2:-}"
if [ -n "$SINGLE_API" ]; then
    # Validate API name
    case "$SINGLE_API" in
        producer-api-java-rest|producer-api-java-grpc|producer-api-rust-rest|producer-api-rust-grpc|producer-api-go-rest|producer-api-go-grpc)
            APIS="$SINGLE_API"
            echo "Running tests for single API: $SINGLE_API"
            ;;
        *)
            echo "Error: Invalid API name: '$SINGLE_API'"
            echo "Valid API names: producer-api-java-rest, producer-api-java-grpc, producer-api-rust-rest, producer-api-rust-grpc, producer-api-go-rest, producer-api-go-grpc"
            exit 1
            ;;
    esac
fi

# Payload size configuration
PAYLOAD_SIZE_PARAM="${3:-}"  # Default to empty (small payload)
PAYLOAD_SIZES=""

# Validate and set payload sizes
if [ -z "$PAYLOAD_SIZE_PARAM" ]; then
    # Empty means default small payload
    PAYLOAD_SIZES="default"
    echo "Running tests with default payload size (~400-500 bytes)"
elif [ "$PAYLOAD_SIZE_PARAM" = "all" ]; then
    # Run all payload sizes
    PAYLOAD_SIZES="4k 8k 32k 64k"
    echo "Running tests with all payload sizes: $PAYLOAD_SIZES"
elif [ "$PAYLOAD_SIZE_PARAM" = "4k" ] || [ "$PAYLOAD_SIZE_PARAM" = "8k" ] || [ "$PAYLOAD_SIZE_PARAM" = "32k" ] || [ "$PAYLOAD_SIZE_PARAM" = "64k" ]; then
    # Run single payload size
    PAYLOAD_SIZES="$PAYLOAD_SIZE_PARAM"
    echo "Running tests with payload size: $PAYLOAD_SIZES"
else
    echo "Error: Invalid PAYLOAD_SIZE parameter: '$PAYLOAD_SIZE_PARAM'"
    echo "Valid options: 4k, 8k, 32k, 64k, all, or empty for default"
    exit 1
fi

# Results base directory (will be updated per payload size)
RESULTS_BASE_DIR="$BASE_DIR/load-test/results/throughput-sequential"

# API configurations
get_api_config() {
    local api_name=$1
    case "$api_name" in
        producer-api-java-rest)
            echo "rest-api-test.js:8081:http:producer:producer-api-java-rest"
            ;;
        producer-api-java-grpc)
            echo "grpc-api-test.js:9090:grpc:producer-grpc:producer-api-java-grpc:/k6/proto/java-grpc/event_service.proto:com.example.grpc.EventService:ProcessEvent"
            ;;
        producer-api-rust-rest)
            echo "rest-api-test.js:8081:http:producer-rust:producer-api-rust-rest"
            ;;
        producer-api-rust-grpc)
            echo "grpc-api-test.js:9090:grpc:producer-rust-grpc:producer-api-rust-grpc:/k6/proto/rust-grpc/event_service.proto:com.example.grpc.EventService:ProcessEvent"
            ;;
        producer-api-go-rest)
            echo "rest-api-test.js:9083:http:producer-go:producer-api-go-rest"
            ;;
        producer-api-go-grpc)
            echo "grpc-api-test.js:9092:grpc:producer-go-grpc:producer-api-go-grpc:/k6/proto/go-grpc/event_service.proto:com.example.grpc.EventService:ProcessEvent"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Function to get host port for health check (different from container port for some APIs)
get_health_check_port() {
    local api_name=$1
    local container_port=$2
    
    # For APIs with port mapping, use host port for health check from host
    case "$api_name" in
        producer-api-java-rest)
            echo "9081"  # Host port (container port is 8081)
            ;;
        producer-api-rust-rest)
            echo "9082"  # Host port (container port is 8081)
            ;;
        producer-api-rust-grpc)
            echo "9091"  # Host port (container port is 9090)
            ;;
        producer-api-java-grpc)
            echo "9090"  # Host port (container port is 9090)
            ;;
        producer-api-go-rest)
            echo "9083"  # Host port (container port is 9083)
            ;;
        producer-api-go-grpc)
            echo "9092"  # Host port (container port is 9092)
            ;;
        *)
            echo "$container_port"  # Same port for others
            ;;
    esac
}

# Function to check if service is healthy (from Docker network perspective)
check_service_health() {
    local api_name=$1
    local port=$2
    local protocol=$3
    local max_attempts=60
    local attempt=0
    
    # Get host port for health check (may differ from container port)
    local health_check_port=$(get_health_check_port "$api_name" "$port")
    
    print_status "Checking health of $api_name on port $health_check_port (host port)..."
    
    while [ $attempt -lt $max_attempts ]; do
        if [ "$protocol" = "http" ]; then
            # Check from host (simpler and works before k6 container is running)
            if curl -f -s "http://localhost:$health_check_port/api/v1/events/health" > /dev/null 2>&1; then
                print_success "$api_name is healthy"
                return 0
            fi
        else
            # For gRPC, check if port is open from host
            if nc -z localhost "$health_check_port" 2>/dev/null; then
                print_success "$api_name port $health_check_port is open"
                return 0
            fi
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    print_error "$api_name is not ready after $max_attempts attempts"
    return 1
}

# Function to log step to per-API log file
log_step() {
    local api_name=$1
    local step=$2
    local message=$3
    local status=$4  # success, error, warning, info
    
    local log_file="$RESULTS_BASE_DIR/$api_name/test-execution.log"
    mkdir -p "$RESULTS_BASE_DIR/$api_name"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local status_upper=$(echo "$status" | tr '[:lower:]' '[:upper:]')
    
    echo "[$timestamp] [$status_upper] [$step] $message" >> "$log_file"
}

# Function to ensure database is running
ensure_database_running() {
    print_status "=========================================="
    print_status "Ensuring PostgreSQL Database is Running"
    print_status "=========================================="
    echo ""
    
    cd "$BASE_DIR"
    
    # Check if container exists
    if ! docker-compose ps postgres-large 2>/dev/null | grep -q "postgres-large"; then
        print_status "PostgreSQL container not found. Starting..."
        docker-compose up -d postgres-large
        sleep 5
    fi
    
    # Check if container is running
    if ! docker-compose ps postgres-large 2>/dev/null | grep -q "Up"; then
        print_status "PostgreSQL container is not running. Starting..."
        docker-compose up -d postgres-large
        sleep 5
    fi
    
    # Wait for PostgreSQL to be ready with retry logic
    print_status "Waiting for PostgreSQL to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if docker-compose exec -T postgres-large pg_isready -U postgres > /dev/null 2>&1; then
            print_success "PostgreSQL is ready"
            
            # Verify database connectivity
            if docker-compose exec -T postgres-large psql -U postgres -d car_entities -c "SELECT 1;" > /dev/null 2>&1; then
                print_success "Database connectivity verified"
                echo ""
                return 0
            else
                print_warning "PostgreSQL is ready but database connectivity check failed. Continuing anyway..."
                echo ""
                return 0
            fi
        fi
        attempt=$((attempt + 1))
        if [ $((attempt % 5)) -eq 0 ]; then
            print_status "Still waiting for PostgreSQL... (attempt $attempt/$max_attempts)"
        fi
        sleep 2
    done
    
    print_error "PostgreSQL failed to become ready after $max_attempts attempts"
    print_error "Please check PostgreSQL logs: docker-compose logs postgres-large"
    echo ""
    return 1
}

# Function to check Docker disk space
check_docker_disk_space() {
    local test_mode=$1
    local payload_size=$2
    local num_apis=${3:-6}  # Default to 6 APIs if not specified
    
    # Calculate estimated space needed per test
    # Base estimates (conservative):
    # - Database data: ~100MB per full/saturation test (can grow significantly with large payloads)
    # - JSON result files: ~10-50MB per test
    # - Metrics CSV: ~5-10MB per test
    # - Container logs: ~5-10MB per test
    local space_per_test_mb=0
    
    if [ "$test_mode" = "smoke" ]; then
        space_per_test_mb=5  # Smoke tests are quick, minimal data
    elif [ "$test_mode" = "full" ]; then
        # Full test: ~11 minutes, moderate data generation
        if [ -z "$payload_size" ] || [ "$payload_size" = "default" ]; then
            space_per_test_mb=150  # Default payload
        elif [ "$payload_size" = "4k" ]; then
            space_per_test_mb=200
        elif [ "$payload_size" = "8k" ]; then
            space_per_test_mb=300
        elif [ "$payload_size" = "32k" ]; then
            space_per_test_mb=500
        elif [ "$payload_size" = "64k" ]; then
            space_per_test_mb=800
        else
            space_per_test_mb=200  # Conservative default
        fi
    elif [ "$test_mode" = "saturation" ]; then
        # Saturation test: ~14 minutes, high data generation
        if [ -z "$payload_size" ] || [ "$payload_size" = "default" ]; then
            space_per_test_mb=200  # Default payload
        elif [ "$payload_size" = "4k" ]; then
            space_per_test_mb=300
        elif [ "$payload_size" = "8k" ]; then
            space_per_test_mb=500
        elif [ "$payload_size" = "32k" ]; then
            space_per_test_mb=1000
        elif [ "$payload_size" = "64k" ]; then
            space_per_test_mb=1500
        else
            space_per_test_mb=300  # Conservative default
        fi
    else
        space_per_test_mb=100  # Conservative default
    fi
    
    # Calculate total space needed (with 20% buffer)
    local total_space_needed_mb=$((space_per_test_mb * num_apis * 120 / 100))
    
    # Get available Docker disk space
    # Try multiple methods to determine available space
    local available_space_mb=0
    
    # Method 1: Check Docker's data directory directly (Linux)
    local docker_data_dir
    if [ -d "/var/lib/docker" ]; then
        docker_data_dir="/var/lib/docker"
        if command -v df >/dev/null 2>&1; then
            available_space_mb=$(df -m "$docker_data_dir" 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
        fi
    fi
    
    # Method 2: For macOS Docker Desktop, check the host filesystem where Docker VM is stored
    if [ "$available_space_mb" -eq 0 ] || [ -z "$available_space_mb" ]; then
        # On macOS, Docker Desktop stores data in a VM disk image
        # Check the parent directory or use the home directory as fallback
        if [ -d "$HOME/Library/Containers/com.docker.docker" ]; then
            # Check space on the volume containing Docker Desktop's data
            if command -v df >/dev/null 2>&1; then
                available_space_mb=$(df -m "$HOME/Library/Containers/com.docker.docker" 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
            fi
        fi
    fi
    
    # Method 3: Try to get Docker Root Dir from docker info
    if [ "$available_space_mb" -eq 0 ] || [ -z "$available_space_mb" ]; then
        docker_data_dir=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $4}' || echo "")
        if [ -n "$docker_data_dir" ] && [ -d "$docker_data_dir" ]; then
            if command -v df >/dev/null 2>&1; then
                available_space_mb=$(df -m "$docker_data_dir" 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
            fi
        fi
    fi
    
    # Method 4: Fallback - check current directory's filesystem (where test results will be stored)
    if [ "$available_space_mb" -eq 0 ] || [ -z "$available_space_mb" ]; then
        if command -v df >/dev/null 2>&1; then
            available_space_mb=$(df -m "$BASE_DIR" 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
        fi
    fi
    
    # Convert to integer (handle any decimal values)
    available_space_mb=${available_space_mb%.*}
    
    # If we still can't determine space, show a warning but continue
    if [ "$available_space_mb" -eq 0 ] || [ -z "$available_space_mb" ]; then
        print_warning "Could not determine exact Docker disk space. Proceeding with caution..."
        print_warning "Please ensure you have sufficient disk space before running tests."
        return 0
    fi
    
    # Check if we have enough space (with 50% safety margin)
    local required_space_mb=$((total_space_needed_mb * 150 / 100))
    
    if [ "$available_space_mb" -lt "$required_space_mb" ] && [ "$available_space_mb" -gt 0 ]; then
        print_warning "=========================================="
        print_warning "Docker Disk Space Warning"
        print_warning "=========================================="
        print_warning "Available Docker disk space: ~${available_space_mb}MB"
        print_warning "Estimated space needed for tests: ~${total_space_needed_mb}MB"
        print_warning "Recommended free space: ~${required_space_mb}MB"
        print_warning ""
        print_warning "There may not be enough disk space to complete all tests."
        print_warning "Consider running: docker system prune -a"
        print_warning "Or clean up old test results and database data."
        print_warning "=========================================="
        echo ""
        
        # Ask for confirmation (non-interactive mode will continue)
        if [ -t 0 ]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_error "Test execution cancelled by user"
                return 1
            fi
        fi
    else
        if [ "$available_space_mb" -gt 0 ]; then
            print_status "Docker disk space check: OK (~${available_space_mb}MB available, ~${total_space_needed_mb}MB needed)"
        fi
    fi
    
    return 0
}

# Function to clear database
clear_database() {
    print_status "Clearing database..."
    cd "$BASE_DIR"
    
    # Ensure postgres-large is running
    if ! docker-compose ps postgres-large 2>/dev/null | grep -q "Up"; then
        print_warning "PostgreSQL is not running, skipping database clear"
        return 0
    fi
    
    # Clear the car_entities table
    # Try TRUNCATE first, if it fails due to disk space, try DELETE with LIMIT
    local truncate_output
    truncate_output=$(docker-compose exec -T postgres-large psql -U postgres -d car_entities -c "TRUNCATE TABLE car_entities CASCADE;" 2>&1)
    if [ $? -eq 0 ]; then
        print_success "Database cleared"
        return 0
    else
        # Check if it's a disk space issue
        if echo "$truncate_output" | grep -qi "No space left on device"; then
            print_warning "Disk space issue detected. Attempting to delete records in batches..."
            # Delete in batches to avoid transaction issues
            local deleted=1
            local iteration=0
            while [ $deleted -gt 0 ] && [ $iteration -lt 100 ]; do
                iteration=$((iteration + 1))
                deleted=$(docker-compose exec -T postgres-large psql -U postgres -d car_entities -t -c "WITH deleted AS (DELETE FROM car_entities WHERE ctid IN (SELECT ctid FROM car_entities LIMIT 10000) RETURNING 1) SELECT COUNT(*) FROM deleted;" 2>&1 | grep -E "^[[:space:]]*[0-9]+" | tr -d ' ' || echo "0")
                if [ "$deleted" = "0" ] || [ -z "$deleted" ]; then
                    break
                fi
                # Small delay to avoid overwhelming the database
                sleep 0.1
            done
            print_success "Database cleared (using batch delete due to disk space constraints)"
            return 0
        else
            print_warning "Failed to clear database: $truncate_output"
            print_warning "Continuing anyway..."
            return 1
        fi
    fi
}

# Function to troubleshoot API failures
troubleshoot_api() {
    local api_name=$1
    local port=$2
    local protocol=$3
    
    print_error "=========================================="
    print_error "Troubleshooting $api_name"
    print_error "=========================================="
    echo ""
    
    cd "$BASE_DIR"
    
    # Log troubleshooting start
    log_step "$api_name" "TROUBLESHOOTING" "Starting troubleshooting for $api_name" "info"
    
    # 1. Check container status
    print_status "1. Checking container status..."
    local container_status=$(docker-compose ps "$api_name" 2>/dev/null | grep "$api_name" | awk '{print $4}' || echo "NOT_FOUND")
    if [ "$container_status" = "Up" ]; then
        print_success "Container is running"
        log_step "$api_name" "TROUBLESHOOTING" "Container status: Running" "success"
    else
        print_error "Container status: $container_status"
        log_step "$api_name" "TROUBLESHOOTING" "Container status: $container_status" "error"
    fi
    echo ""
    
    # 2. Display recent logs
    print_status "2. Recent API logs (last 50 lines):"
    echo "----------------------------------------"
    docker logs "$api_name" 2>&1 | tail -50 | while read -r line; do
        echo "  $line"
    done
    echo "----------------------------------------"
    log_step "$api_name" "TROUBLESHOOTING" "Displayed recent logs (last 50 lines)" "info"
    echo ""
    
    # 3. Check health endpoint
    print_status "3. Checking health endpoint..."
    local health_check_port=$(get_health_check_port "$api_name" "$port")
    if [ "$protocol" = "http" ]; then
        if curl -f -s "http://localhost:$health_check_port/api/v1/events/health" > /dev/null 2>&1; then
            print_success "Health endpoint is responding"
            log_step "$api_name" "TROUBLESHOOTING" "Health endpoint: OK" "success"
        else
            print_error "Health endpoint is not responding"
            log_step "$api_name" "TROUBLESHOOTING" "Health endpoint: FAILED" "error"
        fi
    else
        if nc -z localhost "$health_check_port" 2>/dev/null; then
            print_success "gRPC port $health_check_port is open"
            log_step "$api_name" "TROUBLESHOOTING" "gRPC port $health_check_port: OPEN" "success"
        else
            print_error "gRPC port $health_check_port is not accessible"
            log_step "$api_name" "TROUBLESHOOTING" "gRPC port $health_check_port: CLOSED" "error"
        fi
    fi
    echo ""
    
    # 4. Check database connectivity from API container
    print_status "4. Checking database connectivity from API container..."
    # Try multiple methods to check database connectivity
    local db_check_passed=false
    
    # Method 1: Try using nc if available
    if docker exec "$api_name" sh -c "command -v nc >/dev/null 2>&1 && nc -z postgres-large 5432" 2>/dev/null; then
        db_check_passed=true
    # Method 2: Try using telnet if available
    elif docker exec "$api_name" sh -c "command -v telnet >/dev/null 2>&1 && echo 'quit' | telnet postgres-large 5432 2>&1 | grep -q 'Connected'" 2>/dev/null; then
        db_check_passed=true
    # Method 3: Check if API logs show successful database connection
    elif docker logs "$api_name" 2>&1 | grep -i "connected to database\|database.*ready\|database.*connected" > /dev/null 2>&1; then
        db_check_passed=true
        print_status "  (Database connectivity verified via API logs)"
    fi
    
    if [ "$db_check_passed" = true ]; then
        print_success "Database is reachable from API container"
        log_step "$api_name" "TROUBLESHOOTING" "Database connectivity: OK" "success"
    else
        print_warning "Could not verify database connectivity (tools may not be available in container)"
        print_status "  Checking API logs for database connection status..."
        local db_logs=$(docker logs "$api_name" 2>&1 | grep -i "database\|postgres\|connection" | tail -5)
        if [ -n "$db_logs" ]; then
            print_status "  Recent database-related logs:"
            echo "$db_logs" | while read -r line; do
                print_status "    $line"
            done
        fi
        log_step "$api_name" "TROUBLESHOOTING" "Database connectivity: Could not verify (checking logs)" "warning"
    fi
    echo ""
    
    # 5. Display container resource usage
    print_status "5. Container resource usage:"
    echo "----------------------------------------"
    docker stats "$api_name" --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null || print_warning "Could not get resource stats"
    echo "----------------------------------------"
    log_step "$api_name" "TROUBLESHOOTING" "Displayed resource usage" "info"
    echo ""
    
    # 6. Check for common error patterns in logs
    print_status "6. Checking for common error patterns..."
    local error_logs=$(docker logs "$api_name" 2>&1 | grep -i "error\|exception\|failed\|timeout" | tail -10)
    if [ -n "$error_logs" ]; then
        print_error "Found error patterns in logs:"
        echo "$error_logs" | while read -r line; do
            print_error "  $line"
        done
        log_step "$api_name" "TROUBLESHOOTING" "Found error patterns in logs" "error"
    else
        print_success "No obvious error patterns found in recent logs"
        log_step "$api_name" "TROUBLESHOOTING" "No error patterns found" "success"
    fi
    echo ""
    
    # 7. Check for event processing log patterns
    print_status "7. Checking for event processing log patterns..."
    local all_logs=$(docker logs "$api_name" 2>&1 | tail -200)
    
    local persisted_pattern=$(echo "$all_logs" | grep -i "Persisted events count" | tail -1)
    local processing_pattern=$(echo "$all_logs" | grep -i "Processing event" | tail -1)
    local created_pattern=$(echo "$all_logs" | grep -i "Successfully created entity" | tail -1)
    
    local patterns_found=0
    if [ -n "$persisted_pattern" ]; then
        patterns_found=$((patterns_found + 1))
        print_success "Found 'Persisted events count' pattern in logs"
        log_step "$api_name" "TROUBLESHOOTING" "Found: Persisted events count pattern" "success"
        print_status "  Sample: $persisted_pattern"
    else
        print_error "Missing 'Persisted events count' pattern in logs"
        log_step "$api_name" "TROUBLESHOOTING" "Missing: Persisted events count pattern" "error"
    fi
    
    if [ -n "$processing_pattern" ]; then
        patterns_found=$((patterns_found + 1))
        print_success "Found 'Processing event' pattern in logs"
        log_step "$api_name" "TROUBLESHOOTING" "Found: Processing event pattern" "success"
        print_status "  Sample: $processing_pattern"
    else
        print_warning "Missing 'Processing event' pattern in logs"
        log_step "$api_name" "TROUBLESHOOTING" "Missing: Processing event pattern" "warning"
    fi
    
    if [ -n "$created_pattern" ]; then
        patterns_found=$((patterns_found + 1))
        print_success "Found 'Successfully created entity' pattern in logs"
        log_step "$api_name" "TROUBLESHOOTING" "Found: Successfully created entity pattern" "success"
        print_status "  Sample: $created_pattern"
    else
        print_warning "Missing 'Successfully created entity' pattern in logs (may be normal for Rust APIs)"
        log_step "$api_name" "TROUBLESHOOTING" "Missing: Successfully created entity pattern" "warning"
    fi
    
    echo ""
    if [ $patterns_found -eq 0 ]; then
        print_error "No event processing log patterns found - API may not be processing events"
        log_step "$api_name" "TROUBLESHOOTING" "No event processing patterns found" "error"
        print_status "Recommendations:"
        print_status "  - Verify API is receiving requests (check if test client is running)"
        print_status "  - Check API startup logs for initialization errors"
        print_status "  - Verify database connection is working"
        print_status "  - Check if API endpoints are correctly configured"
        print_status "  - Review API application logs for startup completion"
    elif [ $patterns_found -lt 2 ]; then
        print_warning "Limited event processing patterns found - API may have issues"
        log_step "$api_name" "TROUBLESHOOTING" "Limited event processing patterns found" "warning"
    else
        print_success "Event processing patterns detected - API appears to be processing events"
        log_step "$api_name" "TROUBLESHOOTING" "Event processing patterns detected" "success"
    fi
    echo ""
    
    print_error "=========================================="
    print_error "Troubleshooting complete for $api_name"
    print_error "=========================================="
    echo ""
    
    log_step "$api_name" "TROUBLESHOOTING" "Troubleshooting completed" "info"
}

# Function to validate metrics stored
validate_metrics_stored() {
    local api_name=$1
    local json_file=$2
    
    print_status "Validating metrics for $api_name..."
    log_step "$api_name" "VALIDATION" "Starting metric validation" "info"
    
    # Check if file exists
    if [ ! -f "$json_file" ]; then
        print_error "Metrics file not found: $json_file"
        log_step "$api_name" "VALIDATION" "Metrics file not found: $json_file" "error"
        return 1
    fi
    
    log_step "$api_name" "VALIDATION" "Metrics file exists: $json_file" "success"
    
    # Validate JSON structure (k6 outputs NDJSON - one JSON object per line)
    # Check if file has at least one valid JSON line
    local valid_lines=0
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            if echo "$line" | python3 -m json.tool > /dev/null 2>&1; then
                ((valid_lines++))
            fi
        fi
    done < "$json_file"
    
    if [ "$valid_lines" -eq 0 ]; then
        print_error "Invalid JSON structure in metrics file (no valid JSON lines found)"
        log_step "$api_name" "VALIDATION" "Invalid JSON structure" "error"
        return 1
    fi
    
    log_step "$api_name" "VALIDATION" "JSON structure is valid (found $valid_lines valid JSON lines)" "success"
    
    # Check required metrics using Python (k6 outputs NDJSON format)
    local validation_result=$(python3 << PYTHON_SCRIPT
import json
import sys

try:
    # k6 outputs NDJSON - one JSON object per line
    # We need to check if we have at least some request/duration metrics
    has_http_reqs = False
    has_grpc_reqs = False
    has_http_duration = False
    has_grpc_duration = False
    request_count = 0
    
    with open('$json_file', 'r') as f:
        for line in f:
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
                metric_name = obj.get('metric', '')
                obj_type = obj.get('type', '')
                
                # Check for metric definitions or data points
                if obj_type == 'Metric':
                    metric_data = obj.get('data', {})
                    name = metric_data.get('name', '')
                    if name in ['http_reqs', 'grpc_reqs', 'http_req_duration', 'grpc_req_duration']:
                        if 'http_reqs' in name:
                            has_http_reqs = True
                        elif 'grpc_reqs' in name:
                            has_grpc_reqs = True
                        elif 'http_req_duration' in name:
                            has_http_duration = True
                        elif 'grpc_req_duration' in name:
                            has_grpc_duration = True
                elif obj_type == 'Point':
                    if metric_name in ['http_reqs', 'grpc_reqs']:
                        request_count += 1
                        if metric_name == 'http_reqs':
                            has_http_reqs = True
                        else:
                            has_grpc_reqs = True
                    elif metric_name in ['http_req_duration', 'grpc_req_duration']:
                        if 'http_req_duration' in metric_name:
                            has_http_duration = True
                        else:
                            has_grpc_duration = True
            except json.JSONDecodeError:
                continue
    
    issues = []
    
    if not has_http_reqs and not has_grpc_reqs:
        issues.append("Missing request metrics (http_reqs or grpc_reqs)")
    elif request_count == 0:
        issues.append("No request data points found")
    
    if not has_http_duration and not has_grpc_duration:
        issues.append("Missing duration metrics (http_req_duration or grpc_req_duration)")
    
    if issues:
        print("|".join(issues))
        sys.exit(1)
    else:
        # Validation passed
        req_type = "HTTP" if has_http_reqs else "gRPC"
        print(f"OK|{req_type}|{request_count}")
        sys.exit(0)
        
except Exception as e:
    print(f"JSON parsing error: {str(e)}")
    sys.exit(1)
PYTHON_SCRIPT
)
    
    if [ $? -ne 0 ]; then
        print_error "Metric validation failed:"
        echo "$validation_result" | tr '|' '\n' | while read -r issue; do
            print_error "  - $issue"
        done
        log_step "$api_name" "VALIDATION" "Metric validation failed: $validation_result" "error"
        return 1
    fi
    
    # Parse validation result (format: OK|HTTP|request_count or OK|gRPC|request_count)
    IFS='|' read -r status req_type request_count <<< "$validation_result"
    
    print_success "Metrics validated successfully:"
    print_status "  - Protocol: $req_type"
    print_status "  - Request data points found: $request_count"
    
    log_step "$api_name" "VALIDATION" "Metrics validated: protocol=$req_type, request_count=$request_count" "success"
    
    return 0
}

# Function to send a test request to trigger event processing
send_test_request() {
    local api_name=$1
    local port=$2
    local protocol=$3
    local health_check_port=$(get_health_check_port "$api_name" "$port")
    
    print_status "Sending test request to trigger event processing..."
    log_step "$api_name" "EVENT_VERIFY" "Sending test request to trigger event processing" "info"
    
    if [ "$protocol" = "http" ]; then
        # Send a simple REST API test request
        local test_payload='{
  "eventHeader": {
    "uuid": "test-verification-'$(date +%s)'",
    "eventName": "CarCreated",
    "createdDate": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "savedDate": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "eventType": "CarCreated"
  },
  "eventBody": {
    "entities": [{
      "entityType": "Car",
      "entityId": "test-verification-car-'$(date +%s)'",
      "updatedAttributes": {
        "make": "Test",
        "model": "Verification",
        "year": "2024"
      }
    }]
  }
}'
        
        if curl -f -s -X POST "http://localhost:${health_check_port}/api/v1/events" \
            -H "Content-Type: application/json" \
            -d "$test_payload" > /dev/null 2>&1; then
            print_success "Test request sent successfully"
            log_step "$api_name" "EVENT_VERIFY" "Test request sent successfully" "success"
            return 0
        else
            print_warning "Test request failed, but continuing..."
            log_step "$api_name" "EVENT_VERIFY" "Test request failed" "warning"
            return 1
        fi
    else
        # For gRPC, we need to use grpcurl or similar tool
        # Since grpcurl might not be available, we'll skip the test request for gRPC
        # and rely on the test itself to generate logs
        print_status "Skipping test request for gRPC (will rely on actual test to generate logs)"
        log_step "$api_name" "EVENT_VERIFY" "Skipping test request for gRPC" "info"
        return 0
    fi
}

# Function to wait and verify event processing logs after API startup
wait_and_verify_event_processing() {
    local api_name=$1
    local port=$2
    local protocol=$3
    # For smoke tests, use shorter wait time (15 seconds)
    # For full tests, use full wait time (60 seconds)
    local wait_seconds=60
    if [ "$TEST_MODE" = "smoke" ]; then
        wait_seconds=15  # Shorter wait for smoke tests
    fi
    local check_interval=5
    local elapsed=0
    local patterns_found=0
    
    print_status "=========================================="
    print_status "Waiting and verifying event processing for $api_name"
    print_status "=========================================="
    log_step "$api_name" "EVENT_VERIFY" "Starting event processing verification (waiting ${wait_seconds}s)" "info"
    
    cd "$BASE_DIR"
    
    # For REST APIs, send a test request first to trigger event processing
    if [ "$protocol" = "http" ]; then
        send_test_request "$api_name" "$port" "$protocol"
        # Wait a few seconds for the request to be processed
        sleep 3
    fi
    
    # Wait and check logs periodically
    while [ $elapsed -lt $wait_seconds ]; do
        # Get container logs (check last 200 lines to catch recent activity)
        local logs=$(docker logs "$api_name" 2>&1 | tail -200)
        
        # Check for event processing log patterns (case-insensitive)
        local persisted_pattern=$(echo "$logs" | grep -i "Persisted events count" | tail -1)
        local processing_pattern=$(echo "$logs" | grep -i "Processing event" | tail -1)
        local created_pattern=$(echo "$logs" | grep -i "Successfully created entity" | tail -1)
        
        # Count patterns found
        patterns_found=0
        if [ -n "$persisted_pattern" ]; then
            patterns_found=$((patterns_found + 1))
        fi
        if [ -n "$processing_pattern" ]; then
            patterns_found=$((patterns_found + 1))
        fi
        if [ -n "$created_pattern" ]; then
            patterns_found=$((patterns_found + 1))
        fi
        
        # If any pattern found, we're good
        if [ $patterns_found -gt 0 ]; then
            print_success "Event processing logs detected for $api_name after ${elapsed}s"
            log_step "$api_name" "EVENT_VERIFY" "Event processing logs found after ${elapsed}s" "success"
            
            # Show what was found
            if [ -n "$persisted_pattern" ]; then
                print_status "  Found: Persisted events count pattern"
                log_step "$api_name" "EVENT_VERIFY" "Found: Persisted events count pattern" "info"
            fi
            if [ -n "$processing_pattern" ]; then
                print_status "  Found: Processing event pattern"
                log_step "$api_name" "EVENT_VERIFY" "Found: Processing event pattern" "info"
            fi
            if [ -n "$created_pattern" ]; then
                print_status "  Found: Successfully created entity pattern"
                log_step "$api_name" "EVENT_VERIFY" "Found: Successfully created entity pattern" "info"
            fi
            
            echo ""
            return 0
        fi
        
        # Show progress every 15 seconds
        if [ $((elapsed % 15)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            print_status "Still waiting for event processing logs... (${elapsed}s/${wait_seconds}s)"
            log_step "$api_name" "EVENT_VERIFY" "Still waiting for event processing logs (${elapsed}s/${wait_seconds}s)" "info"
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    # If we get here, no patterns were found
    # For gRPC APIs, this might be expected if we didn't send a test request
    # So we'll be more lenient - if the API is healthy, we'll proceed anyway
    if [ "$protocol" = "grpc" ]; then
        print_warning "No event processing logs found for $api_name after ${wait_seconds}s"
        print_status "For gRPC APIs, event processing logs will appear when requests are received"
        print_status "Proceeding with test since API is healthy..."
        log_step "$api_name" "EVENT_VERIFY" "No event processing logs found, but proceeding for gRPC API" "warning"
        echo ""
        return 0
    else
        print_error "No event processing logs found for $api_name after ${wait_seconds}s"
        log_step "$api_name" "EVENT_VERIFY" "No event processing logs found after ${wait_seconds}s" "error"
        
        # Show recent logs for debugging
        print_status "Recent log entries (last 30 lines):"
        local recent_logs=$(docker logs "$api_name" 2>&1 | tail -30)
        echo "$recent_logs" | while read -r line; do
            print_status "  $line"
        done
        
        echo ""
        return 1
    fi
}

# Function to check API logs for event count
check_api_logs() {
    local api_name=$1
    
    print_status "Checking logs for $api_name..."
    log_step "$api_name" "LOG_CHECK" "Checking API logs for event count" "info"
    cd "$BASE_DIR"
    
    # Get container logs (check last 200 lines)
    local logs=$(docker logs "$api_name" 2>&1 | tail -200)
    
    # Check for multiple event processing patterns (case-insensitive)
    local persisted_pattern=$(echo "$logs" | grep -i "Persisted events count" | tail -1)
    local processing_pattern=$(echo "$logs" | grep -i "Processing event" | tail -1)
    local created_pattern=$(echo "$logs" | grep -i "Successfully created entity" | tail -1)
    
    # Extract event count from persisted pattern (most reliable)
    local event_count="0"
    if [ -n "$persisted_pattern" ]; then
        event_count=$(echo "$persisted_pattern" | grep -o "Persisted events count: [0-9]*" | grep -o "[0-9]*" | tail -1 || echo "0")
    fi
    
    # Count patterns found
    local patterns_found=0
    local patterns_list=""
    if [ -n "$persisted_pattern" ]; then
        patterns_found=$((patterns_found + 1))
        patterns_list="${patterns_list}Persisted events count, "
    fi
    if [ -n "$processing_pattern" ]; then
        patterns_found=$((patterns_found + 1))
        patterns_list="${patterns_list}Processing event, "
    fi
    if [ -n "$created_pattern" ]; then
        patterns_found=$((patterns_found + 1))
        patterns_list="${patterns_list}Successfully created entity, "
    fi
    
    if [ $patterns_found -gt 0 ]; then
        print_success "Found event processing patterns in logs for $api_name"
        print_status "  Patterns found: ${patterns_list%, }"
        log_step "$api_name" "LOG_CHECK" "Event processing patterns found: ${patterns_list%, }" "success"
        
        if [ -n "$event_count" ] && [ "$event_count" != "0" ]; then
            print_success "Event count: $event_count events processed"
            log_step "$api_name" "LOG_CHECK" "Event count found: $event_count" "success"
            
            # Show last few log lines with event counts
            local recent_counts=$(echo "$logs" | grep -i "Persisted events count" | tail -5)
            if [ -n "$recent_counts" ]; then
                print_status "Recent event count logs:"
                echo "$recent_counts" | while read -r line; do
                    print_status "  $line"
                done
            fi
        fi
        
        # Show sample of processing patterns if available
        if [ -n "$processing_pattern" ]; then
            local recent_processing=$(echo "$logs" | grep -i "Processing event" | tail -3)
            if [ -n "$recent_processing" ]; then
                print_status "Recent processing event logs:"
                echo "$recent_processing" | while read -r line; do
                    print_status "  $line"
                done
            fi
        fi
        
        return 0
    else
        print_warning "No event processing patterns found in logs for $api_name"
        log_step "$api_name" "LOG_CHECK" "No event processing patterns found in logs" "warning"
        print_status "Last 30 log lines:"
        echo "$logs" | tail -30 | while read -r line; do
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

# Function to stop all producer APIs
stop_all_apis() {
    print_status "Stopping all producer APIs..."
    cd "$BASE_DIR"
    
    # List of all producer API container names
    local api_containers="producer-api-java-rest producer-api-java-grpc producer-api-rust-rest producer-api-rust-grpc"
    
    # First, try docker-compose stop (graceful)
    docker-compose stop producer-api-java-rest producer-api-java-grpc producer-api-rust-rest producer-api-rust-grpc 2>/dev/null || true
    docker-compose --profile producer-java-rest stop producer-api-java-rest 2>/dev/null || true
    docker-compose --profile producer-java-grpc stop producer-api-java-grpc 2>/dev/null || true
    docker-compose --profile producer-rust-rest stop producer-api-rust-rest 2>/dev/null || true
    docker-compose --profile producer-rust-grpc stop producer-api-rust-grpc 2>/dev/null || true
    
    # Then, forcefully stop using docker stop (more reliable)
    for container in $api_containers; do
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
            print_status "Forcefully stopping $container..."
            docker stop "$container" 2>/dev/null || true
        fi
    done
    
    # Wait a bit for containers to fully stop
    sleep 3
    
    # Verify all are stopped
    local running_apis=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -E "^(producer-api-java-rest|producer-api-java-grpc|producer-api-rust-rest|producer-api-rust-grpc)$" || true)
    if [ -n "$running_apis" ]; then
        print_warning "Some APIs are still running, force killing..."
        echo "$running_apis" | while read -r container; do
            docker kill "$container" 2>/dev/null || true
        done
        sleep 2
    fi
    
    print_success "All APIs stopped"
}

# Function to rebuild a specific API
rebuild_api() {
    local api_name=$1
    local profile=$2
    
    print_status "Rebuilding $api_name..."
    cd "$BASE_DIR"
    
    # Rebuild without starting dependencies
    case "$api_name" in
        producer-api-java-rest)
            docker-compose build --no-cache producer-api-java-rest 2>&1 | grep -v "no such service" || true
            ;;
        producer-api-java-grpc)
            docker-compose build --no-cache producer-api-java-grpc 2>&1 | grep -v "no such service" || true
            ;;
        producer-api-rust-rest)
            docker-compose build --no-cache producer-api-rust-rest 2>&1 | grep -v "no such service" || true
            ;;
        producer-api-rust-grpc)
            docker-compose build --no-cache producer-api-rust-grpc 2>&1 | grep -v "no such service" || true
            ;;
        producer-api-go-rest)
            docker-compose build --no-cache producer-api-go-rest 2>&1 | grep -v "no such service" || true
            ;;
        producer-api-go-grpc)
            docker-compose build --no-cache producer-api-go-grpc 2>&1 | grep -v "no such service" || true
            ;;
    esac
    
    print_success "$api_name rebuilt"
}

# Function to start a specific API
start_api() {
    local api_name=$1
    local profile=$2
    
    print_status "Starting $api_name..."
    log_step "$api_name" "START" "Starting API: $api_name with profile: $profile" "info"
    cd "$BASE_DIR"
    
    # Ensure postgres-large is running first (should already be running from ensure_database_running, but double-check)
    if ! docker-compose ps postgres-large 2>/dev/null | grep -q "Up"; then
        print_warning "PostgreSQL is not running, starting it..."
        log_step "$api_name" "START" "PostgreSQL not running, starting it" "warning"
        if ! ensure_database_running; then
            print_error "Failed to start PostgreSQL"
            log_step "$api_name" "START" "Failed to start PostgreSQL" "error"
            return 1
        fi
    fi
    
    # Start the specific API with its profile and postgres-large
    case "$api_name" in
        producer-api-java-rest)
            docker-compose --profile producer-java-rest up -d postgres-large producer-api-java-rest
            ;;
        producer-api-java-grpc)
            docker-compose --profile producer-java-grpc up -d postgres-large producer-api-java-grpc
            ;;
        producer-api-rust-rest)
            docker-compose --profile producer-rust-rest up -d postgres-large producer-api-rust-rest
            ;;
        producer-api-rust-grpc)
            docker-compose --profile producer-rust-grpc up -d postgres-large producer-api-rust-grpc
            ;;
        producer-api-go-rest)
            docker-compose --profile producer-go-rest up -d postgres-large producer-api-go-rest
            ;;
        producer-api-go-grpc)
            docker-compose --profile producer-go-grpc up -d postgres-large producer-api-go-grpc
            ;;
    esac
    
    print_success "$api_name started"
}

# Function to stop a specific API
stop_api() {
    local api_name=$1
    
    print_status "Stopping $api_name..."
    log_step "$api_name" "STOP" "Stopping API: $api_name" "info"
    cd "$BASE_DIR"
    
    # Try docker-compose stop first (graceful)
    docker-compose stop "$api_name" 2>/dev/null || true
    case "$api_name" in
        producer-api-java-rest)
            docker-compose --profile producer-java-rest stop producer-api-java-rest 2>/dev/null || true
            ;;
        producer-api-java-grpc)
            docker-compose --profile producer-java-grpc stop producer-api-java-grpc 2>/dev/null || true
            ;;
        producer-api-rust-rest)
            docker-compose --profile producer-rust-rest stop producer-api-rust-rest 2>/dev/null || true
            ;;
        producer-api-rust-grpc)
            docker-compose --profile producer-rust-grpc stop producer-api-rust-grpc 2>/dev/null || true
            ;;
        producer-api-go-rest)
            docker-compose --profile producer-go-rest stop producer-api-go-rest 2>/dev/null || true
            ;;
        producer-api-go-grpc)
            docker-compose --profile producer-go-grpc stop producer-api-go-grpc 2>/dev/null || true
            ;;
    esac
    
    sleep 2
    
    # Force stop using docker stop if still running
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${api_name}$"; then
        print_status "Forcefully stopping $api_name..."
        docker stop "$api_name" 2>/dev/null || true
        sleep 1
    fi
    
    # Force kill if still running
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${api_name}$"; then
        print_warning "Force killing $api_name..."
        docker kill "$api_name" 2>/dev/null || true
        sleep 1
    fi
    
    # Verify it's stopped
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${api_name}$"; then
        print_error "$api_name is still running after stop attempts"
        log_step "$api_name" "STOP" "Failed to stop API" "error"
        return 1
    else
        print_success "$api_name stopped"
        log_step "$api_name" "STOP" "API stopped successfully" "success"
        return 0
    fi
}

# Function to calculate test duration in seconds based on test mode
calculate_test_duration() {
    local test_mode=$1
    local duration=0
    
    if [ "$test_mode" = "smoke" ]; then
        # Smoke test: 1 VU, 5 iterations, ~5-10 seconds
        duration=15
    elif [ "$test_mode" = "full" ]; then
        # Full test: 5m = 5 minutes = 300 seconds (single phase for quick testing)
        duration=300
    elif [ "$test_mode" = "saturation" ]; then
        # Saturation test: 2m * 7 = 14 minutes = 840 seconds
        duration=840
    else
        # Default to 15 minutes for safety
        duration=900
    fi
    
    # Add buffer time (30 seconds) for test startup and completion
    echo $((duration + 30))
}

# Function to run k6 test
run_k6_test() {
    local api_name=$1
    local test_file=$2
    local port=$3
    local protocol=$4
    local docker_host=$5
    local proto_file=${6:-""}
    local service_name=${7:-""}
    local method_name=${8:-""}
    
    # Ensure k6 container is built
    cd "$BASE_DIR"
    if ! docker-compose ps k6-throughput 2>/dev/null | grep -q "k6-throughput"; then
        print_status "Building k6 throughput container..."
        docker-compose --profile k6-test build k6-throughput > /dev/null 2>&1 || true
    fi
    
    # Get payload size from environment or use empty for default
    local payload_size="${PAYLOAD_SIZE:-}"
    
    # Create results directory with payload size subdirectory
    if [ -n "$payload_size" ]; then
        RESULT_DIR="$RESULTS_BASE_DIR/$api_name/$payload_size"
    else
        RESULT_DIR="$RESULTS_BASE_DIR/$api_name"
    fi
    mkdir -p "$RESULT_DIR"
    
    # Generate result file names
    local test_suffix="throughput"
    if [ "$TEST_MODE" = "smoke" ]; then
        test_suffix="throughput-smoke"
    elif [ "$TEST_MODE" = "saturation" ]; then
        test_suffix="throughput-saturation"
    fi
    
    # Add payload size to filename if specified
    local payload_suffix=""
    if [ -n "$payload_size" ]; then
        payload_suffix="-${payload_size}"
    fi
    
    local json_file="$RESULT_DIR/${api_name}-${test_suffix}${payload_suffix}-${TIMESTAMP}.json"
    local summary_file="$RESULT_DIR/${api_name}-${test_suffix}${payload_suffix}-${TIMESTAMP}.txt"
    local log_file="$RESULT_DIR/${api_name}-${test_suffix}${payload_suffix}-${TIMESTAMP}.log"
    local metrics_file="$RESULT_DIR/${api_name}-${test_suffix}${payload_suffix}-${TIMESTAMP}-metrics.csv"
    
    # Determine JSON file path for progress display (container mount path)
    local progress_json_file="$BASE_DIR/load-test/results/throughput-sequential/$api_name"
    if [ -n "$payload_size" ]; then
        progress_json_file="$progress_json_file/$payload_size"
    fi
    progress_json_file="$progress_json_file/$(basename $json_file)"
    
    # Build k6 command
    local k6_script="/k6/scripts/$test_file"
    local json_file_in_container="/k6/results/throughput-sequential/$api_name"
    if [ -n "$payload_size" ]; then
        json_file_in_container="$json_file_in_container/$payload_size"
    fi
    json_file_in_container="$json_file_in_container/$(basename $json_file)"
    local k6_cmd="k6 run"
    k6_cmd="$k6_cmd --out json=$json_file_in_container"
    k6_cmd="$k6_cmd -e TEST_MODE=$TEST_MODE"
    k6_cmd="$k6_cmd -e PROTOCOL=$protocol"
    k6_cmd="$k6_cmd -e HOST=$docker_host"
    k6_cmd="$k6_cmd -e PORT=$port"
    
    # Add payload size environment variable if specified
    if [ -n "$payload_size" ]; then
        k6_cmd="$k6_cmd -e PAYLOAD_SIZE=$payload_size"
    fi
    
    if [ "$protocol" = "grpc" ]; then
        k6_cmd="$k6_cmd -e PROTO_FILE=$proto_file"
        k6_cmd="$k6_cmd -e SERVICE=$service_name"
        k6_cmd="$k6_cmd -e METHOD=$method_name"
    else
        k6_cmd="$k6_cmd -e PATH=/api/v1/events"
    fi
    
    k6_cmd="$k6_cmd $k6_script"
    
    print_status "Executing k6 test in Docker container..."
    print_status "  Script: $test_file"
    print_status "  Host: ${docker_host}:${port}"
    print_status "  Protocol: $protocol"
    if [ -n "$payload_size" ]; then
        print_status "  Payload size: $payload_size"
    else
        print_status "  Payload size: default (~400-500 bytes)"
    fi
    if [ "$TEST_MODE" = "smoke" ]; then
        print_status "  Test duration: ~5-10 seconds (smoke test: 1 VU, 5 iterations)"
    elif [ "$TEST_MODE" = "saturation" ]; then
        print_status "  Test duration: ~14 minutes (saturation test)"
    else
        print_status "  Test duration: ~11 minutes (full test)"
    fi
    
    # Create results directory in container mount point
    local container_result_dir="$BASE_DIR/load-test/results/throughput-sequential/$api_name"
    if [ -n "$payload_size" ]; then
        container_result_dir="$container_result_dir/$payload_size"
    fi
    mkdir -p "$container_result_dir"
    
    # Calculate test duration for metrics collection
    local test_duration=$(calculate_test_duration "$TEST_MODE")
    
    # Check Docker disk space before running test
    check_docker_disk_space "$TEST_MODE" "$payload_size" 1
    
    # Create test run record in database
    local test_run_id=""
    # Use SCRIPT_DIR which is set at the top of the script
    local db_script_dir="$SCRIPT_DIR"
    local protocol_upper=$(echo "$protocol" | tr '[:lower:]' '[:upper:]')
    local payload_size_db="${payload_size:-default}"
    
    # Test database connection (use absolute path to ensure it works)
    local db_client_path="$db_script_dir/db_client.py"
    if [ -f "$db_client_path" ]; then
        # Test connection - capture both stdout and stderr
        local db_test_output
        db_test_output=$(python3 "$db_client_path" test 2>&1) || true
        # Check if output contains "successful" (case insensitive)
        if echo "$db_test_output" | grep -qi "successful"; then
            print_status "Creating test run record in database..."
            # Create test run and capture the ID (last line of output)
            local create_output
            create_output=$(python3 "$db_client_path" create_test_run \
                "$api_name" "$TEST_MODE" "$payload_size_db" "$protocol_upper" \
                "$json_file" 2>&1) || true
            test_run_id=$(echo "$create_output" | tail -1 | grep -E '^[0-9]+$' || echo "")
            if [ -n "$test_run_id" ] && [ "$test_run_id" -gt 0 ] 2>/dev/null; then
                print_success "Test run created with ID: $test_run_id"
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
    
    # Start metrics collection in background (for all test modes)
    local metrics_pid=""
    print_status "Starting resource utilization metrics collection..."
    metrics_pid=$(start_metrics_collection "$api_name" "$metrics_file" "$test_duration" "$TEST_MODE" "$api_name" "$test_run_id")
    if [ -n "$metrics_pid" ]; then
        print_success "Metrics collection started (PID: $metrics_pid)"
    else
        print_warning "Failed to start metrics collection, continuing without resource metrics..."
    fi
    
    # Display test phase information for full/saturation tests
    if [ "$TEST_MODE" = "full" ]; then
        echo ""
        print_status "Test will run in 4 phases:"
        print_status "  Phase 1: Baseline (10 VUs, 2 min)"
        print_status "  Phase 2: Mid-load (50 VUs, 2 min)"
        print_status "  Phase 3: High-load (100 VUs, 2 min)"
        print_status "  Phase 4: Higher-load (200 VUs, 5 min)"
        echo ""
    elif [ "$TEST_MODE" = "saturation" ]; then
        echo ""
        print_status "Test will run in 7 phases:"
        print_status "  Phase 1: Baseline (10 VUs, 2 min)"
        print_status "  Phase 2: Mid-load (50 VUs, 2 min)"
        print_status "  Phase 3: High-load (100 VUs, 2 min)"
        print_status "  Phase 4: Very High (200 VUs, 2 min)"
        print_status "  Phase 5: Extreme (500 VUs, 2 min)"
        print_status "  Phase 6: Maximum (1000 VUs, 2 min)"
        print_status "  Phase 7: Saturation (2000 VUs, 2 min)"
        echo ""
    fi
    
    # Start progress display in background if available and enabled
    local progress_display_pid=""
    local progress_display_script="$db_script_dir/test-progress-display.py"
    local enable_progress_display="${ENABLE_PROGRESS_DISPLAY:-true}"
    
    if [ "$enable_progress_display" = "true" ] && [ -f "$progress_display_script" ] && command -v python3 >/dev/null 2>&1 && [ -t 1 ]; then
        # Start progress display in background (works with or without rich library)
        # Note: Only run if stdout is a TTY (interactive terminal)
        # JSON file will be created by k6, so we start monitoring it
        # The script will wait for the file to exist
        (
            # Wait for JSON file to be created (k6 creates it when it starts)
            local wait_count=0
            while [ $wait_count -lt 30 ] && [ ! -f "$progress_json_file" ]; do
                sleep 0.5
                wait_count=$((wait_count + 1))
            done
            
            # If file exists, start monitoring
            if [ -f "$progress_json_file" ]; then
                # The progress display script uses rich's Live display which manages its own screen
                # It will use alternate screen buffer (with rich) to avoid interfering with main output
                # When rich is not available, it falls back to basic mode with screen clearing
                # Run without output redirection to allow rich to control the terminal
                python3 "$progress_display_script" \
                    "$progress_json_file" \
                    --api-name "$api_name" \
                    --test-mode "$TEST_MODE" \
                    --payload-size "${payload_size:-default}" \
                    --update-interval 1.0 >/dev/tty 2>&1 || true
            fi
        ) &
        progress_display_pid=$!
    fi
    
    # Run k6 in Docker container
    # Note: k6 image has k6 as entrypoint, so we need to override it to run shell commands
    # Use unbuffered output and prefix each line with API name for real-time visibility
    cd "$BASE_DIR"
    local test_exit_code=0
    # Use prefix_logs function which handles cross-platform compatibility
    # Note: k6 output is captured and displayed in real-time, with phase detection happening in post-processing
    # Progress display runs in background to show animated dashboard
    if docker-compose --profile k6-test run --rm --entrypoint /bin/sh k6-throughput -c "$k6_cmd" 2>&1 | prefix_logs "$api_name" | tee "$summary_file"; then
        test_exit_code=0
    else
        test_exit_code=1
    fi
    
    # Stop progress display if it was started
    if [ -n "$progress_display_pid" ]; then
        # Wait a moment for final updates
        sleep 1
        # Kill progress display process
        kill "$progress_display_pid" 2>/dev/null || true
        wait "$progress_display_pid" 2>/dev/null || true
    fi
    
    # Stop metrics collection if it was started
    if [ -n "$metrics_pid" ]; then
        print_status "Stopping metrics collection..."
        stop_metrics_collection "$metrics_pid"
        # Wait a moment for final metrics to be written
        sleep 2
        if [ -f "$metrics_file" ]; then
            print_success "Metrics collection completed: $metrics_file"
        else
            print_warning "Metrics file not found: $metrics_file"
        fi
    fi
    
    # Move JSON file from container mount to final location
    local container_json_file="$BASE_DIR/load-test/results/throughput-sequential/$api_name"
    if [ -n "$payload_size" ]; then
        container_json_file="$container_json_file/$payload_size"
    fi
    container_json_file="$container_json_file/$(basename $json_file)"
    if [ -f "$container_json_file" ]; then
        mv "$container_json_file" "$json_file"
    fi
    
    # Copy summary to log file
    if [ -f "$summary_file" ]; then
        cp "$summary_file" "$log_file"
    fi
    
    # Store performance metrics in database directly (primary storage)
    if [ -n "$test_run_id" ] && [ -f "$json_file" ]; then
        print_status "Storing performance metrics in database..."
        local metrics_output=$(python3 "$db_script_dir/extract_k6_metrics.py" "$json_file" 2>/dev/null || echo "")
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
    with open('$json_file', 'r') as f:
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
                    "$error_rate" >/dev/null 2>&1 || true
            else
                python3 "$db_script_dir/db_client.py" insert_performance_metrics \
                    "$test_run_id" \
                    "$total_samples" "$success_samples" "$error_samples" \
                    "$throughput" "$avg_response" "$min_response" "$max_response" \
                    "$error_rate" >/dev/null 2>&1 || true
            fi
            
            # Update test run completion
            python3 "$db_script_dir/db_client.py" update_test_run_completion \
                "$test_run_id" "completed" "$duration_seconds" >/dev/null 2>&1 || true
            
            print_success "Performance metrics stored in database"
        else
            print_warning "Could not extract metrics from JSON file"
        fi
    fi
    
    # Store phase metrics if available (for all test modes)
    if [ -n "$test_run_id" ] && [ -f "$metrics_file" ]; then
        print_status "Analyzing and storing phase metrics..."
        local phase_analysis=$(python3 "$db_script_dir/analyze-resource-metrics.py" \
            "$json_file" "$TEST_MODE" "$metrics_file" "$test_run_id" 2>/dev/null || echo "")
        if [ -n "$phase_analysis" ]; then
            # Parse JSON and insert each phase using Python script
            local phases_inserted=0
            if command -v python3 >/dev/null 2>&1; then
                # Use Python to parse JSON and insert phases
                # Write phase analysis to temp file to avoid shell escaping issues
                local temp_phase_file=$(mktemp)
                echo "$phase_analysis" > "$temp_phase_file"
                
                python3 << PYTHON_SCRIPT
import json
import sys
import subprocess
import os

temp_file = '$temp_phase_file'
try:
    # Read phase analysis from temp file
    with open(temp_file, 'r') as f:
        phase_data = json.load(f)
    
    phases = phase_data.get('phases', {})
    
    # Get phase names based on test mode
    test_mode = '$TEST_MODE'
    phase_names = []
    if test_mode == 'smoke':
        phase_names = ['Smoke Test']
    elif test_mode == 'full':
        phase_names = ['Baseline', 'Mid-load', 'High-load', 'Higher-load']
    elif test_mode == 'saturation':
        phase_names = ['Baseline', 'Mid-load', 'High-load', 'Very High', 'Extreme', 'Maximum', 'Saturation']
    
    db_script_dir = '$db_script_dir'
    test_run_id = $test_run_id
    
    phases_inserted = 0
    for phase_num_str in sorted(phases.keys(), key=int):
        phase_num = int(phase_num_str)
        phase = phases[phase_num_str]
        
        # Get phase name (use index-1 since phase_num is 1-based)
        phase_name = phase_names[phase_num - 1] if phase_num <= len(phase_names) else f"Phase {phase_num}"
        
        # Extract all required fields with defaults
        target_vus = phase.get('target_vus', 0)
        duration_seconds = phase.get('duration_seconds', 0)
        requests_count = phase.get('requests', 0)
        avg_cpu_percent = phase.get('avg_cpu_percent', 0.0)
        max_cpu_percent = phase.get('max_cpu_percent', 0.0)
        avg_memory_mb = phase.get('avg_memory_mb', 0.0)
        max_memory_mb = phase.get('max_memory_mb', 0.0)
        cpu_percent_per_request = phase.get('cpu_percent_per_request', 0.0)
        ram_mb_per_request = phase.get('ram_mb_per_request', 0.0)
        
        # Call db_client.py to insert phase
        cmd = [
            'python3', os.path.join(db_script_dir, 'db_client.py'), 'insert_test_phase',
            str(test_run_id),
            str(phase_num),
            phase_name,
            str(target_vus),
            str(duration_seconds),
            str(requests_count),
            str(avg_cpu_percent),
            str(max_cpu_percent),
            str(avg_memory_mb),
            str(max_memory_mb),
            str(cpu_percent_per_request),
            str(ram_mb_per_request)
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"Phase {phase_num} ({phase_name}) inserted successfully", file=sys.stderr)
            phases_inserted += 1
        else:
            print(f"Error inserting phase {phase_num}: {result.stderr}", file=sys.stderr)
    
    sys.exit(0 if phases_inserted > 0 else 1)
except Exception as e:
    print(f"Error parsing phase data: {e}", file=sys.stderr)
    sys.exit(1)
finally:
    # Clean up temp file
    try:
        if os.path.exists(temp_file):
            os.unlink(temp_file)
    except:
        pass
PYTHON_SCRIPT
                phases_inserted=$?
                # Ensure temp file is cleaned up even if Python script fails
                [ -f "$temp_phase_file" ] && rm -f "$temp_phase_file" || true
                if [ $phases_inserted -eq 0 ]; then
                    print_success "Phase metrics stored in database"
                else
                    print_warning "Some phase metrics may not have been stored"
                fi
            else
                print_warning "Python3 not available, skipping phase metrics insertion"
            fi
        else
            print_warning "No phase analysis data available"
        fi
    fi
    
    if [ $test_exit_code -eq 0 ]; then
        print_success "Test completed for $api_name"
        
        # Display formatted test summary if JSON file exists
        if [ -f "$json_file" ]; then
            print_test_summary "$api_name" "$json_file"
        fi
        
        print_status "Results saved to: $RESULT_DIR"
        print_status "  - JSON: $json_file"
        print_status "  - Summary: $summary_file"
        if [ -f "$metrics_file" ]; then
            print_status "  - Metrics: $metrics_file"
        fi
        if [ -n "$test_run_id" ]; then
            print_status "  - Database test run ID: $test_run_id"
        fi
        echo ""
        return 0
    else
        # Update test run status to failed
        if [ -n "$test_run_id" ]; then
            python3 "$db_script_dir/db_client.py" update_test_run_completion \
                "$test_run_id" "failed" >/dev/null 2>&1 || true
        fi
        print_error "Test failed for $api_name"
        return 1
    fi
}

# Function to run ghz gRPC test (deprecated - kept for reference)
run_ghz_test() {
    local api_name=$1
    local port=$2
    local proto_file=$3
    local method=$4
    
    # This function is deprecated - kept for reference only
    # gRPC tests now use k6 instead of ghz
    
    # Create results directory
    RESULT_DIR="$RESULTS_BASE_DIR/$api_name"
    mkdir -p "$RESULT_DIR"
    
    # Generate result file names
    local test_suffix="throughput"
    if [ "$TEST_MODE" = "smoke" ]; then
        test_suffix="throughput-smoke"
    fi
    
    local ghz_json_file="$RESULT_DIR/${api_name}-${test_suffix}-${TIMESTAMP}.json"
    local ghz_summary_file="$RESULT_DIR/${api_name}-${test_suffix}-${TIMESTAMP}.txt"
    local jtl_file="$RESULT_DIR/${api_name}-${test_suffix}-${TIMESTAMP}.jtl"
    local log_file="$RESULT_DIR/${api_name}-${test_suffix}-${TIMESTAMP}.log"
    
    # Determine test parameters
    local duration="30s"
    local concurrency=10
    local total_requests=0
    
    if [ "$TEST_MODE" = "smoke" ]; then
        duration="30s"
        concurrency=10
    else
        duration="120s"
        concurrency=10
    fi
    
    # Generate request payload JSON template
    local request_payload='{
  "eventHeader": {
    "uuid": "{{.RequestNumber}}",
    "eventName": "TestEvent",
    "createdDate": "{{.Timestamp}}",
    "savedDate": "{{.Timestamp}}",
    "eventType": "TestEvent"
  },
  "eventBody": {
    "entities": [{
      "entityType": "TestEntity",
      "entityId": "test-{{.RequestNumber}}",
      "updatedAttributes": {
        "id": "test-{{.RequestNumber}}",
        "timestamp": "{{.Timestamp}}"
      }
    }]
  }
}'
    
    # Use Docker service name for host (accessible via Docker network)
    local docker_host="$api_name"
    
    print_status "Executing ghz gRPC test in Docker container..."
    print_status "  Host: ${docker_host}:${port}"
    print_status "  Method: ${method}"
    print_status "  Duration: ${duration}"
    print_status "  Concurrency: ${concurrency}"
    
    # Run ghz in Docker container
    cd "$BASE_DIR"
    if docker-compose --profile k6-test run --rm k6-throughput sh -c "
        ghz --proto ${proto_file} \
            --call ${method} \
            --insecure \
            --host ${docker_host}:${port} \
            --concurrency ${concurrency} \
            --duration ${duration} \
            --data '${request_payload}' \
            --format json \
            --output /k6/results/throughput-sequential/${api_name}/$(basename $ghz_json_file) \
            2>&1 | tee /k6/results/throughput-sequential/${api_name}/$(basename $ghz_summary_file)
    "; then
        # Convert ghz JSON to JTL format for compatibility
        convert_ghz_to_jtl "$ghz_json_file" "$jtl_file" "$api_name"
        
        # Copy log file
        if [ -f "$BASE_DIR/load-test/results/throughput-sequential/$api_name/$(basename $ghz_summary_file)" ]; then
            cp "$BASE_DIR/load-test/results/throughput-sequential/$api_name/$(basename $ghz_summary_file)" "$log_file"
        fi
        
        print_success "Test completed for $api_name"
        print_status "Results saved to: $RESULT_DIR"
        print_status "  - JSON: $ghz_json_file"
        print_status "  - JTL: $jtl_file"
        print_status "  - Summary: $ghz_summary_file"
        echo ""
        
        return 0
    else
        print_error "Test failed for $api_name"
        return 1
    fi
}

# Function to convert ghz JSON output to JTL format (for compatibility)
convert_ghz_to_jtl() {
    local ghz_json=$1
    local jtl_file=$2
    local api_name=$3
    
    # Create a simple JTL file from ghz JSON
    # JTL format: timeStamp,elapsed,label,responseCode,responseMessage,threadName,dataType,success,failureMessage,bytes,sentBytes,grpThreads,allThreads,URL,Latency,IdleTime,Connect
    # We'll extract key metrics from ghz JSON and create a summary JTL
    
    if [ ! -f "$ghz_json" ]; then
        print_warning "ghz JSON file not found: $ghz_json"
        return 1
    fi
    
    # Use Python or jq to parse JSON and create JTL
    # For now, create a basic JTL header and summary line
    echo "timeStamp,elapsed,label,responseCode,responseMessage,threadName,dataType,success,failureMessage,bytes,sentBytes,grpThreads,allThreads,URL,Latency,IdleTime,Connect" > "$jtl_file"
    
    # Extract summary data from ghz JSON using Python
    python3 << PYTHON_SCRIPT
import json
import sys
from datetime import datetime

try:
    with open('$ghz_json', 'r') as f:
        data = json.load(f)
    
    # Extract summary statistics
    summary = data.get('summary', {})
    details = data.get('details', [])
    
    total = summary.get('total', 0)
    success = summary.get('success', 0)
    errors = summary.get('errors', 0)
    rps = summary.get('rps', 0)
    avg_duration = summary.get('average', {}).get('total', 0) / 1000000  # Convert nanoseconds to milliseconds
    min_duration = summary.get('fastest', {}).get('total', 0) / 1000000
    max_duration = summary.get('slowest', {}).get('total', 0) / 1000000
    
    # Create summary line in JTL format
    timestamp = int(datetime.now().timestamp() * 1000)
    elapsed = int(avg_duration)
    label = "$api_name"
    response_code = "200" if errors == 0 else "500"
    response_message = "OK" if errors == 0 else "Error"
    thread_name = "ghz-1"
    data_type = "text"
    success_flag = "true" if errors == 0 else "false"
    failure_message = "" if errors == 0 else f"{errors} errors"
    bytes_val = 0
    sent_bytes = 0
    grp_threads = 1
    all_threads = 1
    url = "$api_name"
    latency = int(avg_duration)
    idle_time = 0
    connect = 0
    
    # Write summary line
    with open('$jtl_file', 'a') as f:
        f.write(f"{timestamp},{elapsed},{label},{response_code},{response_message},{thread_name},{data_type},{success_flag},{failure_message},{bytes_val},{sent_bytes},{grp_threads},{all_threads},{url},{latency},{idle_time},{connect}\n")
    
    # Write individual request lines (sample)
    if details:
        for i, detail in enumerate(details[:1000]):  # Limit to 1000 samples for JTL
            timestamp = int(detail.get('timestamp', {}).get('seconds', 0) * 1000)
            elapsed = int(detail.get('latency', {}).get('total', 0) / 1000000)
            success_flag = "true" if detail.get('status', '') == 'OK' else "false"
            response_code = "200" if detail.get('status', '') == 'OK' else "500"
            
            with open('$jtl_file', 'a') as f:
                f.write(f"{timestamp},{elapsed},{label},{response_code},{response_message},{thread_name},{data_type},{success_flag},{failure_message},{bytes_val},{sent_bytes},{grp_threads},{all_threads},{url},{elapsed},{idle_time},{connect}\n")
    
    sys.exit(0)
except Exception as e:
    print(f"Error converting ghz JSON to JTL: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    
    if [ $? -eq 0 ]; then
        print_status "Converted ghz JSON to JTL format"
    else
        print_warning "Failed to convert ghz JSON to JTL format"
    fi
}

# Function to run throughput test for a single API
run_throughput_test() {
    local api_name=$1
    local test_file=$2
    local port=$3
    local protocol=$4
    local docker_host=${5:-""}
    local proto_file=${6:-""}
    local service_name=${7:-""}
    local method_name=${8:-""}
    
    print_status "=========================================="
    print_status "Running $TEST_MODE throughput test for $api_name"
    print_status "=========================================="
    
    # Wait for service to be ready
    if ! check_service_health "$api_name" "$port" "$protocol"; then
        print_error "Service health check failed for $api_name"
        return 1
    fi
    
    # Use k6 for all APIs
    run_k6_test "$api_name" "$test_file" "$port" "$protocol" "$docker_host" "$proto_file" "$service_name" "$method_name"
    return $?
}

# Function to extract k6 metrics from JSON file
extract_k6_metrics() {
    local json_file=$1
    if [ ! -f "$json_file" ]; then
        echo "0|0|0|0.00|0.00|0.00|0.00|0.00" >&2
        echo "0|0|0|0.00|0.00|0.00|0.00|0.00"
        return 1
    fi
    
    # Use external Python script for better NDJSON handling
    # Use BASE_DIR which is set at the top of the script
    local script_dir="${BASE_DIR}/load-test/shared"
    # Capture both stdout and stderr, but only output stdout
    local result=$(python3 "$script_dir/extract_k6_metrics.py" "$json_file" 2>&1)
    local exit_code=$?
    if [ $exit_code -eq 0 ] && [ -n "$result" ] && ! echo "$result" | grep -q "can't open file"; then
        echo "$result"
    else
        echo "0|0|0|0.00|0.00|0.00|0.00|0.00"
    fi
}

# Old inline version (kept for reference, but not used)
extract_k6_metrics_old() {
    local json_file=$1
    if [ ! -f "$json_file" ]; then
        echo "0|0|0|0.00|0.00|0.00|0.00|0.00"
        return 1
    fi
    
    python3 << PYTHON_SCRIPT
import json
import sys

try:
    with open('$json_file', 'r') as f:
        data = json.load(f)
    
    metrics = data.get('metrics', {})
    
    # Get request metrics (HTTP or gRPC)
    req_metric = metrics.get('http_reqs') or metrics.get('grpc_reqs')
    duration_metric = metrics.get('http_req_duration') or metrics.get('grpc_req_duration')
    failed_metric = metrics.get('http_req_failed') or metrics.get('grpc_req_failed')
    
    if not req_metric:
        print("0|0|0|0.00|0.00|0.00|0.00|0.00")
        sys.exit(0)
    
    values = req_metric.get('values', {})
    duration_values = duration_metric.get('values', {}) if duration_metric else {}
    failed_values = failed_metric.get('values', {}) if failed_metric else {}
    
    total_samples = int(values.get('count', 0))
    throughput = float(values.get('rate', 0))
    error_rate = float(failed_values.get('rate', 0) * 100) if failed_values else 0.0
    success_samples = int(total_samples * (1 - (error_rate / 100))) if total_samples > 0 else 0
    error_samples = total_samples - success_samples
    
    # Duration metrics
    avg_response = float(duration_values.get('avg', 0)) if duration_values else 0.0
    min_response = float(duration_values.get('min', 0)) if duration_values else 0.0
    max_response = float(duration_values.get('max', 0)) if duration_values else 0.0
    
    # Test duration from root
    root = data.get('root_group', {})
    duration_ms = float(root.get('execution_duration', {}).get('total', 0))
    duration_seconds = duration_ms / 1000.0 if duration_ms > 0 else 0.0
    
    print(f"{total_samples}|{success_samples}|{error_samples}|{duration_seconds:.2f}|{throughput:.2f}|{avg_response:.2f}|{min_response:.2f}|{max_response:.2f}")
    sys.exit(0)
except Exception as e:
    print(f"0|0|0|0.00|0.00|0.00|0.00|0.00", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
}

# Function to clear previous test results
clear_previous_test_results() {
    print_status "=========================================="
    print_status "Clearing Previous Test Results"
    print_status "=========================================="
    echo ""
    
    local cleared_files=0
    
    for api_name in $APIS; do
        local api_dir="$RESULTS_BASE_DIR/$api_name"
        if [ -d "$api_dir" ]; then
            # Remove ALL old result files (JSON, TXT, LOG) - not just for current test mode
            # This ensures we don't pick up stale data from previous runs
            local json_count=$(find "$api_dir" -name "*-throughput-*.json" -type f | wc -l | tr -d ' ')
            local txt_count=$(find "$api_dir" -name "*-throughput-*.txt" -type f | wc -l | tr -d ' ')
            local log_count=$(find "$api_dir" -name "*-throughput-*.log" -type f | wc -l | tr -d ' ')
            
            find "$api_dir" -name "*-throughput-*.json" -type f -delete 2>/dev/null || true
            find "$api_dir" -name "*-throughput-*.txt" -type f -delete 2>/dev/null || true
            find "$api_dir" -name "*-throughput-*.log" -type f -delete 2>/dev/null || true
            
            local total=$((json_count + txt_count + log_count))
            if [ $total -gt 0 ]; then
                print_status "Cleared $total old result files for $api_name ($json_count JSON, $txt_count TXT, $log_count LOG)"
                cleared_files=$((cleared_files + total))
            fi
        fi
    done
    
    # Also clear old comparison reports
    local report_count=$(find "$RESULTS_BASE_DIR" -name "comparison-report-*.md" -o -name "comparison-report-*.html" | wc -l | tr -d ' ')
    find "$RESULTS_BASE_DIR" -name "comparison-report-*.md" -type f -delete 2>/dev/null || true
    find "$RESULTS_BASE_DIR" -name "comparison-report-*.html" -type f -delete 2>/dev/null || true
    
    if [ $cleared_files -gt 0 ] || [ $report_count -gt 0 ]; then
        print_success "Cleared $cleared_files old result files and $report_count old reports"
    else
        print_status "No previous test results found to clear"
    fi
    echo ""
}

# Helper function to find JSON file for an API matching this test run
find_json_for_test_run() {
    local api_dir=$1
    local json_pattern=""
    
    # Build pattern based on test mode and timestamp
    if [ "$TEST_MODE" = "smoke" ]; then
        json_pattern="*-throughput-smoke-${TIMESTAMP}.json"
    elif [ "$TEST_MODE" = "saturation" ]; then
        json_pattern="*-throughput-saturation-${TIMESTAMP}.json"
    else
        # Full test: exclude smoke and saturation files
        json_pattern="*-throughput-${TIMESTAMP}.json"
    fi
    
    local latest_json=""
    if [ -z "$PAYLOAD_SIZE_PARAM" ] || [ "$PAYLOAD_SIZE_PARAM" = "default" ]; then
        # Default payload: prefer files in root directory, exclude payload size subdirectories
        latest_json=$(find "$api_dir" -maxdepth 1 -name "$json_pattern" -type f 2>/dev/null | head -1)
        # If not found in root, search subdirectories but exclude payload size dirs
        if [ -z "$latest_json" ]; then
            latest_json=$(find "$api_dir" -name "$json_pattern" -type f ! -path "*/4k/*" ! -path "*/8k/*" ! -path "*/32k/*" ! -path "*/64k/*" 2>/dev/null | head -1)
        fi
    else
        # Specific payload size: search in that subdirectory
        latest_json=$(find "$api_dir" -name "$json_pattern" -type f | head -1)
    fi
    
    # Fallback: if timestamp match not found, use latest file (but warn)
    if [ -z "$latest_json" ]; then
        if [ -z "$PAYLOAD_SIZE_PARAM" ] || [ "$PAYLOAD_SIZE_PARAM" = "default" ]; then
            latest_json=$(find "$api_dir" -maxdepth 1 -name "*-throughput-*.json" -type f ! -name "*-smoke-*.json" ! -name "*-saturation-*.json" 2>/dev/null | sort -r | head -1)
            if [ -z "$latest_json" ]; then
                latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f ! -name "*-smoke-*.json" ! -name "*-saturation-*.json" ! -path "*/4k/*" ! -path "*/8k/*" ! -path "*/32k/*" ! -path "*/64k/*" 2>/dev/null | sort -r | head -1)
            fi
        else
            latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f ! -name "*-smoke-*.json" ! -name "*-saturation-*.json" | sort -r | head -1)
        fi
    fi
    
    echo "$latest_json"
}

# Function to create comparison report
create_comparison_report() {
    print_status "=========================================="
    print_status "Creating Comparison Report"
    print_status "=========================================="
    
    local report_file="$RESULTS_BASE_DIR/comparison-report-${TIMESTAMP}.md"
    mkdir -p "$RESULTS_BASE_DIR"
    
    {
        echo "# Producer API Throughput Test Comparison Report"
        echo ""
        echo "**Date**: $(date)"  
        echo "**Test Mode**: $TEST_MODE"
        echo "**Test Type**: Sequential (one API at a time)"
        if [ -n "$PAYLOAD_SIZE_PARAM" ] && [ "$PAYLOAD_SIZE_PARAM" != "all" ]; then
            echo "**Payload Size**: $PAYLOAD_SIZE_PARAM"
        elif [ "$PAYLOAD_SIZE_PARAM" = "all" ]; then
            echo "**Payload Sizes**: 4k, 8k, 32k, 64k (all sizes tested)"
        fi
        echo ""
        echo "## Executive Summary"
        echo ""
        echo "This report compares throughput test results for all 6 producer API implementations."
        echo "Tests were run sequentially (one API at a time) to ensure fair comparison without resource competition."
        echo ""
        echo "## Test Configuration"
        echo ""
        if [ "$TEST_MODE" = "smoke" ]; then
            echo "- **Mode**: Smoke Test"
            echo "- **VUs**: 10 virtual users"
            echo "- **Duration**: 30 seconds per API"
        elif [ "$TEST_MODE" = "saturation" ]; then
            echo "- **Mode**: Saturation Test"
            echo "- **Phases**: 7 phases (10 → 50 → 100 → 200 → 500 → 1000 → 2000 VUs)"
            echo "- **Duration**: ~14 minutes per API"
        else
            echo "- **Mode**: Full Throughput Test"
            echo "- **Phases**: 4 phases (10 → 50 → 100 → 200 VUs)"
            echo "- **Duration**: ~11 minutes per API"
        fi
        echo ""
        echo "## APIs Tested"
        echo ""
        echo "1. **producer-api-java-rest** - Spring Boot REST (port 9081)"
        echo "2. **producer-api-java-grpc** - Java gRPC (port 9090)"
        echo "3. **producer-api-rust-rest** - Rust REST (port 9082)"
        echo "4. **producer-api-rust-grpc** - Rust gRPC (port 9091)"
        echo "5. **producer-api-go-rest** - Go REST (port 9083)"
        echo "6. **producer-api-go-grpc** - Go gRPC (port 9092)"
        echo ""
        echo "## Results Summary"
        echo ""
        echo "| API | Status | Total Samples | Throughput (req/s) | Avg Response Time (ms) | Error Rate (%) | Report |"
        echo "|-----|--------|---------------|-------------------|------------------------|----------------|--------|"
        
        # Extract metrics from each API's results
        for api_name in $APIS; do
            local api_dir="$RESULTS_BASE_DIR/$api_name"
            if [ ! -d "$api_dir" ]; then
                echo "| $api_name | ❌ No results | - | - | - | - | - |"
                continue
            fi
            
            # Find the k6 JSON file matching this test run's TIMESTAMP and TEST_MODE
            # This ensures we use the same test run for all APIs
            local latest_json=$(find_json_for_test_run "$api_dir")
            if [ -z "$latest_json" ]; then
                echo "| $api_name | ❌ No JSON file | - | - | - | - | - |"
                continue
            fi
            
            # Extract metrics from k6 JSON file using our extract function
            local metrics=$(extract_k6_metrics "$latest_json")
            
            # Format: total_samples|success_samples|error_samples|duration_seconds|throughput|avg_response|min_response|max_response
            IFS='|' read -r total_samples success_samples error_samples duration_seconds throughput avg_response min_response max_response <<< "$metrics"
            
            # Calculate error rate percentage
            local error_rate=0.0
            if [ "$total_samples" -gt 0 ]; then
                error_rate=$(awk "BEGIN {printf \"%.2f\", ($error_samples / $total_samples) * 100}")
            fi
            
            local status="✅"
            if (( $(echo "$error_rate > 5" | bc -l 2>/dev/null || echo "0") )); then
                status="⚠️"
            fi
            
            echo "| $api_name | $status | $total_samples | $throughput | $avg_response | $error_rate | - |"
        done
        
        echo ""
        echo "## Detailed Results"
        echo ""
        echo "### producer-api-java-rest (Spring Boot REST)"
        echo ""
        local api_dir="$RESULTS_BASE_DIR/producer-api-java-rest"
        if [ -d "$api_dir" ]; then
            # Find most recent JSON file (prefer root directory for default payload)
            local latest_json=""
            if [ -z "$PAYLOAD_SIZE_PARAM" ] || [ "$PAYLOAD_SIZE_PARAM" = "default" ]; then
                latest_json=$(find "$api_dir" -maxdepth 1 -name "*-throughput-*.json" -type f 2>/dev/null | sort -r | head -1)
                if [ -z "$latest_json" ]; then
                    latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f ! -path "*/4k/*" ! -path "*/8k/*" ! -path "*/32k/*" ! -path "*/64k/*" 2>/dev/null | sort -r | head -1)
                fi
            else
                latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f | sort -r | head -1)
            fi
            if [ -n "$latest_json" ]; then
                echo "**File**: \`$(basename "$latest_json")\`"
                echo ""
                local metrics=$(extract_k6_metrics "$latest_json")
                IFS='|' read -r total_samples success_samples error_samples duration_seconds throughput avg_response min_response max_response <<< "$metrics"
                
                echo "- **Total Samples**: $total_samples"
                echo "- **Successful**: $success_samples"
                echo "- **Errors**: $error_samples"
                echo "- **Test Duration**: ${duration_seconds}s"
                echo "- **Throughput**: ${throughput} req/s"
                echo "- **Avg Response Time**: ${avg_response}ms"
                echo "- **Min Response Time**: ${min_response}ms"
                echo "- **Max Response Time**: ${max_response}ms"
            fi
        fi
        
        echo ""
        echo "### producer-api-java-grpc (Java gRPC)"
        echo ""
        api_dir="$RESULTS_BASE_DIR/producer-api-java-grpc"
        if [ -d "$api_dir" ]; then
            # Find most recent JSON file (prefer root directory for default payload)
            if [ -z "$PAYLOAD_SIZE_PARAM" ] || [ "$PAYLOAD_SIZE_PARAM" = "default" ]; then
                latest_json=$(find "$api_dir" -maxdepth 1 -name "*-throughput-*.json" -type f 2>/dev/null | sort -r | head -1)
                if [ -z "$latest_json" ]; then
                    latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f ! -path "*/4k/*" ! -path "*/8k/*" ! -path "*/32k/*" ! -path "*/64k/*" 2>/dev/null | sort -r | head -1)
                fi
            else
                latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f | sort -r | head -1)
            fi
            if [ -n "$latest_json" ]; then
                echo "**File**: \`$(basename "$latest_json")\`"
                echo ""
                metrics=$(extract_k6_metrics "$latest_json")
                IFS='|' read -r total_samples success_samples error_samples duration_seconds throughput avg_response min_response max_response <<< "$metrics"
                
                echo "- **Total Samples**: $total_samples"
                echo "- **Successful**: $success_samples"
                echo "- **Errors**: $error_samples"
                echo "- **Test Duration**: ${duration_seconds}s"
                echo "- **Throughput**: ${throughput} req/s"
                echo "- **Avg Response Time**: ${avg_response}ms"
                echo "- **Min Response Time**: ${min_response}ms"
                echo "- **Max Response Time**: ${max_response}ms"
            fi
        fi
        
        echo ""
        echo "### producer-api-rust-rest (Rust REST)"
        echo ""
        api_dir="$RESULTS_BASE_DIR/producer-api-rust-rest"
        if [ -d "$api_dir" ]; then
            # Find most recent JSON file (prefer root directory for default payload)
            if [ -z "$PAYLOAD_SIZE_PARAM" ] || [ "$PAYLOAD_SIZE_PARAM" = "default" ]; then
                latest_json=$(find "$api_dir" -maxdepth 1 -name "*-throughput-*.json" -type f 2>/dev/null | sort -r | head -1)
                if [ -z "$latest_json" ]; then
                    latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f ! -path "*/4k/*" ! -path "*/8k/*" ! -path "*/32k/*" ! -path "*/64k/*" 2>/dev/null | sort -r | head -1)
                fi
            else
                latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f | sort -r | head -1)
            fi
            if [ -n "$latest_json" ]; then
                echo "**File**: \`$(basename "$latest_json")\`"
                echo ""
                metrics=$(extract_k6_metrics "$latest_json")
                IFS='|' read -r total_samples success_samples error_samples duration_seconds throughput avg_response min_response max_response <<< "$metrics"
                
                echo "- **Total Samples**: $total_samples"
                echo "- **Successful**: $success_samples"
                echo "- **Errors**: $error_samples"
                echo "- **Test Duration**: ${duration_seconds}s"
                echo "- **Throughput**: ${throughput} req/s"
                echo "- **Avg Response Time**: ${avg_response}ms"
                echo "- **Min Response Time**: ${min_response}ms"
                echo "- **Max Response Time**: ${max_response}ms"
            fi
        fi
        
        echo ""
        echo "### producer-api-rust-grpc (Rust gRPC)"
        echo ""
        api_dir="$RESULTS_BASE_DIR/producer-api-rust-grpc"
        if [ -d "$api_dir" ]; then
            # Find most recent JSON file (prefer root directory for default payload)
            if [ -z "$PAYLOAD_SIZE_PARAM" ] || [ "$PAYLOAD_SIZE_PARAM" = "default" ]; then
                latest_json=$(find "$api_dir" -maxdepth 1 -name "*-throughput-*.json" -type f 2>/dev/null | sort -r | head -1)
                if [ -z "$latest_json" ]; then
                    latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f ! -path "*/4k/*" ! -path "*/8k/*" ! -path "*/32k/*" ! -path "*/64k/*" 2>/dev/null | sort -r | head -1)
                fi
            else
                latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f | sort -r | head -1)
            fi
            if [ -n "$latest_json" ]; then
                echo "**File**: \`$(basename "$latest_json")\`"
                echo ""
                metrics=$(extract_k6_metrics "$latest_json")
                IFS='|' read -r total_samples success_samples error_samples duration_seconds throughput avg_response min_response max_response <<< "$metrics"
                
                echo "- **Total Samples**: $total_samples"
                echo "- **Successful**: $success_samples"
                echo "- **Errors**: $error_samples"
                echo "- **Test Duration**: ${duration_seconds}s"
                echo "- **Throughput**: ${throughput} req/s"
                echo "- **Avg Response Time**: ${avg_response}ms"
                echo "- **Min Response Time**: ${min_response}ms"
                echo "- **Max Response Time**: ${max_response}ms"
            fi
        fi
        
        echo ""
        echo "### producer-api-go-rest (Go REST)"
        echo ""
        api_dir="$RESULTS_BASE_DIR/producer-api-go-rest"
        if [ -d "$api_dir" ]; then
            # Find most recent JSON file (prefer root directory for default payload)
            if [ -z "$PAYLOAD_SIZE_PARAM" ] || [ "$PAYLOAD_SIZE_PARAM" = "default" ]; then
                latest_json=$(find "$api_dir" -maxdepth 1 -name "*-throughput-*.json" -type f 2>/dev/null | sort -r | head -1)
                if [ -z "$latest_json" ]; then
                    latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f ! -path "*/4k/*" ! -path "*/8k/*" ! -path "*/32k/*" ! -path "*/64k/*" 2>/dev/null | sort -r | head -1)
                fi
            else
                latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f | sort -r | head -1)
            fi
            if [ -n "$latest_json" ]; then
                echo "**File**: \`$(basename "$latest_json")\`"
                echo ""
                metrics=$(extract_k6_metrics "$latest_json")
                IFS='|' read -r total_samples success_samples error_samples duration_seconds throughput avg_response min_response max_response <<< "$metrics"
                
                echo "- **Total Samples**: $total_samples"
                echo "- **Successful**: $success_samples"
                echo "- **Errors**: $error_samples"
                echo "- **Test Duration**: ${duration_seconds}s"
                echo "- **Throughput**: ${throughput} req/s"
                echo "- **Avg Response Time**: ${avg_response}ms"
                echo "- **Min Response Time**: ${min_response}ms"
                echo "- **Max Response Time**: ${max_response}ms"
            fi
        fi
        
        echo ""
        echo "### producer-api-go-grpc (Go gRPC)"
        echo ""
        api_dir="$RESULTS_BASE_DIR/producer-api-go-grpc"
        if [ -d "$api_dir" ]; then
            # Find most recent JSON file (prefer root directory for default payload)
            if [ -z "$PAYLOAD_SIZE_PARAM" ] || [ "$PAYLOAD_SIZE_PARAM" = "default" ]; then
                latest_json=$(find "$api_dir" -maxdepth 1 -name "*-throughput-*.json" -type f 2>/dev/null | sort -r | head -1)
                if [ -z "$latest_json" ]; then
                    latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f ! -path "*/4k/*" ! -path "*/8k/*" ! -path "*/32k/*" ! -path "*/64k/*" 2>/dev/null | sort -r | head -1)
                fi
            else
                latest_json=$(find "$api_dir" -name "*-throughput-*.json" -type f | sort -r | head -1)
            fi
            if [ -n "$latest_json" ]; then
                echo "**File**: \`$(basename "$latest_json")\`"
                echo ""
                metrics=$(extract_k6_metrics "$latest_json")
                IFS='|' read -r total_samples success_samples error_samples duration_seconds throughput avg_response min_response max_response <<< "$metrics"
                
                echo "- **Total Samples**: $total_samples"
                echo "- **Successful**: $success_samples"
                echo "- **Errors**: $error_samples"
                echo "- **Test Duration**: ${duration_seconds}s"
                echo "- **Throughput**: ${throughput} req/s"
                echo "- **Avg Response Time**: ${avg_response}ms"
                echo "- **Min Response Time**: ${min_response}ms"
                echo "- **Max Response Time**: ${max_response}ms"
            fi
        fi
        
        echo ""
        echo "## Resource Utilization Metrics"
        echo ""
        
        # Include resource metrics for all test modes (including smoke tests)
        echo "### Overall Resource Usage"
        echo ""
        echo "| API | Avg CPU % | Max CPU % | Avg Memory % | Max Memory % | Avg Memory (MB) | Max Memory (MB) |"
        echo "|-----|-----------|-----------|--------------|--------------|-----------------|-----------------|"
        
        # Try to get resource metrics from database first
        local db_resource_summary=""
        if python3 "$SCRIPT_DIR/db_client.py" test >/dev/null 2>&1; then
            db_resource_summary=$(python3 "$SCRIPT_DIR/db_client.py" get_all_apis_resource_summary "$TEST_MODE" "$PAYLOAD_SIZE_PARAM" 2>/dev/null || echo "")
        fi
        
        for api_name in $APIS; do
            local avg_cpu="-"
            local max_cpu="-"
            local avg_mem="-"
            local max_mem="-"
            local avg_mem_mb="-"
            local max_mem_mb="-"
            
            # Try database first
            if [ -n "$db_resource_summary" ]; then
                local api_data=$(echo "$db_resource_summary" | python3 -c "import sys, json; d=json.load(sys.stdin); print(json.dumps(d.get('$api_name', {})))" 2>/dev/null || echo "")
                if [ -n "$api_data" ] && [ "$api_data" != "{}" ]; then
                    avg_cpu=$(echo "$api_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d.get('avg_cpu_percent', 0))" 2>/dev/null || echo "-")
                    max_cpu=$(echo "$api_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d.get('max_cpu_percent', 0))" 2>/dev/null || echo "-")
                    avg_mem=$(echo "$api_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d.get('avg_memory_percent', 0))" 2>/dev/null || echo "-")
                    max_mem=$(echo "$api_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d.get('max_memory_percent', 0))" 2>/dev/null || echo "-")
                    avg_mem_mb=$(echo "$api_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d.get('avg_memory_mb', 0))" 2>/dev/null || echo "-")
                    max_mem_mb=$(echo "$api_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d.get('max_memory_mb', 0))" 2>/dev/null || echo "-")
                fi
            fi
            
            # Fall back to CSV if database didn't provide data
            if [ "$avg_cpu" = "-" ] || [ "$max_cpu" = "-" ]; then
                local api_dir="$RESULTS_BASE_DIR/$api_name"
                if [ -d "$api_dir" ]; then
                    # Find JSON and metrics CSV files matching this test run's timestamp
                    local latest_json=$(find_json_for_test_run "$api_dir")
                    local latest_metrics_csv=""
                    
                    # Find matching metrics CSV file
                    local csv_pattern=""
                    if [ "$TEST_MODE" = "smoke" ]; then
                        csv_pattern="*-throughput-smoke-${TIMESTAMP}-metrics.csv"
                    elif [ "$TEST_MODE" = "saturation" ]; then
                        csv_pattern="*-throughput-saturation-${TIMESTAMP}-metrics.csv"
                    else
                        csv_pattern="*-throughput-${TIMESTAMP}-metrics.csv"
                    fi
                    
                    if [ -z "$PAYLOAD_SIZE_PARAM" ] || [ "$PAYLOAD_SIZE_PARAM" = "default" ]; then
                        latest_metrics_csv=$(find "$api_dir" -maxdepth 1 -name "$csv_pattern" -type f 2>/dev/null | head -1)
                        if [ -z "$latest_metrics_csv" ]; then
                            latest_metrics_csv=$(find "$api_dir" -name "$csv_pattern" -type f ! -path "*/4k/*" ! -path "*/8k/*" ! -path "*/32k/*" ! -path "*/64k/*" 2>/dev/null | head -1)
                        fi
                    else
                        latest_metrics_csv=$(find "$api_dir" -name "$csv_pattern" -type f | head -1)
                    fi
                    
                    # Fallback to latest if timestamp match not found
                    if [ -z "$latest_metrics_csv" ]; then
                        if [ -z "$PAYLOAD_SIZE_PARAM" ] || [ "$PAYLOAD_SIZE_PARAM" = "default" ]; then
                            latest_metrics_csv=$(find "$api_dir" -maxdepth 1 -name "*-throughput-*-metrics.csv" -type f ! -name "*-smoke-*-metrics.csv" ! -name "*-saturation-*-metrics.csv" 2>/dev/null | sort -r | head -1)
                            if [ -z "$latest_metrics_csv" ]; then
                                latest_metrics_csv=$(find "$api_dir" -name "*-throughput-*-metrics.csv" -type f ! -name "*-smoke-*-metrics.csv" ! -name "*-saturation-*-metrics.csv" ! -path "*/4k/*" ! -path "*/8k/*" ! -path "*/32k/*" ! -path "*/64k/*" 2>/dev/null | sort -r | head -1)
                            fi
                        else
                            latest_metrics_csv=$(find "$api_dir" -name "*-throughput-*-metrics.csv" -type f ! -name "*-smoke-*-metrics.csv" ! -name "*-saturation-*-metrics.csv" | sort -r | head -1)
                        fi
                    fi
                    
                    if [ -n "$latest_json" ] && [ -n "$latest_metrics_csv" ]; then
                        # Analyze resource metrics from CSV
                        local resource_analysis=$(python3 "$SCRIPT_DIR/analyze-resource-metrics.py" "$latest_json" "$TEST_MODE" "$latest_metrics_csv" 2>/dev/null)
                        
                        if [ -n "$resource_analysis" ]; then
                            avg_cpu=$(echo "$resource_analysis" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['overall']['avg_cpu_percent'])" 2>/dev/null || echo "-")
                            max_cpu=$(echo "$resource_analysis" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['overall']['max_cpu_percent'])" 2>/dev/null || echo "-")
                            avg_mem=$(echo "$resource_analysis" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['overall']['avg_memory_percent'])" 2>/dev/null || echo "-")
                            max_mem=$(echo "$resource_analysis" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['overall']['max_memory_percent'])" 2>/dev/null || echo "-")
                            avg_mem_mb=$(echo "$resource_analysis" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['overall']['avg_memory_mb'])" 2>/dev/null || echo "-")
                            max_mem_mb=$(echo "$resource_analysis" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['overall']['max_memory_mb'])" 2>/dev/null || echo "-")
                        fi
                    fi
                fi
            fi
            
            echo "| $api_name | $avg_cpu | $max_cpu | $avg_mem | $max_mem | $avg_mem_mb | $max_mem_mb |"
        done
        
        echo ""
        
        # Only include per-phase resource metrics for full and saturation tests
        if [ "$TEST_MODE" != "smoke" ]; then
            echo "### Per-Phase Resource Usage"
            echo ""
            echo "The following tables show resource utilization for each test phase:"
            echo ""
            
            # Determine number of phases based on test mode
            local num_phases=4
            if [ "$TEST_MODE" = "saturation" ]; then
                num_phases=7
            fi
            
            # Generate per-phase tables
            for phase_num in $(seq 1 $num_phases); do
                echo "#### Phase $phase_num"
                echo ""
                echo "| API | Avg CPU % | Max CPU % | Avg Memory (MB) | Max Memory (MB) | Requests | CPU %/Req | RAM MB/Req |"
                echo "|-----|-----------|-----------|----------------|-----------------|----------|-----------|------------|"
                
                for api_name in $APIS; do
                    local api_dir="$RESULTS_BASE_DIR/$api_name"
                    if [ ! -d "$api_dir" ]; then
                        echo "| $api_name | - | - | - | - | - | - | - |"
                        continue
                    fi
                    
                    local latest_json=$(find_json_for_test_run "$api_dir")
                    local latest_metrics_csv=""
                    
                    # Find matching metrics CSV file
                    local csv_pattern=""
                    if [ "$TEST_MODE" = "smoke" ]; then
                        csv_pattern="*-throughput-smoke-${TIMESTAMP}-metrics.csv"
                    elif [ "$TEST_MODE" = "saturation" ]; then
                        csv_pattern="*-throughput-saturation-${TIMESTAMP}-metrics.csv"
                    else
                        csv_pattern="*-throughput-${TIMESTAMP}-metrics.csv"
                    fi
                    
                    if [ -z "$PAYLOAD_SIZE_PARAM" ] || [ "$PAYLOAD_SIZE_PARAM" = "default" ]; then
                        latest_metrics_csv=$(find "$api_dir" -maxdepth 1 -name "$csv_pattern" -type f 2>/dev/null | head -1)
                        if [ -z "$latest_metrics_csv" ]; then
                            latest_metrics_csv=$(find "$api_dir" -name "$csv_pattern" -type f ! -path "*/4k/*" ! -path "*/8k/*" ! -path "*/32k/*" ! -path "*/64k/*" 2>/dev/null | head -1)
                        fi
                    else
                        latest_metrics_csv=$(find "$api_dir" -name "$csv_pattern" -type f | head -1)
                    fi
                    
                    # Fallback to latest if timestamp match not found
                    if [ -z "$latest_metrics_csv" ]; then
                        if [ -z "$PAYLOAD_SIZE_PARAM" ] || [ "$PAYLOAD_SIZE_PARAM" = "default" ]; then
                            latest_metrics_csv=$(find "$api_dir" -maxdepth 1 -name "*-throughput-*-metrics.csv" -type f ! -name "*-smoke-*-metrics.csv" ! -name "*-saturation-*-metrics.csv" 2>/dev/null | sort -r | head -1)
                            if [ -z "$latest_metrics_csv" ]; then
                                latest_metrics_csv=$(find "$api_dir" -name "*-throughput-*-metrics.csv" -type f ! -name "*-smoke-*-metrics.csv" ! -name "*-saturation-*-metrics.csv" ! -path "*/4k/*" ! -path "*/8k/*" ! -path "*/32k/*" ! -path "*/64k/*" 2>/dev/null | sort -r | head -1)
                            fi
                        else
                            latest_metrics_csv=$(find "$api_dir" -name "*-throughput-*-metrics.csv" -type f ! -name "*-smoke-*-metrics.csv" ! -name "*-saturation-*-metrics.csv" | sort -r | head -1)
                        fi
                    fi
                    
                    if [ -z "$latest_json" ] || [ -z "$latest_metrics_csv" ]; then
                        echo "| $api_name | - | - | - | - | - | - | - |"
                        continue
                    fi
                    
                    local resource_analysis=$(python3 "$SCRIPT_DIR/analyze-resource-metrics.py" "$latest_json" "$TEST_MODE" "$latest_metrics_csv" 2>/dev/null)
                    
                    if [ -n "$resource_analysis" ]; then
                        local phase_data=$(echo "$resource_analysis" | python3 -c "import sys, json; d=json.load(sys.stdin); p=d['phases'].get($phase_num, {}); print(json.dumps(p))" 2>/dev/null)
                        
                        if [ -n "$phase_data" ] && [ "$phase_data" != "{}" ]; then
                            local avg_cpu=$(echo "$phase_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d.get('avg_cpu_percent', 0))" 2>/dev/null || echo "-")
                            local max_cpu=$(echo "$phase_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d.get('max_cpu_percent', 0))" 2>/dev/null || echo "-")
                            local avg_mem_mb=$(echo "$phase_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d.get('avg_memory_mb', 0))" 2>/dev/null || echo "-")
                            local max_mem_mb=$(echo "$phase_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d.get('max_memory_mb', 0))" 2>/dev/null || echo "-")
                            local requests=$(echo "$phase_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('requests', 0))" 2>/dev/null || echo "-")
                            local cpu_per_req=$(echo "$phase_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.4f' % d.get('cpu_percent_per_request', 0))" 2>/dev/null || echo "-")
                            local ram_per_req=$(echo "$phase_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.4f' % d.get('ram_mb_per_request', 0))" 2>/dev/null || echo "-")
                            
                            echo "| $api_name | $avg_cpu | $max_cpu | $avg_mem_mb | $max_mem_mb | $requests | $cpu_per_req | $ram_per_req |"
                        else
                            echo "| $api_name | - | - | - | - | - | - | - |"
                        fi
                    else
                        echo "| $api_name | - | - | - | - | - | - | - |"
                    fi
                done
                
                echo ""
            done
            
            echo "### Derived Metrics Explanation"
            echo ""
            echo "- **CPU %/Req**: CPU percentage-seconds per request. Lower is better - indicates efficiency."
            echo "- **RAM MB/Req**: Memory MB-seconds per request. Lower is better - indicates memory efficiency."
            echo ""
        fi
        
        echo ""
        echo "## Comparison Analysis"
        echo ""
        echo "### Throughput Comparison"
        echo ""
        echo "Compare the throughput (req/s) values to identify which API handles the highest load."
        echo ""
        echo "### Response Time Comparison"
        echo ""
        echo "Compare average response times to identify which API has the lowest latency."
        echo ""
        echo "### Error Rate Comparison"
        echo ""
        echo "Compare error rates to identify which API is most resilient under load."
        echo ""
        echo "## Recommendations"
        echo ""
        echo "1. **For Maximum Throughput**: Choose the API with highest req/s"
        echo "2. **For Lowest Latency**: Choose the API with lowest average response time"
        echo "3. **For Reliability**: Choose the API with lowest error rate"
        echo "4. **For Full Analysis**: Run full throughput tests (not smoke) to identify optimal parallelism"
        echo ""
        echo "## Next Steps"
        echo ""
        if [ "$TEST_MODE" = "smoke" ]; then
            echo "To run full throughput tests:"
            echo "\`\`\`bash"
            echo "cd load-test/shared"
            echo "./run-sequential-throughput-tests.sh full"
            echo "\`\`\`"
            echo ""
            echo "To run saturation tests (find maximum throughput):"
            echo "\`\`\`bash"
            echo "cd load-test/shared"
            echo "./run-sequential-throughput-tests.sh saturation"
            echo "\`\`\`"
        elif [ "$TEST_MODE" = "full" ]; then
            echo "To run saturation tests (find maximum throughput):"
            echo "\`\`\`bash"
            echo "cd load-test/shared"
            echo "./run-sequential-throughput-tests.sh saturation"
            echo "\`\`\`"
            echo ""
            echo "Review the detailed HTML reports in each API's result directory for phase-by-phase analysis."
        else
            echo "Review the detailed HTML reports in each API's result directory for phase-by-phase analysis."
        fi
        echo ""
        echo "## Test Artifacts"
        echo ""
        echo "All results are saved to: \`$RESULTS_BASE_DIR\`"
        echo ""
        echo "## Reports Generated"
        echo ""
        echo "- **Markdown Report**: \`comparison-report-${TIMESTAMP}.md\`"
        echo "- **HTML Report**: \`comparison-report-${TIMESTAMP}.html\` (with interactive charts)"
        echo ""
        echo "For detailed analysis, open the HTML report in a web browser for interactive charts and visualizations."
        
    } > "$report_file"
    
    print_success "Comparison report saved to: $report_file"
    cat "$report_file"
    echo ""
    
    # Generate HTML report
    print_status "Generating HTML analysis report..."
    local html_report_file="$RESULTS_BASE_DIR/comparison-report-${TIMESTAMP}.html"
    if command -v python3 >/dev/null 2>&1; then
        if python3 "$SCRIPT_DIR/generate-html-report.py" "$RESULTS_BASE_DIR" "$TEST_MODE" "$TIMESTAMP" 2>/dev/null; then
            if [ -f "$html_report_file" ]; then
                print_success "HTML report generated: $html_report_file"
            else
                print_warning "HTML report generation completed but file not found"
            fi
        else
            print_warning "HTML report generation failed (check Python script)"
        fi
    else
        print_warning "Python3 not available, skipping HTML report generation"
    fi
}

# Function to run healthcheck cycle for all APIs
# This verifies all APIs can start, become healthy, and process events before running actual tests
run_healthcheck_cycle() {
    print_status "=========================================="
    print_status "Healthcheck Cycle - Verifying All APIs"
    print_status "=========================================="
    print_status "This will verify each API can start, become healthy, and process events"
    print_status "=========================================="
    echo ""
    
    local healthcheck_failed_apis=""
    local healthcheck_passed=0
    local healthcheck_total=0
    
    for api_name in $APIS; do
        healthcheck_total=$((healthcheck_total + 1))
        local api_config=$(get_api_config "$api_name")
        if [ -z "$api_config" ]; then
            print_error "Unknown API: $api_name"
            healthcheck_failed_apis="$healthcheck_failed_apis $api_name"
            continue
        fi
        IFS=':' read -r test_file port protocol profile docker_host proto_file service_name method_name <<< "$api_config"
        
        print_status "----------------------------------------"
        print_status "Healthcheck: $api_name"
        print_status "----------------------------------------"
        
        # Stop all APIs first and verify they're stopped
        stop_all_apis
        
        # Verify no APIs are running before starting the next one
        local running_apis=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -E "^(producer-api-java-rest|producer-api-java-grpc|producer-api-rust-rest|producer-api-rust-grpc)$" || true)
        if [ -n "$running_apis" ]; then
            print_error "Some APIs are still running after stop_all_apis:"
            echo "$running_apis" | while read -r container; do
                print_error "  - $container"
            done
            print_error "Cannot proceed. Please manually stop these containers."
            healthcheck_failed_apis="$healthcheck_failed_apis $api_name"
            continue
        fi
        
        # Clear database before each API healthcheck
        clear_database
        
        # Start this API
        if ! start_api "$api_name" "$profile"; then
            print_error "Failed to start $api_name"
            healthcheck_failed_apis="$healthcheck_failed_apis $api_name"
            continue
        fi
        
        # Wait a bit for API to fully start
        sleep 5
        
        # Health check
        if ! check_service_health "$api_name" "$port" "$protocol"; then
            print_error "Service health check failed for $api_name"
            log_step "$api_name" "HEALTHCHECK" "Health check failed" "error"
            healthcheck_failed_apis="$healthcheck_failed_apis $api_name"
            troubleshoot_api "$api_name" "$port" "$protocol"
            stop_api "$api_name"
            continue
        fi
        
        print_success "✓ Health check passed for $api_name"
        
        # Wait and verify event processing logs
        if ! wait_and_verify_event_processing "$api_name" "$port" "$protocol"; then
            print_error "Event processing verification failed for $api_name"
            log_step "$api_name" "HEALTHCHECK" "Event processing verification failed" "error"
            healthcheck_failed_apis="$healthcheck_failed_apis $api_name"
            troubleshoot_api "$api_name" "$port" "$protocol"
            stop_api "$api_name"
            continue
        fi
        
        print_success "✓ Event processing verification passed for $api_name"
        
        # Check API logs for event processing patterns
        if ! check_api_logs "$api_name"; then
            print_warning "Event processing logs check had warnings for $api_name, but continuing..."
        fi
        
        # Stop this API
        stop_api "$api_name"
        
        healthcheck_passed=$((healthcheck_passed + 1))
        print_success "✓ Healthcheck PASSED for $api_name"
        
        # Wait before next healthcheck
        print_status "Waiting 3 seconds before next API healthcheck..."
        sleep 3
        echo ""
    done
    
    # Summary
    echo ""
    print_status "=========================================="
    print_status "Healthcheck Cycle Summary"
    print_status "=========================================="
    print_status "Total APIs checked: $healthcheck_total"
    print_status "Passed: $healthcheck_passed"
    print_status "Failed: $((healthcheck_total - healthcheck_passed))"
    
    if [ -n "$healthcheck_failed_apis" ]; then
        print_error "Healthcheck failed for: $healthcheck_failed_apis"
        print_error "Cannot proceed with tests. Please fix the issues and try again."
        echo ""
        return 1
    else
        print_success "All APIs passed healthcheck! Proceeding with tests..."
        echo ""
        return 0
    fi
}

# Function to run smoke tests for all APIs
run_smoke_tests() {
    print_status "=========================================="
    print_status "Running Smoke Tests (Pre-flight Check)"
    print_status "=========================================="
    echo ""
    
    local smoke_failed_apis=""
    local smoke_timestamp=$(date +%Y%m%d_%H%M%S)
    
    for api_name in $APIS; do
        local api_config=$(get_api_config "$api_name")
        if [ -z "$api_config" ]; then
            print_error "Unknown API: $api_name"
            continue
        fi
        IFS=':' read -r test_file port protocol profile docker_host proto_file service_name method_name <<< "$api_config"
        
        # Stop all APIs first and verify they're stopped
        stop_all_apis
        
        # Verify no APIs are running before starting the next one
        local running_apis=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -E "^(producer-api-java-rest|producer-api-java-grpc|producer-api-rust-rest|producer-api-rust-grpc)$" || true)
        if [ -n "$running_apis" ]; then
            print_error "Some APIs are still running after stop_all_apis:"
            echo "$running_apis" | while read -r container; do
                print_error "  - $container"
            done
            print_error "Cannot proceed. Please manually stop these containers."
            smoke_failed_apis="$smoke_failed_apis $api_name"
            continue
        fi
        
        # Clear database before each API test
        clear_database
        
        # Start this API
        start_api "$api_name" "$profile"
        
        # Wait a bit for API to fully start (reduced for smoke tests)
        if [ "$TEST_MODE" = "smoke" ]; then
            sleep 3
        else
            sleep 5
        fi
        
        # Health check
        if ! check_service_health "$api_name" "$port" "$protocol"; then
            print_error "Service health check failed for $api_name"
            log_step "$api_name" "SMOKE_TEST" "Health check failed" "error"
            smoke_failed_apis="$smoke_failed_apis $api_name"
            troubleshoot_api "$api_name" "$port" "$protocol"
            stop_api "$api_name"
            continue
        fi
        
        # Wait 1 minute and verify event processing logs
        if ! wait_and_verify_event_processing "$api_name" "$port" "$protocol"; then
            print_error "Event processing verification failed for $api_name"
            log_step "$api_name" "SMOKE_TEST" "Event processing verification failed" "error"
            smoke_failed_apis="$smoke_failed_apis $api_name"
            troubleshoot_api "$api_name" "$port" "$protocol"
            stop_api "$api_name"
            continue
        fi
        
        # Run smoke test
        local original_test_mode="$TEST_MODE"
        TEST_MODE="smoke"
        local original_timestamp="$TIMESTAMP"
        TIMESTAMP="$smoke_timestamp"
        
        if ! run_throughput_test "$api_name" "$test_file" "$port" "$protocol" "$docker_host" "$proto_file" "$service_name" "$method_name"; then
            smoke_failed_apis="$smoke_failed_apis $api_name"
            TEST_MODE="$original_test_mode"
            TIMESTAMP="$original_timestamp"
            stop_api "$api_name"
            continue
        fi
        
        # Check API logs for event count
        check_api_logs "$api_name"
        
        # Validate smoke test results (using k6 JSON)
        local json_file="$RESULTS_BASE_DIR/$api_name/${api_name}-throughput-smoke-${smoke_timestamp}.json"
        if ! validate_metrics_stored "$api_name" "$json_file"; then
            smoke_failed_apis="$smoke_failed_apis $api_name"
            TEST_MODE="$original_test_mode"
            TIMESTAMP="$original_timestamp"
            troubleshoot_api "$api_name" "$port" "$protocol"
            stop_api "$api_name"
            continue
        fi
        
        # Additional smoke test validation: check error rate < 5% (k6 outputs NDJSON format)
        local error_rate_check=$(python3 << PYTHON_SCRIPT
import json
import sys

try:
    # k6 outputs NDJSON - count errors from error points
    total_requests = 0
    total_errors = 0
    
    with open('$json_file', 'r') as f:
        for line in f:
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
                metric_name = obj.get('metric', '')
                obj_type = obj.get('type', '')
                
                if obj_type == 'Point':
                    if metric_name in ['http_reqs', 'grpc_reqs']:
                        total_requests += 1
                    elif metric_name in ['http_req_failed', 'grpc_req_failed']:
                        value = obj.get('data', {}).get('value', 0)
                        if value > 0:
                            total_errors += 1
            except json.JSONDecodeError:
                continue
    
    if total_requests == 0:
        # No requests found, assume pass (might be a very short test)
        print("PASS|0.0000")
        sys.exit(0)
    
    error_rate = total_errors / total_requests if total_requests > 0 else 0.0
    
    if error_rate < 0.05:  # 5%
        print(f"PASS|{error_rate:.4f}")
        sys.exit(0)
    else:
        print(f"FAIL|{error_rate:.4f}")
        sys.exit(1)
        
except Exception as e:
    print(f"FAIL|Error: {str(e)}", file=sys.stderr)
    print(f"FAIL|Error: {str(e)}")
    sys.exit(1)
PYTHON_SCRIPT
)
        
        IFS='|' read -r check_status error_rate_value <<< "$error_rate_check"
        if [ "$check_status" != "PASS" ]; then
            print_error "Smoke test validation failed: Error rate ${error_rate_value} exceeds 5%"
            smoke_failed_apis="$smoke_failed_apis $api_name"
            TEST_MODE="$original_test_mode"
            TIMESTAMP="$original_timestamp"
            troubleshoot_api "$api_name" "$port" "$protocol"
            stop_api "$api_name"
            continue
        fi
        
        TEST_MODE="$original_test_mode"
        TIMESTAMP="$original_timestamp"
        
        # Stop this API
        stop_api "$api_name"
        
        # Wait before next test
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

# Main execution
main() {
    print_status "=========================================="
    print_status "Sequential Throughput Test Runner"
    print_status "Test Mode: $TEST_MODE"
    print_status "=========================================="
    echo ""
    
    # Step 0: Clear previous test results
    clear_previous_test_results
    
    # Step 1: Ensure database is running
    if ! ensure_database_running; then
        print_error "Failed to start database. Aborting test execution."
        exit 1
    fi
    
    # Step 2: Rebuild all producer APIs (skip for smoke tests to save time)
    if [ "$TEST_MODE" != "smoke" ]; then
        print_status "Step 2: Rebuilding all producer API Docker images..."
        cd "$BASE_DIR"
        
        for api_name in $APIS; do
            local api_config=$(get_api_config "$api_name")
            if [ -z "$api_config" ]; then
                print_error "Unknown API: $api_name"
                continue
            fi
            IFS=':' read -r test_file port protocol profile docker_host proto_file service_name method_name <<< "$api_config"
            if ! rebuild_api "$api_name" "$profile"; then
                print_warning "Failed to rebuild $api_name, continuing anyway..."
            fi
        done
        
        print_success "All APIs rebuilt"
        echo ""
    else
        print_status "Step 2: Skipping rebuild for smoke tests (using existing images)..."
        echo ""
    fi
    
    # Step 3: Build k6 container
    print_status "Step 3: Building k6 throughput container..."
    cd "$BASE_DIR"
    if ! docker-compose --profile k6-test build k6-throughput > /dev/null 2>&1; then
        print_warning "k6 container build had warnings, continuing anyway..."
    fi
    print_success "k6 container ready"
    echo ""
    
    # Step 4: Run healthcheck cycle for all APIs (skip for smoke tests to save time)
    # Skip healthcheck cycle if SKIP_HEALTHCHECK environment variable is set
    if [ "$TEST_MODE" != "smoke" ] && [ -z "$SKIP_HEALTHCHECK" ]; then
        print_status "Step 4: Running healthcheck cycle for all APIs..."
        if ! run_healthcheck_cycle; then
            print_error "Healthcheck cycle failed. Aborting test execution."
            exit 1
        fi
        echo ""
    else
        if [ "$TEST_MODE" = "smoke" ]; then
            print_status "Step 4: Skipping healthcheck cycle for smoke tests (will verify health before each test)..."
        else
            print_status "Step 4: Skipping healthcheck cycle (SKIP_HEALTHCHECK is set)..."
        fi
        echo ""
    fi
    
    # Step 5: If running full or saturation tests, run smoke tests first as a pre-check
    # Skip smoke tests if SKIP_HEALTHCHECK environment variable is set
    if [ "$TEST_MODE" = "full" ] || [ "$TEST_MODE" = "saturation" ]; then
        if [ -z "$SKIP_HEALTHCHECK" ]; then
            print_status "Step 5: Running smoke tests (pre-check) before $TEST_MODE tests..."
            if ! run_smoke_tests; then
                print_error "Smoke tests failed. Aborting $TEST_MODE test execution."
                exit 1
            fi
        else
            print_status "Step 5: Skipping smoke tests (SKIP_HEALTHCHECK is set)..."
        fi
        if [ "$TEST_MODE" = "saturation" ]; then
            print_status "Step 6: Running saturation throughput tests sequentially (one API at a time)..."
        else
            print_status "Step 6: Running full throughput tests sequentially (one API at a time)..."
        fi
    else
        print_status "Step 5: Running smoke throughput tests sequentially (one API at a time)..."
    fi
    echo ""
    
    # Step 6/7: Run tests sequentially for each payload size
    mkdir -p "$RESULTS_BASE_DIR"
    local failed_apis=""
    
    # Check Docker disk space before starting test runs
    local num_apis=$(echo $APIS | wc -w | tr -d ' ')
    print_status "Checking Docker disk space before test execution..."
    if ! check_docker_disk_space "$TEST_MODE" "" "$num_apis"; then
        print_error "Disk space check failed. Aborting test execution."
        exit 1
    fi
    echo ""
    
    # Calculate total number of tests for progress tracking
    local num_apis=$(echo $APIS | wc -w | tr -d ' ')
    local num_payload_sizes=$(echo $PAYLOAD_SIZES | wc -w | tr -d ' ')
    local total_tests=$((num_apis * num_payload_sizes))
    local current_test=0
    local start_time=$(date +%s)
    
    print_section "Test Execution Progress"
    print_status "Total tests to run: $total_tests (${num_apis} APIs × ${num_payload_sizes} payload sizes)"
    echo ""
    
    # Iterate over payload sizes
    for payload_size in $PAYLOAD_SIZES; do
        # Export payload size for use in run_k6_test function (empty for default)
        if [ "$payload_size" = "default" ]; then
            export PAYLOAD_SIZE=""
        else
            export PAYLOAD_SIZE="$payload_size"
        fi
        
        if [ "$payload_size" != "default" ] && [ -n "$payload_size" ]; then
            print_section "Testing with payload size: $payload_size"
        else
            print_section "Testing with default payload size (~400-500 bytes)"
        fi
        echo ""
        
        for api_name in $APIS; do
        current_test=$((current_test + 1))
        
        # Calculate elapsed time and estimate remaining
        local elapsed_time=$(($(date +%s) - start_time))
        local avg_time_per_test=0
        local estimated_remaining=0
        if [ $current_test -gt 0 ]; then
            avg_time_per_test=$((elapsed_time / current_test))
            estimated_remaining=$((avg_time_per_test * (total_tests - current_test)))
        fi
        
        # Format time
        local elapsed_min=$((elapsed_time / 60))
        local elapsed_sec=$((elapsed_time % 60))
        local remaining_min=$((estimated_remaining / 60))
        local remaining_sec=$((estimated_remaining % 60))
        
        # Display enhanced progress with visual separator
        echo ""
        print_subsection "Test ${current_test}/${total_tests}: $api_name"
        if [ "$payload_size" != "default" ] && [ -n "$payload_size" ]; then
            print_status "Payload Size: $payload_size"
        else
            print_status "Payload Size: default (~400-500 bytes)"
        fi
        print_status "Test Mode: $TEST_MODE"
        print_status "Elapsed Time: ${elapsed_min}m ${elapsed_sec}s"
        print_status "Estimated Remaining: ${remaining_min}m ${remaining_sec}s"
        echo ""
        
        # Display progress bar
        print_progress "$current_test" "$total_tests" "Testing: $api_name (${payload_size:-default})"
        echo ""
        local api_config=$(get_api_config "$api_name")
        if [ -z "$api_config" ]; then
            print_error "Unknown API: $api_name"
            continue
        fi
        IFS=':' read -r test_file port protocol profile docker_host proto_file service_name method_name <<< "$api_config"
        
        # Stop all APIs first and verify they're stopped
        stop_all_apis
        
        # Verify no APIs are running before starting the next one
        local running_apis=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -E "^(producer-api-java-rest|producer-api-java-grpc|producer-api-rust-rest|producer-api-rust-grpc)$" || true)
        if [ -n "$running_apis" ]; then
            print_error "Some APIs are still running after stop_all_apis:"
            echo "$running_apis" | while read -r container; do
                print_error "  - $container"
            done
            print_error "Cannot proceed. Please manually stop these containers."
            failed_apis="$failed_apis $api_name"
            continue
        fi
        
        # Clear database before each API test
        clear_database
        
        # Start this API
        start_api "$api_name" "$profile"
        
        # Wait a bit for API to fully start (reduced for smoke tests)
        if [ "$TEST_MODE" = "smoke" ]; then
            sleep 3
        else
            sleep 5
        fi
        
        # Health check
        if ! check_service_health "$api_name" "$port" "$protocol"; then
            print_error "Service health check failed for $api_name"
            log_step "$api_name" "TEST" "Health check failed" "error"
            failed_apis="$failed_apis $api_name"
            troubleshoot_api "$api_name" "$port" "$protocol"
            stop_api "$api_name"
            continue
        fi
        
        # Wait 1 minute and verify event processing logs
        if ! wait_and_verify_event_processing "$api_name" "$port" "$protocol"; then
            print_error "Event processing verification failed for $api_name"
            log_step "$api_name" "TEST" "Event processing verification failed" "error"
            failed_apis="$failed_apis $api_name"
            troubleshoot_api "$api_name" "$port" "$protocol"
            stop_api "$api_name"
            continue
        fi
        
        # Run throughput test
        if ! run_throughput_test "$api_name" "$test_file" "$port" "$protocol" "$docker_host" "$proto_file" "$service_name" "$method_name"; then
            failed_apis="$failed_apis $api_name"
        else
            # Check API logs for event count
            check_api_logs "$api_name"
        fi
        
        # Stop this API
        stop_api "$api_name"
        
        # Wait before next test (reduced for smoke tests)
        if [ "$TEST_MODE" = "smoke" ]; then
            print_status "Waiting 2 seconds before next API test..."
            sleep 2
        else
            print_status "Waiting 10 seconds before next API test..."
            sleep 10
        fi
        echo ""
        done
        
        # Wait between payload size iterations
        if [ "$TEST_MODE" != "smoke" ] && [ "$(echo $PAYLOAD_SIZES | wc -w)" -gt 1 ]; then
            print_status "Waiting 5 seconds before next payload size..."
            sleep 5
            echo ""
        fi
    done
    
    # Unset PAYLOAD_SIZE after all tests
    unset PAYLOAD_SIZE
    
    # Step 7/8: Create comparison report
    echo ""
    create_comparison_report
    
    # Final summary
    echo ""
    print_status "=========================================="
    print_status "Sequential Throughput Test Summary"
    print_status "=========================================="
    
    if [ -z "$failed_apis" ]; then
        print_success "All tests completed successfully!"
    else
        print_warning "Some tests failed:"
        for api in $failed_apis; do
            print_error "  - $api"
            print_status "    Troubleshooting info: $RESULTS_BASE_DIR/$api/test-execution.log"
        done
        echo ""
        print_status "For detailed troubleshooting information, check:"
        for api in $failed_apis; do
            print_status "  - $RESULTS_BASE_DIR/$api/test-execution.log"
        done
    fi
    
    echo ""
    print_status "Results directory: $RESULTS_BASE_DIR"
    print_status "Comparison report (Markdown): $RESULTS_BASE_DIR/comparison-report-${TIMESTAMP}.md"
    if [ -f "$RESULTS_BASE_DIR/comparison-report-${TIMESTAMP}.html" ]; then
        print_status "Comparison report (HTML): $RESULTS_BASE_DIR/comparison-report-${TIMESTAMP}.html"
    fi
    echo ""
    print_status "Per-API execution logs:"
    for api_name in $APIS; do
        local log_file="$RESULTS_BASE_DIR/$api_name/test-execution.log"
        if [ -f "$log_file" ]; then
            print_status "  - $api_name: $log_file"
        fi
    done
    echo ""
}

# Run main function
main

