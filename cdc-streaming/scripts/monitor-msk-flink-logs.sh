#!/usr/bin/env bash
# Monitor CloudWatch logs for MSK, Flink, and MSK Connect
# Accesses CloudWatch Logs directly from local machine

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
CONNECTOR_ARN=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.msk_connect_connector_arn.value // ""' 2>/dev/null || echo "")
AWS_REGION=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.aws_region.value // "us-east-1"' 2>/dev/null || echo "us-east-1")
cd "$PROJECT_ROOT"

# Parse arguments
SERVICE="${1:-all}"
SINCE="${2:-30m}"
FOLLOW="${3:-false}"

# Function to tail logs directly from CloudWatch
tail_logs() {
    local log_group="$1"
    local since="${2:-30m}"
    local follow="${3:-false}"
    
    if [ "$follow" = "true" ]; then
        info "Following logs (Ctrl+C to stop)..."
        aws logs tail "$log_group" \
            --since "$since" \
            --format short \
            --region "$AWS_REGION" \
            --follow 2>&1
    else
        aws logs tail "$log_group" \
            --since "$since" \
            --format short \
            --region "$AWS_REGION" \
            2>&1 | tail -200
    fi
}

case "$SERVICE" in
    flink|all)
        if [ -n "$FLINK_APP" ]; then
            section "Flink Application Logs"
            info "Application: $FLINK_APP"
            info "Log Group: /aws/kinesisanalytics/$FLINK_APP"
            info "Since: $SINCE"
            echo ""
            
            tail_logs "/aws/kinesisanalytics/$FLINK_APP" "$SINCE" "$FOLLOW"
            echo ""
        else
            warn "Flink application name not found"
        fi
        ;;
    
    msk-connect|connector|all)
        if [ -n "$CONNECTOR_ARN" ]; then
            # Extract connector name from ARN
            CONNECTOR_NAME=$(echo "$CONNECTOR_ARN" | awk -F'/' '{print $NF}' | awk -F':' '{print $NF}')
            
            section "MSK Connect Logs"
            info "Connector: $CONNECTOR_NAME"
            info "Log Group: /aws/mskconnect/$CONNECTOR_NAME"
            info "Since: $SINCE"
            echo ""
            
            tail_logs "/aws/mskconnect/$CONNECTOR_NAME" "$SINCE" "$FOLLOW"
            echo ""
        else
            warn "MSK Connect connector ARN not found"
        fi
        ;;
    
    msk|all)
        section "MSK Cluster Logs"
        info "Note: MSK Serverless logs are limited"
        info "Checking for available MSK log groups..."
        echo ""
        
        aws logs describe-log-groups \
            --log-group-name-prefix "/aws/msk" \
            --region "$AWS_REGION" \
            --query 'logGroups[*].logGroupName' \
            --output text 2>&1 | head -10
        echo ""
        ;;
    
    *)
        echo "Usage: $0 {flink|msk-connect|msk|all} [since] [follow]"
        echo ""
        echo "Examples:"
        echo "  $0 flink                    # Show Flink logs (last 30m)"
        echo "  $0 flink 1h                 # Show Flink logs (last 1 hour)"
        echo "  $0 msk-connect              # Show MSK Connect logs"
        echo "  $0 msk                      # Show MSK logs"
        echo "  $0 all                      # Show all logs"
        echo "  $0 flink 30m true           # Follow Flink logs (live)"
        echo ""
        exit 1
        ;;
esac

if [ "$SERVICE" = "all" ]; then
    echo ""
    section "Summary"
    info "To monitor specific service:"
    echo "  $0 flink [since] [follow]"
    echo "  $0 msk-connect [since] [follow]"
    echo "  $0 msk [since] [follow]"
fi
