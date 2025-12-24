#!/bin/bash
# Load environment variables from Terraform outputs

set -e

TERRAFORM_DIR="${1:-../../terraform}"

if [ ! -d "$TERRAFORM_DIR" ]; then
    echo "Error: Terraform directory not found: $TERRAFORM_DIR"
    exit 1
fi

echo "Loading environment variables from Terraform outputs..."
echo "Terraform directory: $TERRAFORM_DIR"
echo ""

cd "$TERRAFORM_DIR"

# Get Terraform outputs
DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
TEST_RUNNER_INSTANCE_ID=$(terraform output -raw dsql_test_runner_instance_id 2>/dev/null || echo "")
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

# Check if we got the values
if [ -z "$DSQL_HOST" ] || [ -z "$TEST_RUNNER_INSTANCE_ID" ] || [ -z "$S3_BUCKET" ]; then
    echo "Error: Could not get all required values from Terraform"
    echo ""
    echo "Got:"
    echo "  DSQL_HOST: ${DSQL_HOST:-NOT FOUND}"
    echo "  TEST_RUNNER_INSTANCE_ID: ${TEST_RUNNER_INSTANCE_ID:-NOT FOUND}"
    echo "  S3_BUCKET: ${S3_BUCKET:-NOT FOUND}"
    echo ""
    echo "Make sure Terraform is initialized and outputs are available:"
    echo "  cd $TERRAFORM_DIR"
    echo "  terraform output"
    exit 1
fi

# Export variables
export DSQL_HOST
export TEST_RUNNER_INSTANCE_ID
export S3_BUCKET
export AWS_REGION

echo "✓ Environment variables loaded:"
echo "  DSQL_HOST=$DSQL_HOST"
echo "  TEST_RUNNER_INSTANCE_ID=$TEST_RUNNER_INSTANCE_ID"
echo "  S3_BUCKET=$S3_BUCKET"
echo "  AWS_REGION=$AWS_REGION"
echo ""

# Return to original directory
cd - > /dev/null

# If script was sourced, variables are already exported
# If script was executed, we need to pass them to the parent
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script was executed (not sourced)
    echo "To use these variables, source this script:"
    echo "  source scripts/load_env_from_terraform.sh"
    echo ""
    echo "Or run with eval:"
    echo "  eval \$(scripts/load_env_from_terraform.sh)"
else
    # Script was sourced, variables are already exported
    echo "✓ Variables exported to current shell"
fi

