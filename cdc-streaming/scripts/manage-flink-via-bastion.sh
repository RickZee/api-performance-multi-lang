#!/usr/bin/env bash
# Manage Flink application via bastion host
# This script ensures all Flink operations go through the bastion host

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
section() { echo -e "${CYAN}========================================${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}========================================${NC}"; }

# Get Terraform outputs
cd "$PROJECT_ROOT/terraform"
TERRAFORM_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")
FLINK_APP=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.flink_application_name.value // ""' 2>/dev/null || echo "")
AWS_REGION=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.aws_region.value // "us-east-1"' 2>/dev/null || echo "us-east-1")
BASTION_ID=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.bastion_host_instance_id.value // ""' 2>/dev/null || echo "")
cd "$PROJECT_ROOT"

if [ -z "$FLINK_APP" ]; then
    fail "Flink application name not found. Make sure Flink is deployed."
    exit 1
fi

if [ -z "$BASTION_ID" ]; then
    fail "Bastion host instance ID not found. Make sure bastion host is deployed."
    exit 1
fi

# Function to execute AWS CLI commands on bastion host
execute_aws_on_bastion() {
    local aws_command="$1"
    local description="${2:-Executing AWS command}"
    
    info "$description..."
    
    # Build command to run on bastion
    local commands_json=$(jq -n \
        --arg cmd "$aws_command" \
        '["'$cmd'"]')
    
    # Send command to bastion
    local command_id=$(aws ssm send-command \
        --instance-ids "$BASTION_ID" \
        --region "$AWS_REGION" \
        --document-name "AWS-RunShellScript" \
        --parameters "{\"commands\":$commands_json}" \
        --output json --query 'Command.CommandId' --output text 2>/dev/null || echo "")
    
    if [ -z "$command_id" ]; then
        fail "Failed to send command to bastion host."
        return 1
    fi
    
    info "Command ID: $command_id"
    info "Waiting for command to complete (max 120s)..."
    
    local max_wait=120
    local elapsed=0
    local check_interval=5
    
    while true; do
        local invocation=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$BASTION_ID" \
            --region "$AWS_REGION" \
            --output json 2>/dev/null || echo "{}")
        
        local status=$(echo "$invocation" | jq -r '.Status' 2>/dev/null || echo "InProgress")
        
        if [ "$status" = "Success" ] || [ "$status" = "Failed" ] || [ "$status" = "Cancelled" ] || [ "$status" = "TimedOut" ]; then
            break
        fi
        
        if [ $elapsed -ge $max_wait ]; then
            warn "Timeout: Command did not complete within ${max_wait}s. Current status: $status"
            break
        fi
        
        if [ $((elapsed % 30)) -eq 0 ]; then
            info "Current status: $status (waiting... ${elapsed}s)"
        fi
        
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done
    
    local stdout=$(echo "$invocation" | jq -r '.StandardOutputContent // ""' 2>/dev/null || echo "")
    local stderr=$(echo "$invocation" | jq -r '.StandardErrorContent // ""' 2>/dev/null || echo "")
    
    if [ "$status" = "Success" ]; then
        echo "$stdout"
        if [ -n "$stderr" ]; then
            echo "$stderr" >&2
        fi
        return 0
    else
        fail "Command failed with status: $status"
        if [ -n "$stderr" ]; then echo "$stderr" >&2; fi
        if [ -n "$stdout" ]; then echo "$stdout"; fi
        return 1
    fi
}

# Parse command
ACTION="${1:-status}"

case "$ACTION" in
    status)
        section "Flink Application Status (via Bastion)"
        info "Application: $FLINK_APP"
        info "Region: $AWS_REGION"
        info "Bastion: $BASTION_ID"
        echo ""
        
        execute_aws_on_bastion \
            "aws kinesisanalyticsv2 describe-application --application-name '$FLINK_APP' --region '$AWS_REGION' --query 'ApplicationDetail.{Status:ApplicationStatus,Version:ApplicationVersionId,LastUpdateTimestamp:LastUpdateTimestamp}' --output json" \
            "Checking Flink status"
        ;;
    
    start)
        section "Start Flink Application (via Bastion)"
        info "Application: $FLINK_APP"
        echo ""
        
        # Note: VPC configuration is managed by Terraform's null_resource
        # and should already be added to the application. VPC config is NOT
        # part of start-application's run-configuration parameter.
        info "Starting Flink application (VPC config should already be set via Terraform)"
        RUN_CONFIG='{"ApplicationRestoreConfiguration":{"ApplicationRestoreType":"SKIP_RESTORE_FROM_SNAPSHOT"}}'
        
        RUN_CONFIG_ESCAPED=$(echo "$RUN_CONFIG" | jq -c . | sed "s/'/'\\\\''/g")
        
        execute_aws_on_bastion \
            "aws kinesisanalyticsv2 start-application --application-name '$FLINK_APP' --region '$AWS_REGION' --run-configuration '$RUN_CONFIG_ESCAPED' --output json" \
            "Starting Flink application"
        
        if [ $? -eq 0 ]; then
            info "Waiting for Flink to start..."
            for i in {1..30}; do
                STATUS_OUTPUT=$(execute_aws_on_bastion \
                    "aws kinesisanalyticsv2 describe-application --application-name '$FLINK_APP' --region '$AWS_REGION' --query 'ApplicationDetail.ApplicationStatus' --output text" \
                    "Checking status" 2>&1)
                STATUS=$(echo "$STATUS_OUTPUT" | tail -1 | tr -d '[:space:]')
                echo "[$i/30] Status: $STATUS"
                if [ "$STATUS" = "RUNNING" ]; then
                    pass "Flink is RUNNING!"
                    break
                elif [ "$STATUS" = "READY" ]; then
                    warn "Flink returned to READY (check logs for errors)"
                    break
                fi
                sleep 5
            done
        fi
        ;;
    
    stop)
        section "Stop Flink Application (via Bastion)"
        info "Application: $FLINK_APP"
        echo ""
        
        execute_aws_on_bastion \
            "aws kinesisanalyticsv2 stop-application --application-name '$FLINK_APP' --region '$AWS_REGION' --output json" \
            "Stopping Flink application"
        ;;
    
    logs)
        section "Flink Application Logs (via Bastion)"
        info "Application: $FLINK_APP"
        echo ""
        
        SINCE="${2:-30m}"
        execute_aws_on_bastion \
            "aws logs tail '/aws/kinesisanalytics/$FLINK_APP' --since '$SINCE' --format short --region '$AWS_REGION' 2>&1 | tail -100" \
            "Fetching Flink logs (last $SINCE)"
        ;;
    
    *)
        echo "Usage: $0 {status|start|stop|logs [since]}"
        echo ""
        echo "Examples:"
        echo "  $0 status              # Check Flink application status"
        echo "  $0 start               # Start Flink application"
        echo "  $0 stop                # Stop Flink application"
        echo "  $0 logs                # Show logs (last 30m)"
        echo "  $0 logs 1h             # Show logs (last 1 hour)"
        exit 1
        ;;
esac

