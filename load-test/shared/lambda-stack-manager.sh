#!/bin/bash

# Lambda Stack Manager
# Manages CloudFormation stacks for Lambda functions

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/color-output.sh" 2>/dev/null || true

# Configuration
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LAMBDA_CONFIG_FILE="$SCRIPT_DIR/lambda-config.json"
LAMBDA_DEPLOYMENT_CONFIG_FILE="$SCRIPT_DIR/lambda-deployment-config.json"

# Function to print section header
print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to get stack status
get_stack_status() {
    local stack_name=$1
    local region="${AWS_REGION:-us-east-1}"
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND"
}

# Function to get stack outputs
get_stack_outputs() {
    local stack_name=$1
    local region="${AWS_REGION:-us-east-1}"
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --query 'Stacks[0].Outputs' \
        --output json 2>/dev/null || echo "[]"
}

# Function to get API URL from stack
get_api_url_from_stack() {
    local stack_name=$1
    local region="${AWS_REGION:-us-east-1}"
    
    local outputs=$(get_stack_outputs "$stack_name" "$region")
    echo "$outputs" | python3 -c "
import json
import sys
try:
    outputs = json.load(sys.stdin)
    for output in outputs:
        if output.get('OutputKey') == 'ApiUrl':
            print(output.get('OutputValue', ''))
            sys.exit(0)
    print('', file=sys.stderr)
    sys.exit(1)
except:
    print('', file=sys.stderr)
    sys.exit(1)
"
}

# Function to wait for stack operation
wait_for_stack() {
    local stack_name=$1
    local operation=$2  # CREATE, UPDATE, DELETE
    local region="${AWS_REGION:-us-east-1}"
    local max_wait=1800  # 30 minutes
    local waited=0
    
    print_status "Waiting for stack $operation to complete..."
    
    while [ $waited -lt $max_wait ]; do
        local status=$(get_stack_status "$stack_name" "$region")
        
        case "$status" in
            *"_COMPLETE")
                print_success "Stack operation completed: $status"
                return 0
                ;;
            *"_FAILED"|*"_ROLLBACK"*)
                print_error "Stack operation failed: $status"
                return 1
                ;;
            *)
                print_status "Stack status: $status (waited ${waited}s)"
                sleep 10
                waited=$((waited + 10))
                ;;
        esac
    done
    
    print_error "Stack operation timed out after ${max_wait}s"
    return 1
}

# Function to delete stack
delete_stack() {
    local stack_name=$1
    local region="${AWS_REGION:-us-east-1}"
    
    print_section "Deleting Stack: $stack_name"
    
    local status=$(get_stack_status "$stack_name" "$region")
    if [ "$status" = "NOT_FOUND" ]; then
        print_warning "Stack $stack_name does not exist"
        return 0
    fi
    
    print_status "Current stack status: $status"
    
    aws cloudformation delete-stack \
        --stack-name "$stack_name" \
        --region "$region" || {
        print_error "Failed to initiate stack deletion"
        return 1
    }
    
    wait_for_stack "$stack_name" "DELETE" "$region"
    return $?
}

# Function to check if stack exists
stack_exists() {
    local stack_name=$1
    local region="${AWS_REGION:-us-east-1}"
    
    local status=$(get_stack_status "$stack_name" "$region")
    [ "$status" != "NOT_FOUND" ]
}

# Main execution (if run directly)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    ACTION="${1:-status}"
    STACK_NAME="${2:-}"
    
    case "$ACTION" in
        status)
            if [ -z "$STACK_NAME" ]; then
                print_error "Usage: $0 status <stack-name>"
                exit 1
            fi
            status=$(get_stack_status "$STACK_NAME")
            echo "Stack status: $status"
            ;;
        outputs)
            if [ -z "$STACK_NAME" ]; then
                print_error "Usage: $0 outputs <stack-name>"
                exit 1
            fi
            get_stack_outputs "$STACK_NAME" | python3 -m json.tool
            ;;
        api-url)
            if [ -z "$STACK_NAME" ]; then
                print_error "Usage: $0 api-url <stack-name>"
                exit 1
            fi
            get_api_url_from_stack "$STACK_NAME"
            ;;
        delete)
            if [ -z "$STACK_NAME" ]; then
                print_error "Usage: $0 delete <stack-name>"
                exit 1
            fi
            delete_stack "$STACK_NAME"
            ;;
        *)
            echo "Usage: $0 {status|outputs|api-url|delete} <stack-name>"
            exit 1
            ;;
    esac
fi
