#!/bin/bash
set -e

# Shared deployment script for Lambda functions using SAM CLI
# Usage: deploy-lambda.sh <project-name> [options]

PROJECT_NAME="${1:-}"

if [ -z "$PROJECT_NAME" ]; then
    echo "Error: Project name is required"
    echo "Usage: $0 <project-name> [--stack-name NAME] [--region REGION] [options...]"
    exit 1
fi

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
API_DIR="$PROJECT_ROOT/$PROJECT_NAME"

if [ ! -d "$API_DIR" ]; then
    echo "Error: Project directory not found: $API_DIR"
    exit 1
fi

# Default values
STACK_NAME="$PROJECT_NAME"
REGION="${AWS_REGION:-us-east-1}"
S3_BUCKET="${S3_BUCKET:-}"
CAPABILITIES="CAPABILITY_IAM"

# Detect project type (go or python)
if [ -f "$API_DIR/go.mod" ]; then
    PROJECT_TYPE="go"
elif [ -f "$API_DIR/requirements.txt" ]; then
    PROJECT_TYPE="python"
else
    echo "Warning: Could not determine project type, assuming Go"
    PROJECT_TYPE="go"
fi

# Parse command line arguments
shift  # Remove project name from arguments
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
      # For Python projects, pass through remaining arguments
      if [ "$PROJECT_TYPE" = "python" ]; then
        EXTRA_ARGS="$EXTRA_ARGS $1"
        shift
      else
        echo "Unknown option: $1"
        echo "Usage: $0 <project-name> [--stack-name NAME] [--region REGION] [--s3-bucket BUCKET] [--database-url URL] [--aurora-endpoint ENDPOINT] [--database-name NAME] [--database-user USER] [--database-password PASSWORD] [--vpc-id VPC_ID] [--subnet-ids SUBNET_IDS] [--guided]"
        exit 1
      fi
      ;;
  esac
done

cd "$API_DIR"

echo "Deploying Lambda function: $STACK_NAME"
echo "Region: $REGION"
echo "Project Type: $PROJECT_TYPE"

# Build the Lambda function first
echo "Building Lambda function..."
if [ -f "$API_DIR/scripts/build-lambda.sh" ]; then
    "$API_DIR/scripts/build-lambda.sh"
else
    echo "Error: Build script not found: $API_DIR/scripts/build-lambda.sh"
    exit 1
fi

# Check if SAM CLI is installed
if ! command -v sam &> /dev/null; then
    echo "Error: AWS SAM CLI is not installed"
    echo "Install it from: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html"
    exit 1
fi

# Deploy based on project type
if [ "$PROJECT_TYPE" = "python" ]; then
    # Python deployment (simpler, uses --resolve-s3)
    sam deploy \
        --template-file "$API_DIR/sam-template.yaml" \
        --stack-name "$STACK_NAME" \
        --capabilities "$CAPABILITIES" \
        --resolve-s3 \
        $EXTRA_ARGS
else
    # Go deployment (with parameter handling)
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
        --template-file "$API_DIR/sam-template.yaml" \
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
        --template-file "$API_DIR/sam-template.yaml" \
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
fi

echo ""
echo "Deployment complete!"
