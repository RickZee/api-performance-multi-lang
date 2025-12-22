#!/bin/bash
# Run comprehensive DSQL performance test suite
# Executes test matrix from test-config.json and collects results

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

if [ -z "$TEST_RUNNER_INSTANCE_ID" ] || [ -z "$DSQL_HOST" ]; then
    echo "Error: Test runner EC2 instance or DSQL host not found"
    exit 1
fi

# Expected instance type for extreme scaling tests
EXPECTED_INSTANCE_TYPE="m5a.2xlarge"

# Function to start EC2 instance if stopped
start_instance_if_needed() {
    echo "=== Checking EC2 Instance Status ==="
    INSTANCE_STATE=$(aws ec2 describe-instances \
        --instance-ids "$TEST_RUNNER_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "unknown")
    
    INSTANCE_TYPE=$(aws ec2 describe-instances \
        --instance-ids "$TEST_RUNNER_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].InstanceType' \
        --output text 2>/dev/null || echo "unknown")
    
    echo "Instance state: $INSTANCE_STATE"
    echo "Instance type: $INSTANCE_TYPE"
    
    if [ "$INSTANCE_TYPE" != "$EXPECTED_INSTANCE_TYPE" ]; then
        echo "Warning: Instance type is $INSTANCE_TYPE, expected $EXPECTED_INSTANCE_TYPE"
        echo "  For extreme scaling tests, m5a.2xlarge is recommended (8 vCPU, 32 GB RAM)"
    fi
    
    if [ "$INSTANCE_STATE" != "running" ]; then
        echo "Starting instance $TEST_RUNNER_INSTANCE_ID..."
        aws ec2 start-instances --instance-ids "$TEST_RUNNER_INSTANCE_ID" --region "$AWS_REGION"
        
        echo "Waiting for instance to be running..."
        aws ec2 wait instance-running --instance-ids "$TEST_RUNNER_INSTANCE_ID" --region "$AWS_REGION"
        
        echo "Waiting for SSM agent to be ready..."
        local max_wait=60
        local wait_count=0
        while [ $wait_count -lt $max_wait ]; do
            SSM_STATUS=$(aws ssm describe-instance-information \
                --filters "Key=InstanceIds,Values=$TEST_RUNNER_INSTANCE_ID" \
                --region "$AWS_REGION" \
                --query 'InstanceInformationList[0].PingStatus' \
                --output text 2>/dev/null || echo "Offline")
            
            if [ "$SSM_STATUS" = "Online" ]; then
                echo "SSM agent is online"
                break
            fi
            
            wait_count=$((wait_count + 1))
            sleep 2
        done
        
        if [ "$SSM_STATUS" != "Online" ]; then
            echo "Warning: SSM agent not online after $max_wait seconds, continuing anyway..."
        fi
    else
        echo "Instance is already running"
    fi
    echo ""
}

# Function to stop EC2 instance
stop_instance() {
    echo ""
    echo "=== Stopping EC2 Instance to Minimize Costs ==="
    aws ec2 stop-instances --instance-ids "$TEST_RUNNER_INSTANCE_ID" --region "$AWS_REGION" >/dev/null 2>&1 || {
        echo "Warning: Failed to stop instance (may already be stopped)"
    }
    echo "Instance stop command sent"
}

# Set trap to stop instance on exit
trap stop_instance EXIT

# Start instance before tests
start_instance_if_needed

# Check for resume option
RESUME="${RESUME:-false}"
if [ "$RESUME" = "true" ] && [ -d "$SCRIPT_DIR/results/latest" ]; then
    RESULTS_DIR="$SCRIPT_DIR/results/latest"
    TIMESTAMP=$(basename "$RESULTS_DIR")
    echo "Resuming from previous test run: $TIMESTAMP"
    echo "Will skip already completed tests"
else
    # Create new results directory
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    RESULTS_DIR="$SCRIPT_DIR/results/$TIMESTAMP"
    mkdir -p "$RESULTS_DIR"
    mkdir -p "$SCRIPT_DIR/results"  # Ensure results directory exists
    ln -sfn "$TIMESTAMP" "$SCRIPT_DIR/results/latest"
fi

echo "=========================================="
echo "DSQL Performance Test Suite"
echo "=========================================="
echo "Results directory: $RESULTS_DIR"
echo ""

# Clear database before test run
echo "=== Clearing Database Before Test Run ==="
cd "$PROJECT_ROOT" && ./scripts/clear-dsql-load-test-data.sh || {
    echo "Warning: Failed to clear database, continuing anyway..."
}
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

# Parse test configuration
CONFIG_FILE="$SCRIPT_DIR/test-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: test-config.json not found"
    exit 1
fi

# Generate test manifest
MANIFEST_FILE="$RESULTS_DIR/manifest.json"
cat > "$MANIFEST_FILE" << EOF
{
  "test_run_id": "$TIMESTAMP",
  "start_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "dsql_host": "$DSQL_HOST",
  "iam_username": "$IAM_USERNAME",
  "aws_region": "$AWS_REGION",
  "tests": []
}
EOF

# Function to run a single test
run_test() {
    local test_id=$1
    local scenario=$2
    local threads=$3
    local iterations=$4
    local count=$5
    local payload_size=$6
    
    echo "Running test: $test_id"
    echo "  Scenario: $scenario, Threads: $threads, Iterations: $iterations, Count: $count, Payload: ${payload_size:-default}"
    
    # Warn for extreme scaling tests
    if [ "$threads" -ge 500 ] || [ "${count:-0}" -ge 500 ]; then
        echo "  ⚠️  Extreme scaling test detected - ensure instance type is m5a.2xlarge or larger"
    fi
    
    # Calculate or use MAX_POOL_SIZE from environment
    MAX_POOL_SIZE="${MAX_POOL_SIZE:-}"
    if [ -z "$MAX_POOL_SIZE" ]; then
        # Calculate based on thread count: threads/2, min 10, max 1000
        MAX_POOL_SIZE=$((threads / 2))
        if [ $MAX_POOL_SIZE -lt 10 ]; then
            MAX_POOL_SIZE=10
        fi
        if [ $MAX_POOL_SIZE -gt 1000 ]; then
            MAX_POOL_SIZE=1000
        fi
    fi
    
    # Build commands
    COMMANDS_JSON=$(jq -n \
        --arg s3_bucket "$S3_BUCKET" \
        --arg dsql_host "$DSQL_HOST" \
        --arg iam_user "$IAM_USERNAME" \
        --arg aws_region "$AWS_REGION" \
        --arg scenario "$scenario" \
        --arg threads "$threads" \
        --arg iterations "$iterations" \
        --arg count "$count" \
        --arg payload_size "${payload_size:-}" \
        --arg test_id "$test_id" \
        --arg output_dir "/tmp/results" \
        --arg max_pool_size "$MAX_POOL_SIZE" \
        '[
            "set +e",
            "cd /tmp",
            "rm -rf dsql-load-test-java",
            "mkdir -p dsql-load-test-java",
            "mkdir -p /tmp/results",
            "cd dsql-load-test-java || exit 1",
            (if ($s3_bucket | length > 0) then "aws s3 cp s3://" + $s3_bucket + "/dsql-load-test-java.tar.gz ./" else "echo \"S3 not available\"" end),
            "tar xzf dsql-load-test-java.tar.gz 2>/dev/null || true",
            "if ! command -v mvn &> /dev/null; then dnf install -y maven >/dev/null 2>&1 || yum install -y maven >/dev/null 2>&1 || true; fi",
            "mvn clean package -DskipTests -q || { echo \"Maven build failed\"; exit 1; }",
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
            (if ($payload_size | length > 0) then "export PAYLOAD_SIZE=" + $payload_size else "unset PAYLOAD_SIZE" end),
            "export TEST_ID=" + $test_id,
            "export OUTPUT_DIR=/tmp/results",
            "export MAX_POOL_SIZE=" + $max_pool_size,
            "echo \"OUTPUT_DIR is set to: $OUTPUT_DIR\"",
            "echo \"TEST_ID is set to: $TEST_ID\"",
            "JAVA_EXIT=0",
            "java -jar target/dsql-load-test-1.0.0.jar 2>&1 | tee /tmp/test-output.log || JAVA_EXIT=$?",
            "echo \"=== Java application exit code: $JAVA_EXIT ===\"",
            "sleep 3",
            "echo \"=== Result files after test ===\"",
            "ls -lah /tmp/results/ 2>/dev/null || echo \"No results directory\"",
            "echo \"=== Checking test-output.log for export message ===\"",
            "grep -i -E \"exported|Results exported\" /tmp/test-output.log 2>/dev/null || echo \"No export message found in log\""
        ]')
    
    # Execute test
    COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$TEST_RUNNER_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --document-name "AWS-RunShellScript" \
        --parameters "{\"commands\":$COMMANDS_JSON,\"workingDirectory\":[\"/tmp\"],\"executionTimeout\":[\"1800\"]}" \
        --output json | jq -r '.Command.CommandId')
    
    # Wait for completion
    for i in {1..300}; do
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
    
    # Get result JSON - download from bastion
    echo "  Downloading result JSON from bastion..."
    DOWNLOAD_CMD=$(jq -n \
        --arg test_id "$test_id" \
        '[
            "if [ -f /tmp/results/" + $test_id + ".json ]; then",
            "  cat /tmp/results/" + $test_id + ".json",
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
    
    # Extract result JSON, handle empty/null cases
    RESULT_JSON=$(echo "$DOWNLOAD_OUTPUT" | jq -r '.StandardOutputContent // empty' 2>/dev/null)
    
    # If result is empty or just whitespace, use empty JSON object
    if [ -z "$RESULT_JSON" ] || [ "$(echo "$RESULT_JSON" | tr -d '[:space:]')" = "" ]; then
        RESULT_JSON="{}"
        echo "  Warning: Result file not found or empty on bastion, using empty JSON"
    fi
    
    # Save result
    echo "$RESULT_JSON" > "$RESULTS_DIR/$test_id.json"
    
    # Update manifest
    jq --arg test_id "$test_id" \
       --arg scenario "$scenario" \
       --arg threads "$threads" \
       --arg iterations "$iterations" \
       --arg count "$count" \
       --arg payload_size "${payload_size:-default}" \
       '.tests += [{
         "test_id": $test_id,
         "scenario": ($scenario | tonumber),
         "threads": ($threads | tonumber),
         "iterations": ($iterations | tonumber),
         "count": ($count | tonumber),
         "payload_size": $payload_size,
         "status": "completed"
       }]' "$MANIFEST_FILE" > "$MANIFEST_FILE.tmp" && mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"
    
    echo "  Completed: $test_id"
    echo ""
}

# Parse and execute tests from config
TEST_NUM=1
TOTAL_TESTS=0

# Count total tests first
for group in $(jq -r '.test_groups | keys_unsorted[]' "$CONFIG_FILE"); do
    scenario=$(jq -r ".test_groups.$group.scenario" "$CONFIG_FILE")
    # Handle both arrays and single values - use jq to normalize in single pass
    threads_array=$(jq -r ".test_groups.$group.threads // .baseline.threads | if type == \"array\" then .[] else . end" "$CONFIG_FILE")
    iterations_array=$(jq -r ".test_groups.$group.iterations // .baseline.iterations | if type == \"array\" then .[] else . end" "$CONFIG_FILE")
    count_array=$(jq -r ".test_groups.$group.count // .test_groups.$group.batch_size // .baseline.batch_size // 1 | if type == \"array\" then .[] else . end" "$CONFIG_FILE")
    payload_array=$(jq -r ".test_groups.$group.payload_size // .baseline.payload_size | if type == \"array\" then .[] else . end" "$CONFIG_FILE")
    
    for t in $threads_array; do
        for i in $iterations_array; do
            for c in $count_array; do
                for p in $payload_array; do
                    TOTAL_TESTS=$((TOTAL_TESTS + 1))
                done
            done
        done
    done
done

echo "Total tests to run: $TOTAL_TESTS"
echo "Estimated time: ~$((TOTAL_TESTS * 5)) minutes"
echo ""

# Execute tests
for group in $(jq -r '.test_groups | keys_unsorted[]' "$CONFIG_FILE"); do
    echo "=== Test Group: $group ==="
    
    scenario=$(jq -r ".test_groups.$group.scenario" "$CONFIG_FILE")
    # Handle both arrays and single values - use jq to normalize in single pass
    threads_array=$(jq -r ".test_groups.$group.threads // .baseline.threads | if type == \"array\" then .[] else . end" "$CONFIG_FILE")
    iterations_array=$(jq -r ".test_groups.$group.iterations // .baseline.iterations | if type == \"array\" then .[] else . end" "$CONFIG_FILE")
    count_array=$(jq -r ".test_groups.$group.count // .test_groups.$group.batch_size // .baseline.batch_size // 1 | if type == \"array\" then .[] else . end" "$CONFIG_FILE")
    payload_array=$(jq -r ".test_groups.$group.payload_size // .baseline.payload_size | if type == \"array\" then .[] else . end" "$CONFIG_FILE")
    
    for t in $threads_array; do
        for i in $iterations_array; do
            for c in $count_array; do
                for p in $payload_array; do
                    # Generate test ID
                    payload_str=$(echo "$p" | sed 's/null/default/' | tr -d '"')
                    test_id=$(printf "test-%03d-scenario%d-threads%d-loops%d-count%d-payload%s" \
                             $TEST_NUM $scenario $t $i $c "$payload_str")
                    
                    # Check if test already completed (resume mode)
                    if [ "$RESUME" = "true" ] && [ -f "$RESULTS_DIR/$test_id.json" ]; then
                        echo "[$TEST_NUM/$TOTAL_TESTS] SKIPPED (already completed): $test_id"
                    else
                        echo "[$TEST_NUM/$TOTAL_TESTS]"
                        run_test "$test_id" "$scenario" "$t" "$i" "$c" "$p"
                    fi
                    
                    TEST_NUM=$((TEST_NUM + 1))
                done
            done
        done
    done
done

# Update manifest with end time
jq ".end_time = \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" "$MANIFEST_FILE" > "$MANIFEST_FILE.tmp" && mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"

echo "=========================================="
echo "Test Suite Complete"
echo "=========================================="
echo "Results saved to: $RESULTS_DIR"
echo ""
echo "Next steps:"
echo "  1. Run analysis: python3 $SCRIPT_DIR/analyze-results.py $RESULTS_DIR"
echo "  2. Generate report: python3 $SCRIPT_DIR/generate-report.py $RESULTS_DIR"
echo ""

