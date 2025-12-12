#!/bin/bash

# Common functions library for shell scripts
# Source this file in other scripts: source "$(dirname "$0")/../shared/common.sh"

# Get the directory where the script is located
get_script_dir() {
    if [ -n "${BASH_SOURCE[0]}" ]; then
        dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    else
        dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")"
    fi
}

# Get the project root directory (assumes scripts are in scripts/ or */scripts/)
get_project_root() {
    local script_dir="${1:-$(get_script_dir)}"
    local current_dir="$script_dir"
    
    # Try to find project root by looking for common markers
    while [ "$current_dir" != "/" ]; do
        if [ -f "$current_dir/README.md" ] || \
           [ -f "$current_dir/.git" ] || \
           [ -f "$current_dir/docker-compose.yml" ] || \
           [ -d "$current_dir/scripts" ]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    
    # Fallback: go up from scripts directory
    if [[ "$script_dir" == *"/scripts"* ]]; then
        echo "$(dirname "$(dirname "$script_dir")")"
    else
        echo "$(dirname "$script_dir")"
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate numeric input
is_numeric() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# Validate port number
is_valid_port() {
    local port="$1"
    if is_numeric "$port" && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Validate hostname/IP
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

# Check network connectivity
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

# Create directory if it doesn't exist
ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        if [[ $? -eq 0 ]]; then
            return 0
        else
            return 1
        fi
    fi
    return 0
}

# Get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Format duration
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

# Calculate percentage
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

# Check if running in Docker
is_docker_environment() {
    [[ -f /.dockerenv ]] || grep -q docker /proc/1/cgroup 2>/dev/null
}

# Show script header
show_script_header() {
    local script_name="$1"
    local description="$2"
    
    echo "========================================"
    echo "$script_name"
    if [[ -n "$description" ]]; then
        echo "$description"
    fi
    echo "Started at: $(get_timestamp)"
    echo "========================================"
    echo ""
}

# Show script footer
show_script_footer() {
    local start_time="$1"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo "========================================"
    echo "Script completed successfully"
    echo "Duration: $(format_duration $duration)"
    echo "Finished at: $(get_timestamp)"
    echo "========================================"
}

# Parse command line arguments (helper function)
# Usage: parse_args "$@" --key1 value1 --key2 value2
parse_args() {
    local args=("$@")
    local i=0
    
    while [ $i -lt ${#args[@]} ]; do
        local arg="${args[$i]}"
        
        if [[ "$arg" == --* ]]; then
            local key="${arg#--}"
            local value="${args[$((i+1))]}"
            
            # Handle boolean flags
            if [[ -z "$value" ]] || [[ "$value" == --* ]]; then
                eval "${key//-/_}=true"
                i=$((i+1))
            else
                eval "${key//-/_}=\"$value\""
                i=$((i+2))
            fi
        else
            i=$((i+1))
        fi
    done
}

# Require command to be installed
require_command() {
    local cmd="$1"
    local install_hint="${2:-}"
    
    if ! command_exists "$cmd"; then
        echo "Error: $cmd is required but not installed"
        if [ -n "$install_hint" ]; then
            echo "$install_hint"
        fi
        exit 1
    fi
}

# Require file to exist
require_file() {
    local file="$1"
    local description="${2:-File}"
    
    if [ ! -f "$file" ]; then
        echo "Error: $description not found: $file"
        exit 1
    fi
}

# Require directory to exist
require_directory() {
    local dir="$1"
    local description="${2:-Directory}"
    
    if [ ! -d "$dir" ]; then
        echo "Error: $description not found: $dir"
        exit 1
    fi
}

