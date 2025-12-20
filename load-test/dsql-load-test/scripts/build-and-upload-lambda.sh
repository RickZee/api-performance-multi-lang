#!/bin/bash
# Build and upload DSQL Load Test Lambda package to S3

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAMBDA_DIR="$SCRIPT_DIR/../lambda"
TERRAFORM_DIR="$SCRIPT_DIR/../../../../terraform"

echo "=========================================="
echo "DSQL Load Test Lambda - Build & Upload"
echo "=========================================="
echo ""

# Check if AWS credentials are configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "ERROR: AWS credentials not configured!"
    echo "Please run 'aws configure' or set AWS credentials."
    exit 1
fi

# Get S3 bucket name from Terraform
if [ -f "$TERRAFORM_DIR/terraform.tfstate" ] || [ -f "$TERRAFORM_DIR/.terraform/terraform.tfstate" ]; then
    echo "Getting S3 bucket name from Terraform..."
    cd "$TERRAFORM_DIR"
    BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    cd - > /dev/null
    
    if [ -z "$BUCKET_NAME" ]; then
        echo "WARNING: Could not get S3 bucket name from Terraform."
        echo "Please provide the bucket name manually:"
        read -p "S3 bucket name: " BUCKET_NAME
    else
        echo "Found S3 bucket: $BUCKET_NAME"
    fi
else
    echo "Terraform state not found. Please provide S3 bucket name:"
    read -p "S3 bucket name: " BUCKET_NAME
fi

if [ -z "$BUCKET_NAME" ]; then
    echo "ERROR: S3 bucket name is required!"
    exit 1
fi

# Build Lambda package
echo ""
echo "Building Lambda package..."
cd "$LAMBDA_DIR"

# Clean previous build
rm -f lambda-deployment.zip
rm -rf __pycache__ *.pyc .pytest_cache

# Install dependencies
echo "Installing dependencies..."
pip install -r requirements.txt -t . --quiet

# Create deployment package
echo "Creating deployment package..."
zip -r lambda-deployment.zip . \
  -x "*.pyc" \
  -x "__pycache__/*" \
  -x "*.pyc" \
  -x ".pytest_cache/*" \
  -x "tests/*" \
  -x "*.md" \
  -x ".git/*" \
  -x "*.gitignore" \
  > /dev/null

PACKAGE_SIZE=$(du -h lambda-deployment.zip | cut -f1)
echo "Package created: lambda-deployment.zip ($PACKAGE_SIZE)"

# Upload to S3
echo ""
echo "Uploading to S3..."
S3_KEY="dsql-load-test/lambda-deployment.zip"
aws s3 cp lambda-deployment.zip "s3://${BUCKET_NAME}/${S3_KEY}"

echo ""
echo "=========================================="
echo "Upload complete!"
echo "=========================================="
echo "S3 location: s3://${BUCKET_NAME}/${S3_KEY}"
echo ""
echo "Next steps:"
echo "1. Run 'terraform apply' in the terraform directory to update the Lambda"
echo "2. Or if Lambda is already deployed, it will auto-update on next terraform apply"
echo ""
