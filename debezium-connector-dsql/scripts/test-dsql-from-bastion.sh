#!/bin/bash
# Test DSQL connection directly from bastion host
# This script runs on the bastion via SSM

set -e

DSQL_HOST="${DSQL_HOST:-vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws}"
DSQL_DB="${DSQL_DB:-car_entities}"
IAM_USER="${IAM_USER:-lambda_dsql_user}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "=========================================="
echo "DSQL Connection Test from Bastion"
echo "=========================================="
echo "DSQL Host: $DSQL_HOST"
echo "Database: $DSQL_DB"
echo "IAM User: $IAM_USER"
echo "Region: $AWS_REGION"
echo ""

# Step 1: Generate IAM token
echo "=== Step 1: Generate IAM Token ==="
TOKEN=$(aws rds generate-db-auth-token \
    --hostname "$DSQL_HOST" \
    --port 5432 \
    --region "$AWS_REGION" \
    --username "$IAM_USER" 2>&1)

if [ $? -ne 0 ]; then
    echo "✗ Token generation failed: $TOKEN"
    exit 1
fi

TOKEN_LENGTH=${#TOKEN}
echo "✓ Token generated (length: $TOKEN_LENGTH)"
echo ""

# Step 2: Test connection
echo "=== Step 2: Test Connection ==="
export PGPASSWORD="$TOKEN"

echo "Testing connection to $DSQL_DB..."
if psql -h "$DSQL_HOST" -U "$IAM_USER" -d "$DSQL_DB" -p 5432 -c "SELECT version();" 2>&1; then
    echo "✓ Connection successful!"
else
    CONN_ERROR=$?
    echo "✗ Connection failed (exit code: $CONN_ERROR)"
    exit $CONN_ERROR
fi
echo ""

# Step 3: Test table access
echo "=== Step 3: Test Table Access ==="
echo "Querying event_headers table..."
if psql -h "$DSQL_HOST" -U "$IAM_USER" -d "$DSQL_DB" -p 5432 -c "SELECT COUNT(*) FROM event_headers;" 2>&1; then
    echo "✓ Table access successful!"
else
    echo "✗ Table access failed"
    exit 1
fi
echo ""

# Step 4: List tables
echo "=== Step 4: List Available Tables ==="
psql -h "$DSQL_HOST" -U "$IAM_USER" -d "$DSQL_DB" -p 5432 -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' LIMIT 10;" 2>&1 || echo "Table listing failed"
echo ""

echo "=========================================="
echo "Connection Test Complete"
echo "=========================================="
