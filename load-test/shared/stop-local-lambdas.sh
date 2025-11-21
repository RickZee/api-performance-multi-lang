#!/bin/bash

# Stop Local Lambda Functions
# Stops all Lambda functions running locally via SAM Local

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/color-output.sh" 2>/dev/null || true

# Configuration
PID_FILE_DIR="$SCRIPT_DIR/.lambda-pids"

# Function to print section header
print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to stop a Lambda function
stop_lambda() {
    local api_name=$1
    local pid_file="$PID_FILE_DIR/${api_name}.pid"
    
    if [ ! -f "$pid_file" ]; then
        print_warning "$api_name is not running (no PID file found)"
        return 0
    fi
    
    local pid=$(cat "$pid_file")
    
    if ! ps -p "$pid" > /dev/null 2>&1; then
        print_warning "$api_name process (PID: $pid) is not running"
        rm -f "$pid_file"
        return 0
    fi
    
    print_status "Stopping $api_name (PID: $pid)..."
    
    # Kill the process
    kill "$pid" 2>/dev/null || true
    
    # Wait for process to stop
    local max_wait=10
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if ! ps -p "$pid" > /dev/null 2>&1; then
            print_success "$api_name stopped"
            rm -f "$pid_file"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    
    # Force kill if still running
    if ps -p "$pid" > /dev/null 2>&1; then
        print_warning "Force killing $api_name (PID: $pid)..."
        kill -9 "$pid" 2>/dev/null || true
        sleep 1
        if ! ps -p "$pid" > /dev/null 2>&1; then
            print_success "$api_name force stopped"
            rm -f "$pid_file"
            return 0
        else
            print_error "Failed to stop $api_name"
            return 1
        fi
    fi
    
    rm -f "$pid_file"
    return 0
}

# Function to stop all Lambda functions
stop_all_lambdas() {
    print_section "Stopping All Local Lambda Functions"
    
    if [ ! -d "$PID_FILE_DIR" ]; then
        print_warning "No PID directory found. No Lambda functions appear to be running."
        return 0
    fi
    
    local stopped=0
    local failed=0
    
    # Find all PID files
    for pid_file in "$PID_FILE_DIR"/*.pid; do
        if [ -f "$pid_file" ]; then
            local api_name=$(basename "$pid_file" .pid)
            if stop_lambda "$api_name"; then
                stopped=$((stopped + 1))
            else
                failed=$((failed + 1))
            fi
        fi
    done
    
    # Clean up PID directory if empty
    if [ -d "$PID_FILE_DIR" ] && [ -z "$(ls -A "$PID_FILE_DIR")" ]; then
        rmdir "$PID_FILE_DIR"
    fi
    
    # Summary
    print_section "Stop Summary"
    print_status "Stopped: $stopped"
    print_status "Failed: $failed"
    
    if [ $failed -gt 0 ]; then
        print_error "Some Lambda functions failed to stop"
        return 1
    else
        print_success "All Lambda functions stopped successfully"
        return 0
    fi
}

# Main execution
main() {
    if [ $# -gt 0 ]; then
        # Stop specific APIs
        print_section "Stopping Specified Lambda Functions"
        local stopped=0
        local failed=0
        
        for api_name in "$@"; do
            if stop_lambda "$api_name"; then
                stopped=$((stopped + 1))
            else
                failed=$((failed + 1))
            fi
        done
        
        if [ $failed -gt 0 ]; then
            exit 1
        else
            exit 0
        fi
    else
        # Stop all
        stop_all_lambdas
        exit $?
    fi
}

# Run main function
main "$@"

