#!/bin/bash
# Deploy Aurora PostgreSQL Infrastructure
# Creates VPC and Aurora cluster, outputs connection details

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
echo -e "${CYAN}Aurora PostgreSQL Deployment${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

cd "$TERRAFORM_DIR"

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${YELLOW}⚠ terraform.tfvars not found${NC}"
    echo "  Creating from terraform.tfvars.example..."
    if [ -f "terraform.tfvars.example" ]; then
        cp terraform.tfvars.example terraform.tfvars
        echo -e "${GREEN}✓ Created terraform.tfvars${NC}"
        echo ""
        echo -e "${YELLOW}⚠ Please edit terraform.tfvars with your values:${NC}"
        echo "  - database_password (required)"
        echo "  - Other variables as needed"
        echo ""
        read -p "Press Enter after editing terraform.tfvars, or Ctrl+C to exit..."
    else
        echo -e "${RED}✗ terraform.tfvars.example not found${NC}"
        exit 1
    fi
fi

# Check for required variables
if ! grep -q "database_password" terraform.tfvars || grep -q "database_password = \"\"" terraform.tfvars; then
    echo -e "${RED}✗ database_password must be set in terraform.tfvars${NC}"
    exit 1
fi

# Initialize Terraform
echo -e "${BLUE}[1/4] Initializing Terraform...${NC}"

# Check if backend is configured
if [ -f "terraform.tfbackend" ]; then
    echo "  Using S3 backend configuration..."
    if terraform init -backend-config=terraform.tfbackend; then
        echo -e "${GREEN}✓ Terraform initialized with S3 backend${NC}"
    else
        echo -e "${RED}✗ Terraform initialization failed${NC}"
        exit 1
    fi
else
    echo "  Using local state (backend not configured yet)..."
    if terraform init -backend=false; then
        echo -e "${GREEN}✓ Terraform initialized with local state${NC}"
        echo -e "${YELLOW}  Note: After first apply, run ./scripts/setup-backend.sh to migrate to S3${NC}"
    else
        echo -e "${RED}✗ Terraform initialization failed${NC}"
        exit 1
    fi
fi

# Plan
echo ""
echo -e "${BLUE}[2/4] Planning Terraform changes...${NC}"
if terraform plan -out=tfplan; then
    echo -e "${GREEN}✓ Plan created${NC}"
else
    echo -e "${RED}✗ Plan failed${NC}"
    exit 1
fi

# Confirm
echo ""
echo -e "${YELLOW}Review the plan above.${NC}"
read -p "Apply changes? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    rm -f tfplan
    exit 0
fi

# Apply
echo ""
echo -e "${BLUE}[3/4] Applying Terraform changes...${NC}"
echo -e "${YELLOW}This may take 10-15 minutes for Aurora cluster creation...${NC}"
if terraform apply tfplan; then
    echo -e "${GREEN}✓ Infrastructure deployed${NC}"
    rm -f tfplan
else
    echo -e "${RED}✗ Deployment failed${NC}"
    rm -f tfplan
    exit 1
fi

# Output connection details
echo ""
echo -e "${BLUE}[4/4] Connection Details${NC}"
echo ""
echo -e "${CYAN}Aurora Endpoint:${NC}"
terraform output -raw aurora_endpoint
echo ""

echo -e "${CYAN}R2DBC Connection String:${NC}"
terraform output -raw aurora_r2dbc_connection_string
echo ""

echo -e "${CYAN}Security Group ID:${NC}"
terraform output -raw aurora_security_group_id
echo ""

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Update docker-compose environment:"
echo "     export AURORA_R2DBC_URL=\$(cd terraform && terraform output -raw aurora_r2dbc_connection_string)"
echo "     export AURORA_USERNAME=\$(cd terraform && terraform output -raw database_user || echo 'postgres')"
echo "     export AURORA_PASSWORD=<your-password>"
echo ""
echo "  2. Configure Confluent Cloud connector:"
echo "     export DB_HOSTNAME=\$(cd terraform && terraform output -raw aurora_endpoint)"
echo "     export DB_PORT=5432"
echo "     export DB_USERNAME=postgres"
echo "     export DB_PASSWORD=<your-password>"
echo "     export DB_NAME=car_entities"
echo ""
echo "  3. Restart API with Aurora connection:"
echo "     cd cdc-streaming"
echo "     docker-compose -f docker-compose.k6-confluent.yml up -d producer-api-java-rest"
echo ""
