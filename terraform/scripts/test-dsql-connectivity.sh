#!/bin/bash
# Test DSQL connectivity from EC2 test runner instance
# This script should be run on the EC2 instance via SSM Session Manager

set -e

# Get values from Terraform outputs (run this from your local machine first)
# DSQL_ENDPOINT=$(cd terraform && terraform output -raw aurora_dsql_endpoint)
# DSQL_HOST=$(cd terraform && terraform output -raw aurora_dsql_host)
# IAM_USER=$(cd terraform && terraform output -raw iam_database_user || echo "lambda_dsql_user")

DSQL_ENDPOINT="${DSQL_ENDPOINT:-vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com}"
DSQL_HOST="${DSQL_HOST:-vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws}"
IAM_USER="${IAM_USER:-lambda_dsql_user}"
REGION="${AWS_REGION:-us-east-1}"
DB_NAME="${DB_NAME:-car_entities}"

echo "=== DSQL Connectivity Test ==="
echo "Endpoint (VPC): $DSQL_ENDPOINT"
echo "Host (DSQL): $DSQL_HOST"
echo "IAM User: $IAM_USER"
echo "Region: $REGION"
echo "Database: $DB_NAME"
echo ""

# Check installed tools
echo "Checking installed tools..."
echo -n "psql: " && (which psql && psql --version | head -n1) || echo "NOT FOUND"
echo -n "java: " && (which java && java -version 2>&1 | head -n1) || echo "NOT FOUND"
echo -n "git: " && (which git && git --version) || echo "NOT FOUND"
echo -n "aws: " && (which aws && aws --version) || echo "NOT FOUND"
echo ""

# Generate IAM auth token
echo "Generating IAM authentication token..."
TOKEN=$(aws rds generate-db-auth-token \
  --hostname $DSQL_ENDPOINT \
  --port 5432 \
  --username $IAM_USER \
  --region $REGION 2>&1)

if [ $? -eq 0 ] && [ -n "$TOKEN" ]; then
  echo "✓ Token generated successfully"
  echo "Token length: ${#TOKEN} characters"
  echo "Token preview: ${TOKEN:0:50}..."
else
  echo "✗ Failed to generate token"
  echo "Error: $TOKEN"
  exit 1
fi

# Test connection with VPC endpoint DNS
echo ""
echo "Testing DSQL connection (VPC endpoint DNS)..."
PGPASSWORD="$TOKEN" psql \
  -h $DSQL_ENDPOINT \
  -p 5432 \
  -U $IAM_USER \
  -d $DB_NAME \
  -c "SELECT version();" 2>&1

if [ $? -eq 0 ]; then
  echo ""
  echo "✓ DSQL connection successful (VPC endpoint)!"
else
  echo ""
  echo "✗ DSQL connection failed (VPC endpoint)"
  echo "Trying DSQL host format..."
  
  # Try DSQL host format
  PGPASSWORD="$TOKEN" psql \
    -h $DSQL_HOST \
    -p 5432 \
    -U $IAM_USER \
    -d $DB_NAME \
    -c "SELECT version();" 2>&1
  
  if [ $? -eq 0 ]; then
    echo ""
    echo "✓ DSQL connection successful (DSQL host format)!"
  else
    echo ""
    echo "✗ DSQL connection failed (both formats)"
    exit 1
  fi
fi

# Test table access
echo ""
echo "Checking for event_headers table..."
PGPASSWORD="$TOKEN" psql \
  -h $DSQL_ENDPOINT \
  -p 5432 \
  -U $IAM_USER \
  -d $DB_NAME \
  -c "\d event_headers" 2>&1 | head -n 20 || echo "Table may not exist yet"

echo ""
echo "=== Test Complete ==="
