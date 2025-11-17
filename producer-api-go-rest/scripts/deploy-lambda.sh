#!/bin/bash
set -e

# Deployment script for Lambda using SAM CLI
# This script builds and deploys the Lambda function using AWS SAM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
STACK_NAME="producer-api-go-rest-lambda"
REGION="${AWS_REGION:-us-east-1}"
S3_BUCKET="${S3_BUCKET:-}"
CAPABILITIES="CAPABILITY_IAM"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --stack-name)
      STACK_NAME="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --s3-bucket)
      S3_BUCKET="$2"
      shift 2
      ;;
    --database-url)
      DATABASE_URL="$2"
      shift 2
      ;;
    --aurora-endpoint)
      AURORA_ENDPOINT="$2"
      shift 2
      ;;
    --database-name)
      DATABASE_NAME="$2"
      shift 2
      ;;
    --database-user)
      DATABASE_USER="$2"
      shift 2
      ;;
    --database-password)
      DATABASE_PASSWORD="$2"
      shift 2
      ;;
    --vpc-id)
      VPC_ID="$2"
      shift 2
      ;;
    --subnet-ids)
      SUBNET_IDS="$2"
      shift 2
      ;;
    --guided)
      GUIDED="--guided"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--stack-name NAME] [--region REGION] [--s3-bucket BUCKET] [--database-url URL] [--aurora-endpoint ENDPOINT] [--database-name NAME] [--database-user USER] [--database-password PASSWORD] [--vpc-id VPC_ID] [--subnet-ids SUBNET_IDS] [--guided]"
      exit 1
      ;;
  esac
done

echo "Deploying Lambda function: $STACK_NAME"
echo "Region: $REGION"

# Build the Lambda function first
echo "Building Lambda function..."
"$SCRIPT_DIR/build-lambda.sh"

# Prepare SAM parameters
PARAMETERS=""
if [ -n "$DATABASE_URL" ]; then
  PARAMETERS="$PARAMETERS ParameterKey=DatabaseURL,ParameterValue=\"$DATABASE_URL\""
fi
if [ -n "$AURORA_ENDPOINT" ]; then
  PARAMETERS="$PARAMETERS ParameterKey=AuroraEndpoint,ParameterValue=\"$AURORA_ENDPOINT\""
fi
if [ -n "$DATABASE_NAME" ]; then
  PARAMETERS="$PARAMETERS ParameterKey=DatabaseName,ParameterValue=\"$DATABASE_NAME\""
fi
if [ -n "$DATABASE_USER" ]; then
  PARAMETERS="$PARAMETERS ParameterKey=DatabaseUser,ParameterValue=\"$DATABASE_USER\""
fi
if [ -n "$DATABASE_PASSWORD" ]; then
  PARAMETERS="$PARAMETERS ParameterKey=DatabasePassword,ParameterValue=\"$DATABASE_PASSWORD\""
fi
if [ -n "$VPC_ID" ]; then
  PARAMETERS="$PARAMETERS ParameterKey=VpcId,ParameterValue=\"$VPC_ID\""
fi
if [ -n "$SUBNET_IDS" ]; then
  PARAMETERS="$PARAMETERS ParameterKey=SubnetIds,ParameterValue=\"$SUBNET_IDS\""
fi

# Deploy using SAM
if [ -n "$GUIDED" ]; then
  # Guided deployment
  sam deploy \
    --template-file "$PROJECT_ROOT/sam-template.yaml" \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --capabilities "$CAPABILITIES" \
    $GUIDED
else
  # Non-guided deployment
  if [ -z "$S3_BUCKET" ]; then
    echo "Error: S3 bucket is required for non-guided deployment. Use --s3-bucket or --guided"
    exit 1
  fi

  sam deploy \
    --template-file "$PROJECT_ROOT/sam-template.yaml" \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --s3-bucket "$S3_BUCKET" \
    --capabilities "$CAPABILITIES" \
    --parameter-overrides $PARAMETERS
fi

# Get API URL from stack outputs
echo ""
echo "Deployment complete!"
echo "Getting stack outputs..."
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs' \
  --output table

