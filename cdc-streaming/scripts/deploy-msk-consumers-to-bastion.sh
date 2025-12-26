#!/usr/bin/env bash
# Deploy MSK consumers to bastion host
# Uploads consumer code and sets up systemd services for running consumers

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

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

# Get bastion instance ID
cd terraform
BASTION_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
MSK_BOOTSTRAP=$(terraform output -raw msk_bootstrap_brokers 2>/dev/null || echo "")
cd "$PROJECT_ROOT"

if [ -z "$BASTION_ID" ]; then
    fail "Bastion host instance ID not found. Make sure bastion host is deployed."
    exit 1
fi

if [ -z "$MSK_BOOTSTRAP" ]; then
    fail "MSK bootstrap servers not found. Make sure MSK is deployed."
    exit 1
fi

info "Bastion ID: $BASTION_ID"
info "MSK Bootstrap: $MSK_BOOTSTRAP"
info "AWS Region: $AWS_REGION"
echo ""

# Create temporary directory for packaging
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

info "Packaging consumers for deployment..."
cd "$PROJECT_ROOT/cdc-streaming/consumers-msk"

# Copy all consumers and shared module
cp -r shared "$TEMP_DIR/"
for consumer in loan-consumer loan-payment-consumer car-consumer service-consumer; do
    mkdir -p "$TEMP_DIR/$consumer"
    cp "$consumer/consumer.py" "$TEMP_DIR/$consumer/"
    cp "$consumer/requirements.txt" "$TEMP_DIR/$consumer/" 2>/dev/null || true
done

# Create deployment package
cd "$TEMP_DIR"
tar -czf consumers-msk.tar.gz *
cd "$PROJECT_ROOT"

info "Uploading consumers to S3 for bastion download..."
# Get S3 bucket name
cd terraform
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
cd "$PROJECT_ROOT"

if [ -z "$S3_BUCKET" ]; then
    fail "S3 bucket name not found. Make sure S3 bucket is deployed."
    exit 1
fi

# Upload to S3
S3_KEY="msk-consumers/consumers-msk-$(date +%Y%m%d-%H%M%S).tar.gz"
info "Uploading to s3://${S3_BUCKET}/${S3_KEY}..."
aws s3 cp "$TEMP_DIR/consumers-msk.tar.gz" "s3://${S3_BUCKET}/${S3_KEY}" --region "$AWS_REGION"

if [ $? -ne 0 ]; then
    fail "Failed to upload to S3"
    exit 1
fi

pass "Consumers uploaded to S3"

info "Downloading consumers on bastion host..."
# Download from S3 on bastion
DOWNLOAD_COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"mkdir -p /opt/msk-consumers\",\"cd /opt/msk-consumers\",\"aws s3 cp s3://${S3_BUCKET}/${S3_KEY} consumers-msk.tar.gz\",\"tar -xzf consumers-msk.tar.gz\",\"rm consumers-msk.tar.gz\",\"chmod -R 755 /opt/msk-consumers\",\"ls -la /opt/msk-consumers\"]" \
    --output text \
    --query 'Command.CommandId')

info "Waiting for download to complete..."
sleep 10

# Check download status
DOWNLOAD_STATUS=$(aws ssm get-command-invocation \
    --command-id "$DOWNLOAD_COMMAND_ID" \
    --instance-id "$BASTION_ID" \
    --query 'Status' \
    --output text 2>/dev/null || echo "Unknown")

if [ "$DOWNLOAD_STATUS" = "Success" ]; then
    pass "Consumers downloaded and extracted on bastion"
else
    warn "Download status: $DOWNLOAD_STATUS"
    aws ssm get-command-invocation \
        --command-id "$DOWNLOAD_COMMAND_ID" \
        --instance-id "$BASTION_ID" \
        --query '[StandardOutputContent,StandardErrorContent]' \
        --output text
    fail "Failed to download consumers on bastion"
    exit 1
fi

info "Installing Python dependencies on bastion..."
INSTALL_COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["cd /opt/msk-consumers/shared && python3 -m pip install --user -r requirements.txt 2>&1 || python3 -m pip install --user confluent-kafka aws-msk-iam-sasl-signer-python backports.zoneinfo"]' \
    --output text \
    --query 'Command.CommandId')

info "Waiting for dependency installation..."
sleep 10

INSTALL_STATUS=$(aws ssm get-command-invocation \
    --command-id "$INSTALL_COMMAND_ID" \
    --instance-id "$BASTION_ID" \
    --query 'Status' \
    --output text 2>/dev/null || echo "Unknown")

if [ "$INSTALL_STATUS" = "Success" ]; then
    pass "Dependencies installed successfully"
else
    warn "Dependency installation status: $INSTALL_STATUS"
    aws ssm get-command-invocation \
        --command-id "$INSTALL_COMMAND_ID" \
        --instance-id "$BASTION_ID" \
        --query '[StandardOutputContent,StandardErrorContent]' \
        --output text
fi

info "Creating systemd service files..."
# Create systemd service for each consumer
SERVICE_FILES=""
for consumer in loan-consumer loan-payment-consumer car-consumer service-consumer; do
    # Determine topic name
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
    
    SERVICE_FILE="/tmp/${consumer}-msk.service"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=MSK ${consumer} for CDC streaming
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/msk-consumers/${consumer}
Environment="KAFKA_BOOTSTRAP_SERVERS=${MSK_BOOTSTRAP}"
Environment="KAFKA_TOPIC=${TOPIC}"
Environment="AWS_REGION=${AWS_REGION}"
Environment="CONSUMER_GROUP_ID=${consumer}-group-msk"
Environment="KAFKA_CLIENT_ID=${consumer}-client-msk"
Environment="PYTHONPATH=/opt/msk-consumers/shared:/opt/msk-consumers/${consumer}"
ExecStart=/usr/bin/python3 /opt/msk-consumers/${consumer}/consumer.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    SERVICE_FILES="$SERVICE_FILES $SERVICE_FILE"
done

# Upload all service files to S3, then download on bastion
info "Uploading systemd service files to S3..."
SERVICE_TAR="$TEMP_DIR/services.tar.gz"
# Create tar with service files from /tmp
cd /tmp
tar -czf "$SERVICE_TAR" $(basename -a $SERVICE_FILES) 2>/dev/null || {
    # Fallback: create tar from temp dir
    cd "$TEMP_DIR"
    tar -czf "$SERVICE_TAR" *.service
}
cd "$PROJECT_ROOT"

SERVICE_S3_KEY="msk-consumers/services-$(date +%Y%m%d-%H%M%S).tar.gz"
aws s3 cp "$SERVICE_TAR" "s3://${S3_BUCKET}/${SERVICE_S3_KEY}" --region "$AWS_REGION"

if [ $? -ne 0 ]; then
    fail "Failed to upload service files to S3"
    exit 1
fi

pass "Service files uploaded to S3"

info "Installing systemd services on bastion..."
INSTALL_SERVICES_COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"cd /tmp\",\"rm -f *.service services.tar.gz\",\"aws s3 cp s3://${S3_BUCKET}/${SERVICE_S3_KEY} services.tar.gz\",\"tar -xzf services.tar.gz\",\"ls -la /tmp/*.service\",\"for service in loan-consumer-msk loan-payment-consumer-msk car-consumer-msk service-consumer-msk; do if [ -f /tmp/\\\$service.service ]; then sudo cp /tmp/\\\$service.service /etc/systemd/system/\\\$service.service && sudo chmod 644 /etc/systemd/system/\\\$service.service && echo Installed \\\$service.service; else echo Service file not found: \\\$service.service; fi; done\",\"rm -f services.tar.gz /tmp/*.service\",\"ls -la /etc/systemd/system/*-msk.service\"]" \
    --output text \
    --query 'Command.CommandId')

sleep 5

INSTALL_SERVICES_STATUS=$(aws ssm get-command-invocation \
    --command-id "$INSTALL_SERVICES_COMMAND_ID" \
    --instance-id "$BASTION_ID" \
    --query 'Status' \
    --output text 2>/dev/null || echo "Unknown")

if [ "$INSTALL_SERVICES_STATUS" = "Success" ]; then
    pass "Systemd service files installed"
else
    warn "Service installation status: $INSTALL_SERVICES_STATUS"
fi

info "Reloading systemd and enabling services..."
RELOAD_COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo systemctl daemon-reload","for consumer in loan-consumer loan-payment-consumer car-consumer service-consumer; do sudo systemctl enable ${consumer}-msk.service; done"]' \
    --output text \
    --query 'Command.CommandId')

sleep 3

pass "MSK consumers deployed to bastion host"
echo ""
info "To start consumers, run on bastion:"
echo "  sudo systemctl start loan-consumer-msk loan-payment-consumer-msk car-consumer-msk service-consumer-msk"
echo ""
info "To check status:"
echo "  sudo systemctl status loan-consumer-msk"
echo ""
info "To view logs:"
echo "  sudo journalctl -u loan-consumer-msk -f"

