#!/bin/bash
# Run both scenarios with 100 threads and provide detailed stats

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

echo "=========================================="
echo "DSQL Load Test - 100 Threads"
echo "=========================================="
echo ""

# Get initial counts
echo "=== Getting Initial Database State ==="
INITIAL_COUNT=$(./scripts/query-dsql.sh "SELECT COUNT(*) FROM car_entities_schema.business_events;" 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")
echo "Initial business_events count: $INITIAL_COUNT"
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
else
    echo "Warning: S3 bucket not found, will upload directly via SSM"
fi

echo ""
echo "=== Building and running on bastion host (100 THREADS) ==="
echo "Configuration:"
echo "  Threads: 100"
echo "  Iterations: 2 per thread"
echo "  Count: 2 inserts/batch per iteration"
echo "  Event Type: CarCreated"
echo "  Payload Size: default (~0.5-0.7 KB)"
echo "  Expected: ~400 rows (100 threads × 2 iterations × 2 inserts = 400 per scenario)"
echo ""

# Build and run both scenarios with 100 threads
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
        "export ITERATIONS=2",
        "export COUNT=2",
        "export EVENT_TYPE=CarCreated",
        "java -jar target/dsql-load-test-1.0.0.jar"
    ]')

COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$COMMANDS_JSON,\"workingDirectory\":[\"/tmp\"],\"executionTimeout\":[\"1800\"]}" \
    --output json | jq -r '.Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo "Waiting for test to complete (this may take several minutes with 100 threads)..."
echo ""

# Poll for completion with progress updates
for i in {1..300}; do
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
        echo "  Still running... ($((i * 3)) seconds elapsed)"
    fi
    
    sleep 3
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Test Execution Results"
echo "=========================================="
INVOCATION=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --output json 2>/dev/null)

STATUS=$(echo "$INVOCATION" | jq -r '.Status // "Unknown"' 2>/dev/null)
echo "Status: $STATUS"
echo "Total Execution Time: ${DURATION} seconds"
echo ""

echo "=== Test Output ==="
echo "$INVOCATION" | jq -r '.StandardOutputContent // ""' 2>/dev/null

if [ -n "$(echo "$INVOCATION" | jq -r '.StandardErrorContent // ""' 2>/dev/null)" ]; then
    echo ""
    echo "=== Errors/Warnings ==="
    echo "$INVOCATION" | jq -r '.StandardErrorContent' 2>/dev/null | grep -E "(ERROR|FATAL|Exception)" | head -20 || echo "No critical errors found"
fi

echo ""
echo "=========================================="
echo "Database Validation & Statistics"
echo "=========================================="
sleep 3  # Wait for database propagation

# Get final counts
FINAL_COUNT=$(./scripts/query-dsql.sh "SELECT COUNT(*) FROM car_entities_schema.business_events;" 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")
NEW_ROWS=$((FINAL_COUNT - INITIAL_COUNT))

echo ""
echo "=== Row Count Statistics ==="
echo "Initial count: $INITIAL_COUNT"
echo "Final count: $FINAL_COUNT"
echo "New rows inserted: $NEW_ROWS"
echo "Expected: ~800 rows (400 per scenario × 2 scenarios)"
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
echo "=== Event Type Distribution ==="
./scripts/query-dsql.sh "SELECT event_type, COUNT(*) as count 
FROM car_entities_schema.business_events
WHERE id LIKE 'load-test-%'
GROUP BY event_type 
ORDER BY event_type;" 2>/dev/null || echo "Could not query event types"

echo ""
echo "=== Event Data Size Statistics ==="
./scripts/query-dsql.sh "SELECT 
  MIN(LENGTH(event_data::text)) as min_size_bytes,
  MAX(LENGTH(event_data::text)) as max_size_bytes,
  AVG(LENGTH(event_data::text))::int as avg_size_bytes,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY LENGTH(event_data::text))::int as median_size_bytes
FROM car_entities_schema.business_events
WHERE id LIKE 'load-test-%';" 2>/dev/null || echo "Could not query size statistics"

echo ""
echo "=== Insert Timestamp Analysis ==="
./scripts/query-dsql.sh "SELECT 
  DATE_TRUNC('second', created_date) as second,
  COUNT(*) as inserts_per_second
FROM car_entities_schema.business_events
WHERE id LIKE 'load-test-%'
GROUP BY DATE_TRUNC('second', created_date)
ORDER BY second
LIMIT 20;" 2>/dev/null || echo "Could not query timestamp analysis"

echo ""
echo "=== Recent Events Sample ==="
./scripts/query-dsql.sh "SELECT 
  id,
  event_type,
  LENGTH(event_data::text) as size_bytes,
  created_date
FROM car_entities_schema.business_events
WHERE id LIKE 'load-test-%'
ORDER BY created_date DESC
LIMIT 10;" 2>/dev/null || echo "Could not query sample events"

echo ""
echo "=== Performance Summary ==="
if [ "$NEW_ROWS" -gt 0 ]; then
    ROWS_PER_SECOND=$((NEW_ROWS / DURATION))
    echo "Total rows inserted: $NEW_ROWS"
    echo "Total execution time: ${DURATION} seconds"
    echo "Average throughput: ${ROWS_PER_SECOND} rows/second"
    echo ""
    
    if [ "$NEW_ROWS" -ge 700 ] && [ "$NEW_ROWS" -le 900 ]; then
        echo "✅ Validation PASSED: Expected ~800 rows, got $NEW_ROWS"
    else
        echo "⚠️  Validation WARNING: Expected ~800 rows, got $NEW_ROWS"
    fi
else
    echo "❌ Validation FAILED: No new rows inserted"
fi

echo ""
echo "=========================================="
echo "Test Complete"
echo "=========================================="
