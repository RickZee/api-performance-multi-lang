#!/usr/bin/env bash
# Comprehensive IAM connection test for DSQL
# Usage: ./test-dsql-iam-connection.sh [iam_username] [dsql_host] [database_name]

set -euo pipefail

IAM_USER="${1:-dsql_iam_user}"
DSQL_HOST="${2:-$(cd "$(dirname "$0")/.." && terraform output -raw aurora_dsql_host 2>/dev/null || echo "")}"
DATABASE_NAME="${3:-$(cd "$(dirname "$0")/.." && terraform output -raw aurora_dsql_database_name 2>/dev/null || echo "postgres")}"

if [ -z "$DSQL_HOST" ]; then
  echo "Error: DSQL host not provided and could not read from Terraform"
  echo "Usage: $0 [iam_username] [dsql_host] [database_name]"
  exit 1
fi

echo "=== Testing IAM Connection to DSQL ==="
echo "DSQL Host: $DSQL_HOST"
echo "IAM User: $IAM_USER"
echo "Database: $DATABASE_NAME"
echo ""

echo "1. Generating IAM authentication token..."
IAM_TOKEN=$(aws rds generate-db-auth-token \
  --hostname "$DSQL_HOST" \
  --port 5432 \
  --region us-east-1 \
  --username "$IAM_USER" 2>&1)

if [ $? -ne 0 ]; then
  echo "❌ Token generation failed: $IAM_TOKEN"
  exit 1
fi

echo "✅ Token generated successfully (length: ${#IAM_TOKEN})"

echo ""
echo "2. Testing connection..."
export PGPASSWORD="$IAM_TOKEN"
CONNECTION_RESULT=$(psql "postgresql://${IAM_USER}@${DSQL_HOST}:5432/${DATABASE_NAME}?sslmode=require" -c "SELECT current_user, current_database(), version();" 2>&1)

if [ $? -eq 0 ]; then
  echo "✅✅✅ Connection successful! ✅✅✅"
  echo ""
  echo "$CONNECTION_RESULT"
  echo ""
  echo "3. Testing table access..."
  psql "postgresql://${IAM_USER}@${DSQL_HOST}:5432/${DATABASE_NAME}?sslmode=require" -c "\dt" 2>&1 | head -10
  echo ""
  echo "✅ All tests passed!"
else
  echo "❌ Connection failed:"
  echo "$CONNECTION_RESULT"
  echo ""
  echo "Troubleshooting steps:"
  echo "1. Verify IAM role mapping exists: ./verify-dsql-iam-mapping.sh $IAM_USER $DSQL_HOST"
  echo "2. Check IAM policy has dsql:DbConnect permission"
  echo "3. Verify IAM user exists in database"
  exit 1
fi

