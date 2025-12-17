#!/bin/bash

# Deploy All Lambda Functions
# Deploys all Lambda functions to AWS using SAM

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/color-output.sh" 2>/dev/null || true

# Configuration
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LAMBDA_CONFIG_FILE="$SCRIPT_DIR/lambda-config.json"
LAMBDA_DEPLOYMENT_CONFIG_FILE="$SCRIPT_DIR/lambda-deployment-config.json"
REGION="${AWS_REGION:-us-east-1}"
S3_BUCKET="${S3_BUCKET:-}"

# Function to print section header
print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to get deployment configuration
get_deployment_config() {
    if [ -f "$LAMBDA_DEPLOYMENT_CONFIG_FILE" ]; then
        cat "$LAMBDA_DEPLOYMENT_CONFIG_FILE"
    else
        # Return default config
        echo '{
  "aws": {
    "region": "us-east-1",
    "s3_bucket": "",
    "vpc_id": "",
    "subnet_ids": []
  },
  "database": {
    "aurora_endpoint": "",
    "database_name": "car_entities",
    "database_user": "postgres",
    "database_password": ""
  }
}'
    fi
}

# Function to get all Lambda API names
get_all_lambda_apis() {
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

# Function to deploy a single Lambda function
deploy_lambda() {
    local api_name=$1
    local deployment_config_json=$2
    
    print_section "Deploying Lambda: $api_name"
    
    local api_dir="$BASE_DIR/$api_name"
    
    if [ ! -d "$api_dir" ]; then
        print_error "Lambda API directory not found: $api_dir"
        return 1
    fi
    
    # Check if deploy script exists
    if [ ! -f "$api_dir/scripts/deploy-lambda.sh" ]; then
        print_error "Deploy script not found: $api_dir/scripts/deploy-lambda.sh"
        return 1
    fi
    
    # Parse deployment config
    local stack_name="$api_name"
    local db_url=$(echo "$deployment_config_json" | python3 -c "import json, sys; config = json.load(sys.stdin); db = config.get('database', {}); print(f\"postgresql://{db.get('database_user', 'postgres')}:{db.get('database_password', '')}@{db.get('aurora_endpoint', '')}:5432/{db.get('database_name', 'car_entities')}\")" 2>/dev/null || echo "")
    local aurora_endpoint=$(echo "$deployment_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('database', {}).get('aurora_endpoint', ''))" 2>/dev/null || echo "")
    local db_name=$(echo "$deployment_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('database', {}).get('database_name', 'car_entities'))" 2>/dev/null || echo "car_entities")
    local db_user=$(echo "$deployment_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('database', {}).get('database_user', 'postgres'))" 2>/dev/null || echo "postgres")
    local db_password=$(echo "$deployment_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('database', {}).get('database_password', ''))" 2>/dev/null || echo "")
    local vpc_id=$(echo "$deployment_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('aws', {}).get('vpc_id', ''))" 2>/dev/null || echo "")
    local subnet_ids=$(echo "$deployment_config_json" | python3 -c "import json, sys; subnets = json.load(sys.stdin).get('aws', {}).get('subnet_ids', []); print(','.join(subnets) if subnets else '')" 2>/dev/null || echo "")
    
    # Deploy using the API's deploy script
    cd "$api_dir"
    
    local deploy_cmd="bash scripts/deploy-lambda.sh"
    deploy_cmd="$deploy_cmd --stack-name $stack_name"
    deploy_cmd="$deploy_cmd --region $REGION"
    
    if [ -n "$S3_BUCKET" ]; then
        deploy_cmd="$deploy_cmd --s3-bucket $S3_BUCKET"
    fi
    
    if [ -n "$aurora_endpoint" ]; then
        deploy_cmd="$deploy_cmd --aurora-endpoint $aurora_endpoint"
        deploy_cmd="$deploy_cmd --database-name $db_name"
        deploy_cmd="$deploy_cmd --database-user $db_user"
        deploy_cmd="$deploy_cmd --database-password $db_password"
    elif [ -n "$db_url" ]; then
        deploy_cmd="$deploy_cmd --database-url $db_url"
    fi
    
    if [ -n "$vpc_id" ] && [ -n "$subnet_ids" ]; then
        deploy_cmd="$deploy_cmd --vpc-id $vpc_id"
        deploy_cmd="$deploy_cmd --subnet-ids $subnet_ids"
    fi
    
    print_status "Deploying with command: $deploy_cmd"
    
    eval "$deploy_cmd" || {
        print_error "Failed to deploy $api_name"
        return 1
    }
    
    # Get API URL from stack
    if [ -f "$SCRIPT_DIR/lambda-stack-manager.sh" ]; then
        local api_url=$(bash "$SCRIPT_DIR/lambda-stack-manager.sh" api-url "$stack_name" 2>/dev/null || echo "")
        if [ -n "$api_url" ]; then
            print_success "API URL: $api_url"
            # Store API URL
            local endpoints_file="$SCRIPT_DIR/.lambda-endpoints.json"
            python3 -c "
import json
import os
endpoints = {}
if os.path.exists('$endpoints_file'):
    with open('$endpoints_file', 'r') as f:
        endpoints = json.load(f)
endpoints['$api_name'] = '$api_url'
with open('$endpoints_file', 'w') as f:
    json.dump(endpoints, f, indent=2)
"
        fi
    fi
    
    return 0
}

# Main execution
main() {
    print_section "Deploying All Lambda Functions to AWS"
    
    # Check prerequisites
    if ! command -v aws >/dev/null 2>&1; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! command -v sam >/dev/null 2>&1; then
        print_error "SAM CLI is not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    # Get deployment configuration
    local deployment_config_json=$(get_deployment_config)
    
    # Get S3 bucket
    if [ -z "$S3_BUCKET" ]; then
        S3_BUCKET=$(echo "$deployment_config_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('aws', {}).get('s3_bucket', ''))" 2>/dev/null || echo "")
    fi
    
    if [ -z "$S3_BUCKET" ]; then
        print_error "S3 bucket not specified. Set S3_BUCKET environment variable or configure in lambda-deployment-config.json"
        exit 1
    fi
    
    # Check if S3 bucket exists
    if ! aws s3 ls "s3://$S3_BUCKET" >/dev/null 2>&1; then
        print_error "S3 bucket does not exist or is not accessible: $S3_BUCKET"
        exit 1
    fi
    
    print_status "Using S3 bucket: $S3_BUCKET"
    print_status "Region: $REGION"
    
    # Get list of APIs to deploy
    local apis=($(get_all_lambda_apis))
    
    if [ ${#apis[@]} -eq 0 ]; then
        print_error "No Lambda APIs found to deploy"
        exit 1
    fi
    
    print_status "APIs to deploy: ${apis[*]}"
    
    # Deploy each Lambda function
    local deployed=0
    local failed=0
    
    for api_name in "${apis[@]}"; do
        if deploy_lambda "$api_name" "$deployment_config_json"; then
            deployed=$((deployed + 1))
        else
            failed=$((failed + 1))
        fi
    done
    
    # Summary
    print_section "Deployment Summary"
    print_status "Deployed: $deployed"
    print_status "Failed: $failed"
    
    if [ $failed -gt 0 ]; then
        print_error "Some Lambda functions failed to deploy"
        exit 1
    else
        print_success "All Lambda functions deployed successfully"
        
        # Display API URLs
        local endpoints_file="$SCRIPT_DIR/.lambda-endpoints.json"
        if [ -f "$endpoints_file" ]; then
            print_section "API Gateway Endpoints"
            python3 -c "
import json
with open('$endpoints_file', 'r') as f:
    endpoints = json.load(f)
    for api_name, url in endpoints.items():
        print(f'{api_name}: {url}')
"
        fi
        
        exit 0
    fi
}

# Run main function
main "$@"
