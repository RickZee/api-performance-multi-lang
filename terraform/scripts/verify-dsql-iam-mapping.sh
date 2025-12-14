#!/usr/bin/env bash
# Verify IAM role mapping for DSQL database user
# Usage: ./verify-dsql-iam-mapping.sh [iam_username] [dsql_host]

set -euo pipefail

IAM_USER="${1:-dsql_iam_user}"
DSQL_HOST="${2:-$(cd "$(dirname "$0")/.." && terraform output -raw aurora_dsql_host 2>/dev/null || echo "")}"

if [ -z "$DSQL_HOST" ]; then
  echo "Error: DSQL host not provided and could not read from Terraform"
  echo "Usage: $0 [iam_username] [dsql_host]"
  exit 1
fi

echo "=== Verifying IAM Role Mapping ==="
echo "DSQL Host: $DSQL_HOST"
echo "IAM User: $IAM_USER"
echo ""

echo "1. Generating admin token..."
export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token \
  --region us-east-1 \
  --hostname "$DSQL_HOST" 2>&1)

if [ $? -ne 0 ]; then
  echo "❌ Failed to generate admin token: $PGPASSWORD"
  exit 1
fi

echo "✅ Admin token generated"

echo ""
echo "2. Querying IAM role mappings for $IAM_USER..."
psql "postgresql://admin@${DSQL_HOST}:5432/postgres?sslmode=require" <<SQL
SELECT 
  pg_role_name,
  arn,
  iam_oid
FROM sys.iam_pg_role_mappings
WHERE pg_role_name = '$IAM_USER';
SQL

MAPPING_EXISTS=$?

echo ""
if [ $MAPPING_EXISTS -eq 0 ]; then
  ROW_COUNT=$(psql "postgresql://admin@${DSQL_HOST}:5432/postgres?sslmode=require" -t -c "SELECT COUNT(*) FROM sys.iam_pg_role_mappings WHERE pg_role_name = '$IAM_USER';" 2>/dev/null | tr -d ' ')
  if [ "$ROW_COUNT" -gt 0 ]; then
    echo "✅ Role mapping exists for $IAM_USER"
  else
    echo "❌ No role mapping found for $IAM_USER"
    echo ""
    echo "To create the mapping, run:"
    echo "  AWS IAM GRANT $IAM_USER TO '<iam-role-arn>';"
    exit 1
  fi
else
  echo "⚠️  Error querying role mappings"
  exit 1
fi

echo ""
echo "3. All role mappings:"
psql "postgresql://admin@${DSQL_HOST}:5432/postgres?sslmode=require" -c "SELECT pg_role_name, arn FROM sys.iam_pg_role_mappings;" 2>&1

