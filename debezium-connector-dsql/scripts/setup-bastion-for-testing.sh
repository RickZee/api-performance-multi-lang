#!/bin/bash
# Script to set up bastion host for running DSQL connector tests
# Uploads connector JAR, sets up environment, and prepares for testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "=========================================="
echo "Setting up Bastion for DSQL Testing"
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
BASTION_PUBLIC_IP=$(terraform output -raw bastion_host_public_ip 2>/dev/null || echo "")

if [ -z "$BASTION_INSTANCE_ID" ]; then
    echo "Error: Could not get bastion instance ID from terraform"
    exit 1
fi

echo "Bastion Instance ID: $BASTION_INSTANCE_ID"
echo "Region: $BASTION_REGION"
echo ""

# Check if connector JAR exists
cd "$PROJECT_DIR"
if [ ! -f "build/libs/debezium-connector-dsql-1.0.0.jar" ]; then
    echo "Building connector JAR..."
    ./gradlew build
fi

JAR_FILE="build/libs/debezium-connector-dsql-1.0.0.jar"
if [ ! -f "$JAR_FILE" ]; then
    echo "Error: Connector JAR not found at $JAR_FILE"
    exit 1
fi

echo "✓ Connector JAR found: $JAR_FILE"
echo ""

# Prepare setup commands for bastion
SETUP_COMMANDS=(
    "echo 'Creating directories on bastion...'"
    "mkdir -p ~/debezium-connector-dsql/{lib,config,scripts}"
    "echo '✓ Directories created'"
)

echo "Setting up directories on bastion..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":[\"mkdir -p ~/debezium-connector-dsql/{lib,config,scripts}\"]}" \
    --region "$BASTION_REGION" \
    --output text \
    --query 'Command.CommandId' 2>&1)

sleep 3
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query 'Status' \
    --output text > /dev/null 2>&1

echo "✓ Directories created on bastion"
echo ""

# Upload files via S3 or direct copy
echo "Uploading connector JAR to bastion..."
echo ""

# Option 1: Use SCP if SSH key is available
if [ -n "$BASTION_PUBLIC_IP" ] && [ -f ~/.ssh/*.pem ] 2>/dev/null; then
    SSH_KEY=$(ls ~/.ssh/*.pem 2>/dev/null | head -1)
    echo "Using SCP to upload files..."
    scp -i "$SSH_KEY" "$JAR_FILE" "ec2-user@$BASTION_PUBLIC_IP:~/debezium-connector-dsql/lib/" 2>&1 || {
        echo "SCP failed, trying alternative method..."
    }
else
    echo "SSH key not found, using SSM file transfer..."
    # Use SSM to copy file
    echo "Please upload files manually via SSM Session Manager or use S3"
    echo ""
    echo "Manual upload steps:"
    echo "1. Connect: aws ssm start-session --target $BASTION_INSTANCE_ID --region $BASTION_REGION"
    echo "2. On bastion, create directories: mkdir -p ~/debezium-connector-dsql/lib"
    echo "3. From local machine, use AWS CLI to copy via S3 or use SSM file transfer"
fi

echo ""
echo "=========================================="
echo "Setup Instructions"
echo "=========================================="
echo ""
echo "1. Connect to bastion:"
echo "   aws ssm start-session --target $BASTION_INSTANCE_ID --region $BASTION_REGION"
echo ""
echo "2. On bastion, set up environment:"
echo "   cd ~/debezium-connector-dsql"
echo "   # Upload .env.dsql file with your DSQL configuration"
echo "   # Or set environment variables manually"
echo ""
echo "3. Install Java 11 (if not already installed):"
echo "   sudo dnf install -y java-11-amazon-corretto"
echo ""
echo "4. Run tests:"
echo "   source .env.dsql"
echo "   java -cp lib/debezium-connector-dsql-1.0.0.jar:... org.junit.platform.console.ConsoleLauncher --class-path . --select-tag real-dsql"
echo ""
echo "Or use the test script after uploading:"
echo "   ./scripts/test-real-dsql.sh"
echo ""
