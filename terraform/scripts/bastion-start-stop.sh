#!/bin/bash
# Start or stop Bastion Host EC2 instance for cost optimization
# Useful for dev/staging environments to save costs during off-hours

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/.."

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Start or stop Bastion Host EC2 instance for cost optimization.

COMMANDS:
    start       Start the bastion host instance
    stop        Stop the bastion host instance
    status      Check the current status of the instance
    restart     Restart the instance (stop then start)

OPTIONS:
    --instance-id INSTANCE_ID    Bastion instance ID (optional, will be retrieved from Terraform)
    --region REGION              AWS region (optional, defaults to Terraform output or us-east-1)
    --wait                       Wait for operation to complete (default: true)
    --no-wait                    Don't wait for operation to complete
    -h, --help                   Show this help message

EXAMPLES:
    # Start bastion host
    $0 start

    # Stop bastion host
    $0 stop

    # Check instance status
    $0 status

    # Restart the instance
    $0 restart

    # Stop without waiting
    $0 stop --no-wait

EOF
    exit 1
}

# Parse arguments
COMMAND=""
INSTANCE_ID=""
AWS_REGION=""
WAIT=true

while [[ $# -gt 0 ]]; do
    case $1 in
        start|stop|status|restart)
            COMMAND="$1"
            shift
            ;;
        --instance-id)
            INSTANCE_ID="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --wait)
            WAIT=true
            shift
            ;;
        --no-wait)
            WAIT=false
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            usage
            ;;
    esac
done

if [ -z "$COMMAND" ]; then
    echo -e "${RED}Error: COMMAND is required${NC}"
    usage
fi

# Get Terraform outputs
cd "$TERRAFORM_DIR" || exit 1

if [ -z "$INSTANCE_ID" ]; then
    INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
fi

if [ -z "$AWS_REGION" ]; then
    AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
fi

if [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}Error: Bastion host instance ID not found.${NC}"
    echo "Make sure Terraform has been applied and bastion host is enabled."
    exit 1
fi

# Function to get instance status
get_status() {
    aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "unknown"
}

# Function to wait for instance state
wait_for_state() {
    local target_state="$1"
    local max_wait="${2:-300}"  # Default 5 minutes
    local elapsed=0
    local check_interval=10

    echo -e "${BLUE}Waiting for instance to reach state: ${target_state}${NC}"
    
    while [ $elapsed -lt $max_wait ]; do
        local current_state=$(get_status)
        
        if [ "$current_state" = "$target_state" ]; then
            echo -e "${GREEN}Instance is now ${target_state}${NC}"
            return 0
        fi
        
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo -e "${BLUE}Current state: ${current_state} (waiting... ${elapsed}s)${NC}"
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    local final_state=$(get_status)
    echo -e "${RED}Timeout: Instance did not reach ${target_state} within ${max_wait}s (current: ${final_state})${NC}"
    return 1
}

# Function to wait for SSM to be ready (only for start command)
wait_for_ssm() {
    local max_wait=120  # 2 minutes
    local elapsed=0
    local check_interval=5

    echo -e "${BLUE}Waiting for SSM to be ready...${NC}"
    
    while [ $elapsed -lt $max_wait ]; do
        if aws ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null | grep -q "Online"; then
            echo -e "${GREEN}SSM is ready${NC}"
            return 0
        fi
        
        if [ $((elapsed % 15)) -eq 0 ]; then
            echo -e "${BLUE}SSM not ready yet (waiting... ${elapsed}s)${NC}"
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    echo -e "${YELLOW}Warning: SSM may not be ready yet (timeout after ${max_wait}s)${NC}"
    return 1
}

# Execute command
case "$COMMAND" in
    status)
        STATUS=$(get_status)
        echo -e "${BLUE}Bastion Host Status:${NC}"
        echo "  Instance ID: $INSTANCE_ID"
        echo "  Region: $AWS_REGION"
        echo "  State: $STATUS"
        
        if [ "$STATUS" = "running" ]; then
            # Get additional info
            PUBLIC_IP=$(aws ec2 describe-instances \
                --instance-ids "$INSTANCE_ID" \
                --region "$AWS_REGION" \
                --query 'Reservations[0].Instances[0].PublicIpAddress' \
                --output text 2>/dev/null || echo "N/A")
            echo "  Public IP: $PUBLIC_IP"
            
            # Check SSM status
            SSM_STATUS=$(aws ssm describe-instance-information \
                --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
                --region "$AWS_REGION" \
                --query 'InstanceInformationList[0].PingStatus' \
                --output text 2>/dev/null || echo "Unknown")
            echo "  SSM Status: $SSM_STATUS"
        fi
        ;;
    
    start)
        CURRENT_STATUS=$(get_status)
        
        if [ "$CURRENT_STATUS" = "running" ]; then
            echo -e "${YELLOW}Bastion host is already running${NC}"
            exit 0
        fi
        
        echo -e "${BLUE}Starting bastion host instance: $INSTANCE_ID${NC}"
        
        aws ec2 start-instances \
            --instance-ids "$INSTANCE_ID" \
            --region "$AWS_REGION" > /dev/null
        
        if [ "$WAIT" = true ]; then
            if wait_for_state "running"; then
                echo -e "${GREEN}Bastion host started successfully${NC}"
                # Wait for SSM to be ready
                wait_for_ssm || true
            else
                echo -e "${RED}Failed to start bastion host${NC}"
                exit 1
            fi
        else
            echo -e "${YELLOW}Bastion host start initiated (not waiting for completion)${NC}"
        fi
        ;;
    
    stop)
        CURRENT_STATUS=$(get_status)
        
        if [ "$CURRENT_STATUS" = "stopped" ]; then
            echo -e "${YELLOW}Bastion host is already stopped${NC}"
            exit 0
        fi
        
        echo -e "${BLUE}Stopping bastion host instance: $INSTANCE_ID${NC}"
        
        aws ec2 stop-instances \
            --instance-ids "$INSTANCE_ID" \
            --region "$AWS_REGION" > /dev/null
        
        if [ "$WAIT" = true ]; then
            if wait_for_state "stopped"; then
                echo -e "${GREEN}Bastion host stopped successfully${NC}"
            else
                echo -e "${RED}Failed to stop bastion host${NC}"
                exit 1
            fi
        else
            echo -e "${YELLOW}Bastion host stop initiated (not waiting for completion)${NC}"
        fi
        ;;
    
    restart)
        echo -e "${BLUE}Restarting bastion host instance: $INSTANCE_ID${NC}"
        
        # Stop first
        CURRENT_STATUS=$(get_status)
        if [ "$CURRENT_STATUS" = "running" ]; then
            echo -e "${BLUE}Stopping instance...${NC}"
            "$0" stop --instance-id "$INSTANCE_ID" --region "$AWS_REGION" --wait
        fi
        
        # Then start
        echo -e "${BLUE}Starting instance...${NC}"
        "$0" start --instance-id "$INSTANCE_ID" --region "$AWS_REGION" --wait
        ;;
    
    *)
        echo -e "${RED}Error: Unknown command: $COMMAND${NC}"
        usage
        ;;
esac


