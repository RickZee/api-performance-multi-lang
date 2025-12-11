#!/bin/bash
# Setup Terraform S3 Backend
# Migrates local state to S3 backend after initial infrastructure creation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Terraform S3 Backend Setup${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

cd "$TERRAFORM_DIR"

# Check if backend resources exist
echo -e "${BLUE}[1/4] Checking backend resources...${NC}"
BUCKET_NAME=$(terraform output -raw terraform_state_bucket_name 2>/dev/null || echo "")

if [ -z "$BUCKET_NAME" ]; then
    echo -e "${YELLOW}⚠ Backend resources not found in Terraform state${NC}"
    echo "  This script requires the S3 bucket to be created first."
    echo ""
    echo "  Steps:"
    echo "  1. Ensure enable_terraform_state_backend = true in terraform.tfvars"
    echo "  2. Run: terraform apply"
    echo "  3. Then run this script again"
    exit 1
fi

echo -e "${GREEN}✓ Found backend resources:${NC}"
echo "  Bucket: $BUCKET_NAME"
echo -e "${CYAN}  Locking: S3 native (use_lockfile) - no DynamoDB required${NC}"
echo ""

# Check if backend config already exists
if [ -f "terraform.tfbackend" ]; then
    echo -e "${YELLOW}⚠ terraform.tfbackend already exists${NC}"
    read -p "Overwrite? (yes/no): " overwrite
    if [ "$overwrite" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi
fi

# Create backend config file
echo -e "${BLUE}[2/4] Creating backend configuration...${NC}"
cat > terraform.tfbackend <<EOF
bucket       = "$BUCKET_NAME"
key          = "terraform.tfstate"
region       = "${AWS_REGION:-us-east-1}"
encrypt      = true
use_lockfile = true
EOF

echo -e "${GREEN}✓ Created terraform.tfbackend${NC}"
echo ""

# Check current backend status
echo -e "${BLUE}[3/4] Checking current backend status...${NC}"
if terraform init -backend=false > /dev/null 2>&1; then
    CURRENT_BACKEND=$(terraform version -json 2>/dev/null | grep -q "backend" && echo "configured" || echo "local")
else
    CURRENT_BACKEND="local"
fi

if [ "$CURRENT_BACKEND" = "configured" ]; then
    echo -e "${YELLOW}⚠ Backend is already configured${NC}"
    read -p "Re-initialize with new backend config? (yes/no): " reinit
    if [ "$reinit" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi
fi

# Migrate state
echo ""
echo -e "${BLUE}[4/4] Migrating state to S3 backend...${NC}"
echo -e "${YELLOW}This will copy your local state to S3${NC}"
read -p "Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# Initialize with backend
if terraform init -backend-config=terraform.tfbackend -migrate-state; then
    echo -e "${GREEN}✓ State migrated to S3 backend${NC}"
else
    echo -e "${RED}✗ State migration failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Backend Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}Your Terraform state is now stored in S3:${NC}"
echo "  Bucket: $BUCKET_NAME"
echo "  Key:    terraform.tfstate"
echo -e "${CYAN}  Lock:   S3 native (use_lockfile) - no DynamoDB required${NC}"
echo ""
echo -e "${CYAN}Future terraform commands will use the S3 backend automatically.${NC}"
echo ""
