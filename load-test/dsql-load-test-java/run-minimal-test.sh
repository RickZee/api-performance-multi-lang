#!/bin/bash
# Run both scenarios with minimal data and validate in database

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Get Terraform outputs
cd "$PROJECT_ROOT/terraform" || exit 1

# Use test runner EC2 instance (separate from bastion host)
TEST_RUNNER_INSTANCE_ID=$(terraform output -raw dsql_test_runner_instance_id 2>/dev/null || echo "")
# Fallback to bastion if test runner not enabled
if [ -z "$TEST_RUNNER_INSTANCE_ID" ]; then
    TEST_RUNNER_INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
    echo "Warning: Test runner EC2 not enabled, using bastion host instead"
fi

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
IAM_USERNAME=$(terraform output -raw iam_database_username 2>/dev/null || echo "lambda_dsql_user")
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")

if [ -z "$TEST_RUNNER_INSTANCE_ID" ]; then
    echo "Error: Test runner EC2 instance not found"
    exit 1
fi

if [ -z "$DSQL_HOST" ]; then
    echo "Error: DSQL host not found"
    exit 1
fi

echo "=== Getting initial row count ==="
INITIAL_COUNT=$(cd "$PROJECT_ROOT" && ./scripts/query-dsql.sh "SELECT COUNT(*) FROM car_entities_schema.business_events;" 2>/dev/null | grep -E '^[[:space:]]*[0-9]+[[:space:]]*$' | tr -d '[:space:]' | head -1 || echo "0")
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
        "# Install Java 21 (LTS) if not present",
        "if ! command -v java &> /dev/null || ! java -version 2>&1 | grep -q \"version \\\"21\"; then",
        "  echo \"Installing Java 21 (Amazon Corretto)...\"",
        "  dnf install -y java-21-amazon-corretto-devel >/dev/null 2>&1 || yum install -y java-21-amazon-corretto-devel >/dev/null 2>&1",
        "  alternatives --set java /usr/lib/jvm/java-21-amazon-corretto/bin/java 2>/dev/null || true",
        "fi",
        "echo \"Java version:\"",
        "java -version 2>&1",
        "echo \"\"",
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
        "export OUTPUT_DIR=/tmp/results",
        "export TEST_ID=minimal-test-$(date +%s)",
        "mkdir -p /tmp/results",
        "echo \"=== Running Load Test with Detailed Stats ===\"",
        "java -jar target/dsql-load-test-1.0.0.jar",
        "echo \"\"",
        "echo \"=== Test Results JSON ===\"",
        "ls -lah /tmp/results/ 2>/dev/null || echo \"No results directory\"",
        "cat /tmp/results/*.json 2>/dev/null || echo \"No result JSON files\""
    ]')

COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$TEST_RUNNER_INSTANCE_ID" \
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
        --instance-id "$TEST_RUNNER_INSTANCE_ID" \
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
    --instance-id "$TEST_RUNNER_INSTANCE_ID" \
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
echo "=== Downloading Test Results ==="
# Create results directory
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
RESULTS_DIR="$SCRIPT_DIR/results/$TIMESTAMP"
mkdir -p "$RESULTS_DIR"
mkdir -p "$SCRIPT_DIR/results"  # Ensure results directory exists

# Download result JSON files from test runner
DOWNLOAD_CMD=$(jq -n '[
    "if [ -d /tmp/results ]; then",
    "  for f in /tmp/results/*.json; do",
    "    if [ -f \"$f\" ]; then",
    "      echo \"=== $(basename $f) ===\"",
    "      cat \"$f\"",
    "      echo \"\"",
    "    fi",
    "  done",
    "else",
    "  echo \"No results directory found\"",
    "fi"
]')

DOWNLOAD_ID=$(aws ssm send-command \
    --instance-ids "$TEST_RUNNER_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$DOWNLOAD_CMD,\"workingDirectory\":[\"/tmp\"]}" \
    --output json | jq -r '.Command.CommandId')

# Wait for download command to complete
for i in {1..30}; do
    DOWNLOAD_STATUS=$(aws ssm get-command-invocation \
        --command-id "$DOWNLOAD_ID" \
        --instance-id "$TEST_RUNNER_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query "Status" \
        --output text 2>/dev/null || echo "InProgress")
    
    if [ "$DOWNLOAD_STATUS" != "InProgress" ]; then
        break
    fi
    sleep 2
done

DOWNLOAD_OUTPUT=$(aws ssm get-command-invocation \
    --command-id "$DOWNLOAD_ID" \
    --instance-id "$TEST_RUNNER_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --output json 2>/dev/null)

# Extract and save result JSON files
RESULT_CONTENT=$(echo "$DOWNLOAD_OUTPUT" | jq -r '.StandardOutputContent // ""' 2>/dev/null)

if [ -n "$RESULT_CONTENT" ] && [ "$RESULT_CONTENT" != "No results directory found" ]; then
    # Parse the output to extract individual JSON files
    # The output format is: === filename ===\n{json}\n\n=== filename ===\n{json}\n
    CURRENT_FILE=""
    CURRENT_JSON=""
    IN_JSON=false
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^===.*===$ ]]; then
            # Save previous file if exists
            if [ -n "$CURRENT_FILE" ] && [ -n "$CURRENT_JSON" ]; then
                echo "$CURRENT_JSON" > "$RESULTS_DIR/$CURRENT_FILE"
                echo "Saved: $RESULTS_DIR/$CURRENT_FILE"
            fi
            # Extract filename from === filename ===
            CURRENT_FILE=$(echo "$line" | sed 's/^=== \(.*\) ===$/\1/')
            CURRENT_JSON=""
            IN_JSON=true
        elif [ "$IN_JSON" = true ] && [ -n "$line" ]; then
            if [ -z "$CURRENT_JSON" ]; then
                CURRENT_JSON="$line"
            else
                CURRENT_JSON="$CURRENT_JSON"$'\n'"$line"
            fi
        fi
    done <<< "$RESULT_CONTENT"
    
    # Save last file
    if [ -n "$CURRENT_FILE" ] && [ -n "$CURRENT_JSON" ]; then
        echo "$CURRENT_JSON" > "$RESULTS_DIR/$CURRENT_FILE"
        echo "Saved: $RESULTS_DIR/$CURRENT_FILE"
    fi
    
    # Create symlink to latest
    ln -sfn "$TIMESTAMP" "$SCRIPT_DIR/results/latest"
    echo ""
    echo "Results saved to: $RESULTS_DIR"
else
    echo "Warning: No result files found on test runner"
fi

echo ""
echo "=== Validating in Database ==="
sleep 2  # Wait a bit for database propagation

FINAL_COUNT=$(cd "$PROJECT_ROOT" && ./scripts/query-dsql.sh "SELECT COUNT(*) FROM car_entities_schema.business_events;" 2>/dev/null | grep -E '^[[:space:]]*[0-9]+[[:space:]]*$' | tr -d '[:space:]' | head -1 || echo "0")
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
cd "$PROJECT_ROOT" && ./scripts/query-dsql.sh "SELECT event_type, COUNT(*) as count FROM car_entities_schema.business_events GROUP BY event_type ORDER BY event_type;" 2>/dev/null || echo "Could not query event types"

echo ""
echo "=== Sample Events ==="
cd "$PROJECT_ROOT" && ./scripts/query-dsql.sh "SELECT id, event_name, event_type, created_date FROM car_entities_schema.business_events ORDER BY created_date DESC LIMIT 5;" 2>/dev/null || echo "Could not query sample events"

echo ""
echo "=== Test Complete ==="
echo "Results saved to: $RESULTS_DIR"
