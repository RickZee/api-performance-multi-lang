#!/bin/bash
# Rollback Aurora PostgreSQL password to previous value
# Restores password from backup file created during rotation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/.."
VALIDATE_SCRIPT="$SCRIPT_DIR/validate-db-connection.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
BACKUP_FILE=""
FORCE=false

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Rollback Aurora PostgreSQL master password to previous value.

OPTIONS:
    --backup-file FILE     Path to password backup file (required)
    --force                Skip confirmation prompts
    -h, --help             Show this help message

EXAMPLES:
    # Rollback using latest backup
    $0 --backup-file ~/.aurora-password-backups/password_backup_20240101_120000.txt

    # List available backups
    ls -lt ~/.aurora-password-backups/

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-file)
            BACKUP_FILE="$2"
            shift 2
            ;;
        --force)
            FORCE=true
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=0
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found"
        missing=1
    fi
    
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not found"
        missing=1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq not found (required for JSON parsing)"
        missing=1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_warn "kubectl not found (EKS rollback will be skipped)"
    fi
    
    if [ ! -f "$VALIDATE_SCRIPT" ]; then
        log_error "Validation script not found: $VALIDATE_SCRIPT"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to read backup file
read_backup_file() {
    if [ -z "$BACKUP_FILE" ]; then
        log_error "Backup file not specified"
        usage
    fi
    
    if [ ! -f "$BACKUP_FILE" ]; then
        log_error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi
    
    log_info "Reading backup file: $BACKUP_FILE"
    
    # Extract values from backup file
    CLUSTER_ID=$(grep "^Cluster ID:" "$BACKUP_FILE" | cut -d: -f2 | xargs || echo "")
    AURORA_ENDPOINT=$(grep "^Endpoint:" "$BACKUP_FILE" | cut -d: -f2 | xargs || echo "")
    DATABASE_NAME=$(grep "^Database:" "$BACKUP_FILE" | cut -d: -f2 | xargs || echo "")
    DATABASE_USER=$(grep "^User:" "$BACKUP_FILE" | cut -d: -f2 | xargs || echo "")
    AWS_REGION=$(grep "^Region:" "$BACKUP_FILE" | cut -d: -f2 | xargs || echo "")
    OLD_PASSWORD=$(grep "^Current Password:" "$BACKUP_FILE" | cut -d: -f2 | xargs || echo "")
    
    if [ -z "$OLD_PASSWORD" ]; then
        log_error "Could not extract password from backup file"
        exit 1
    fi
    
    if [ -z "$CLUSTER_ID" ] || [ -z "$AURORA_ENDPOINT" ]; then
        log_error "Backup file is missing required information"
        exit 1
    fi
    
    # Set defaults
    DATABASE_NAME=${DATABASE_NAME:-car_entities}
    DATABASE_USER=${DATABASE_USER:-postgres}
    AWS_REGION=${AWS_REGION:-us-east-1}
    AURORA_PORT="5432"
    
    log_success "Backup file read successfully"
    log_info "  Cluster ID: $CLUSTER_ID"
    log_info "  Endpoint: $AURORA_ENDPOINT"
    log_info "  Database: $DATABASE_NAME"
    log_info "  User: $DATABASE_USER"
    log_info "  Region: $AWS_REGION"
}

# Function to get current Terraform outputs
get_terraform_outputs() {
    log_info "Getting current Terraform outputs..."
    cd "$TERRAFORM_DIR"
    
    # Get Lambda function names
    GRPC_FUNCTION=$(terraform output -raw grpc_function_name 2>/dev/null || echo "")
    REST_FUNCTION=$(terraform output -raw rest_function_name 2>/dev/null || echo "")
    PYTHON_REST_FUNCTION=$(terraform output -raw python_rest_function_name 2>/dev/null || echo "")
    
    # Get EKS cluster name
    EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
    
    log_success "Retrieved Terraform outputs"
}

# Function to update Aurora cluster password
update_aurora_password() {
    log_info "Rolling back Aurora cluster master password..."
    
    aws rds modify-db-cluster \
        --db-cluster-identifier "$CLUSTER_ID" \
        --master-user-password "$OLD_PASSWORD" \
        --apply-immediately \
        --region "$AWS_REGION" \
        > /dev/null
    
    log_success "Aurora password rollback initiated"
    
    # Wait for cluster to be available
    log_info "Waiting for cluster to be available..."
    local max_wait=600  # 10 minutes
    local elapsed=0
    local status
    
    while [ $elapsed -lt $max_wait ]; do
        status=$(aws rds describe-db-clusters \
            --db-cluster-identifier "$CLUSTER_ID" \
            --region "$AWS_REGION" \
            --query 'DBClusters[0].Status' \
            --output text 2>/dev/null || echo "unknown")
        
        if [ "$status" = "available" ]; then
            log_success "Cluster is available"
            break
        fi
        
        log_info "Cluster status: $status (waiting...)"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    if [ "$status" != "available" ]; then
        log_error "Cluster did not become available within $max_wait seconds"
        return 1
    fi
    
    # Verify old password works
    log_info "Verifying old password..."
    sleep 5
    
    local db_name_clean=$(echo "$DATABASE_NAME" | tr -d '"')
    if "$VALIDATE_SCRIPT" --endpoint "$AURORA_ENDPOINT:$AURORA_PORT" --user "$DATABASE_USER" --password "$OLD_PASSWORD" --database "$db_name_clean" --timeout 30; then
        log_success "Old password verified"
    else
        log_error "Old password verification failed"
        return 1
    fi
}

# Function to update Lambda function environment variables
update_lambda_function() {
    local function_name=$1
    
    if [ -z "$function_name" ]; then
        return 0
    fi
    
    log_info "Rolling back Lambda function: $function_name"
    
    # Get current environment variables
    local env_vars=$(aws lambda get-function-configuration \
        --function-name "$function_name" \
        --region "$AWS_REGION" \
        --query 'Environment.Variables' \
        --output json 2>/dev/null || echo "{}")
    
    if [ "$env_vars" = "{}" ] || [ -z "$env_vars" ]; then
        log_warn "Could not retrieve environment variables for $function_name (function may not exist)"
        return 0
    fi
    
    # Update DATABASE_PASSWORD in environment variables
    local updated_env_vars=$(echo "$env_vars" | jq --arg pass "$OLD_PASSWORD" '.DATABASE_PASSWORD = $pass')
    
    # Also update DATABASE_URL if it exists
    local database_url=$(echo "$env_vars" | jq -r '.DATABASE_URL // ""')
    if [ -n "$database_url" ] && [[ "$database_url" == *"@"* ]]; then
        local url_scheme=$(echo "$database_url" | sed -n 's|^\([^:]\+\):.*|\1|p')
        local url_user=$(echo "$database_url" | sed -n 's|.*://\([^:]\+\):.*|\1|p')
        local url_host=$(echo "$database_url" | sed -n 's|.*@\([^/]\+\)/.*|\1|p')
        local url_db=$(echo "$database_url" | sed -n 's|.*/\([^?]\+\)\?.*|\1|p')
        
        if [ -n "$url_scheme" ] && [ -n "$url_user" ] && [ -n "$url_host" ] && [ -n "$url_db" ]; then
            local new_database_url="${url_scheme}://${url_user}:${OLD_PASSWORD}@${url_host}/${url_db}"
            updated_env_vars=$(echo "$updated_env_vars" | jq --arg url "$new_database_url" '.DATABASE_URL = $url')
        fi
    fi
    
    # Update Lambda function
    # AWS CLI requires environment variables in format: Variables={...}
    # Convert to compact JSON and escape properly
    local env_json=$(echo "$updated_env_vars" | jq -c .)
    local env_payload="{\"Variables\":$env_json}"
    
    aws lambda update-function-configuration \
        --function-name "$function_name" \
        --environment "$env_payload" \
        --region "$AWS_REGION" \
        > /dev/null
    
    log_success "Rolled back Lambda function: $function_name"
}

# Function to update all Lambda functions
update_lambda_functions() {
    log_info "Rolling back Lambda functions..."
    
    update_lambda_function "$GRPC_FUNCTION"
    update_lambda_function "$REST_FUNCTION"
    update_lambda_function "$PYTHON_REST_FUNCTION"
    
    log_success "All Lambda functions rolled back"
}

# Function to update EKS secrets
update_eks_secrets() {
    if [ -z "$EKS_CLUSTER_NAME" ]; then
        log_info "EKS cluster not found, skipping EKS rollback"
        return 0
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_warn "kubectl not found, skipping EKS rollback"
        return 0
    fi
    
    log_info "Rolling back EKS secrets..."
    
    # Update kubeconfig
    log_info "Updating kubeconfig for cluster: $EKS_CLUSTER_NAME"
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME" > /dev/null 2>&1
    
    # Update the secret
    local r2dbc_url="r2dbc:postgresql://${AURORA_ENDPOINT}:${AURORA_PORT}/${DATABASE_NAME}"
    
    kubectl create secret generic aurora-credentials \
        --from-literal=r2dbc-url="$r2dbc_url" \
        --from-literal=username="$DATABASE_USER" \
        --from-literal=password="$OLD_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f - > /dev/null
    
    log_success "EKS secret rolled back"
    
    # Trigger rolling restart
    log_info "Triggering rolling restart of deployments..."
    kubectl rollout restart deployment -l app=producer-api-java-rest 2>/dev/null || true
    log_success "Deployments restarted"
}

# Function to update terraform.tfvars
update_terraform_tfvars() {
    log_info "Rolling back terraform.tfvars..."
    
    local tfvars_file="$TERRAFORM_DIR/terraform.tfvars"
    
    if [ ! -f "$tfvars_file" ]; then
        log_warn "terraform.tfvars not found"
        return 0
    fi
    
    # Update password in file
    if grep -q "^database_password\s*=" "$tfvars_file"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^database_password\s*=.*|database_password = \"$OLD_PASSWORD\"|" "$tfvars_file"
        else
            sed -i "s|^database_password\s*=.*|database_password = \"$OLD_PASSWORD\"|" "$tfvars_file"
        fi
        log_success "Updated terraform.tfvars"
    else
        log_warn "database_password not found in terraform.tfvars"
    fi
}

# Function to update .env.aurora file
update_env_aurora() {
    log_info "Rolling back .env.aurora file..."
    
    local project_root="$TERRAFORM_DIR/.."
    local env_file="$project_root/.env.aurora"
    
    if [ ! -f "$env_file" ]; then
        log_warn ".env.aurora not found, creating it..."
    fi
    
    # Create/update .env.aurora file with old password
    local db_name_clean=$(echo "$DATABASE_NAME" | tr -d '"')
    local r2dbc_url="r2dbc:postgresql://${AURORA_ENDPOINT}:${AURORA_PORT}/${db_name_clean}"
    
    cat > "$env_file" << EOF
# Aurora PostgreSQL Connection
# Generated by rollback-aurora-password.sh
# Last updated: $(date)
# Source this file: source .env.aurora

export AURORA_R2DBC_URL="$r2dbc_url"
export AURORA_USERNAME="$DATABASE_USER"
export AURORA_PASSWORD="$OLD_PASSWORD"

# For Confluent Cloud CDC Connector
export DB_HOSTNAME="$AURORA_ENDPOINT"
export DB_PORT="5432"
export DB_USERNAME="$DATABASE_USER"
export DB_PASSWORD="$OLD_PASSWORD"
export DB_NAME="$db_name_clean"

# Use Aurora instead of local PostgreSQL
export USE_AURORA="true"
EOF
    
    chmod 600 "$env_file"
    log_success "Updated .env.aurora file"
}

# Function to validate connection
validate_connection() {
    log_info "Validating connection with old password..."
    
    local db_name_clean=$(echo "$DATABASE_NAME" | tr -d '"')
    if "$VALIDATE_SCRIPT" --endpoint "$AURORA_ENDPOINT:$AURORA_PORT" --user "$DATABASE_USER" --password "$OLD_PASSWORD" --database "$db_name_clean"; then
        log_success "Connection validated"
    else
        log_error "Connection validation failed"
        return 1
    fi
}

# Function to print summary
print_summary() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Password Rollback Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${GREEN}✓${NC} Aurora cluster password rolled back"
    echo -e "${GREEN}✓${NC} Terraform variables rolled back"
    echo -e "${GREEN}✓${NC} .env.aurora file rolled back"
    echo -e "${GREEN}✓${NC} Lambda functions rolled back"
    
    if [ -n "$EKS_CLUSTER_NAME" ]; then
        echo -e "${GREEN}✓${NC} EKS secrets rolled back"
    fi
    
    echo ""
    echo -e "${YELLOW}⚠ IMPORTANT:${NC}"
    echo "  1. Update CDC connector configurations manually if needed"
    echo "  2. Verify all applications are working correctly"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Aurora Password Rollback${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    check_prerequisites
    read_backup_file
    get_terraform_outputs
    
    if [ "$FORCE" = false ]; then
        echo ""
        log_warn "This will rollback the Aurora PostgreSQL master password to the previous value"
        log_warn "All consumers (Lambda, EKS) will be updated"
        echo ""
        read -p "Continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Aborted by user"
            exit 0
        fi
        echo ""
    fi
    
    update_aurora_password || {
        log_error "Failed to rollback Aurora password"
        exit 1
    }
    
    update_lambda_functions
    update_eks_secrets
    update_terraform_tfvars
    update_env_aurora
    
    # Wait a moment for all updates to propagate
    sleep 5
    
    validate_connection
    
    print_summary
    
    # Clear password from environment
    unset OLD_PASSWORD
}

# Run main function
main
