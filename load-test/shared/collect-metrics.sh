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
    
    # Export variables for background process
    export METRICS_INTERVAL
    
    # Create CSV header if file doesn't exist
    if [ ! -f "$metrics_file" ]; then
        echo "timestamp,datetime,container,cpu_percent,memory_percent,memory_used_mb,memory_limit_mb,network_io,block_io" > "$metrics_file"
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
    
    # Wait a moment for container to be fully ready
    sleep 2
    
    # Export variables needed in background process
    export container_name
    export metrics_file
    export METRICS_INTERVAL
    
    # Start collection in background
    # Use bash -c with function definitions inline to avoid sourcing issues
    bash -c "
        # Define convert_to_mb function
        convert_to_mb() {
            local value=\$1
            local unit=\$(echo \"\$value\" | grep -oE '[A-Za-z]+\$')
            local num=\$(echo \"\$value\" | grep -oE '^[0-9.]+')
            
            case \"\$unit\" in
                \"B\")
                    echo \"\$num / 1024 / 1024\" | bc -l | awk '{printf \"%.2f\", \$1}'
                    ;;
                \"KiB\"|\"KB\")
                    echo \"\$num / 1024\" | bc -l | awk '{printf \"%.2f\", \$1}'
                    ;;
                \"MiB\"|\"MB\")
                    echo \"\$num\" | awk '{printf \"%.2f\", \$1}'
                    ;;
                \"GiB\"|\"GB\")
                    echo \"\$num * 1024\" | bc -l | awk '{printf \"%.2f\", \$1}'
                    ;;
                *)
                    echo \"0\"
                    ;;
            esac
        }
        
        # Define collect_container_metrics function
        collect_container_metrics() {
            local container_name=\$1
            local metrics_file=\$2
            local timestamp=\$(date +%s)
            local date_str=\$(date '+%Y-%m-%d %H:%M:%S')
            
            # Verify container exists and is running
            local found_container=\"\"
            if docker ps --format '{{.Names}}' | grep -qE \"^\${container_name}\$\"; then
                found_container=\"\$container_name\"
            else
                found_container=\$(docker ps --format '{{.Names}}' | grep -E \"\${container_name}\" | head -1)
            fi
            
            if [ -z \"\$found_container\" ]; then
                return 1
            fi
            
            container_name=\"\$found_container\"
            
            # Get container stats
            local stats=\"\"
            if ! stats=\$(docker stats --no-stream --format '{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}}' \"\$container_name\" 2>/dev/null); then
                return 1
            fi
            
            if [ -z \"\$stats\" ]; then
                return 1
            fi
            
            # Parse stats
            local cpu_perc=\$(echo \"\$stats\" | cut -d',' -f1 | sed 's/%//')
            local mem_usage=\$(echo \"\$stats\" | cut -d',' -f2)
            local mem_perc=\$(echo \"\$stats\" | cut -d',' -f3 | sed 's/%//')
            local net_io=\$(echo \"\$stats\" | cut -d',' -f4)
            local block_io=\$(echo \"\$stats\" | cut -d',' -f5)
            
            # Extract memory values
            local mem_used=\$(echo \"\$mem_usage\" | cut -d'/' -f1 | xargs)
            local mem_limit=\$(echo \"\$mem_usage\" | cut -d'/' -f2 | xargs)
            
            # Convert memory to MB
            local mem_used_mb=\$(convert_to_mb \"\$mem_used\")
            local mem_limit_mb=\$(convert_to_mb \"\$mem_limit\")
            
            # Write to CSV
            echo \"\$timestamp,\$date_str,\$container_name,\$cpu_perc,\$mem_perc,\$mem_used_mb,\$mem_limit_mb,\$net_io,\$block_io\" >> \"\$metrics_file\"
        }
        
        # Main collection loop
        local end_time=\$((\$(date +%s) + $duration))
        local collection_count=0
        local start_time=\$(date +%s)
        local error_count=0
        local max_errors=10
        
        # Collect immediately on start (with retry)
        local retry=0
        while [ \$retry -lt 3 ]; do
            if collect_container_metrics \"\$container_name\" \"\$metrics_file\" 2>&1; then
                collection_count=\$((collection_count + 1))
                break
            else
                retry=\$((retry + 1))
                sleep 1
            fi
        done
        
        # Main collection loop
        while [ \$(date +%s) -lt \$end_time ]; do
            sleep \${METRICS_INTERVAL:-5}
            if collect_container_metrics \"\$container_name\" \"\$metrics_file\" 2>&1; then
                collection_count=\$((collection_count + 1))
                error_count=0
            else
                error_count=\$((error_count + 1))
                if [ \$error_count -ge \$max_errors ]; then
                    echo \"\$(date '+%Y-%m-%d %H:%M:%S') [WARN] Too many collection errors for '\$container_name', stopping early\" >&2
                    break
                fi
            fi
        done
        
        # Collect one final sample
        sleep 1
        collect_container_metrics \"\$container_name\" \"\$metrics_file\" 2>&1 && collection_count=\$((collection_count + 1)) || true
        
        local elapsed=\$(( \$(date +%s) - start_time ))
        echo \"\$(date '+%Y-%m-%d %H:%M:%S') [INFO] Metrics collection completed for '\$container_name': \$collection_count samples collected over \${elapsed}s\" >&2
    " &
    
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

