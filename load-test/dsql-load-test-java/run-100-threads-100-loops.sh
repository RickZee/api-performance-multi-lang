#!/bin/bash
# Run 100 threads with 100 loops (iterations) with minimal data and detailed stats

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

if [ -z "$BASTION_INSTANCE_ID" ] || [ -z "$DSQL_HOST" ]; then
    echo "Error: Bastion host or DSQL host not found"
    exit 1
fi

echo "=========================================="
echo "DSQL Load Test - 100 Threads, 100 Loops"
echo "=========================================="
echo ""

# Calculate expected rows
THREADS=100
ITERATIONS=100
COUNT=2
EXPECTED_SCENARIO1=$((THREADS * ITERATIONS * COUNT))
EXPECTED_SCENARIO2=$((THREADS * ITERATIONS * COUNT))
EXPECTED_TOTAL=$((EXPECTED_SCENARIO1 + EXPECTED_SCENARIO2))

echo "Configuration:"
echo "  Threads: $THREADS"
echo "  Iterations: $ITERATIONS per thread"
echo "  Count: $COUNT inserts/batch per iteration"
echo "  Event Type: CarCreated"
echo "  Payload Size: default (~0.5-0.7 KB)"
echo ""
echo "Expected Rows:"
echo "  Scenario 1 (Individual): $EXPECTED_SCENARIO1 rows"
echo "  Scenario 2 (Batch): $EXPECTED_SCENARIO2 rows"
echo "  Total Expected: $EXPECTED_TOTAL rows"
echo ""

# Get initial count
echo "=== Getting Initial Database State ==="
INITIAL_COUNT=$(./scripts/query-dsql.sh "SELECT COUNT(*) FROM car_entities_schema.business_events WHERE id LIKE 'load-test-%';" 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")
echo "Initial load-test rows: $INITIAL_COUNT"
echo ""

START_TIME=$(date +%s)

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
fi

echo ""
echo "=== Building and running on bastion host ==="
echo "This will take several minutes with 100 threads × 100 iterations..."
echo ""

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
        "tar xzf dsql-load-test-java.tar.gz 2>/dev/null || true",
        "if ! command -v mvn &> /dev/null; then dnf install -y maven >/dev/null 2>&1 || yum install -y maven >/dev/null 2>&1; fi",
        "mvn clean package -DskipTests -q",
        "export DSQL_HOST=" + $dsql_host,
        "export DSQL_PORT=5432",
        "export DATABASE_NAME=postgres",
        "export IAM_USERNAME=" + $iam_user,
        "export AWS_REGION=" + $aws_region,
        "export SCENARIO=both",
        "export THREADS=100",
        "export ITERATIONS=100",
        "export COUNT=2",
        "export EVENT_TYPE=CarCreated",
        "java -jar target/dsql-load-test-1.0.0.jar"
    ]')

COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$COMMANDS_JSON,\"workingDirectory\":[\"/tmp\"],\"executionTimeout\":[\"3600\"]}" \
    --output json | jq -r '.Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo "Monitoring progress (this may take 10-20 minutes)..."
echo ""

# Poll for completion with progress updates
for i in {1..600}; do
    STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query "Status" \
        --output text 2>/dev/null || echo "InProgress")
    
    if [ "$STATUS" != "InProgress" ]; then
        break
    fi
    
    # Show progress every 30 seconds
    if [ $((i % 10)) -eq 0 ]; then
        ELAPSED=$((i * 3))
        MINUTES=$((ELAPSED / 60))
        SECONDS=$((ELAPSED % 60))
        echo "  Still running... (${MINUTES}m ${SECONDS}s elapsed)"
    fi
    
    sleep 3
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Test Execution Complete"
echo "=========================================="
INVOCATION=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --output json 2>/dev/null)

STATUS=$(echo "$INVOCATION" | jq -r '.Status // "Unknown"' 2>/dev/null)
echo "Status: $STATUS"
echo "Total Execution Time: ${DURATION} seconds ($(($DURATION / 60)) minutes)"
echo ""

echo "=== Test Output Summary ==="
echo "$INVOCATION" | jq -r '.StandardOutputContent // ""' 2>/dev/null | grep -E "(Scenario|Total Success|Total Errors|Throughput|Expected total|Completed)" | head -30

echo ""
echo "=========================================="
echo "Database Validation & Statistics"
echo "=========================================="
sleep 5  # Wait for database propagation

# Get final counts
FINAL_COUNT=$(./scripts/query-dsql.sh "SELECT COUNT(*) FROM car_entities_schema.business_events WHERE id LIKE 'load-test-%';" 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")
NEW_ROWS=$((FINAL_COUNT - INITIAL_COUNT))

echo ""
echo "=== Row Count Statistics ==="
echo "Initial count: $INITIAL_COUNT"
echo "Final count: $FINAL_COUNT"
echo "New rows inserted: $NEW_ROWS"
echo "Expected: $EXPECTED_TOTAL rows"
echo "Difference: $((NEW_ROWS - EXPECTED_TOTAL)) rows"
echo ""

# Scenario breakdown
echo "=== Scenario Breakdown ==="
./scripts/query-dsql.sh "SELECT 
  CASE 
    WHEN id LIKE 'load-test-individual%' THEN 'Scenario 1 (Individual)'
    WHEN id LIKE 'load-test-batch%' THEN 'Scenario 2 (Batch)'
    ELSE 'Other'
  END as scenario,
  COUNT(*) as count
FROM car_entities_schema.business_events
WHERE id LIKE 'load-test-%'
GROUP BY scenario
ORDER BY scenario;" 2>/dev/null || echo "Could not query scenario breakdown"

echo ""
echo "=== Performance Statistics ==="
SCENARIO1_COUNT=$(./scripts/query-dsql.sh "SELECT COUNT(*) FROM car_entities_schema.business_events WHERE id LIKE 'load-test-individual-%';" 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")
SCENARIO2_COUNT=$(./scripts/query-dsql.sh "SELECT COUNT(*) FROM car_entities_schema.business_events WHERE id LIKE 'load-test-batch-%';" 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")

echo "Scenario 1 (Individual): $SCENARIO1_COUNT rows (Expected: $EXPECTED_SCENARIO1)"
echo "Scenario 2 (Batch): $SCENARIO2_COUNT rows (Expected: $EXPECTED_SCENARIO2)"
echo ""

if [ "$NEW_ROWS" -gt 0 ]; then
    ROWS_PER_SECOND=$((NEW_ROWS / DURATION))
    echo "Overall Performance:"
    echo "  Total rows: $NEW_ROWS"
    echo "  Total time: ${DURATION} seconds"
    echo "  Average throughput: ${ROWS_PER_SECOND} rows/second"
    echo ""
fi

echo "=== Validation Summary ==="
if [ "$NEW_ROWS" -eq "$EXPECTED_TOTAL" ]; then
    echo "✅ PERFECT MATCH: Expected $EXPECTED_TOTAL rows, got exactly $NEW_ROWS rows"
elif [ "$NEW_ROWS" -ge $((EXPECTED_TOTAL - 10)) ] && [ "$NEW_ROWS" -le $((EXPECTED_TOTAL + 10)) ]; then
    echo "✅ VALIDATION PASSED: Expected $EXPECTED_TOTAL rows, got $NEW_ROWS rows (within 10 row tolerance)"
else
    echo "⚠️  VALIDATION WARNING: Expected $EXPECTED_TOTAL rows, got $NEW_ROWS rows (difference: $((NEW_ROWS - EXPECTED_TOTAL)))"
fi

echo ""
echo "=========================================="
echo "Test Complete"
echo "=========================================="
