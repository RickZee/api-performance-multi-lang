#!/bin/bash
# Load environment from Terraform and run full test suite with progress

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$(cd "$PROJECT_ROOT/../terraform" && pwd)"

echo "=================================================================================="
echo "DSQL Performance Test Suite - Full Run (from Terraform outputs)"
echo "=================================================================================="
echo ""

# Load environment variables from Terraform
echo "Step 1: Loading environment variables from Terraform..."
cd "$TERRAFORM_DIR"

DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
TEST_RUNNER_INSTANCE_ID=$(terraform output -raw dsql_test_runner_instance_id 2>/dev/null || echo "")
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

if [ -z "$DSQL_HOST" ] || [ -z "$TEST_RUNNER_INSTANCE_ID" ] || [ -z "$S3_BUCKET" ]; then
    echo "❌ Error: Could not get all required values from Terraform"
    echo ""
    echo "Got:"
    echo "  DSQL_HOST: ${DSQL_HOST:-NOT FOUND}"
    echo "  TEST_RUNNER_INSTANCE_ID: ${TEST_RUNNER_INSTANCE_ID:-NOT FOUND}"
    echo "  S3_BUCKET: ${S3_BUCKET:-NOT FOUND}"
    echo ""
    echo "Make sure Terraform is initialized:"
    echo "  cd $TERRAFORM_DIR"
    echo "  terraform init"
    echo "  terraform output"
    exit 1
fi

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

# Return to project root
cd "$PROJECT_ROOT"

# Validate setup
echo "Step 2: Validating setup..."
python3 tests/validation/validate_setup.py || {
    echo ""
    echo "⚠️  Setup validation had some issues, but continuing..."
    echo ""
}

# Run test suite
echo "Step 3: Running full test suite..."
echo ""
echo "This will:"
echo "  1. Clear the database (DROP and CREATE table)"
echo "  2. Run all 32 tests"
echo "  3. Show real-time progress with time estimates"
echo ""
echo "Estimated duration: 2-4 hours"
echo ""

python3 scripts/run_full_suite_with_progress.py

