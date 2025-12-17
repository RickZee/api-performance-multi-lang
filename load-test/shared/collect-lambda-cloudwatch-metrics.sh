#!/bin/bash

# Collect Lambda CloudWatch Metrics
# Collects comprehensive CloudWatch metrics for Lambda functions

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/color-output.sh" 2>/dev/null || true

# Configuration
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_BASE_DIR="$BASE_DIR/results/lambda-tests"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REGION="${AWS_REGION:-us-east-1}"

# Function to print section header
print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to export CloudWatch Logs
export_cloudwatch_logs() {
    local function_name=$1
    local start_time=$2
    local end_time=$3
    local output_file=$4
    
    print_status "Exporting CloudWatch Logs for $function_name..."
    
    local log_group="/aws/lambda/$function_name"
    
    # Check if log group exists
    if ! aws logs describe-log-groups --log-group-name-prefix "$log_group" --region "$REGION" --query "logGroups[?logGroupName=='$log_group']" --output text | grep -q "$log_group"; then
        print_warning "Log group $log_group does not exist"
        return 1
    fi
    
    # Export logs
    aws logs filter-log-events \
        --log-group-name "$log_group" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --region "$REGION" \
        --output json > "$output_file" 2>&1 || {
        print_warning "Failed to export CloudWatch Logs"
        return 1
    }
    
    print_success "CloudWatch Logs exported to: $output_file"
    return 0
}

# Function to get CloudWatch metrics
get_cloudwatch_metrics() {
    local function_name=$1
    local start_time=$2
    local end_time=$3
    local metric_name=$4
    
    # Convert timestamps to ISO format for CloudWatch
    local start_iso=$(date -u -r $((start_time / 1000)) +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || date -u -d "@$((start_time / 1000))" +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || echo "")
    local end_iso=$(date -u -r $((end_time / 1000)) +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || date -u -d "@$((end_time / 1000))" +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || echo "")
    
    aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name "$metric_name" \
        --dimensions Name=FunctionName,Value="$function_name" \
        --start-time "$start_iso" \
        --end-time "$end_iso" \
        --period 60 \
        --statistics Average,Maximum,Sum \
        --region "$REGION" \
        --output json 2>/dev/null || echo "{}"
}

# Function to collect all metrics for a Lambda function
collect_lambda_metrics() {
    local function_name=$1
    local start_time=$2
    local end_time=$3
    local api_name=$4
    
    print_section "Collecting CloudWatch Metrics: $function_name"
    
    # Set up results directory
    local api_results_dir="$RESULTS_BASE_DIR/$api_name"
    mkdir -p "$api_results_dir"
    
    # Export CloudWatch Logs
    local log_file="$api_results_dir/${api_name}-cloudwatch-logs-${TIMESTAMP}.log"
    export_cloudwatch_logs "$function_name" "$start_time" "$end_time" "$log_file" || true
    
    # Get CloudWatch metrics
    local metrics_file="$api_results_dir/${api_name}-cloudwatch-metrics-${TIMESTAMP}.json"
    
    print_status "Collecting CloudWatch metrics..."
    
    python3 -c "
import json
import subprocess
import sys

function_name = '$function_name'
start_time = $start_time
end_time = $end_time
region = '$REGION'

metrics = {
    'function_name': function_name,
    'start_time': start_time,
    'end_time': end_time,
    'metrics': {}
}

# Collect various metrics
metric_names = [
    'Invocations',
    'Errors',
    'Duration',
    'Throttles',
    'ConcurrentExecutions',
    'DeadLetterErrors'
]

for metric_name in metric_names:
    try:
        result = subprocess.run(
            ['aws', 'cloudwatch', 'get-metric-statistics',
             '--namespace', 'AWS/Lambda',
             '--metric-name', metric_name,
             '--dimensions', f'Name=FunctionName,Value={function_name}',
             '--start-time', f'{(start_time // 1000)}',
             '--end-time', f'{(end_time // 1000)}',
             '--period', '60',
             '--statistics', 'Average,Maximum,Sum,Minimum',
             '--region', region,
             '--output', 'json'],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0:
            metrics['metrics'][metric_name] = json.loads(result.stdout)
    except Exception as e:
        print(f'Warning: Failed to get {metric_name}: {e}', file=sys.stderr)

print(json.dumps(metrics, indent=2))
" > "$metrics_file" 2>&1 || {
        print_warning "Failed to collect some CloudWatch metrics"
    }
    
    print_success "CloudWatch metrics saved to: $metrics_file"
    
    # Analyze Lambda metrics from logs if analyzer is available
    if [ -f "$SCRIPT_DIR/analyze-lambda-metrics.py" ] && [ -f "$log_file" ]; then
        print_status "Analyzing Lambda metrics from CloudWatch Logs..."
        local analysis_file="$api_results_dir/${api_name}-lambda-metrics-${TIMESTAMP}.json"
        
        python3 "$SCRIPT_DIR/analyze-lambda-metrics.py" "$log_file" > "$analysis_file" 2>&1 || {
            print_warning "Failed to analyze Lambda metrics"
        }
        
        print_success "Lambda metrics analysis saved to: $analysis_file"
    fi
    
    return 0
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -lt 4 ]; then
        echo "Usage: $0 <function_name> <start_time_ms> <end_time_ms> <api_name>"
        exit 1
    fi
    
    FUNCTION_NAME=$1
    START_TIME=$2
    END_TIME=$3
    API_NAME=$4
    
    collect_lambda_metrics "$FUNCTION_NAME" "$START_TIME" "$END_TIME" "$API_NAME"
fi
