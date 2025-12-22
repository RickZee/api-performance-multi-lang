#!/bin/bash
# Re-run extreme scaling tests (tests 25-32) that had corrupted result files
# These tests use 500-5000 threads and may produce large result files
#
# Enhanced for improved connection handling:
# - Increased connection pool size (up to 2000)
# - Connection retry with exponential backoff
# - Per-iteration connection acquisition for better distribution

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Get Terraform outputs
cd "$PROJECT_ROOT/terraform" || exit 1

TEST_RUNNER_INSTANCE_ID=$(terraform output -raw dsql_test_runner_instance_id 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
IAM_USERNAME=$(terraform output -raw iam_database_username 2>/dev/null || echo "lambda_dsql_user")
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")

if [ -z "$TEST_RUNNER_INSTANCE_ID" ] || [ -z "$DSQL_HOST" ]; then
    echo "Error: Test runner EC2 instance or DSQL host not found"
    exit 1
fi

# Start instance if stopped
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$TEST_RUNNER_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "unknown")

if [ "$INSTANCE_STATE" != "running" ]; then
    echo "Starting test runner instance..."
    aws ec2 start-instances --instance-ids "$TEST_RUNNER_INSTANCE_ID" --region "$AWS_REGION"
    aws ec2 wait instance-running --instance-ids "$TEST_RUNNER_INSTANCE_ID" --region "$AWS_REGION"
    echo "Instance is running"
fi

# Wait for SSM agent
echo "Waiting for SSM agent..."
for i in {1..30}; do
    SSM_STATUS=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$TEST_RUNNER_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || echo "Offline")
    
    if [ "$SSM_STATUS" = "Online" ]; then
        echo "SSM agent is online"
        break
    fi
    sleep 2
done

# Create results directory
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
RESULTS_DIR="$SCRIPT_DIR/results/extreme-scaling-$TIMESTAMP"
mkdir -p "$RESULTS_DIR"
echo "Results directory: $RESULTS_DIR"
echo ""

# Create deployment package
echo "=== Creating deployment package ==="
cd "$SCRIPT_DIR"
tar czf /tmp/dsql-load-test-java.tar.gz pom.xml src/ 2>/dev/null || {
    echo "Error: Failed to create tar archive"
    exit 1
}

# Upload to S3
if [ -n "$S3_BUCKET" ]; then
    echo "=== Uploading to S3 ==="
    aws s3 cp /tmp/dsql-load-test-java.tar.gz "s3://$S3_BUCKET/dsql-load-test-java.tar.gz" >/dev/null 2>&1
    echo "Uploaded to s3://$S3_BUCKET/dsql-load-test-java.tar.gz"
    echo ""
fi

# Extreme scaling tests to re-run
declare -a EXTREME_TESTS=(
    "test-025:1:500:10:20"
    "test-026:1:1000:10:20"
    "test-027:2:500:5:100"
    "test-028:2:1000:5:100"
    "test-029:2:500:10:500"
    "test-030:2:1000:10:500"
    "test-031:2:2000:5:1000"
    "test-032:2:5000:2:1000"
)

echo "=== Re-running Extreme Scaling Tests ==="
echo "Total tests: ${#EXTREME_TESTS[@]}"
echo ""

for test_config in "${EXTREME_TESTS[@]}"; do
    IFS=':' read -r test_id scenario threads iterations count <<< "$test_config"
    
    echo "[$test_id] Running: Scenario $scenario, Threads: $threads, Iterations: $iterations, Count: $count"
    
    # Build SSM command
    COMMANDS_JSON=$(jq -n \
        --arg s3_bucket "$S3_BUCKET" \
        --arg dsql_host "$DSQL_HOST" \
        --arg iam_user "$IAM_USERNAME" \
        --arg aws_region "$AWS_REGION" \
        --arg scenario "$scenario" \
        --arg threads "$threads" \
        --arg iterations "$iterations" \
        --arg count "$count" \
        --arg test_id "$test_id" \
        --arg output_dir "/tmp/results" \
        '[
            "set +e",
            "cd /tmp",
            "rm -rf dsql-load-test-java",
            "mkdir -p dsql-load-test-java",
            "mkdir -p /tmp/results",
            "cd dsql-load-test-java",
            (if ($s3_bucket | length > 0) then "aws s3 cp s3://" + $s3_bucket + "/dsql-load-test-java.tar.gz ./" else "echo \"S3 not available\"" end),
            "tar xzf dsql-load-test-java.tar.gz 2>/dev/null || echo \"Warning: Failed to extract\"",
            "if ! command -v mvn &> /dev/null; then dnf install -y maven >/dev/null 2>&1 || yum install -y maven >/dev/null 2>&1; fi",
            "mvn clean package -DskipTests -q || echo \"Warning: Maven build failed\"",
            "export DSQL_HOST=" + $dsql_host,
            "export DSQL_PORT=5432",
            "export DATABASE_NAME=postgres",
            "export IAM_USERNAME=" + $iam_user,
            "export AWS_REGION=" + $aws_region,
            "export SCENARIO=" + $scenario,
            "export THREADS=" + $threads,
            "export ITERATIONS=" + $iterations,
            "export COUNT=" + $count,
            "export EVENT_TYPE=CarCreated",
            "unset PAYLOAD_SIZE",
            "export TEST_ID=" + $test_id,
            "export OUTPUT_DIR=/tmp/results",
            "# Enhanced connection settings for extreme scaling",
            "export MAX_POOL_SIZE=$(( " + $threads + " / 3 < 2000 ? " + $threads + " / 3 : 2000 ))",
            "export CONNECTION_MAX_RETRIES=5",
            "export CONNECTION_RETRY_DELAY_MS=300",
            "java -jar target/dsql-load-test-1.0.0.jar 2>&1 | tee /tmp/test-output.log || echo \"Warning: Java application failed\"",
            "sleep 5",
            "echo \"=== Result files ===\"",
            "ls -lah /tmp/results/ 2>/dev/null || echo \"No results directory\"",
            "if [ -f /tmp/results/" + $test_id + ".json ]; then",
            "  FILE_SIZE=$(stat -c%s /tmp/results/" + $test_id + ".json 2>/dev/null || stat -f%z /tmp/results/" + $test_id + ".json 2>/dev/null || echo 0)",
            "  echo \"Result file size: $FILE_SIZE bytes\"",
            (if ($s3_bucket | length > 0) then "  if [ $FILE_SIZE -gt 50000 ]; then aws s3 cp /tmp/results/" + $test_id + ".json s3://" + $s3_bucket + "/test-results/" + $test_id + ".json && echo \"Uploaded to S3\" || echo \"S3 upload failed\"; fi" else "  echo \"S3 bucket not configured\"" end),
            "fi"
        ]')
    
    # Send command
    COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$TEST_RUNNER_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --document-name "AWS-RunShellScript" \
        --parameters "{\"commands\":$COMMANDS_JSON,\"workingDirectory\":[\"/tmp\"],\"executionTimeout\":[\"1800\"]}" \
        --output json | jq -r '.Command.CommandId')
    
    # Wait for completion (extreme tests may take longer)
    echo "  Waiting for test to complete..."
    for i in {1..120}; do
        STATUS=$(aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "$TEST_RUNNER_INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query "Status" \
            --output text 2>/dev/null || echo "InProgress")
        
        if [ "$STATUS" != "InProgress" ]; then
            break
        fi
        sleep 5
    done
    
    # Download result using S3 or direct SSM (for large files, use S3)
    echo "  Downloading result JSON..."
    
    # Try to get file via SSM first, but also prepare S3 upload from test runner
    DOWNLOAD_CMD=$(jq -n \
        --arg test_id "$test_id" \
        --arg s3_bucket "$S3_BUCKET" \
        '[
            "if [ -f /tmp/results/" + $test_id + ".json ]; then",
            "  FILE_SIZE=$(stat -c%s /tmp/results/" + $test_id + ".json 2>/dev/null || stat -f%z /tmp/results/" + $test_id + ".json 2>/dev/null || echo 0)",
            "  if [ $FILE_SIZE -gt 100000 ]; then",
            "    echo \"File is large ($FILE_SIZE bytes), uploading to S3...\"",
            (if ($s3_bucket | length > 0) then "    aws s3 cp /tmp/results/" + $test_id + ".json s3://" + $s3_bucket + "/test-results/" + $test_id + ".json" else "    echo \"S3 not available\"" end),
            "    echo \"S3_UPLOAD_COMPLETE\"",
            "  else",
            "    cat /tmp/results/" + $test_id + ".json",
            "  fi",
            "else",
            "  echo \"{}\"",
            "fi"
        ]')
    
    DOWNLOAD_ID=$(aws ssm send-command \
        --instance-ids "$TEST_RUNNER_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --document-name "AWS-RunShellScript" \
        --parameters "{\"commands\":$DOWNLOAD_CMD,\"workingDirectory\":[\"/tmp\"]}" \
        --output json | jq -r '.Command.CommandId')
    
    # Wait for download
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
    
    RESULT_CONTENT=$(echo "$DOWNLOAD_OUTPUT" | jq -r '.StandardOutputContent // ""' 2>/dev/null)
    
    # Check if file was uploaded to S3
    if echo "$RESULT_CONTENT" | grep -q "S3_UPLOAD_COMPLETE"; then
        echo "  Large file detected, downloading from S3..."
        if [ -n "$S3_BUCKET" ]; then
            # Wait a moment for S3 upload to complete
            sleep 3
            # Try downloading from S3
            if aws s3 cp "s3://$S3_BUCKET/test-results/$test_id.json" "$RESULTS_DIR/$test_id.json" 2>/dev/null; then
                echo "  ✅ Downloaded from S3 successfully"
            else
                echo "  ⚠️  Warning: Failed to download from S3, file may not be uploaded yet"
                echo "  Waiting 5 more seconds and retrying..."
                sleep 5
                if aws s3 cp "s3://$S3_BUCKET/test-results/$test_id.json" "$RESULTS_DIR/$test_id.json" 2>/dev/null; then
                    echo "  ✅ Downloaded from S3 on retry"
                else
                    echo "  ⚠️  Warning: Still failed, checking if file exists..."
                    aws s3 ls "s3://$S3_BUCKET/test-results/$test_id.json" 2>&1 | head -1
                    echo "{}" > "$RESULTS_DIR/$test_id.json"
                fi
            fi
        fi
    else
        # Save directly from SSM output (for small files)
        if [ -n "$RESULT_CONTENT" ] && [ "$RESULT_CONTENT" != "{}" ] && [ "$RESULT_CONTENT" != "File is large"* ]; then
            echo "$RESULT_CONTENT" > "$RESULTS_DIR/$test_id.json"
        else
            echo "  Warning: Empty result or file was large, checking S3 anyway..."
            # Even if no S3_UPLOAD_COMPLETE message, check S3 in case upload happened
            if [ -n "$S3_BUCKET" ]; then
                if aws s3 cp "s3://$S3_BUCKET/test-results/$test_id.json" "$RESULTS_DIR/$test_id.json" 2>/dev/null; then
                    echo "  ✅ Found file in S3"
                else
                    echo "{}" > "$RESULTS_DIR/$test_id.json"
                fi
            else
                echo "{}" > "$RESULTS_DIR/$test_id.json"
            fi
        fi
    fi
    
    # Validate JSON
    if python3 -m json.tool "$RESULTS_DIR/$test_id.json" > /dev/null 2>&1; then
        echo "  ✅ Valid JSON saved: $RESULTS_DIR/$test_id.json"
    else
        echo "  ⚠️  Warning: Invalid JSON file (may be truncated)"
    fi
    
    echo ""
done

echo "=== Extreme Scaling Tests Complete ==="
echo "Results saved to: $RESULTS_DIR"
echo ""
echo "To merge with main results, copy files to results/latest/"

