#!/bin/bash
# Deploy Java REST API to EKS
# This script builds the Docker image, pushes to ECR (or uses local), and deploys to EKS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/.."
K8S_DIR="$TERRAFORM_DIR/k8s"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploy Java API to EKS${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl is not installed${NC}"
    echo "  Install with: brew install kubectl"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI is not installed${NC}"
    exit 1
fi

# Get EKS cluster name from Terraform
echo -e "${BLUE}Step 1: Getting EKS cluster information...${NC}"
cd "$TERRAFORM_DIR"

CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}✗ EKS cluster not found. Make sure EKS is enabled and deployed.${NC}"
    echo "  Run: terraform apply"
    exit 1
fi

CLUSTER_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
echo -e "${GREEN}✓ Found EKS cluster: $CLUSTER_NAME${NC}"
echo ""

# Update kubeconfig
echo -e "${BLUE}Step 2: Updating kubeconfig...${NC}"
aws eks update-kubeconfig --region "$CLUSTER_REGION" --name "$CLUSTER_NAME" 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ kubeconfig updated${NC}"
else
    echo -e "${RED}✗ Failed to update kubeconfig${NC}"
    exit 1
fi
echo ""

# Get Aurora connection details
echo -e "${BLUE}Step 3: Getting Aurora connection details...${NC}"
AURORA_ENDPOINT=$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")
AURORA_PASSWORD=$(terraform output -raw aurora_connection_string 2>/dev/null | grep -oP 'password=\K[^@]+' || echo "")

if [ -z "$AURORA_ENDPOINT" ]; then
    echo -e "${YELLOW}⚠ Aurora endpoint not found. Using values from terraform.tfvars${NC}"
    # Try to get from tfvars
    AURORA_PASSWORD=$(grep "database_password" "$TERRAFORM_DIR/terraform.tfvars" | cut -d'"' -f2 || echo "")
fi

if [ -z "$AURORA_ENDPOINT" ] || [ -z "$AURORA_PASSWORD" ]; then
    echo -e "${RED}✗ Missing Aurora connection details${NC}"
    echo "  Please ensure Aurora is deployed and terraform outputs are available"
    exit 1
fi

echo -e "${GREEN}✓ Aurora endpoint: $AURORA_ENDPOINT${NC}"
echo ""

# Create Aurora secret
echo -e "${BLUE}Step 4: Creating Aurora credentials secret...${NC}"
R2DBC_URL="r2dbc:postgresql://${AURORA_ENDPOINT}:5432/car_entities"

kubectl create secret generic aurora-credentials \
  --from-literal=r2dbc-url="$R2DBC_URL" \
  --from-literal=username=postgres \
  --from-literal=password="$AURORA_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f - 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Secret created/updated${NC}"
else
    echo -e "${RED}✗ Failed to create secret${NC}"
    exit 1
fi
echo ""

# Deploy API
echo -e "${BLUE}Step 5: Deploying Java API to EKS...${NC}"
kubectl apply -f "$K8S_DIR/java-api-deployment.yaml" 2>&1
kubectl apply -f "$K8S_DIR/java-api-service.yaml" 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Deployment created${NC}"
else
    echo -e "${RED}✗ Failed to deploy${NC}"
    exit 1
fi
echo ""

# Wait for deployment
echo -e "${BLUE}Step 6: Waiting for deployment to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/producer-api-java-rest 2>&1 || true
echo ""

# Get service endpoint
echo -e "${BLUE}Step 7: Getting service endpoint...${NC}"
sleep 10
SERVICE_URL=$(kubectl get service producer-api-java-rest -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "$SERVICE_URL" ]; then
    echo -e "${GREEN}✓ Service endpoint: http://$SERVICE_URL${NC}"
else
    echo -e "${YELLOW}⚠ LoadBalancer endpoint not ready yet. Check with:${NC}"
    echo "  kubectl get service producer-api-java-rest"
fi
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deployment Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Useful commands:${NC}"
echo "  Check pods:        kubectl get pods -l app=producer-api-java-rest"
echo "  Check service:     kubectl get service producer-api-java-rest"
echo "  View logs:         kubectl logs -l app=producer-api-java-rest -f"
echo "  Scale deployment:  kubectl scale deployment producer-api-java-rest --replicas=3"
echo "  Delete:            kubectl delete -f $K8S_DIR/"
echo ""
