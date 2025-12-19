#!/bin/bash
# Script to install Docker Engine on bastion host
# Based on instructions in test-on-ec2-md

set -e

echo "=========================================="
echo "Installing Docker Engine on Bastion Host"
echo "=========================================="
echo ""

# Get bastion info from terraform
TERRAFORM_DIR="../terraform"
if [ ! -d "$TERRAFORM_DIR" ]; then
    TERRAFORM_DIR="../../terraform"
fi

if [ ! -d "$TERRAFORM_DIR" ]; then
    echo "Error: Could not find terraform directory"
    exit 1
fi

cd "$TERRAFORM_DIR"

# Get bastion instance ID
BASTION_INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
BASTION_REGION=$(terraform output -raw bastion_host_ssm_command 2>/dev/null | sed -n 's/.*--region \([^ ]*\).*/\1/p' || echo "us-east-1")

if [ -z "$BASTION_INSTANCE_ID" ]; then
    echo "Error: Could not get bastion instance ID from terraform"
    echo "Please ensure terraform is initialized and bastion host is deployed"
    exit 1
fi

echo "Bastion Instance ID: $BASTION_INSTANCE_ID"
echo "Region: $BASTION_REGION"
echo ""

# Check if we should use SSM or SSH
USE_SSM=true
if command -v aws &> /dev/null; then
    if aws ssm describe-instance-information --instance-information-filter-list key=InstanceIds,valueSet=$BASTION_INSTANCE_ID --region $BASTION_REGION &>/dev/null; then
        USE_SSM=true
    else
        USE_SSM=false
    fi
else
    USE_SSM=false
fi

if [ "$USE_SSM" = true ]; then
    echo "Using SSM Session Manager to connect"
    SSM_CMD="aws ssm start-session --target $BASTION_INSTANCE_ID --region $BASTION_REGION"
    echo ""
    echo "To install Docker, run the following commands on the bastion:"
    echo ""
    echo "1. Connect to bastion:"
    echo "   $SSM_CMD"
    echo ""
else
    BASTION_PUBLIC_IP=$(terraform output -raw bastion_host_public_ip 2>/dev/null || echo "")
    if [ -z "$BASTION_PUBLIC_IP" ]; then
        echo "Error: Could not get bastion public IP"
        exit 1
    fi
    echo "Bastion Public IP: $BASTION_PUBLIC_IP"
    echo ""
    echo "To install Docker, run the following commands on the bastion:"
    echo ""
    echo "1. Connect to bastion:"
    echo "   ssh ec2-user@$BASTION_PUBLIC_IP"
    echo ""
fi

echo "2. Once connected, run these commands:"
echo ""
echo "   # Update system packages"
echo "   sudo dnf update -y"
echo ""
echo "   # Install Docker Engine"
echo "   sudo yum install -y docker"
echo ""
echo "   # Start and enable Docker service"
echo "   sudo systemctl start docker"
echo "   sudo systemctl enable docker"
echo "   sudo systemctl status docker"
echo ""
echo "   # Add user to docker group"
echo "   sudo usermod -aG docker ec2-user"
echo "   newgrp docker"
echo ""
echo "   # Test Docker"
echo "   docker version"
echo "   docker run --rm hello-world"
echo ""
echo "   # (Optional) Install Docker Compose Plugin"
echo "   sudo mkdir -p /usr/local/lib/docker/cli-plugins"
echo "   sudo curl -SL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose"
echo "   sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose"
echo "   docker compose version"
echo ""
echo "=========================================="
echo "Installation Instructions Complete"
echo "=========================================="
echo ""
echo "After installation, log out and reconnect for group changes to take effect."
