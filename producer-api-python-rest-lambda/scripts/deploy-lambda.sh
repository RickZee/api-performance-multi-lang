#!/bin/bash
set -e

# Deploy script for Lambda deployment using SAM
# This script deploys the Python Lambda function to AWS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Deploying Lambda function for producer-api-python-rest-lambda..."

# Build the Lambda package first
echo "Building Lambda package..."
"$SCRIPT_DIR/build-lambda.sh"

# Check if SAM CLI is installed
if ! command -v sam &> /dev/null; then
    echo "Error: AWS SAM CLI is not installed"
    echo "Install it from: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html"
    exit 1
fi

# Deploy using SAM
cd "$PROJECT_ROOT"
sam deploy \
    --template-file sam-template.yaml \
    --stack-name producer-api-python-rest-lambda \
    --capabilities CAPABILITY_IAM \
    --resolve-s3 \
    "$@"

echo "Deployment complete!"
