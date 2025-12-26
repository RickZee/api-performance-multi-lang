#!/usr/bin/env bash
# Install MSK consumer systemd services directly on bastion
# This script creates service files directly on the bastion host

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Get configuration
cd terraform
BASTION_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
MSK_BOOTSTRAP=$(terraform output -raw msk_bootstrap_brokers 2>/dev/null || echo "")
AWS_REGION="us-east-1"  # Default region
cd "$PROJECT_ROOT"

if [ -z "$BASTION_ID" ]; then
    echo "Error: Bastion host instance ID not found"
    exit 1
fi

if [ -z "$MSK_BOOTSTRAP" ]; then
    echo "Error: MSK bootstrap servers not found"
    exit 1
fi

echo "Installing MSK consumer systemd services on bastion..."
echo "Bastion ID: $BASTION_ID"
echo "MSK Bootstrap: $MSK_BOOTSTRAP"
echo ""

# Create service files for each consumer
for consumer in loan-consumer loan-payment-consumer car-consumer service-consumer; do
    case "$consumer" in
        loan-consumer)
            TOPIC="filtered-loan-created-events-msk"
            ;;
        loan-payment-consumer)
            TOPIC="filtered-loan-payment-submitted-events-msk"
            ;;
        car-consumer)
            TOPIC="filtered-car-created-events-msk"
            ;;
        service-consumer)
            TOPIC="filtered-service-events-msk"
            ;;
    esac
    
    echo "Creating service file for $consumer..."
    
    SERVICE_CONTENT="[Unit]
Description=MSK ${consumer} for CDC streaming
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/msk-consumers/${consumer}
Environment=\"KAFKA_BOOTSTRAP_SERVERS=${MSK_BOOTSTRAP}\"
Environment=\"KAFKA_TOPIC=${TOPIC}\"
Environment=\"AWS_REGION=${AWS_REGION}\"
Environment=\"CONSUMER_GROUP_ID=${consumer}-group-msk\"
Environment=\"KAFKA_CLIENT_ID=${consumer}-client-msk\"
Environment=\"PYTHONPATH=/opt/msk-consumers/shared:/opt/msk-consumers/${consumer}\"
ExecStart=/usr/bin/python3 /opt/msk-consumers/${consumer}/consumer.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target"
    
    # Create service file locally, encode it, then install on bastion
    TEMP_SERVICE_FILE=$(mktemp)
    echo "$SERVICE_CONTENT" > "$TEMP_SERVICE_FILE"
    SERVICE_B64=$(base64 -i "$TEMP_SERVICE_FILE")
    rm "$TEMP_SERVICE_FILE"
    
    # Install service file via SSM
    INSTALL_COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$BASTION_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"echo '${SERVICE_B64}' | base64 -d > /tmp/${consumer}-msk.service\",\"sudo cp /tmp/${consumer}-msk.service /etc/systemd/system/${consumer}-msk.service\",\"sudo chmod 644 /etc/systemd/system/${consumer}-msk.service\",\"rm /tmp/${consumer}-msk.service\",\"echo Installed ${consumer}-msk.service\"]" \
        --output text \
        --query 'Command.CommandId')
    
    echo "  Command ID: $INSTALL_COMMAND_ID"
    sleep 3
    
    STATUS=$(aws ssm get-command-invocation \
        --command-id "$INSTALL_COMMAND_ID" \
        --instance-id "$BASTION_ID" \
        --query 'Status' \
        --output text 2>/dev/null || echo "Unknown")
    
    if [ "$STATUS" = "Success" ]; then
        echo "  ✓ Installed ${consumer}-msk.service"
    else
        echo "  ✗ Failed to install ${consumer}-msk.service (Status: $STATUS)"
        aws ssm get-command-invocation \
            --command-id "$INSTALL_COMMAND_ID" \
            --instance-id "$BASTION_ID" \
            --query '[StandardOutputContent,StandardErrorContent]' \
            --output text
    fi
done

echo ""
echo "Reloading systemd daemon..."
RELOAD_COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo systemctl daemon-reload","for consumer in loan-consumer-msk loan-payment-consumer-msk car-consumer-msk service-consumer-msk; do sudo systemctl enable $consumer.service 2>&1; done","ls -la /etc/systemd/system/*-msk.service"]' \
    --output text \
    --query 'Command.CommandId')

sleep 3

RELOAD_STATUS=$(aws ssm get-command-invocation \
    --command-id "$RELOAD_COMMAND_ID" \
    --instance-id "$BASTION_ID" \
    --query 'Status' \
    --output text 2>/dev/null || echo "Unknown")

if [ "$RELOAD_STATUS" = "Success" ]; then
    echo "✓ Systemd services installed and enabled"
    echo ""
    echo "To start consumers:"
    echo "  sudo systemctl start loan-consumer-msk loan-payment-consumer-msk car-consumer-msk service-consumer-msk"
    echo ""
    echo "To check status:"
    echo "  sudo systemctl status loan-consumer-msk"
else
    echo "⚠ Service installation may have issues (Status: $RELOAD_STATUS)"
fi

