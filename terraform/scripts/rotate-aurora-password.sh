#!/bin/bash
# Rotate Aurora PostgreSQL master password
# Updates Aurora cluster and all consumers (Lambda, EKS, CDC connectors)

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
BACKUP_DIR="$HOME/.aurora-password-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/password_backup_$TIMESTAMP.txt"

# Flags
DRY_RUN=false
SKIP_LAMBDA=false
SKIP_EKS=false
FORCE=false

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Rotate Aurora PostgreSQL master password and update all consumers.

OPTIONS:
    --dry-run              Show what would be done without making changes
    --skip-lambda          Skip updating Lambda functions
    --skip-eks             Skip updating EKS secrets
    --force                Skip confirmation prompts
    --backup-dir DIR       Directory for password backups (default: ~/.aurora-password-backups)
    -h, --help             Show this help message

EXAMPLES:
    # Dry run to see what would happen
    $0 --dry-run

    # Rotate password with all updates
    $0

    # Rotate password skipping EKS (if not using EKS)
    $0 --skip-eks

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-lambda)
            SKIP_LAMBDA=true
            shift
            ;;
        --skip-eks)
            SKIP_EKS=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
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
    
    if [ "$SKIP_EKS" = false ] && ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found (required for EKS updates)"
        missing=1
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

# Function to get Terraform outputs
get_terraform_outputs() {
    log_info "Getting Terraform outputs..."
    cd "$TERRAFORM_DIR"
    
    CLUSTER_ID=$(terraform output -raw aurora_endpoint 2>/dev/null | cut -d. -f1 | sed 's/-cluster$//' || echo "")
    if [ -z "$CLUSTER_ID" ]; then
        CLUSTER_ID=$(terraform output -raw aurora_endpoint 2>/dev/null | cut -d. -f1 || echo "")
    fi
    
    # Try to get cluster identifier from Terraform state
    if [ -z "$CLUSTER_ID" ]; then
        CLUSTER_ID=$(terraform state show 'module.aurora[0].aws_rds_cluster.this' 2>/dev/null | grep 'cluster_identifier' | awk '{print $3}' || echo "")
    fi
    
    # Fallback: try to extract from endpoint
    AURORA_ENDPOINT=$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")
    if [ -n "$AURORA_ENDPOINT" ] && [ -z "$CLUSTER_ID" ]; then
        # Extract cluster name from endpoint (format: cluster-name.xxxxx.region.rds.amazonaws.com)
        CLUSTER_ID=$(echo "$AURORA_ENDPOINT" | cut -d. -f1 | sed 's/-cluster$//')
    fi
    
    AURORA_ENDPOINT=$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")
    AURORA_PORT=$(terraform output -raw aurora_port 2>/dev/null || echo "5432")
    DATABASE_NAME=$(terraform output -raw aurora_endpoint 2>/dev/null | xargs -I {} terraform state show 'module.aurora[0].aws_rds_cluster.this' 2>/dev/null | grep 'database_name' | awk '{print $3}' | tr -d '"' || echo "car_entities")
    DATABASE_USER=$(terraform output -raw aurora_endpoint 2>/dev/null | xargs -I {} terraform state show 'module.aurora[0].aws_rds_cluster.this' 2>/dev/null | grep 'master_username' | awk '{print $3}' | tr -d '"' || echo "postgres")
    AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || aws configure get region || echo "us-east-1")
    
    # Get Lambda function names
    GRPC_FUNCTION=$(terraform output -raw grpc_function_name 2>/dev/null || echo "")
    REST_FUNCTION=$(terraform output -raw rest_function_name 2>/dev/null || echo "")
    PYTHON_REST_FUNCTION=$(terraform output -raw python_rest_function_name 2>/dev/null || echo "")
    
    # Get EKS cluster name
    EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
    
    # Get current password from terraform.tfvars
    TFVARS_FILE="$TERRAFORM_DIR/terraform.tfvars"
    if [ -f "$TFVARS_FILE" ]; then
        CURRENT_PASSWORD=$(grep -E "^database_password\s*=" "$TFVARS_FILE" | cut -d'"' -f2 | head -1 || echo "")
    fi
    
    if [ -z "$AURORA_ENDPOINT" ]; then
        log_error "Could not determine Aurora endpoint from Terraform outputs"
        log_info "Make sure Aurora is enabled and deployed: terraform apply"
        exit 1
    fi
    
    # Construct full cluster identifier (AWS format)
    if [[ "$CLUSTER_ID" != *-cluster ]]; then
        CLUSTER_ID="${CLUSTER_ID}-cluster"
    fi
    
    # Try to get actual cluster identifier from AWS
    ACTUAL_CLUSTER_ID=$(aws rds describe-db-clusters --region "$AWS_REGION" --query "DBClusters[?Endpoint=='$AURORA_ENDPOINT'].DBClusterIdentifier" --output text 2>/dev/null || echo "")
    if [ -n "$ACTUAL_CLUSTER_ID" ]; then
        CLUSTER_ID="$ACTUAL_CLUSTER_ID"
    fi
    
    log_success "Retrieved Terraform outputs"
    log_info "  Cluster ID: $CLUSTER_ID"
    log_info "  Endpoint: $AURORA_ENDPOINT"
    log_info "  Database: $DATABASE_NAME"
    log_info "  User: $DATABASE_USER"
    log_info "  Region: $AWS_REGION"
}

# Function to validate current connection
validate_current_connection() {
    log_info "Validating current database connection..."
    
    if [ -z "$CURRENT_PASSWORD" ]; then
        log_warn "Current password not found in terraform.tfvars"
        log_info "Please enter current password manually:"
        read -s CURRENT_PASSWORD
        echo
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would validate connection with current password"
        return 0
    fi
    
    # Strip quotes from database name if present
    DB_NAME_CLEAN=$(echo "$DATABASE_NAME" | tr -d '"')
    if "$VALIDATE_SCRIPT" --endpoint "$AURORA_ENDPOINT:$AURORA_PORT" --user "$DATABASE_USER" --password "$CURRENT_PASSWORD" --database "$DB_NAME_CLEAN"; then
        log_success "Current password is valid"
        return 0
    else
        log_error "Current password validation failed"
        return 1
    fi
}

# Function to backup current password
backup_password() {
    log_info "Backing up current password..."
    
    mkdir -p "$BACKUP_DIR"
    
    cat > "$BACKUP_FILE" << EOF
Aurora Password Backup
======================
Timestamp: $(date)
Cluster ID: $CLUSTER_ID
Endpoint: $AURORA_ENDPOINT
Database: $DATABASE_NAME
User: $DATABASE_USER
Region: $AWS_REGION

Current Password: $CURRENT_PASSWORD

To rollback, use:
  $SCRIPT_DIR/rollback-aurora-password.sh --backup-file $BACKUP_FILE

Or manually:
  1. Update Aurora: aws rds modify-db-cluster --db-cluster-identifier $CLUSTER_ID --master-user-password "$CURRENT_PASSWORD" --apply-immediately --region $AWS_REGION
  2. Update terraform.tfvars: database_password = "$CURRENT_PASSWORD"
  3. Update .env.aurora file with old password
  4. Update Lambda functions (see backup file for function names)
  5. Update EKS secrets (if applicable)
EOF
    
    chmod 600 "$BACKUP_FILE"
    log_success "Password backed up to: $BACKUP_FILE"
}

# Function to generate new password
generate_new_password() {
    log_info "Generating new secure password..."
    
    # Generate 32-character password with mixed case, numbers, and special chars
    # AWS RDS password requirements:
    # - 8-128 characters
    # - Contains uppercase, lowercase, numbers, and special characters
    NEW_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32 | sed 's/\([a-z]\)/\U\1/' | sed 's/\([A-Z]\)/\L\1/' | head -c 32)
    
    # Ensure it meets AWS requirements by adding required character types
    NEW_PASSWORD="${NEW_PASSWORD}A1!"
    
    # Trim to 32 characters if longer
    NEW_PASSWORD=$(echo "$NEW_PASSWORD" | head -c 32)
    
    log_success "New password generated (32 characters)"
}

# Function to update Aurora cluster password
update_aurora_password() {
    log_info "Updating Aurora cluster master password..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would run: aws rds modify-db-cluster --db-cluster-identifier $CLUSTER_ID --master-user-password <NEW_PASSWORD> --apply-immediately --region $AWS_REGION"
        return 0
    fi
    
    aws rds modify-db-cluster \
        --db-cluster-identifier "$CLUSTER_ID" \
        --master-user-password "$NEW_PASSWORD" \
        --apply-immediately \
        --region "$AWS_REGION" \
        > /dev/null
    
    log_success "Aurora password update initiated"
    
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
    
    # Verify new password works
    log_info "Verifying new password..."
    sleep 5  # Give it a moment for password to propagate
    
    DB_NAME_CLEAN=$(echo "$DATABASE_NAME" | tr -d '"')
    if "$VALIDATE_SCRIPT" --endpoint "$AURORA_ENDPOINT:$AURORA_PORT" --user "$DATABASE_USER" --password "$NEW_PASSWORD" --database "$DB_NAME_CLEAN" --timeout 30; then
        log_success "New password verified"
    else
        log_error "New password verification failed"
        log_warn "Password may need a few more seconds to propagate"
        return 1
    fi
}

# Function to update Lambda function environment variables
update_lambda_function() {
    local function_name=$1
    
    if [ -z "$function_name" ]; then
        return 0
    fi
    
    log_info "Updating Lambda function: $function_name"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would update Lambda function $function_name with new DATABASE_PASSWORD"
        return 0
    fi
    
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
    local updated_env_vars=$(echo "$env_vars" | jq --arg pass "$NEW_PASSWORD" '.DATABASE_PASSWORD = $pass')
    
    # Also update DATABASE_URL if it exists and contains password
    local database_url=$(echo "$env_vars" | jq -r '.DATABASE_URL // ""')
    if [ -n "$database_url" ] && [[ "$database_url" == *"@"* ]]; then
        # Extract parts of connection string and rebuild with new password
        local url_scheme=$(echo "$database_url" | sed -n 's|^\([^:]\+\):.*|\1|p')
        local url_user=$(echo "$database_url" | sed -n 's|.*://\([^:]\+\):.*|\1|p')
        local url_host=$(echo "$database_url" | sed -n 's|.*@\([^/]\+\)/.*|\1|p')
        local url_db=$(echo "$database_url" | sed -n 's|.*/\([^?]\+\)\?.*|\1|p')
        
        if [ -n "$url_scheme" ] && [ -n "$url_user" ] && [ -n "$url_host" ] && [ -n "$url_db" ]; then
            local new_database_url="${url_scheme}://${url_user}:${NEW_PASSWORD}@${url_host}/${url_db}"
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
    
    log_success "Updated Lambda function: $function_name"
}

# Function to update all Lambda functions
update_lambda_functions() {
    if [ "$SKIP_LAMBDA" = true ]; then
        log_info "Skipping Lambda function updates"
        return 0
    fi
    
    log_info "Updating Lambda functions..."
    
    update_lambda_function "$GRPC_FUNCTION"
    update_lambda_function "$REST_FUNCTION"
    update_lambda_function "$PYTHON_REST_FUNCTION"
    
    log_success "All Lambda functions updated"
}

# Function to update EKS secrets
update_eks_secrets() {
    if [ "$SKIP_EKS" = true ]; then
        log_info "Skipping EKS secret updates"
        return 0
    fi
    
    if [ -z "$EKS_CLUSTER_NAME" ]; then
        log_info "EKS cluster not found, skipping EKS updates"
        return 0
    fi
    
    log_info "Updating EKS secrets..."
    
    # Update kubeconfig
    log_info "Updating kubeconfig for cluster: $EKS_CLUSTER_NAME"
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME" > /dev/null 2>&1
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would update Kubernetes secret aurora-credentials with new password"
        return 0
    fi
    
    # Update the secret
    local r2dbc_url="r2dbc:postgresql://${AURORA_ENDPOINT}:${AURORA_PORT}/${DATABASE_NAME}"
    
    kubectl create secret generic aurora-credentials \
        --from-literal=r2dbc-url="$r2dbc_url" \
        --from-literal=username="$DATABASE_USER" \
        --from-literal=password="$NEW_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f - > /dev/null
    
    log_success "EKS secret updated"
    
    # Trigger rolling restart of deployments using the secret
    log_info "Triggering rolling restart of deployments..."
    kubectl rollout restart deployment -l app=producer-api-java-rest 2>/dev/null || true
    log_success "Deployments restarted"
}

# Function to update terraform.tfvars
update_terraform_tfvars() {
    log_info "Updating terraform.tfvars..."
    
    local tfvars_file="$TERRAFORM_DIR/terraform.tfvars"
    
    if [ ! -f "$tfvars_file" ]; then
        log_warn "terraform.tfvars not found, creating it..."
        touch "$tfvars_file"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would update database_password in $tfvars_file"
        return 0
    fi
    
    # Backup original file
    cp "$tfvars_file" "${tfvars_file}.backup.${TIMESTAMP}"
    
    # Update password in file
    if grep -q "^database_password\s*=" "$tfvars_file"; then
        # Update existing entry
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s|^database_password\s*=.*|database_password = \"$NEW_PASSWORD\"|" "$tfvars_file"
        else
            # Linux
            sed -i "s|^database_password\s*=.*|database_password = \"$NEW_PASSWORD\"|" "$tfvars_file"
        fi
    else
        # Add new entry
        echo "" >> "$tfvars_file"
        echo "database_password = \"$NEW_PASSWORD\"" >> "$tfvars_file"
    fi
    
    log_success "Updated terraform.tfvars"
    log_warn "Original file backed up to: ${tfvars_file}.backup.${TIMESTAMP}"
}

# Function to update .env.aurora file
update_env_aurora() {
    log_info "Updating .env.aurora file..."
    
    local project_root="$TERRAFORM_DIR/.."
    local env_file="$project_root/.env.aurora"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would update .env.aurora with new credentials"
        return 0
    fi
    
    # Backup original file if it exists
    if [ -f "$env_file" ]; then
        cp "$env_file" "${env_file}.backup.${TIMESTAMP}"
    fi
    
    # Create/update .env.aurora file
    local db_name_clean=$(echo "$DATABASE_NAME" | tr -d '"')
    local r2dbc_url="r2dbc:postgresql://${AURORA_ENDPOINT}:${AURORA_PORT}/${db_name_clean}"
    
    cat > "$env_file" << EOF
# Aurora PostgreSQL Connection
# Generated by rotate-aurora-password.sh
# Last updated: $(date)
# Source this file: source .env.aurora

export AURORA_R2DBC_URL="$r2dbc_url"
export AURORA_USERNAME="$DATABASE_USER"
export AURORA_PASSWORD="$NEW_PASSWORD"

# For Confluent Cloud CDC Connector
export DB_HOSTNAME="$AURORA_ENDPOINT"
export DB_PORT="5432"
export DB_USERNAME="$DATABASE_USER"
export DB_PASSWORD="$NEW_PASSWORD"
export DB_NAME="$db_name_clean"

# Use Aurora instead of local PostgreSQL
export USE_AURORA="true"
EOF
    
    chmod 600 "$env_file"
    log_success "Updated .env.aurora file"
    if [ -f "${env_file}.backup.${TIMESTAMP}" ]; then
        log_warn "Original file backed up to: ${env_file}.backup.${TIMESTAMP}"
    fi
}

# Function to validate all connections
validate_all_connections() {
    log_info "Validating all connections..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would validate connections from all consumers"
        return 0
    fi
    
    # Validate database connection
    DB_NAME_CLEAN=$(echo "$DATABASE_NAME" | tr -d '"')
    if "$VALIDATE_SCRIPT" --endpoint "$AURORA_ENDPOINT:$AURORA_PORT" --user "$DATABASE_USER" --password "$NEW_PASSWORD" --database "$DB_NAME_CLEAN"; then
        log_success "Database connection validated"
    else
        log_error "Database connection validation failed"
        return 1
    fi
    
    # Note: Lambda and EKS validation would require invoking functions/checking pods
    # which is beyond the scope of this script
    log_info "Lambda and EKS connections should be validated manually"
}

# Function to print summary
print_summary() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Password Rotation Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${GREEN}✓${NC} Aurora cluster password updated"
    echo -e "${GREEN}✓${NC} Terraform variables updated"
    echo -e "${GREEN}✓${NC} .env.aurora file updated"
    
    if [ "$SKIP_LAMBDA" = false ]; then
        echo -e "${GREEN}✓${NC} Lambda functions updated"
    fi
    
    if [ "$SKIP_EKS" = false ] && [ -n "$EKS_CLUSTER_NAME" ]; then
        echo -e "${GREEN}✓${NC} EKS secrets updated"
    fi
    
    echo ""
    echo -e "${YELLOW}⚠ IMPORTANT:${NC}"
    echo "  1. Update CDC connector configurations manually (Confluent Cloud)"
    echo "  2. Verify all applications are working correctly"
    echo "  3. Password backup saved to: $BACKUP_FILE"
    echo ""
    echo -e "${CYAN}To rollback if needed:${NC}"
    echo "  $SCRIPT_DIR/rollback-aurora-password.sh --backup-file $BACKUP_FILE"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Aurora Password Rotation${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN MODE - No changes will be made"
        echo ""
    fi
    
    check_prerequisites
    get_terraform_outputs
    
    if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
        echo ""
        log_warn "This will rotate the Aurora PostgreSQL master password"
        log_warn "All consumers (Lambda, EKS, CDC) will be updated"
        echo ""
        read -p "Continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Aborted by user"
            exit 0
        fi
        echo ""
    fi
    
    validate_current_connection || exit 1
    backup_password
    generate_new_password
    
    update_aurora_password || {
        log_error "Failed to update Aurora password"
        exit 1
    }
    
    update_lambda_functions
    update_eks_secrets
    update_terraform_tfvars
    update_env_aurora
    
    # Wait a moment for all updates to propagate
    sleep 5
    
    validate_all_connections
    
    print_summary
    
    # Clear password from environment
    unset NEW_PASSWORD
    unset CURRENT_PASSWORD
}

# Run main function
main
