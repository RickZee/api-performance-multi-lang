#!/bin/bash

# Color definitions for consistent output across all scripts
# Source this file in other scripts: source "$(dirname "$0")/../shared/color-output.sh"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Bold colors
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_BLUE='\033[1;34m'

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    echo -e "${PURPLE}[DEBUG]${NC} $1"
}

print_header() {
    echo -e "${BOLD_BLUE}=== $1 ===${NC}"
}

print_separator() {
    echo -e "${CYAN}$(printf '=%.0s' {1..50})${NC}"
}

# Function to print test results
print_test_result() {
    local test_name="$1"
    local status="$2"
    local details="$3"
    
    if [[ "$status" == "PASS" ]]; then
        echo -e "${GREEN}✓${NC} ${test_name} - ${details}"
    elif [[ "$status" == "FAIL" ]]; then
        echo -e "${RED}✗${NC} ${test_name} - ${details}"
    elif [[ "$status" == "WARN" ]]; then
        echo -e "${YELLOW}⚠${NC} ${test_name} - ${details}"
    else
        echo -e "${BLUE}•${NC} ${test_name} - ${details}"
    fi
}

# Function to print progress
print_progress() {
    local current="$1"
    local total="$2"
    local description="$3"
    
    local percentage=$((current * 100 / total))
    local filled=$((percentage / 2))
    local empty=$((50 - filled))
    
    printf "\r${BLUE}[${NC}"
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "${BLUE}]${NC} ${percentage}%% - ${description}"
    
    if [[ "$current" == "$total" ]]; then
        echo ""
    fi
}
