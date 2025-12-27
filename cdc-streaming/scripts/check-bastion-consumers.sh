#!/usr/bin/env bash
# Check status and logs of dockerized consumers running on bastion hosts
#
# Usage:
#   ./cdc-streaming/scripts/check-bastion-consumers.sh [OPTIONS] [CONSUMER_NAME]
#
# Options:
#   -s, --status          Show status only (default)
#   -l, --logs [LINES]   Show logs (default: 50 lines, use -f to follow)
#   -f, --follow         Follow logs (only with --logs)
#   -a, --all            Show all consumers (default)
#
# Examples:
#   ./cdc-streaming/scripts/check-bastion-consumers.sh
#   ./cdc-streaming/scripts/check-bastion-consumers.sh --status
#   ./cdc-streaming/scripts/check-bastion-consumers.sh --logs 100 loan-consumer
#   ./cdc-streaming/scripts/check-bastion-consumers.sh --logs --follow loan-consumer
#   ./cdc-streaming/scripts/check-bastion-consumers.sh --logs car-consumer

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
ACTION="status"
LOG_LINES=50
FOLLOW_LOGS=false
CONSUMER_NAME=""
SHOW_ALL=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Check status and logs of dockerized consumers running on bastion hosts"
            echo ""
            echo "Usage:"
            echo "  $0 [OPTIONS] [CONSUMER_NAME]"
            echo ""
            echo "Options:"
            echo "  -s, --status          Show status only (default)"
            echo "  -l, --logs [LINES]   Show logs (default: 50 lines)"
            echo "  -f, --follow         Follow logs (not supported via SSM, shows message)"
            echo "  -a, --all            Show all consumers (default)"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Consumer Names:"
            echo "  loan-consumer, loan-payment-consumer, car-consumer, service-consumer"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Check status of all consumers"
            echo "  $0 --status                           # Same as above"
            echo "  $0 --logs 100 loan-consumer           # Show last 100 lines of logs"
            echo "  $0 --logs car-consumer                # Show last 50 lines (default)"
            echo "  $0 --logs --follow loan-consumer      # Attempt to follow (shows info)"
            exit 0
            ;;
        -s|--status)
            ACTION="status"
            shift
            ;;
        -l|--logs)
            ACTION="logs"
            if [[ $2 =~ ^[0-9]+$ ]]; then
                LOG_LINES="$2"
                shift 2
            elif [[ "$2" == "-f" ]] || [[ "$2" == "--follow" ]]; then
                FOLLOW_LOGS=true
                shift 2
            else
                shift
            fi
            ;;
        -f|--follow)
            FOLLOW_LOGS=true
            shift
            ;;
        -a|--all)
            SHOW_ALL=true
            CONSUMER_NAME=""
            shift
            ;;
        loan-consumer|loan-payment-consumer|car-consumer|service-consumer)
            CONSUMER_NAME="$1"
            SHOW_ALL=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [OPTIONS] [CONSUMER_NAME]"
            echo "Run '$0 --help' for more information."
            exit 1
            ;;
    esac
done

# Get Terraform outputs
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
cd "$TERRAFORM_DIR" || exit 1

# Get all outputs in one go to minimize terraform calls
TERRAFORM_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")

# Extract values from cached outputs
AWS_REGION=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.aws_region.value // "us-east-1"' 2>/dev/null || echo "us-east-1")
BASTION_INSTANCE_ID=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.bastion_host_instance_id.value // ""' 2>/dev/null || echo "")

cd "$PROJECT_ROOT"

if [ -z "$BASTION_INSTANCE_ID" ]; then
    fail "Bastion host instance ID not found. Make sure Terraform has been applied and bastion host is enabled."
    exit 1
fi

# Function to get container name from consumer name
get_container_name() {
    local consumer="$1"
    case "$consumer" in
        loan-consumer)
            echo "cdc-loan-consumer-msk"
            ;;
        loan-payment-consumer)
            echo "cdc-loan-payment-consumer-msk"
            ;;
        car-consumer)
            echo "cdc-car-consumer-msk"
            ;;
        service-consumer)
            echo "cdc-service-consumer-msk"
            ;;
        *)
            echo ""
            ;;
    esac
}

# All consumer names
ALL_CONSUMERS=("loan-consumer" "loan-payment-consumer" "car-consumer" "service-consumer")

section "Bastion Host Consumer Status"
echo ""
info "Bastion Host: $BASTION_INSTANCE_ID"
info "AWS Region: $AWS_REGION"
info "Action: $ACTION"
if [ -n "$CONSUMER_NAME" ]; then
    info "Consumer: $CONSUMER_NAME"
else
    info "Consumers: All"
fi
echo ""

# Function to execute command on bastion via SSM
execute_on_bastion() {
    local commands_json="$1"
    
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
    
    # Poll for command completion with progress indicator
    local max_wait=60
    local wait_interval=1
    local elapsed=0
    local status="InProgress"
    local show_progress=false
    
    # Only show progress for longer operations
    if [ "$DEBUG" != "true" ]; then
        show_progress=false
    fi
    
    while [ "$status" = "InProgress" ] && [ $elapsed -lt $max_wait ]; do
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
        
        if [ $elapsed -gt 3 ]; then
            wait_interval=2
        fi
        
        # Show progress every 5 seconds
        if [ $show_progress = true ] && [ $((elapsed % 5)) -eq 0 ]; then
            echo -ne "\r${BLUE}Waiting for command to complete... ${elapsed}s${NC}" >&2
        fi
        
        status=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$BASTION_INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query "Status" \
            --output text 2>/dev/null || echo "InProgress")
    done
    
    if [ $show_progress = true ]; then
        echo -ne "\r${NC}" >&2  # Clear progress line
    fi
    
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

# Function to check Docker status
check_status() {
    local consumers_to_check=()
    
    if [ "$SHOW_ALL" = true ]; then
        consumers_to_check=("${ALL_CONSUMERS[@]}")
    else
        consumers_to_check=("$CONSUMER_NAME")
    fi
    
    # Build list of full container names to check
    local container_names_list=""
    for consumer in "${consumers_to_check[@]}"; do
        local container_name=$(get_container_name "$consumer")
        if [ -n "$container_name" ]; then
            if [ -z "$container_names_list" ]; then
                container_names_list="$container_name"
            else
                container_names_list="$container_names_list|$container_name"
            fi
        fi
    done
    
    if [ -z "$container_names_list" ]; then
        warn "No valid consumer names provided"
        return 1
    fi
    
    info "Checking Docker container status..."
    echo ""
    
    # Build docker ps command using full container names
    # Note: container_names_list is expanded here before being passed to jq
    local docker_cmd="CONTAINERS=\$(docker ps -a --format '{{.Names}}|{{.Status}}|{{.Image}}' 2>/dev/null | grep -E '($container_names_list)' || echo ''); if [ -n \"\$CONTAINERS\" ]; then echo \"\$CONTAINERS\"; else echo 'NONE'; fi"
    
    local commands_json=$(jq -n \
        --arg cmd1 "cd /opt/msk-consumers 2>/dev/null || cd /tmp" \
        --arg cmd2 "$docker_cmd" \
        '[$cmd1, $cmd2]')
    
    local result=$(execute_on_bastion "$commands_json")
    
    if [ $? -eq 0 ]; then
        if echo "$result" | grep -q "^NONE$" || [ -z "$result" ]; then
            warn "No Docker consumer containers found on bastion host"
        else
            echo -e "${CYAN}Docker Containers:${NC}"
            echo ""
            printf "%-30s %-25s %-40s\n" "CONTAINER NAME" "STATUS" "IMAGE"
            echo "--------------------------------------------------------------------------------"
            echo "$result" | while IFS='|' read -r name status image; do
                if echo "$status" | grep -q "Up"; then
                    printf "${GREEN}%-30s${NC} ${GREEN}%-25s${NC} %-40s\n" "$name" "$status" "$image"
                elif echo "$status" | grep -q "Exited"; then
                    printf "${YELLOW}%-30s${NC} ${YELLOW}%-25s${NC} %-40s\n" "$name" "$status" "$image"
                else
                    printf "${RED}%-30s${NC} ${RED}%-25s${NC} %-40s\n" "$name" "$status" "$image"
                fi
            done
            echo ""
        fi
    else
        warn "Could not check Docker container status"
    fi
    
    # Check systemd services
    echo ""
    info "Checking systemd services..."
    echo ""
    
    # Check each service individually for better output
    local active_count=0
    local total_count=0
    local services_found=false
    
    echo -e "${CYAN}Systemd Services:${NC}"
    echo ""
    printf "%-35s %-15s %-15s\n" "SERVICE NAME" "STATUS" "RESTARTS"
    echo "--------------------------------------------------------------------------------"
    
    for consumer in "${ALL_CONSUMERS[@]}"; do
        local service_name="${consumer}-msk"
        
        # Check if service exists and get status
        local check_cmd="if systemctl list-unit-files 2>/dev/null | grep -q '${service_name}.service'; then STATUS=\$(systemctl is-active '${service_name}' 2>/dev/null | head -1 | tr -d '\n\r' || echo 'inactive'); RESTART_COUNT=\$(systemctl show '${service_name}' --property=NRestarts --value 2>/dev/null | head -1 | tr -d '\n\r' || echo '0'); echo \"\${STATUS}|\${RESTART_COUNT}\"; else echo 'NOT_FOUND'; fi"
        
        local check_commands_json=$(jq -n \
            --arg cmd "$check_cmd" \
            '[$cmd]')
        
        local service_result=$(execute_on_bastion "$check_commands_json" 2>/dev/null || echo "ERROR|0")
        
        if echo "$service_result" | grep -q "NOT_FOUND"; then
            continue
        fi
        
        services_found=true
        total_count=$((total_count + 1))
        
        local status=$(echo "$service_result" | cut -d'|' -f1 | tr -d '\n\r' | xargs)
        local restarts=$(echo "$service_result" | cut -d'|' -f2 | tr -d '\n\r' | xargs)
        
        if [ "$status" = "active" ]; then
            printf "${GREEN}%-35s${NC} ${GREEN}%-15s${NC} %-15s\n" "$service_name" "$status" "$restarts"
            active_count=$((active_count + 1))
        elif [ "$status" = "activating" ]; then
            printf "${YELLOW}%-35s${NC} ${YELLOW}%-15s${NC} %-15s\n" "$service_name" "$status" "$restarts"
        elif [ "$status" = "failed" ] || [ "$status" = "inactive" ]; then
            printf "${RED}%-35s${NC} ${RED}%-15s${NC} %-15s\n" "$service_name" "$status" "$restarts"
        else
            printf "%-35s %-15s %-15s\n" "$service_name" "$status" "$restarts"
        fi
    done
    
    echo ""
    
    if [ "$services_found" = true ]; then
        if [ "$active_count" -eq "$total_count" ] && [ "$total_count" -gt 0 ]; then
            pass "All $total_count systemd services are active"
        elif [ "$active_count" -gt 0 ]; then
            warn "$active_count/$total_count systemd services are active"
        else
            fail "No systemd services are active ($total_count found)"
            echo ""
            info "To view service logs: $0 --logs <consumer-name>"
            info "To restart services: ./cdc-streaming/scripts/start-bastion-consumers.sh --force"
        fi
    else
        info "No systemd services found (consumers may be running as Docker containers)"
    fi
}

# Function to show logs
show_logs() {
    local consumers_to_check=()
    
    if [ "$SHOW_ALL" = true ]; then
        consumers_to_check=("${ALL_CONSUMERS[@]}")
    else
        consumers_to_check=("$CONSUMER_NAME")
    fi
    
    if [ "$FOLLOW_LOGS" = true ]; then
        warn "Following logs is not supported via SSM. Showing last $LOG_LINES lines instead."
        warn "To follow logs, connect to bastion: terraform output -raw bastion_host_ssm_command | bash"
        echo ""
    fi
    
    for consumer in "${consumers_to_check[@]}"; do
        local container_name=$(get_container_name "$consumer")
        
        if [ -z "$container_name" ]; then
            warn "Unknown consumer: $consumer"
            continue
        fi
        
        section "Logs: $consumer ($container_name)"
        echo ""
        
        # Try Docker logs first
        info "Checking Docker container logs..."
        local docker_cmd="if docker ps --format '{{.Names}}' | grep -q '^${container_name}$'; then echo '=== DOCKER LOGS ==='; docker logs --tail ${LOG_LINES} '${container_name}' 2>&1; elif docker ps -a --format '{{.Names}}' | grep -q '^${container_name}$'; then echo '=== DOCKER LOGS (container stopped) ==='; docker logs --tail ${LOG_LINES} '${container_name}' 2>&1; else echo 'DOCKER_NOT_FOUND'; fi"
        
        local commands_json=$(jq -n \
            --arg cmd1 "cd /opt/msk-consumers 2>/dev/null || cd /tmp" \
            --arg cmd2 "$docker_cmd" \
            '[$cmd1, $cmd2]')
        
        local docker_result=$(execute_on_bastion "$commands_json" 2>/dev/null || echo "")
        
        if [ -n "$docker_result" ] && ! echo "$docker_result" | grep -q "DOCKER_NOT_FOUND"; then
            echo "$docker_result"
            echo ""
        fi
        
        # Also check systemd logs
        local service_name="${consumer}-msk"
        info "Checking systemd service logs ($service_name)..."
        echo ""
        
        local systemd_cmd="if systemctl list-unit-files 2>/dev/null | grep -q '${service_name}.service'; then echo '=== SYSTEMD LOGS ==='; sudo journalctl -u ${service_name} --no-pager -n ${LOG_LINES} 2>&1; else echo 'SYSTEMD_NOT_FOUND'; fi"
        
        local systemd_commands_json=$(jq -n \
            --arg cmd "$systemd_cmd" \
            '[$cmd]')
        
        local systemd_result=$(execute_on_bastion "$systemd_commands_json" 2>/dev/null || echo "")
        
        if [ -n "$systemd_result" ] && ! echo "$systemd_result" | grep -q "SYSTEMD_NOT_FOUND"; then
            echo "$systemd_result"
        elif echo "$docker_result" | grep -q "DOCKER_NOT_FOUND"; then
            warn "No logs found for $consumer (neither Docker container nor systemd service found)"
            echo ""
            info "To start the consumer:"
            echo "  ./cdc-streaming/scripts/start-bastion-consumers.sh"
        fi
        
        echo ""
    done
}

# Main execution
case "$ACTION" in
    status)
        check_status
        ;;
    logs)
        show_logs
        ;;
    *)
        fail "Unknown action: $ACTION"
        exit 1
        ;;
esac

echo ""
pass "Operation completed"

