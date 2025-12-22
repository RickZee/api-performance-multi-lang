#!/bin/bash

# Clear Docker logs for CDC streaming consumers
# Usage: ./clear-consumer-logs.sh [--all | --spring | --flink | --restart | --recreate]
#
# Options:
#   --all       Clear logs for all CDC consumers (default)
#   --spring    Clear logs for Spring consumers only
#   --flink     Clear logs for Flink consumers only
#   --restart   Recreate containers to fully clear logs (recommended)
#   --recreate  Same as --restart (explicit recreate)
#   --soft      Soft restart only (logs may persist)
#   -h, --help  Show this help message

set +e  # Don't exit on error - we want to handle errors gracefully

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDC_DIR="$(dirname "$SCRIPT_DIR")"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Consumer container patterns
SPRING_CONSUMERS=(
    "cdc-loan-consumer-spring"
    "cdc-loan-payment-consumer-spring"
    "cdc-service-consumer-spring"
    "cdc-car-consumer-spring"
)

FLINK_CONSUMERS=(
    "cdc-loan-consumer-flink"
    "cdc-loan-payment-consumer-flink"
    "cdc-service-consumer-flink"
    "cdc-car-consumer-flink"
)

info() { echo -e "${BLUE}ℹ${NC} $1"; }
pass() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }

clear_container_logs() {
    local container_name="$1"
    
    # Check if container exists and is running
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "${YELLOW}[SKIP]${NC} Container '${container_name}' not found"
        return 1
    fi
    
    # Check if container is running - don't clear logs of stopped containers
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "${YELLOW}[SKIP]${NC} Container '${container_name}' is not running (will not clear logs)"
        return 1
    fi
    
    # Get the container ID
    local container_id
    container_id=$(docker inspect --format='{{.Id}}' "$container_name" 2>/dev/null || echo "")
    
    if [ -z "$container_id" ]; then
        echo -e "${RED}[ERROR]${NC} Could not get ID for container '${container_name}'"
        return 1
    fi
    
    # Docker log file path (Linux default)
    local log_file="/var/lib/docker/containers/${container_id}/${container_id}-json.log"
    
    # On macOS with Docker Desktop, we need to access the VM
    if [[ "$(uname)" == "Darwin" ]]; then
        # Use docker run to access Docker's VM filesystem
        # NOTE: This method can be problematic and may break containers
        # Better to use --restart flag to recreate containers instead
        echo -e "${BLUE}[CLEAR]${NC} Clearing logs for '${container_name}'..."
        echo -e "${YELLOW}[WARN]${NC} Log truncation on macOS may not work reliably"
        echo -e "${YELLOW}[WARN]${NC} Consider using --restart flag instead to recreate containers"
        
        # Skip truncation on macOS - it's unreliable and can break containers
        echo -e "${YELLOW}[SKIP]${NC} Skipping log truncation for '${container_name}' (use --restart instead)"
        return 1
    else
        # Linux: Direct access to log files (requires sudo)
        if sudo truncate -s 0 "$log_file" 2>/dev/null; then
            echo -e "${GREEN}[OK]${NC} Cleared logs for '${container_name}'"
            return 0
        else
            echo -e "${RED}[ERROR]${NC} Failed to clear logs for '${container_name}'"
            return 1
        fi
    fi
}

clear_logs_via_truncate() {
    local containers=("$@")
    local success_count=0
    local fail_count=0
    
    echo "=============================================="
    echo "Clearing CDC Consumer Docker Logs"
    echo "=============================================="
    echo ""
    
    for container in "${containers[@]}"; do
        if clear_container_logs "$container"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    echo ""
    echo "=============================================="
    echo -e "Results: ${GREEN}${success_count} cleared${NC}, ${YELLOW}${fail_count} skipped/failed${NC}"
    echo "=============================================="
}

restart_containers_soft() {
    local containers=("$@")
    local success_count=0
    local fail_count=0
    
    echo "=============================================="
    echo "Soft Restart CDC Consumers (logs may persist)"
    echo "=============================================="
    echo ""
    
    for container in "${containers[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            echo -e "${YELLOW}[RESTART]${NC} Restarting '${container}'..."
            if docker restart "$container" >/dev/null 2>&1; then
                echo -e "${GREEN}[OK]${NC} Restarted '${container}'"
                ((success_count++))
            else
                echo -e "${RED}[ERROR]${NC} Failed to restart '${container}'"
                ((fail_count++))
            fi
        else
            echo -e "${YELLOW}[SKIP]${NC} Container '${container}' not found"
            ((fail_count++))
        fi
    done
    
    echo ""
    echo "=============================================="
    echo -e "Results: ${GREEN}${success_count} restarted${NC}, ${YELLOW}${fail_count} skipped/failed${NC}"
    echo "=============================================="
    
    # Brief pause to let containers stabilize
    if [ $success_count -gt 0 ]; then
        info "Waiting 5s for containers to stabilize..."
        sleep 5
    fi
}

recreate_containers() {
    local containers=("$@")
    local success_count=0
    local fail_count=0
    
    echo "=============================================="
    echo "Recreating CDC Consumers (fully clears logs)"
    echo "=============================================="
    echo ""
    
    # Convert container names to service names for docker-compose
    # Container names are like "cdc-car-consumer-spring" -> service is "car-consumer"
    local services=()
    for container in "${containers[@]}"; do
        # Extract service name: cdc-X-consumer-Y -> X-consumer or X-consumer-Y
        local service="${container#cdc-}"  # Remove "cdc-" prefix
        # Map to docker-compose service names
        case "$service" in
            car-consumer-spring) services+=("car-consumer") ;;
            car-consumer-flink) services+=("car-consumer-flink") ;;
            loan-consumer-spring) services+=("loan-consumer") ;;
            loan-consumer-flink) services+=("loan-consumer-flink") ;;
            loan-payment-consumer-spring) services+=("loan-payment-consumer") ;;
            loan-payment-consumer-flink) services+=("loan-payment-consumer-flink") ;;
            service-consumer-spring) services+=("service-consumer") ;;
            service-consumer-flink) services+=("service-consumer-flink") ;;
            *) services+=("$service") ;;
        esac
    done
    
    # Remove duplicates
    local unique_services=($(echo "${services[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    cd "$CDC_DIR"
    
    echo -e "${YELLOW}[STOP]${NC} Stopping and removing containers..."
    # Use proper array quoting to prevent expansion issues
    if docker-compose rm -f -s "${unique_services[@]}" 2>&1 | grep -v "level=warning" || true; then
        echo -e "${GREEN}[OK]${NC} Containers removed"
    else
        echo -e "${YELLOW}[WARN]${NC} Some containers may not have been removed (continuing anyway)"
    fi
    
    echo ""
    echo -e "${YELLOW}[CREATE]${NC} Recreating containers..."
    # Use proper array quoting and check exit code properly
    if docker-compose up -d "${unique_services[@]}" 2>&1 | grep -v "level=warning"; then
        # Check if containers actually started
        sleep 2  # Brief pause for containers to start
        local running_count=0
        for service in "${unique_services[@]}"; do
            if docker-compose ps "$service" 2>/dev/null | grep -q "Up"; then
                ((running_count++))
            fi
        done
        success_count=$running_count
        fail_count=$((${#unique_services[@]} - running_count))
        if [ $success_count -gt 0 ]; then
            echo -e "${GREEN}[OK]${NC} $success_count containers recreated and running"
        fi
        if [ $fail_count -gt 0 ]; then
            echo -e "${RED}[ERROR]${NC} $fail_count containers failed to start"
        fi
    else
        fail_count=${#unique_services[@]}
        echo -e "${RED}[ERROR]${NC} Failed to recreate containers"
    fi
    
    echo ""
    echo "=============================================="
    echo -e "Results: ${GREEN}${success_count} recreated${NC}, ${YELLOW}${fail_count} failed${NC}"
    echo "=============================================="
    
    # Wait for containers to be fully ready and verify they're running
    if [ $success_count -gt 0 ]; then
        info "Waiting 10s for containers to connect to Kafka..."
        sleep 10
        
        # Verify containers are actually running and producing logs
        local verified_count=0
        for service in "${unique_services[@]}"; do
            if docker-compose ps "$service" 2>/dev/null | grep -q "Up"; then
                # Check if container has any output (even startup logs)
                if docker-compose logs --tail=1 "$service" 2>&1 | grep -v "level=warning" | grep -q .; then
                    ((verified_count++))
                fi
            fi
        done
        
        if [ $verified_count -lt $success_count ]; then
            warn "Only $verified_count/$success_count containers are producing logs"
            warn "Some containers may not have started properly"
        fi
    fi
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Clear Docker logs for CDC streaming consumers"
    echo ""
    echo "Options:"
    echo "  --all       Clear logs for all CDC consumers (default)"
    echo "  --spring    Clear logs for Spring consumers only"
    echo "  --flink     Clear logs for Flink consumers only"
    echo "  --restart   Recreate containers to fully clear logs (recommended)"
    echo "  --recreate  Same as --restart"
    echo "  --soft      Soft restart only (logs may persist in Docker)"
    echo "  --quiet     Suppress detailed output"
    echo "  -h, --help  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Clear all consumer logs (truncate method)"
    echo "  $0 --spring           # Clear only Spring consumer logs"
    echo "  $0 --restart          # Recreate all consumers (fully clears logs)"
    echo "  $0 --restart --flink  # Recreate only Flink consumers"
    echo "  $0 --soft             # Soft restart (logs may persist)"
}

# Main
MODE="truncate"
TARGET="all"
QUIET=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --spring)
            TARGET="spring"
            shift
            ;;
        --flink)
            TARGET="flink"
            shift
            ;;
        --restart|--recreate)
            MODE="recreate"
            shift
            ;;
        --soft)
            MODE="soft"
            shift
            ;;
        --all)
            TARGET="all"
            shift
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Determine which containers to target
case "$TARGET" in
    spring)
        CONTAINERS=("${SPRING_CONSUMERS[@]}")
        ;;
    flink)
        CONTAINERS=("${FLINK_CONSUMERS[@]}")
        ;;
    all|*)
        CONTAINERS=("${SPRING_CONSUMERS[@]}" "${FLINK_CONSUMERS[@]}")
        ;;
esac

# Execute the appropriate action
case "$MODE" in
    recreate)
        recreate_containers "${CONTAINERS[@]}"
        ;;
    soft)
        restart_containers_soft "${CONTAINERS[@]}"
        ;;
    truncate|*)
        clear_logs_via_truncate "${CONTAINERS[@]}"
        ;;
esac

