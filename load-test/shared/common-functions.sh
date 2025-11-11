#!/bin/bash

# Common functions for load test scripts
# Source this file in other scripts: source "$(dirname "$0")/../shared/common-functions.sh"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate numeric input
is_numeric() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# Function to validate port number
is_valid_port() {
    local port="$1"
    if is_numeric "$port" && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Function to validate hostname/IP
is_valid_host() {
    local host="$1"
    if [[ -n "$host" ]] && [[ "$host" != "localhost" ]]; then
        # Basic validation for hostname/IP
        if [[ "$host" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ "$host" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            return 0
        else
            return 1
        fi
    else
        return 0  # localhost is always valid
    fi
}

# Function to check network connectivity
check_connectivity() {
    local host="$1"
    local port="$2"
    local protocol="${3:-http}"
    
    if command_exists curl; then
        if curl -f -s --connect-timeout 5 "${protocol}://${host}:${port}" > /dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    elif command_exists nc; then
        if nc -z "$host" "$port" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Function to create directory if it doesn't exist
ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        if [[ $? -eq 0 ]]; then
            print_success "Created directory: $dir"
        else
            print_error "Failed to create directory: $dir"
            return 1
        fi
    fi
}

# Function to validate test parameters
validate_test_params() {
    local threads="$1"
    local rampup="$2"
    local loops="$3"
    
    local errors=()
    
    if ! is_numeric "$threads" || [ "$threads" -lt 1 ]; then
        errors+=("Threads must be a positive number")
    fi
    
    if ! is_numeric "$rampup" || [ "$rampup" -lt 0 ]; then
        errors+=("Ramp-up must be a non-negative number")
    fi
    
    if ! is_numeric "$loops" || [ "$loops" -lt 1 ]; then
        errors+=("Loops must be a positive number")
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        for error in "${errors[@]}"; do
            print_error "$error"
        done
        return 1
    fi
    
    return 0
}

# Function to get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to format duration
format_duration() {
    local seconds="$1"
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    if [ "$hours" -gt 0 ]; then
        printf "%dh %dm %ds" "$hours" "$minutes" "$secs"
    elif [ "$minutes" -gt 0 ]; then
        printf "%dm %ds" "$minutes" "$secs"
    else
        printf "%ds" "$secs"
    fi
}

# Function to calculate percentage
calculate_percentage() {
    local part="$1"
    local total="$2"
    local decimals="${3:-2}"
    
    if [ "$total" -eq 0 ]; then
        echo "0.00"
    else
        echo "scale=$decimals; $part * 100 / $total" | bc -l 2>/dev/null || echo "0.00"
    fi
}

# Function to check if running in Docker
is_docker_environment() {
    [[ -f /.dockerenv ]] || grep -q docker /proc/1/cgroup 2>/dev/null
}

# Function to get script directory
get_script_dir() {
    dirname "$(readlink -f "$0")"
}

# Function to show script header
show_script_header() {
    local script_name="$1"
    local description="$2"
    
    print_separator
    print_header "$script_name"
    if [[ -n "$description" ]]; then
        print_status "$description"
    fi
    print_status "Started at: $(get_timestamp)"
    print_separator
    echo ""
}

# Function to show script footer
show_script_footer() {
    local start_time="$1"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    print_separator
    print_success "Script completed successfully"
    print_status "Duration: $(format_duration $duration)"
    print_status "Finished at: $(get_timestamp)"
    print_separator
}

# Function to parse JTL file and extract metrics
# Usage: parse_jtl_file <jtl_file>
# Returns: key:value pairs for total, success, failed, success_rate, error_rate, avg_time, min_time, max_time, p90, p95, p99, throughput, total_bytes, total_sent_bytes
parse_jtl_file() {
    local jtl_file=$1
    
    if [ ! -f "$jtl_file" ]; then
        echo "ERROR: File not found: $jtl_file" >&2
        return 1
    fi
    
    # Check if file has data (more than just header)
    local line_count=$(wc -l < "$jtl_file" | tr -d ' ')
    if [ "$line_count" -le 1 ]; then
        echo "ERROR: No data found in JTL file" >&2
        return 1
    fi
    
    # Parse JTL file (CSV format) - extract times first, then sort externally for BSD awk compatibility
    local temp_times=$(mktemp)
    
    awk -F',' '
    BEGIN {
        total=0
        success=0
        failed=0
        total_time=0
        min_time=999999
        max_time=0
        total_bytes=0
        total_sent_bytes=0
    }
    NR > 1 {  # Skip header
        elapsed=$2
        success_flag=$8
        bytes=$10
        sent_bytes=$11
        
        total++
        if (success_flag == "true") {
            success++
        } else {
            failed++
        }
        
        total_time += elapsed
        if (elapsed < min_time) min_time = elapsed
        if (elapsed > max_time) max_time = elapsed
        
        total_bytes += bytes
        total_sent_bytes += sent_bytes
        
        # Store response times for percentile calculation
        print elapsed > "'"$temp_times"'"
    }
    END {
        if (total > 0) {
            avg_time = total_time / total
            success_rate = (success / total) * 100
            error_rate = (failed / total) * 100
            
            # Throughput calculation (simplified)
            if (total_time > 0) {
                throughput = (total * 1000) / total_time
            } else {
                throughput = 0
            }
            
            printf "total:%d\n", total
            printf "success:%d\n", success
            printf "failed:%d\n", failed
            printf "success_rate:%.2f\n", success_rate
            printf "error_rate:%.2f\n", error_rate
            printf "avg_time:%.2f\n", avg_time
            printf "min_time:%.2f\n", min_time
            printf "max_time:%.2f\n", max_time
            printf "throughput:%.2f\n", throughput
            printf "total_bytes:%d\n", total_bytes
            printf "total_sent_bytes:%d\n", total_sent_bytes
        }
    }
    ' "$jtl_file"
    
    # Calculate percentiles using sorted times
    if [ -f "$temp_times" ] && [ -s "$temp_times" ]; then
        local sorted_times=$(sort -n "$temp_times")
        local count=$(echo "$sorted_times" | wc -l | tr -d ' ')
        if [ "$count" -gt 0 ]; then
            local p90_idx=$(awk "BEGIN {printf \"%.0f\", ($count * 0.90)}")
            local p95_idx=$(awk "BEGIN {printf \"%.0f\", ($count * 0.95)}")
            local p99_idx=$(awk "BEGIN {printf \"%.0f\", ($count * 0.99)}")
            
            # Get percentile values (1-indexed, so add 1)
            local p90=$(echo "$sorted_times" | sed -n "${p90_idx}p")
            local p95=$(echo "$sorted_times" | sed -n "${p95_idx}p")
            local p99=$(echo "$sorted_times" | sed -n "${p99_idx}p")
            
            printf "p90:%.2f\n" "$p90"
            printf "p95:%.2f\n" "$p95"
            printf "p99:%.2f\n" "$p99"
        else
            printf "p90:0.00\n"
            printf "p95:0.00\n"
            printf "p99:0.00\n"
        fi
        rm -f "$temp_times"
    else
        printf "p90:0.00\n"
        printf "p95:0.00\n"
        printf "p99:0.00\n"
        rm -f "$temp_times"
    fi
}
