#!/bin/bash
# Deploy Flink Application JAR to S3 for Managed Service for Apache Flink
# This script builds the Flink application and uploads it to S3

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

FLINK_DIR="$PROJECT_ROOT/cdc-streaming/flink-msk"
JAR_KEY="${FLINK_APP_JAR_KEY:-flink-app.jar}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploy Flink Application to S3${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Java is installed
if ! command -v java &> /dev/null; then
    echo -e "${RED}✗ Java is not installed${NC}"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI is not installed${NC}"
    exit 1
fi

# Get S3 bucket name from Terraform output
cd terraform
S3_BUCKET=$(terraform output -raw flink_s3_bucket_name 2>/dev/null || echo "")
cd "$PROJECT_ROOT"

if [ -z "$S3_BUCKET" ]; then
    echo -e "${YELLOW}⚠ S3 bucket not found in Terraform outputs${NC}"
    echo -e "${YELLOW}Please provide S3 bucket name:${NC}"
    read -r S3_BUCKET
fi

if [ -z "$S3_BUCKET" ]; then
    echo -e "${RED}✗ S3 bucket name is required${NC}"
    exit 1
fi

echo "S3 Bucket: $S3_BUCKET"
echo "JAR Key: $JAR_KEY"
echo "AWS Region: $AWS_REGION"
echo ""

# Navigate to Flink directory
cd "$FLINK_DIR"

# Build the Flink application
echo -e "${BLUE}Building Flink application...${NC}"
./gradlew clean fatJar

# Find the JAR file
JAR_FILE=$(find build/libs -name "*-all.jar" | head -n 1)

if [ -z "$JAR_FILE" ]; then
    echo -e "${RED}✗ JAR file not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ JAR file built: $JAR_FILE${NC}"
echo ""

# Upload to S3
echo -e "${BLUE}Uploading JAR to S3...${NC}"
aws s3 cp "$JAR_FILE" "s3://$S3_BUCKET/$JAR_KEY" --region "$AWS_REGION"

echo ""
echo -e "${GREEN}✓ Flink application deployed to S3!${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Go to AWS Console → Kinesis Analytics → Applications"
echo "2. Select your Flink application"
echo "3. Update the application code to use: s3://$S3_BUCKET/$JAR_KEY"
echo "4. Set environment variable: BOOTSTRAP_SERVERS=<msk-bootstrap-servers>"
echo "5. Start the application"

