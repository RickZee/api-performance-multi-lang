#!/bin/bash
# Deploy Java load test to bastion host and run tests

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

# Verify IAM grant before proceeding
echo "=== Verifying IAM Grant Status ==="
PROJECT_NAME=$(grep -E "^project_name\s*=" terraform.tfvars 2>/dev/null | sed 's/#.*$//' | cut -d'"' -f2 | tr -d ' ' || echo "producer-api")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
BASTION_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_NAME}-bastion-role"

VERIFY_QUERY="SELECT pg_role_name, arn FROM sys.iam_pg_role_mappings WHERE pg_role_name = '${IAM_USERNAME}' AND arn = '${BASTION_ROLE_ARN}';"
VERIFY_COMMANDS=$(jq -n \
    --arg dsql_host "$DSQL_HOST" \
    --arg aws_region "$AWS_REGION" \
    --arg query "$VERIFY_QUERY" \
    '[
        "export DSQL_HOST=" + $dsql_host,
        "export AWS_REGION=" + $aws_region,
        "TOKEN=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST 2>/dev/null)",
        "export PGPASSWORD=$TOKEN",
        "RESULT=$(psql -h $DSQL_HOST -U admin -d postgres -p 5432 -t -A -c " + ($query | @sh) + " 2>/dev/null || echo \"\")",
        "if [ -z \"$RESULT\" ]; then",
        "  echo \"⚠️  IAM grant not found. Running grant script...\"",
        "  exit 1",
        "else",
        "  echo \"✅ IAM grant verified: $RESULT\"",
        "fi"
    ]')

VERIFY_OUTPUT=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$VERIFY_COMMANDS}" \
    --output json 2>&1)

VERIFY_COMMAND_ID=$(echo "$VERIFY_OUTPUT" | jq -r '.Command.CommandId' 2>/dev/null || echo "")

if [ -n "$VERIFY_COMMAND_ID" ] && [ "$VERIFY_COMMAND_ID" != "null" ]; then
    sleep 5
    VERIFY_RESULT=$(aws ssm get-command-invocation \
        --command-id "$VERIFY_COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null)
    
    VERIFY_STATUS=$(echo "$VERIFY_RESULT" | jq -r '.Status' 2>/dev/null)
    VERIFY_STDOUT=$(echo "$VERIFY_RESULT" | jq -r '.StandardOutputContent // ""' 2>/dev/null)
    
    if [ "$VERIFY_STATUS" = "Success" ] && echo "$VERIFY_STDOUT" | grep -q "✅"; then
        echo "$VERIFY_STDOUT" | grep "✅"
    else
        echo "⚠️  IAM grant verification failed or not found"
        echo "Running grant-bastion-dsql-access.sh script..."
        cd "$PROJECT_ROOT" && ./scripts/grant-bastion-dsql-access.sh || {
            echo "Error: Failed to grant IAM access"
            exit 1
        }
    fi
else
    echo "⚠️  Could not verify IAM grant, proceeding anyway..."
fi

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
    aws s3 cp /tmp/dsql-load-test-java.tar.gz "s3://$S3_BUCKET/dsql-load-test-java.tar.gz"
    echo "Uploaded to s3://$S3_BUCKET/dsql-load-test-java.tar.gz"
else
    echo "Warning: S3 bucket not found, will upload directly via SSM"
fi

echo ""
echo "=== Building and running on bastion host ==="

# Build and run Scenario 1
echo "=== Scenario 1: Individual Inserts ==="
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
        "aws s3 cp s3://" + $s3_bucket + "/dsql-load-test-java.tar.gz ./",
        "tar xzf dsql-load-test-java.tar.gz",
        "if ! command -v mvn &> /dev/null; then dnf install -y maven >/dev/null 2>&1 || yum install -y maven >/dev/null 2>&1; fi",
        "mvn clean package -DskipTests -q",
        "export DSQL_HOST=" + $dsql_host,
        "export DSQL_PORT=5432",
        "export DATABASE_NAME=postgres",
        "export IAM_USERNAME=" + $iam_user,
        "export AWS_REGION=" + $aws_region,
        "export SCENARIO=1",
        "export THREADS=5",
        "export ITERATIONS=2",
        "export COUNT=1",
        "java -jar target/dsql-load-test-1.0.0.jar"
    ]')

COMMAND_ID1=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$COMMANDS_JSON,\"workingDirectory\":[\"/tmp\"],\"executionTimeout\":[\"600\"]}" \
    --output json | jq -r '.Command.CommandId')

echo "Command ID: $COMMAND_ID1"
echo "Waiting for Scenario 1 to complete (this may take a few minutes)..."
sleep 15

# Poll for completion
for i in {1..60}; do
    STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID1" \
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
echo "=== Scenario 1 Results ==="
INVOCATION1=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID1" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --output json 2>/dev/null)

STATUS1=$(echo "$INVOCATION1" | jq -r '.Status // "Unknown"' 2>/dev/null)
echo "Status: $STATUS1"
echo ""
echo "Output:"
echo "$INVOCATION1" | jq -r '.StandardOutputContent // ""' 2>/dev/null
if [ -n "$(echo "$INVOCATION1" | jq -r '.StandardErrorContent // ""' 2>/dev/null)" ]; then
    echo ""
    echo "Errors:"
    echo "$INVOCATION1" | jq -r '.StandardErrorContent' 2>/dev/null
fi

# Build and run Scenario 2
echo ""
echo "=== Scenario 2: Batch Inserts ==="
COMMANDS_JSON2=$(jq -n \
    --arg dsql_host "$DSQL_HOST" \
    --arg iam_user "$IAM_USERNAME" \
    --arg aws_region "$AWS_REGION" \
    '[
        "cd /tmp/dsql-load-test-java",
        "export DSQL_HOST=" + $dsql_host,
        "export DSQL_PORT=5432",
        "export DATABASE_NAME=postgres",
        "export IAM_USERNAME=" + $iam_user,
        "export AWS_REGION=" + $aws_region,
        "export SCENARIO=2",
        "export THREADS=5",
        "export ITERATIONS=2",
        "export COUNT=10",
        "java -jar target/dsql-load-test-1.0.0.jar"
    ]')

COMMAND_ID2=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$COMMANDS_JSON2,\"workingDirectory\":[\"/tmp/dsql-load-test-java\"],\"executionTimeout\":[\"600\"]}" \
    --output json | jq -r '.Command.CommandId')

echo "Command ID: $COMMAND_ID2"
echo "Waiting for Scenario 2 to complete (this may take a few minutes)..."
sleep 15

# Poll for completion
for i in {1..60}; do
    STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID2" \
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
echo "=== Scenario 2 Results ==="
INVOCATION2=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID2" \
    --instance-id "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --output json 2>/dev/null)

STATUS2=$(echo "$INVOCATION2" | jq -r '.Status // "Unknown"' 2>/dev/null)
echo "Status: $STATUS2"
echo ""
echo "Output:"
echo "$INVOCATION2" | jq -r '.StandardOutputContent // ""' 2>/dev/null
if [ -n "$(echo "$INVOCATION2" | jq -r '.StandardErrorContent // ""' 2>/dev/null)" ]; then
    echo ""
    echo "Errors:"
    echo "$INVOCATION2" | jq -r '.StandardErrorContent' 2>/dev/null
fi

echo ""
echo "=== Deployment and testing complete ==="
