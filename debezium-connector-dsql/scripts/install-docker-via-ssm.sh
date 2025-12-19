#!/bin/bash
# Script to install Docker on bastion host via SSM
# This script runs from your local machine and executes commands on the bastion

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "=========================================="
echo "Installing Docker on Bastion via SSM"
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

BASTION_INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
BASTION_REGION=$(terraform output -raw bastion_host_ssm_command 2>/dev/null | sed -n 's/.*--region \([^ ]*\).*/\1/p' || echo "us-east-1")

if [ -z "$BASTION_INSTANCE_ID" ]; then
    echo "Error: Could not get bastion instance ID from terraform"
    exit 1
fi

echo "Bastion Instance ID: $BASTION_INSTANCE_ID"
echo "Region: $BASTION_REGION"
echo ""

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI not found. Please install AWS CLI first."
    exit 1
fi

# Prepare installation commands as JSON array
INSTALL_COMMANDS=(
    "echo 'Updating system packages...'"
    "sudo dnf update -y || sudo yum update -y"
    "echo 'Installing Docker Engine...'"
    "sudo yum install -y docker"
    "echo 'Starting Docker service...'"
    "sudo systemctl start docker"
    "sudo systemctl enable docker"
    "echo 'Adding ec2-user to docker group...'"
    "sudo usermod -aG docker ec2-user"
    "echo 'Testing Docker installation...'"
    "sudo docker version"
    "sudo docker run --rm hello-world"
    "echo ''"
    "echo '✓ Docker installation complete!'"
    "echo '⚠ Please log out and reconnect for group changes to take effect'"
    "echo '   Or run: newgrp docker'"
)

echo "Sending installation commands to bastion via SSM..."
echo ""

# Build JSON array for commands
JSON_COMMANDS="["
for i in "${!INSTALL_COMMANDS[@]}"; do
    if [ $i -gt 0 ]; then
        JSON_COMMANDS+=","
    fi
    JSON_COMMANDS+="\"${INSTALL_COMMANDS[$i]}\""
done
JSON_COMMANDS+="]"

# Execute via SSM
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$JSON_COMMANDS}" \
    --region "$BASTION_REGION" \
    --output text \
    --query 'Command.CommandId' 2>&1)

if [ -z "$COMMAND_ID" ]; then
    echo "Error: Failed to send SSM command"
    exit 1
fi

echo "Command ID: $COMMAND_ID"
echo ""
echo "Waiting for command to complete..."
echo ""

# Wait for command to complete
sleep 5

# Get command output
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent, StandardErrorContent]' \
    --output text

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Connect to bastion: aws ssm start-session --target $BASTION_INSTANCE_ID --region $BASTION_REGION"
echo "2. Run: newgrp docker (or log out and reconnect)"
echo "3. Test: docker version (should work without sudo)"
echo ""
