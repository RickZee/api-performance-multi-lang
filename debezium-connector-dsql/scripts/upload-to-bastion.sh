#!/bin/bash
# Script to upload connector files to bastion host via S3 or SSM

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
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")

cd "$PROJECT_DIR"

echo "Uploading files to bastion..."
echo ""

# Build connector if needed
if [ ! -f "build/libs/debezium-connector-dsql-1.0.0.jar" ]; then
    echo "Building connector..."
    ./gradlew build
fi

# Option 1: Upload via S3 (if bucket available)
if [ -n "$S3_BUCKET" ]; then
    echo "Uploading to S3 bucket: $S3_BUCKET"
    aws s3 cp build/libs/debezium-connector-dsql-1.0.0.jar \
        "s3://$S3_BUCKET/debezium-connector-dsql.jar" \
        --region "$BASTION_REGION"
    
    echo "Downloading on bastion via SSM..."
    aws ssm send-command \
        --instance-ids "$BASTION_INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "{\"commands\":[\"mkdir -p ~/debezium-connector-dsql/lib\",\"aws s3 cp s3://$S3_BUCKET/debezium-connector-dsql.jar ~/debezium-connector-dsql/lib/\"]}" \
        --region "$BASTION_REGION" \
        --output text \
        --query 'Command.CommandId' > /dev/null
    
    echo "✓ Files uploaded via S3"
else
    echo "S3 bucket not available. Please upload manually:"
    echo ""
    echo "1. Connect to bastion:"
    echo "   aws ssm start-session --target $BASTION_INSTANCE_ID --region $BASTION_REGION"
    echo ""
    echo "2. On bastion, create directory:"
    echo "   mkdir -p ~/debezium-connector-dsql/lib"
    echo ""
    echo "3. From another terminal, use SCP (if SSH key available):"
    echo "   scp -i ~/.ssh/key.pem build/libs/debezium-connector-dsql-1.0.0.jar ec2-user@<bastion-ip>:~/debezium-connector-dsql/lib/"
fi

echo ""
echo "Next: Set up .env.dsql on bastion and run tests"
