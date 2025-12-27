#!/usr/bin/env bash
# Start MSK consumers on bastion host
# Supports both Docker containers and systemd services
#
# Usage:
#   ./cdc-streaming/scripts/start-bastion-consumers.sh [OPTIONS]
#
# Options:
#   -h, --help           Show this help message
#   -f, --force          Force restart even if already running
#   -d, --docker         Use Docker (default: try systemd first, fallback to Docker)
#
# Examples:
#   ./cdc-streaming/scripts/start-bastion-consumers.sh
#   ./cdc-streaming/scripts/start-bastion-consumers.sh --force
#   ./cdc-streaming/scripts/start-bastion-consumers.sh --docker

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

# Default values
FORCE_RESTART=false
USE_DOCKER=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Start MSK consumers on bastion host using Docker"
            echo ""
            echo "Usage:"
            echo "  $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -h, --help           Show this help message"
            echo "  -f, --force          Force restart even if already running"
            echo "  -b, --build          Build images before starting"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Start consumers"
            echo "  $0 --force                           # Restart all consumers"
            echo "  $0 --build                           # Build and start"
            exit 0
            ;;
        -f|--force)
            FORCE_RESTART=true
            shift
            ;;
        -d|--docker)
            USE_DOCKER=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run '$0 --help' for usage information."
            exit 1
            ;;
    esac
done

# Get Terraform outputs
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
cd "$TERRAFORM_DIR" || exit 1

TERRAFORM_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")
AWS_REGION=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.aws_region.value // "us-east-1"' 2>/dev/null || echo "us-east-1")
BASTION_INSTANCE_ID=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.bastion_host_instance_id.value // ""' 2>/dev/null || echo "")
MSK_BOOTSTRAP=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.msk_bootstrap_brokers.value // ""' 2>/dev/null || echo "")

cd "$PROJECT_ROOT"

if [ -z "$BASTION_INSTANCE_ID" ]; then
    fail "Bastion host instance ID not found. Make sure Terraform has been applied and bastion host is enabled."
    exit 1
fi

if [ -z "$MSK_BOOTSTRAP" ]; then
    fail "MSK bootstrap servers not found. Make sure MSK is deployed."
    exit 1
fi

section "Start MSK Consumers on Bastion Host"
echo ""
info "Bastion Host: $BASTION_INSTANCE_ID"
info "AWS Region: $AWS_REGION"
info "MSK Bootstrap: $MSK_BOOTSTRAP"
echo ""

# Function to execute command on bastion via SSM
execute_on_bastion() {
    local commands_json="$1"
    local wait_for_completion="${2:-true}"
    
    # Send command to bastion host
    local command_output=$(aws ssm send-command \
        --instance-ids "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --document-name "AWS-RunShellScript" \
        --parameters "{\"commands\":$commands_json}" \
        --output json 2>&1)
    
    local command_id=$(echo "$command_output" | jq -r '.Command.CommandId' 2>/dev/null || echo "")
    
    if [ -z "$command_id" ] || [ "$command_id" = "null" ]; then
        fail "Failed to send command to bastion host"
        echo "$command_output" | jq . 2>/dev/null || echo "$command_output"
        return 1
    fi
    
    if [ "$wait_for_completion" = "false" ]; then
        echo "$command_id"
        return 0
    fi
    
    # Poll for command completion
    local max_wait=120
    local wait_interval=2
    local elapsed=0
    local status="InProgress"
    
    while [ "$status" = "InProgress" ] && [ $elapsed -lt $max_wait ]; do
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
        
        if [ $elapsed -gt 10 ]; then
            wait_interval=3
        fi
        
        status=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$BASTION_INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query "Status" \
            --output text 2>/dev/null || echo "InProgress")
    done
    
    # Get full command invocation details
    local invocation=$(aws ssm get-command-invocation \
        --command-id "$command_id" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null)
    
    local final_status=$(echo "$invocation" | jq -r '.Status' 2>/dev/null || echo "Unknown")
    local stdout=$(echo "$invocation" | jq -r '.StandardOutputContent // ""' 2>/dev/null || echo "")
    local stderr=$(echo "$invocation" | jq -r '.StandardErrorContent // ""' 2>/dev/null || echo "")
    
    if [ "$final_status" = "Success" ]; then
        if [ -n "$stdout" ]; then
            echo "$stdout"
        fi
        if [ -n "$stderr" ]; then
            echo "$stderr" >&2
        fi
        return 0
    else
        fail "Command failed with status: $final_status"
        if [ -n "$stderr" ]; then
            echo "$stderr" >&2
        fi
        if [ -n "$stdout" ]; then
            echo "$stdout"
        fi
        return 1
    fi
}

# Check if consumers are already running (check both systemd and Docker)
info "Checking current consumer status..."

# Check systemd services first
CHECK_SYSTEMD_CMD=$(jq -n \
    --arg cmd "for service in loan-consumer-msk loan-payment-consumer-msk car-consumer-msk service-consumer-msk; do if systemctl is-active --quiet \$service 2>/dev/null; then echo \$service; fi; done" \
    '[$cmd]')

RUNNING_SYSTEMD=$(execute_on_bastion "$CHECK_SYSTEMD_CMD" 2>/dev/null || echo "")

# Check Docker containers
CHECK_DOCKER_CMD=$(jq -n \
    --arg cmd "docker ps --format '{{.Names}}' 2>/dev/null | grep -E '(cdc-loan-consumer-msk|cdc-loan-payment-consumer-msk|cdc-car-consumer-msk|cdc-service-consumer-msk)' || echo 'none'" \
    '[$cmd]')

RUNNING_DOCKER=$(execute_on_bastion "$CHECK_DOCKER_CMD" 2>/dev/null || echo "none")

if [ -n "$RUNNING_SYSTEMD" ] && [ "$RUNNING_SYSTEMD" != "" ]; then
    RUNNING_COUNT=$(echo "$RUNNING_SYSTEMD" | wc -l | tr -d ' ')
    if [ "$FORCE_RESTART" = true ]; then
        info "Found $RUNNING_COUNT running systemd services - restarting (--force flag)"
        USE_DOCKER=false  # Use systemd since they're already running as systemd
    else
        pass "Found $RUNNING_COUNT consumers running as systemd services"
        info "Use --force to restart them"
        exit 0
    fi
elif echo "$RUNNING_DOCKER" | grep -qE "(cdc-loan-consumer-msk|cdc-loan-payment-consumer-msk|cdc-car-consumer-msk|cdc-service-consumer-msk)"; then
    RUNNING_COUNT=$(echo "$RUNNING_DOCKER" | grep -cE "(cdc-loan-consumer-msk|cdc-loan-payment-consumer-msk|cdc-car-consumer-msk|cdc-service-consumer-msk)" || echo "0")
    if [ "$FORCE_RESTART" = true ]; then
        info "Found $RUNNING_COUNT running Docker containers - restarting (--force flag)"
        USE_DOCKER=true  # Use Docker since they're already running as Docker
    else
        pass "Found $RUNNING_COUNT consumers running as Docker containers"
        info "Use --force to restart them"
        exit 0
    fi
else
    info "No consumers currently running"
    # Try systemd first unless Docker is explicitly requested
    if [ "$USE_DOCKER" = false ]; then
        # Check if systemd services exist
        CHECK_SERVICES_EXIST_CMD=$(jq -n \
            --arg cmd "systemctl list-unit-files | grep -E '(loan-consumer-msk|loan-payment-consumer-msk|car-consumer-msk|service-consumer-msk)' | wc -l" \
            '[$cmd]')
        SERVICES_EXIST=$(execute_on_bastion "$CHECK_SERVICES_EXIST_CMD" 2>/dev/null || echo "0")
        if [ "$SERVICES_EXIST" -gt 0 ]; then
            info "Systemd services found - will use systemd"
            USE_DOCKER=false
        else
            info "No systemd services found - will use Docker"
            USE_DOCKER=true
        fi
    fi
fi

# Ensure consumers are deployed first
info "Checking if consumers are deployed on bastion..."
CHECK_DEPLOYED_CMD=$(jq -n \
    --arg cmd "test -d /opt/msk-consumers/loan-consumer && echo 'deployed' || echo 'not_deployed'" \
    '[$cmd]')

DEPLOYED_STATUS=$(execute_on_bastion "$CHECK_DEPLOYED_CMD" 2>/dev/null || echo "not_deployed")

if echo "$DEPLOYED_STATUS" | grep -q "not_deployed"; then
    warn "Consumers not deployed on bastion yet"
    info "Deploying consumers first..."
    if [ -f "$SCRIPT_DIR/deploy-msk-consumers-to-bastion.sh" ]; then
        info "Running: ./cdc-streaming/scripts/deploy-msk-consumers-to-bastion.sh"
        "$SCRIPT_DIR/deploy-msk-consumers-to-bastion.sh" || {
            fail "Failed to deploy consumers. Please run manually: ./cdc-streaming/scripts/deploy-msk-consumers-to-bastion.sh"
            exit 1
        }
    else
        fail "deploy-msk-consumers-to-bastion.sh not found. Please deploy consumers first."
        exit 1
    fi
else
    pass "Consumers are deployed on bastion"
fi

# Start consumers based on deployment type
if [ "$USE_DOCKER" = true ]; then
    # Start using Docker
    info "Starting MSK consumers using Docker..."
    
    # Stop existing containers if force restart
    if [ "$FORCE_RESTART" = true ]; then
        info "Stopping existing Docker containers..."
        STOP_CMD=$(jq -n \
            --arg cmd "cd /opt/msk-consumers 2>/dev/null || cd /tmp && docker-compose -f docker-compose.msk.yml stop loan-consumer loan-payment-consumer car-consumer service-consumer 2>&1 || docker stop cdc-loan-consumer-msk cdc-loan-payment-consumer-msk cdc-car-consumer-msk cdc-service-consumer-msk 2>&1 || true" \
            '[$cmd]')
        
        execute_on_bastion "$STOP_CMD" > /dev/null 2>&1 || true
    fi
    
    START_CMD=$(jq -n \
        --arg cmd "cd /opt/msk-consumers && export KAFKA_BOOTSTRAP_SERVERS='${MSK_BOOTSTRAP}' && export AWS_REGION='${AWS_REGION}' && docker-compose -f docker-compose.msk.yml up -d loan-consumer loan-payment-consumer car-consumer service-consumer 2>&1" \
        '[$cmd]')
    
    START_OUTPUT=$(execute_on_bastion "$START_CMD" || echo "")
    
    # Verify Docker containers
    sleep 3
    VERIFY_CMD=$(jq -n \
        --arg cmd "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'NAMES|cdc-loan-consumer-msk|cdc-loan-payment-consumer-msk|cdc-car-consumer-msk|cdc-service-consumer-msk' || echo 'none'" \
        '[$cmd]')
    
    FINAL_STATUS=$(execute_on_bastion "$VERIFY_CMD" || echo "none")
    RUNNING_COUNT=$(echo "$FINAL_STATUS" | grep -cE "(cdc-loan-consumer-msk|cdc-loan-payment-consumer-msk|cdc-car-consumer-msk|cdc-service-consumer-msk)" || echo "0")
else
    # Start using systemd
    info "Starting MSK consumers using systemd services..."
    
    # Stop existing services if force restart
    if [ "$FORCE_RESTART" = true ]; then
        info "Stopping existing systemd services..."
        STOP_CMD=$(jq -n \
            --arg cmd "sudo systemctl stop loan-consumer-msk loan-payment-consumer-msk car-consumer-msk service-consumer-msk 2>&1 || true" \
            '[$cmd]')
        
        execute_on_bastion "$STOP_CMD" > /dev/null 2>&1 || true
    fi
    
    START_CMD=$(jq -n \
        --arg cmd "sudo systemctl start loan-consumer-msk loan-payment-consumer-msk car-consumer-msk service-consumer-msk 2>&1" \
        '[$cmd]')
    
    START_OUTPUT=$(execute_on_bastion "$START_CMD" || echo "")
    
    # Verify systemd services
    sleep 5
    VERIFY_CMD=$(jq -n \
        --arg cmd "for service in loan-consumer-msk loan-payment-consumer-msk car-consumer-msk service-consumer-msk; do if systemctl is-active --quiet \$service 2>/dev/null; then echo \"\$service: active\"; else STATUS=\$(systemctl is-active \$service 2>/dev/null || echo 'inactive'); echo \"\$service: \$STATUS\"; fi; done" \
        '[$cmd]')
    
    FINAL_STATUS=$(execute_on_bastion "$VERIFY_CMD" || echo "none")
    RUNNING_COUNT=$(echo "$FINAL_STATUS" | grep -c ": active" || echo "0")
    # Remove any whitespace/newlines
    RUNNING_COUNT=$(echo "$RUNNING_COUNT" | tr -d '[:space:]')
    if [ -z "$RUNNING_COUNT" ] || [ "$RUNNING_COUNT" = "" ]; then
        RUNNING_COUNT=0
    fi
fi

# Report results
if [ "$RUNNING_COUNT" -eq 4 ]; then
    pass "All 4 MSK consumers are running on bastion host"
    echo ""
    echo "$FINAL_STATUS"
elif [ "$RUNNING_COUNT" -gt 0 ]; then
    warn "Only $RUNNING_COUNT/4 consumers are running"
    echo "$FINAL_STATUS"
    exit 1
else
    fail "No consumers are running"
    echo "Start output: $START_OUTPUT"
    echo "Status: $FINAL_STATUS"
    exit 1
fi

echo ""
pass "MSK consumers started successfully on bastion host"
info "To check status: ./cdc-streaming/scripts/check-bastion-consumers.sh --status"
info "To view logs: ./cdc-streaming/scripts/check-bastion-consumers.sh --logs <consumer-name>"

