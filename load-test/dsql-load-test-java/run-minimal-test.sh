#!/bin/bash
# Run both scenarios with minimal data and validate in database

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Get Terraform outputs
cd "$PROJECT_ROOT/terraform" || exit 1

BASTION_INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
IAM_USERNAME=$(terraform output -raw iam_database_username 2>/dev/null || echo "lambda_dsql_user")
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")

if [ -z "$BASTION_INSTANCE_ID" ]; then
    echo "Error: Bastion host not found"
    exit 1
fi

if [ -z "$DSQL_HOST" ]; then
    echo "Error: DSQL host not found"
    exit 1
fi

echo "=== Getting initial row count ==="
INITIAL_COUNT=$(./scripts/query-dsql.sh "SELECT COUNT(*) FROM car_entities_schema.business_events;" 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")
echo "Initial business_events count: $INITIAL_COUNT"
echo ""

echo "=== Creating deployment package ==="
cd "$SCRIPT_DIR"
tar czf /tmp/dsql-load-test-java.tar.gz pom.xml src/ 2>/dev/null || {
    echo "Error: Failed to create tar archive"
    exit 1
}

echo ""
echo "=== Uploading to S3 ==="
if [ -n "$S3_BUCKET" ]; then
    aws s3 cp /tmp/dsql-load-test-java.tar.gz "s3://$S3_BUCKET/dsql-load-test-java.tar.gz" >/dev/null 2>&1
    echo "Uploaded to s3://$S3_BUCKET/dsql-load-test-java.tar.gz"
else
    echo "Warning: S3 bucket not found, will upload directly via SSM"
fi

echo ""
echo "=== Building and running on bastion host (MINIMAL DATA) ==="

# Build and run both scenarios with minimal data
COMMANDS_JSON=$(jq -n \
    --arg s3_bucket "$S3_BUCKET" \
    --arg dsql_host "$DSQL_HOST" \
    --arg iam_user "$IAM_USERNAME" \
    --arg aws_region "$AWS_REGION" \
    '[
        "set -e",
        "cd /tmp",
        "rm -rf dsql-load-test-java",
        "mkdir -p dsql-load-test-java",
        "cd dsql-load-test-java",
        (if ($s3_bucket | length > 0) then "aws s3 cp s3://" + $s3_bucket + "/dsql-load-test-java.tar.gz ./" else "echo \"S3 not available\"" end),
        "tar xzf dsql-load-test-java.tar.gz",
        "if ! command -v mvn &> /dev/null; then dnf install -y maven >/dev/null 2>&1 || yum install -y maven >/dev/null 2>&1; fi",
        "mvn clean package -DskipTests -q",
        "export DSQL_HOST=" + $dsql_host,
        "export DSQL_PORT=5432",
        "export DATABASE_NAME=postgres",
        "export IAM_USERNAME=" + $iam_user,
        "export AWS_REGION=" + $aws_region,
        "export SCENARIO=both",
        "export THREADS=2",
        "export ITERATIONS=2",
        "export COUNT=2",
        "export EVENT_TYPE=CarCreated",
        "java -jar target/dsql-load-test-1.0.0.jar"
    ]')

COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$COMMANDS_JSON,\"workingDirectory\":[\"/tmp\"],\"executionTimeout\":[\"600\"]}" \
    --output json | jq -r '.Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo "Waiting for test to complete (minimal data: 2 threads, 2 iterations, 2 inserts/batch)..."
sleep 10

# Poll for completion
for i in {1..60}; do
    STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query "Status" \
        --output text 2>/dev/null || echo "InProgress")
    
    if [ "$STATUS" != "InProgress" ]; then
        break
    fi
    sleep 3
done

echo ""
echo "=== Test Results ==="
INVOCATION=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --output json 2>/dev/null)

STATUS=$(echo "$INVOCATION" | jq -r '.Status // "Unknown"' 2>/dev/null)
echo "Status: $STATUS"
echo ""
echo "Output:"
echo "$INVOCATION" | jq -r '.StandardOutputContent // ""' 2>/dev/null
if [ -n "$(echo "$INVOCATION" | jq -r '.StandardErrorContent // ""' 2>/dev/null)" ]; then
    echo ""
    echo "Errors:"
    echo "$INVOCATION" | jq -r '.StandardErrorContent' 2>/dev/null
fi

echo ""
echo "=== Validating in Database ==="
sleep 2  # Wait a bit for database propagation

FINAL_COUNT=$(./scripts/query-dsql.sh "SELECT COUNT(*) FROM car_entities_schema.business_events;" 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")
NEW_ROWS=$((FINAL_COUNT - INITIAL_COUNT))

echo "Initial count: $INITIAL_COUNT"
echo "Final count: $FINAL_COUNT"
echo "New rows inserted: $NEW_ROWS"
echo ""

# Expected: 2 threads * 2 iterations * 2 inserts = 8 for Scenario 1
#          2 threads * 2 iterations * 2 rows/batch = 8 for Scenario 2
#          Total: 16 rows
EXPECTED_MIN=14  # Allow some margin for errors
EXPECTED_MAX=18

if [ "$NEW_ROWS" -ge "$EXPECTED_MIN" ] && [ "$NEW_ROWS" -le "$EXPECTED_MAX" ]; then
    echo "✅ Validation PASSED: Expected ~16 rows, got $NEW_ROWS"
else
    echo "⚠️  Validation WARNING: Expected ~16 rows, got $NEW_ROWS"
fi

echo ""
echo "=== Event Type Breakdown ==="
./scripts/query-dsql.sh "SELECT event_type, COUNT(*) as count FROM car_entities_schema.business_events GROUP BY event_type ORDER BY event_type;" 2>/dev/null || echo "Could not query event types"

echo ""
echo "=== Sample Events ==="
./scripts/query-dsql.sh "SELECT id, event_name, event_type, created_date FROM car_entities_schema.business_events ORDER BY created_date DESC LIMIT 5;" 2>/dev/null || echo "Could not query sample events"

echo ""
echo "=== Test Complete ==="
