#!/bin/bash
# Complete setup script for bastion host to run DSQL connector tests
# Installs Java, sets up directories, and prepares environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# Get bastion info
TERRAFORM_DIR="../terraform"
if [ ! -d "$TERRAFORM_DIR" ]; then
    TERRAFORM_DIR="../../terraform"
fi

cd "$TERRAFORM_DIR"

BASTION_INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
BASTION_REGION=$(terraform output -raw bastion_host_ssm_command 2>/dev/null | sed -n 's/.*--region \([^ ]*\).*/\1/p' || echo "us-east-1")

if [ -z "$BASTION_INSTANCE_ID" ]; then
    echo "Error: Could not get bastion instance ID"
    exit 1
fi

echo "=========================================="
echo "Complete Bastion Setup for DSQL Testing"
echo "=========================================="
echo ""
echo "Bastion: $BASTION_INSTANCE_ID"
echo "Region: $BASTION_REGION"
echo ""

# Prepare setup commands
SETUP_COMMANDS=(
    "echo '=== Installing Java 11 ==='"
    "sudo dnf install -y java-11-amazon-corretto || sudo yum install -y java-11-amazon-corretto"
    "java -version"
    "echo ''"
    "echo '=== Creating project directories ==='"
    "mkdir -p ~/debezium-connector-dsql/{lib,config,scripts,logs}"
    "cd ~/debezium-connector-dsql"
    "echo '✓ Directories created'"
    "echo ''"
    "echo '=== Setting up environment ==='"
    "cat > ~/debezium-connector-dsql/README-BASTION.txt <<'EOF'"
    "Bastion Setup for DSQL Connector Testing"
    "========================================"
    ""
    "Next steps:"
    "1. Upload connector JAR to lib/ directory"
    "2. Create .env.dsql with your DSQL configuration"
    "3. Run tests using: source .env.dsql && java -cp 'lib/*' ..."
    ""
    "See BASTION-TESTING-GUIDE.md for details"
    "EOF"
    "echo '✓ Setup complete'"
    "echo ''"
    "echo '=== Current directory structure ==='"
    "ls -la ~/debezium-connector-dsql/"
    "echo ''"
    "echo '=== Java version ==='"
    "java -version"
    "echo ''"
    "echo '=== Docker status ==='"
    "sudo docker version | head -5 || echo 'Docker not available'"
)

# Build JSON
JSON_CMDS="["
for i in "${!SETUP_COMMANDS[@]}"; do
    if [ $i -gt 0 ]; then
        JSON_CMDS+=","
    fi
    CMD="${SETUP_COMMANDS[$i]//\"/\\\"}"
    JSON_CMDS+="\"$CMD\""
done
JSON_CMDS+="]"

echo "Sending setup commands to bastion..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$JSON_CMDS}" \
    --region "$BASTION_REGION" \
    --output text \
    --query 'Command.CommandId' 2>&1)

echo "Command ID: $COMMAND_ID"
echo "Waiting for execution..."
sleep 8

# Get output
echo ""
echo "=== Setup Output ==="
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$BASTION_REGION" \
    --query '[Status, StandardOutputContent]' \
    --output text

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Connect to bastion:"
echo "   aws ssm start-session --target $BASTION_INSTANCE_ID --region $BASTION_REGION"
echo ""
echo "2. Upload connector JAR:"
echo "   # From local machine:"
echo "   ./scripts/upload-to-bastion.sh"
echo "   # Or manually via SCP/SSM"
echo ""
echo "3. Create .env.dsql on bastion with your DSQL configuration"
echo ""
echo "4. Run tests (see BASTION-TESTING-GUIDE.md)"
echo ""
