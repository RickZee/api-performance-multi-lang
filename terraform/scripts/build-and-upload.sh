#!/bin/bash
set -e

# Build and upload Lambda functions to S3
# This script builds both Go gRPC and Go REST Lambda functions and uploads them to S3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$TERRAFORM_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed. Please install it first."
    exit 1
fi

# Get S3 bucket name from Terraform output or variable
print_info "Getting S3 bucket name from Terraform..."
cd "$TERRAFORM_DIR"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    print_info "Initializing Terraform..."
    terraform init
fi

# Get bucket name from Terraform output or state
BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")

if [ -z "$BUCKET_NAME" ]; then
    print_warn "Could not get S3 bucket name from Terraform output."
    print_info "Please provide the S3 bucket name:"
    read -r BUCKET_NAME
fi

if [ -z "$BUCKET_NAME" ]; then
    print_error "S3 bucket name is required"
    exit 1
fi

print_info "Using S3 bucket: $BUCKET_NAME"

# Build gRPC Lambda function
print_info "Building gRPC Lambda function..."
cd "$PROJECT_ROOT/producer-api-go-grpc"
if [ -f "scripts/build-lambda.sh" ]; then
    bash scripts/build-lambda.sh
    if [ -f "lambda-deployment.zip" ]; then
        print_info "Uploading gRPC Lambda to S3..."
        aws s3 cp lambda-deployment.zip "s3://${BUCKET_NAME}/grpc/lambda-deployment.zip"
        print_info "gRPC Lambda uploaded successfully"
        # Clean up local zip file
        rm -f lambda-deployment.zip
    else
        print_error "gRPC Lambda deployment package not found"
        exit 1
    fi
else
    print_error "gRPC Lambda build script not found"
    exit 1
fi

# Build REST Lambda function
print_info "Building REST Lambda function..."
cd "$PROJECT_ROOT/producer-api-go-rest"
if [ -f "scripts/build-lambda.sh" ]; then
    bash scripts/build-lambda.sh
    if [ -f "lambda-deployment.zip" ]; then
        print_info "Uploading REST Lambda to S3..."
        aws s3 cp lambda-deployment.zip "s3://${BUCKET_NAME}/rest/lambda-deployment.zip"
        print_info "REST Lambda uploaded successfully"
        # Clean up local zip file
        rm -f lambda-deployment.zip
    else
        print_error "REST Lambda deployment package not found"
        exit 1
    fi
else
    print_error "REST Lambda build script not found"
    exit 1
fi

# Build Python REST Lambda function
print_info "Building Python REST Lambda function..."
cd "$PROJECT_ROOT/producer-api-python-rest-lambda"
if [ -f "scripts/build-lambda.sh" ]; then
    bash scripts/build-lambda.sh
    if [ -f "lambda-deployment.zip" ]; then
        print_info "Uploading Python REST Lambda to S3..."
        aws s3 cp lambda-deployment.zip "s3://${BUCKET_NAME}/python-rest/lambda-deployment.zip"
        print_info "Python REST Lambda uploaded successfully"
        # Clean up local zip file
        rm -f lambda-deployment.zip
    else
        print_error "Python REST Lambda deployment package not found"
        exit 1
    fi
else
    print_error "Python REST Lambda build script not found"
    exit 1
fi

print_info "All Lambda functions built and uploaded successfully!"

