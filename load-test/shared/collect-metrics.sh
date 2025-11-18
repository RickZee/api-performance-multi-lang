#!/bin/bash

# Metrics Collection Script
# Collects CPU and memory metrics for containers during load tests

# Don't use set -e in this script as it breaks background subshells
# We'll handle errors explicitly where needed

# Configuration
METRICS_INTERVAL=${METRICS_INTERVAL:-5}  # Collect every 5 seconds
METRICS_FILE=${1:-"metrics.csv"}

# Function to collect metrics for a container
collect_container_metrics() {
    local container_name=$1
    local timestamp=$(date +%s)
    local date_str=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Verify container exists and is running - try multiple matching strategies
    local found_container=""
    
    # First try exact match
    if docker ps --format "{{.Names}}" | grep -qE "^${container_name}$"; then
        found_container="$container_name"
    else
        # Try to find container by partial name match
        found_container=$(docker ps --format "{{.Names}}" | grep -E "${container_name}" | head -1)
    fi
    
    if [ -z "$found_container" ]; then
        # Container not found - return failure
        # Don't log here as it's called frequently in background loop
        return 1
    fi
    
    # Use found container name (may be different from input)
    container_name="$found_container"
    
    # Get container stats
    local stats=""
    if ! stats=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}}" "$container_name" 2>/dev/null); then
        return 1
    fi
    
    if [ -z "$stats" ]; then
        return 1
    fi
    
    # Parse stats
    local cpu_perc=$(echo "$stats" | cut -d',' -f1 | sed 's/%//')
    local mem_usage=$(echo "$stats" | cut -d',' -f2)
    local mem_perc=$(echo "$stats" | cut -d',' -f3 | sed 's/%//')
    local net_io=$(echo "$stats" | cut -d',' -f4)
    local block_io=$(echo "$stats" | cut -d',' -f5)
    
    # Extract memory values (format: "1.234GiB / 2GiB")
    local mem_used=$(echo "$mem_usage" | cut -d'/' -f1 | xargs)
    local mem_limit=$(echo "$mem_usage" | cut -d'/' -f2 | xargs)
    
    # Convert memory to MB for easier comparison
    local mem_used_mb=$(convert_to_mb "$mem_used")
    local mem_limit_mb=$(convert_to_mb "$mem_limit")
    
    # Write to CSV
    echo "$timestamp,$date_str,$container_name,$cpu_perc,$mem_perc,$mem_used_mb,$mem_limit_mb,$net_io,$block_io" >> "$METRICS_FILE"
}

# Function to convert memory units to MB
convert_to_mb() {
    local value=$1
    local unit=$(echo "$value" | grep -oE '[A-Za-z]+$')
    local num=$(echo "$value" | grep -oE '^[0-9.]+')
    
    case "$unit" in
        "B")
            echo "$num / 1024 / 1024" | bc -l | awk '{printf "%.2f", $1}'
            ;;
        "KiB"|"KB")
            echo "$num / 1024" | bc -l | awk '{printf "%.2f", $1}'
            ;;
        "MiB"|"MB")
            echo "$num" | awk '{printf "%.2f", $1}'
            ;;
        "GiB"|"GB")
            echo "$num * 1024" | bc -l | awk '{printf "%.2f", $1}'
            ;;
        *)
            echo "0"
            ;;
    esac
}

# Function to start metrics collection in background
start_metrics_collection() {
    local container_name=$1
    local metrics_file=$2
    local duration=${3:-300}  # Default 5 minutes
    local test_mode=${4:-""}  # Optional: test mode (full, saturation, smoke)
    local api_name=${5:-""}   # Optional: API name for metadata
    local test_run_id=${6:-""}  # Optional: test run ID for database storage
    
    # Export variables for background process
    export METRICS_INTERVAL
    export TEST_RUN_ID="$test_run_id"
    
    # Create CSV header with metadata if file doesn't exist
    if [ ! -f "$metrics_file" ]; then
        local start_timestamp=$(date +%s)
        local start_datetime=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Write metadata as comments (lines starting with #)
        echo "# Metrics collection metadata" >> "$metrics_file"
        echo "# Start timestamp: $start_timestamp" >> "$metrics_file"
        echo "# Start datetime: $start_datetime" >> "$metrics_file"
        if [ -n "$test_mode" ]; then
            echo "# Test mode: $test_mode" >> "$metrics_file"
        fi
        if [ -n "$api_name" ]; then
            echo "# API name: $api_name" >> "$metrics_file"
        fi
        echo "# Container: $container_name" >> "$metrics_file"
        echo "# Collection duration: ${duration}s" >> "$metrics_file"
        echo "# Collection interval: ${METRICS_INTERVAL}s" >> "$metrics_file"
        if [ -n "$test_run_id" ]; then
            echo "# Test run ID: $test_run_id" >> "$metrics_file"
        fi
        echo "#" >> "$metrics_file"
        echo "timestamp,datetime,container,cpu_percent,memory_percent,memory_used_mb,memory_limit_mb,network_io,block_io" >> "$metrics_file"
    fi
    
    # Verify container exists before starting collection
    local found_container=$(docker ps --format "{{.Names}}" | grep -E "^${container_name}$|${container_name}_" | head -1)
    if [ -z "$found_container" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Container '$container_name' not found, cannot start metrics collection" >&2
        echo ""
        return 1
    fi
    
    # Use found container name if different
    if [ "$found_container" != "$container_name" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Using container name '$found_container' instead of '$container_name'" >&2
        container_name="$found_container"
    fi
    
    # Ensure metrics file path is absolute
    if [[ ! "$metrics_file" = /* ]]; then
        metrics_file="$(pwd)/$metrics_file"
    fi
    
    # Ensure directory exists
    mkdir -p "$(dirname "$metrics_file")"
    
    # Wait a moment for container to be fully ready (reduced for smoke tests)
    if [ "$test_mode" = "smoke" ]; then
        sleep 0.5  # Reduced from 2 seconds for smoke tests
    else
        sleep 2
    fi
    
    # Export variables needed in background process
    export container_name
    export metrics_file
    export METRICS_INTERVAL
    export test_run_id
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Start collection in background
    # Use a heredoc to avoid quote escaping issues
    (
        # Define convert_to_mb function
        convert_to_mb() {
            local value=$1
            local unit=$(echo "$value" | grep -oE '[A-Za-z]+$')
            local num=$(echo "$value" | grep -oE '^[0-9.]+')
            
            case "$unit" in
                "B")
                    echo "$num / 1024 / 1024" | bc -l | awk '{printf "%.2f", $1}'
                    ;;
                "KiB"|"KB")
                    echo "$num / 1024" | bc -l | awk '{printf "%.2f", $1}'
                    ;;
                "MiB"|"MB")
                    echo "$num" | awk '{printf "%.2f", $1}'
                    ;;
                "GiB"|"GB")
                    echo "$num * 1024" | bc -l | awk '{printf "%.2f", $1}'
                    ;;
                *)
                    echo "0"
                    ;;
            esac
        }
        
        # Define collect_container_metrics function
        collect_container_metrics() {
            local container_name=$1
            local metrics_file=$2
            local timestamp=$(date +%s)
            local date_str=$(date '+%Y-%m-%d %H:%M:%S')
            
            # Verify container exists and is running
            local found_container=""
            if docker ps --format '{{.Names}}' | grep -qE "^${container_name}$"; then
                found_container="$container_name"
            else
                found_container=$(docker ps --format '{{.Names}}' | grep -E "${container_name}" | head -1)
            fi
            
            if [ -z "$found_container" ]; then
                return 1
            fi
            
            container_name="$found_container"
            
            # Get container stats
            local stats=""
            if ! stats=$(docker stats --no-stream --format '{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}}' "$container_name" 2>/dev/null); then
                return 1
            fi
            
            if [ -z "$stats" ]; then
                return 1
            fi
            
            # Parse stats
            local cpu_perc=$(echo "$stats" | cut -d',' -f1 | sed 's/%//')
            local mem_usage=$(echo "$stats" | cut -d',' -f2)
            local mem_perc=$(echo "$stats" | cut -d',' -f3 | sed 's/%//')
            local net_io=$(echo "$stats" | cut -d',' -f4)
            local block_io=$(echo "$stats" | cut -d',' -f5)
            
            # Extract memory values
            local mem_used=$(echo "$mem_usage" | cut -d'/' -f1 | xargs)
            local mem_limit=$(echo "$mem_usage" | cut -d'/' -f2 | xargs)
            
            # Convert memory to MB
            local mem_used_mb=$(convert_to_mb "$mem_used")
            local mem_limit_mb=$(convert_to_mb "$mem_limit")
            
            # Write to PostgreSQL if test_run_id is provided (primary storage)
            if [ -n "${TEST_RUN_ID}" ] && [ "${TEST_RUN_ID}" != "" ]; then
                # Parse network_io (format: "1.2MB / 3.4MB" or "1.2MB/3.4MB")
                local net_rx=""
                local net_tx=""
                if [ -n "$net_io" ]; then
                    net_rx=$(echo "$net_io" | cut -d'/' -f1 | xargs)
                    net_tx=$(echo "$net_io" | cut -d'/' -f2 | xargs)
                fi
                
                # Parse block_io (format: "1.2MB / 3.4MB" or "1.2MB/3.4MB")
                local block_read=""
                local block_write=""
                if [ -n "$block_io" ]; then
                    block_read=$(echo "$block_io" | cut -d'/' -f1 | xargs)
                    block_write=$(echo "$block_io" | cut -d'/' -f2 | xargs)
                fi
                
                # Convert timestamp to ISO format for PostgreSQL
                local timestamp_iso=$(date -u -r $timestamp '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S')
                
                # Use Python helper to insert into database (primary storage)
                python3 "${SCRIPT_DIR}/db_client.py" insert_resource_metric \
                    "${TEST_RUN_ID}" \
                    "$timestamp_iso" \
                    "$cpu_perc" \
                    "$mem_perc" \
                    "$mem_used_mb" \
                    "$mem_limit_mb" \
                    "$net_rx" \
                    "$net_tx" \
                    "$block_read" \
                    "$block_write" 2>/dev/null || true
            fi
            
            # Write to CSV as backup (only if database write failed or test_run_id not provided)
            if [ -z "${TEST_RUN_ID}" ] || [ "${TEST_RUN_ID}" = "" ]; then
                echo "$timestamp,$date_str,$container_name,$cpu_perc,$mem_perc,$mem_used_mb,$mem_limit_mb,$net_io,$block_io" >> "$metrics_file"
            fi
        }
        
        # Main collection loop
        local end_time=$(($(date +%s) + $duration))
        local collection_count=0
        local start_time=$(date +%s)
        local error_count=0
        local max_errors=10
        
        # Collect immediately on start (with retry)
        local retry=0
        while [ $retry -lt 3 ]; do
            if collect_container_metrics "$container_name" "$metrics_file" 2>&1; then
                collection_count=$((collection_count + 1))
                break
            else
                retry=$((retry + 1))
                sleep 1
            fi
        done
        
        # Main collection loop
        while [ $(date +%s) -lt $end_time ]; do
            sleep ${METRICS_INTERVAL:-5}
            if collect_container_metrics "$container_name" "$metrics_file" 2>&1; then
                collection_count=$((collection_count + 1))
                error_count=0
            else
                error_count=$((error_count + 1))
                if [ $error_count -ge $max_errors ]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Too many collection errors for '$container_name', stopping early" >&2
                    break
                fi
            fi
        done
        
        # Collect one final sample
        sleep 1
        collect_container_metrics "$container_name" "$metrics_file" 2>&1 && collection_count=$((collection_count + 1)) || true
        
        local elapsed=$(( $(date +%s) - start_time ))
        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Metrics collection completed for '$container_name': $collection_count samples collected over ${elapsed}s" >&2
    ) &
    
    local pid=$!
    echo "$pid"  # Return PID
}

# Function to stop metrics collection
stop_metrics_collection() {
    local pid=$1
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ "$1" = "start" ]; then
        start_metrics_collection "$2" "$3" "${4:-300}"
    elif [ "$1" = "stop" ]; then
        stop_metrics_collection "$2"
    else
        echo "Usage: $0 {start|stop} [container_name] [metrics_file] [duration]"
        exit 1
    fi
fi

