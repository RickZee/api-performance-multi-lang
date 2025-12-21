#!/bin/bash
# Clear load test data from DSQL database

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT/terraform" || exit 1

BASTION_INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")

if [ -z "$BASTION_INSTANCE_ID" ] || [ -z "$DSQL_HOST" ]; then
    echo "Error: Bastion host or DSQL host not found"
    exit 1
fi

echo "=== Clearing Load Test Data from DSQL ==="
echo "This will delete all rows with id LIKE 'load-test-%'"
echo ""

# Get count before deletion
BEFORE_COUNT=$(./scripts/query-dsql.sh "SELECT COUNT(*) FROM car_entities_schema.business_events WHERE id LIKE 'load-test-%';" 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")
echo "Rows before deletion: $BEFORE_COUNT"

# Delete load test data
echo ""
echo "Deleting load test data..."
./scripts/query-dsql.sh "DELETE FROM car_entities_schema.business_events WHERE id LIKE 'load-test-%';" 2>/dev/null

# Get count after deletion
AFTER_COUNT=$(./scripts/query-dsql.sh "SELECT COUNT(*) FROM car_entities_schema.business_events WHERE id LIKE 'load-test-%';" 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")
DELETED=$((BEFORE_COUNT - AFTER_COUNT))

echo ""
echo "Rows after deletion: $AFTER_COUNT"
echo "Rows deleted: $DELETED"
echo ""
echo "✅ Database cleared"
