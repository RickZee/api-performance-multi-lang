#!/bin/bash
# Deploy MSK Infrastructure via Terraform
# This script deploys MSK Serverless, MSK Connect, Managed Flink, and Glue Schema Registry

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploy MSK Infrastructure${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}✗ Terraform is not installed${NC}"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI is not installed${NC}"
    exit 1
fi

# Navigate to terraform directory
cd terraform

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init
fi

# Validate Terraform configuration
echo -e "${BLUE}Validating Terraform configuration...${NC}"
terraform validate

# Plan Terraform changes
echo -e "${BLUE}Planning Terraform changes...${NC}"
terraform plan -out=tfplan

# Ask for confirmation
echo -e "${YELLOW}Do you want to apply these changes? (yes/no)${NC}"
read -r response
if [[ "$response" != "yes" ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

# Apply Terraform changes
echo -e "${BLUE}Applying Terraform changes...${NC}"
terraform apply tfplan

# Clean up plan file
rm -f tfplan

# Display outputs
echo ""
echo -e "${GREEN}✓ MSK Infrastructure deployed successfully!${NC}"
echo ""
echo -e "${BLUE}MSK Cluster Information:${NC}"
terraform output -json | jq -r '
  if .msk_cluster_name.value then
    "Cluster Name: \(.msk_cluster_name.value)\n" +
    "Bootstrap Brokers: \(.msk_bootstrap_brokers.value // "N/A")\n" +
    "Cluster ARN: \(.msk_cluster_arn.value // "N/A")"
  else
    "MSK cluster not deployed (enable_msk = false)"
  end
'

echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Upload Flink application JAR to S3: ./scripts/deploy-msk-flink-app.sh"
echo "2. Start the Flink application in AWS Console"
echo "3. Verify MSK Connect connector is running"
echo "4. Deploy consumers: docker-compose -f docker-compose.msk.yml up -d"

