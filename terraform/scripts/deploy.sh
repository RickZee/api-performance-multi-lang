#!/bin/bash
set -e

# Terraform deployment script
# This script initializes Terraform, plans, and applies the configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed. Please install it first."
    exit 1
fi

# Parse command line arguments
AUTO_APPROVE=false
SKIP_PLAN=false
BUILD_AND_UPLOAD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        -s|--skip-plan)
            SKIP_PLAN=true
            shift
            ;;
        -b|--build-upload)
            BUILD_AND_UPLOAD=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Usage: $0 [-a|--auto-approve] [-s|--skip-plan] [-b|--build-upload]"
            exit 1
            ;;
    esac
done

cd "$TERRAFORM_DIR"

# Build and upload Lambda functions if requested
if [ "$BUILD_AND_UPLOAD" = true ]; then
    print_step "Building and uploading Lambda functions..."
    bash "$SCRIPT_DIR/build-and-upload.sh"
fi

# Initialize Terraform
print_step "Initializing Terraform..."

# Check if backend is configured
if [ -f "terraform.tfbackend" ]; then
    print_info "Using S3 backend configuration..."
    terraform init -backend-config=terraform.tfbackend
else
    print_info "Using local state (backend not configured yet)..."
    print_warn "After first apply, run ./scripts/setup-backend.sh to migrate to S3"
    terraform init -backend=false
fi

# Format Terraform files
print_step "Formatting Terraform files..."
terraform fmt -recursive

# Validate Terraform configuration
print_step "Validating Terraform configuration..."
terraform validate

# Plan Terraform changes
if [ "$SKIP_PLAN" = false ]; then
    print_step "Planning Terraform changes..."
    terraform plan -out=tfplan
    
    if [ "$AUTO_APPROVE" = false ]; then
        echo ""
        print_warn "Review the plan above. Do you want to apply these changes? (yes/no)"
        read -r response
        if [ "$response" != "yes" ]; then
            print_info "Deployment cancelled."
            rm -f tfplan
            exit 0
        fi
    fi
fi

# Apply Terraform changes
print_step "Applying Terraform changes..."
if [ "$SKIP_PLAN" = true ]; then
    if [ "$AUTO_APPROVE" = true ]; then
        terraform apply -auto-approve
    else
        terraform apply
    fi
else
    terraform apply tfplan
    rm -f tfplan
fi

# Show outputs
print_step "Deployment complete! Outputs:"
terraform output

print_info "Deployment finished successfully!"
