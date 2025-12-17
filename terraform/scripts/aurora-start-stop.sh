#!/bin/bash
# Start or stop Aurora PostgreSQL cluster for cost optimization
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

Start or stop Aurora PostgreSQL cluster for cost optimization.

COMMANDS:
    start       Start the Aurora cluster
    stop        Stop the Aurora cluster
    status      Check the current status of the cluster

OPTIONS:
    --cluster-id CLUSTER_ID    Aurora cluster identifier (optional, will be retrieved from Terraform)
    --region REGION            AWS region (optional, defaults to Terraform output or us-east-1)
    --wait                     Wait for operation to complete (default: true)
    -h, --help                 Show this help message

EXAMPLES:
    # Start Aurora cluster
    $0 start

    # Stop Aurora cluster
    $0 stop

    # Check cluster status
    $0 status

    # Stop without waiting
    $0 stop --no-wait

EOF
    exit 1
}

# Function to log messages
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Parse arguments
COMMAND=""
CLUSTER_ID=""
AWS_REGION=""
WAIT=true

while [[ $# -gt 0 ]]; do
    case $1 in
        start|stop|status)
            COMMAND="$1"
            shift
            ;;
        --cluster-id)
            CLUSTER_ID="$2"
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
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [ -z "$COMMAND" ]; then
    log_error "Command is required (start, stop, or status)"
    usage
fi

# Get cluster information from Terraform
get_cluster_info() {
    log_info "Getting cluster information from Terraform..."
    cd "$TERRAFORM_DIR"

    if [ -z "$CLUSTER_ID" ]; then
        # Try to get cluster identifier from Terraform output
        AURORA_ENDPOINT=$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")
        if [ -n "$AURORA_ENDPOINT" ]; then
            # Extract cluster name from endpoint (format: cluster-name.xxxxx.region.rds.amazonaws.com)
            CLUSTER_ID=$(echo "$AURORA_ENDPOINT" | cut -d. -f1 | sed 's/-cluster$//')
            if [[ "$CLUSTER_ID" != *-cluster ]]; then
                CLUSTER_ID="${CLUSTER_ID}-cluster"
            fi
        else
            log_error "Could not determine Aurora cluster ID from Terraform outputs"
            log_info "Please provide cluster ID with --cluster-id option"
            exit 1
        fi
    fi

    if [ -z "$AWS_REGION" ]; then
        AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || aws configure get region || echo "us-east-1")
    fi

    log_success "Cluster ID: $CLUSTER_ID"
    log_info "Region: $AWS_REGION"
}

# Check cluster status
check_status() {
    local status=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_ID" \
        --region "$AWS_REGION" \
        --query 'DBClusters[0].Status' \
        --output text 2>/dev/null || echo "not-found")

    if [ "$status" = "not-found" ]; then
        log_error "Cluster not found: $CLUSTER_ID"
        return 1
    fi

    echo "$status"
}

# Start Aurora cluster
start_cluster() {
    log_info "Starting Aurora cluster: $CLUSTER_ID"

    local current_status=$(check_status)
    if [ "$current_status" = "available" ]; then
        log_warn "Cluster is already running"
        return 0
    fi

    if [ "$current_status" != "stopped" ]; then
        log_error "Cluster is in state: $current_status (expected 'stopped')"
        return 1
    fi

    # Start the cluster
    aws rds start-db-cluster \
        --db-cluster-identifier "$CLUSTER_ID" \
        --region "$AWS_REGION" \
        > /dev/null

    log_success "Cluster start initiated"

    if [ "$WAIT" = true ]; then
        log_info "Waiting for cluster to become available..."
        local max_wait=600  # 10 minutes
        local elapsed=0
        local status

        while [ $elapsed -lt $max_wait ]; do
            status=$(check_status)
            if [ "$status" = "available" ]; then
                log_success "Cluster is now available"
                return 0
            fi

            log_info "Cluster status: $status (waiting...)"
            sleep 10
            elapsed=$((elapsed + 10))
        done

        log_error "Cluster did not become available within $max_wait seconds"
        return 1
    fi
}

# Stop Aurora cluster
stop_cluster() {
    log_info "Stopping Aurora cluster: $CLUSTER_ID"

    local current_status=$(check_status)
    if [ "$current_status" = "stopped" ]; then
        log_warn "Cluster is already stopped"
        return 0
    fi

    if [ "$current_status" != "available" ]; then
        log_error "Cluster is in state: $current_status (expected 'available')"
        return 1
    fi

    # Stop the cluster
    aws rds stop-db-cluster \
        --db-cluster-identifier "$CLUSTER_ID" \
        --region "$AWS_REGION" \
        > /dev/null

    log_success "Cluster stop initiated"

    if [ "$WAIT" = true ]; then
        log_info "Waiting for cluster to stop..."
        local max_wait=300  # 5 minutes
        local elapsed=0
        local status

        while [ $elapsed -lt $max_wait ]; do
            status=$(check_status)
            if [ "$status" = "stopped" ]; then
                log_success "Cluster is now stopped"
                return 0
            fi

            log_info "Cluster status: $status (waiting...)"
            sleep 10
            elapsed=$((elapsed + 10))
        done

        log_error "Cluster did not stop within $max_wait seconds"
        return 1
    fi
}

# Show cluster status
show_status() {
    local status=$(check_status)
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${BLUE}Cluster Status${NC}"
        echo "  Cluster ID: $CLUSTER_ID"
        echo "  Region: $AWS_REGION"
        echo "  Status: $status"
        echo ""

        if [ "$status" = "available" ]; then
            log_info "Cluster is running (incurring costs)"
        elif [ "$status" = "stopped" ]; then
            log_info "Cluster is stopped (not incurring compute costs, only storage)"
        else
            log_warn "Cluster is in transition state: $status"
        fi
    fi
}

# Main execution
main() {
    # Check prerequisites
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found"
        exit 1
    fi

    if ! command -v terraform &> /dev/null; then
        log_warn "Terraform not found, cluster ID must be provided with --cluster-id"
    fi

    get_cluster_info

    case "$COMMAND" in
        start)
            start_cluster
            ;;
        stop)
            stop_cluster
            ;;
        status)
            show_status
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            usage
            ;;
    esac
}

# Run main function
main
