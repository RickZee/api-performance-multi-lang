#!/bin/bash
# Run DSQL validation via bastion host using SSM
# This script uploads the events file to the bastion host,
# runs validation using Python scripts already on the bastion,
# and retrieves results

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get parameters
EVENTS_FILE="${1:-/tmp/k6-sent-events.json}"
BASTION_INSTANCE_ID="${2:-}"
AWS_REGION="${3:-us-east-1}"

if [ -z "$BASTION_INSTANCE_ID" ]; then
    # Try to get from terraform
    BASTION_INSTANCE_ID=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
    if [ -z "$BASTION_INSTANCE_ID" ]; then
        echo -e "${RED}Error: Bastion host instance ID required${NC}"
        echo "Usage: $0 [EVENTS_FILE] [BASTION_INSTANCE_ID] [AWS_REGION]"
        exit 1
    fi
fi

if [ ! -f "$EVENTS_FILE" ]; then
    echo -e "${RED}Error: Events file not found: $EVENTS_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}DSQL Validation via Bastion Host${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Bastion Instance ID: $BASTION_INSTANCE_ID"
echo "Events File: $EVENTS_FILE"
echo "Region: $AWS_REGION"
echo ""

# Get DSQL connection parameters from terraform
cd "$PROJECT_ROOT/terraform" || exit 1
DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
IAM_USERNAME=$(grep -E "^iam_database_user\s*=" terraform.tfvars 2>/dev/null | head -1 | sed 's/#.*$//' | cut -d'"' -f2 | tr -d ' ' || echo "")
DSQL_PORT=$(terraform output -raw aurora_dsql_port 2>/dev/null || echo "5432")
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || aws configure get region 2>/dev/null || echo "us-east-1")

if [ -z "$DSQL_HOST" ] || [ -z "$IAM_USERNAME" ]; then
    echo -e "${RED}Error: DSQL connection parameters not found in terraform${NC}"
    exit 1
fi

echo "DSQL Host: $DSQL_HOST"
echo "IAM Username: $IAM_USERNAME"
echo "DSQL Port: $DSQL_PORT"
echo ""

# Create temporary directory on bastion
BASTION_TEMP_DIR="/tmp/validation-$$"
BASTION_EVENTS_FILE="$BASTION_TEMP_DIR/events.json"

echo -e "${BLUE}Uploading events file to bastion host...${NC}"

# Upload events file to S3 first, then download on bastion (handles large files)
echo -e "${BLUE}Uploading events file via S3...${NC}"

# Get S3 bucket from terraform
S3_BUCKET=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw s3_bucket_name 2>/dev/null || echo "")
if [ -z "$S3_BUCKET" ]; then
    echo -e "${RED}Error: S3 bucket not found in terraform outputs${NC}" >&2
    exit 1
fi

# Upload to S3
S3_KEY="validation/events-$$.json"
aws s3 cp "$EVENTS_FILE" "s3://$S3_BUCKET/$S3_KEY" --region "$AWS_REGION" > /dev/null 2>&1 || {
    echo -e "${RED}Failed to upload events file to S3${NC}" >&2
    exit 1
}

# Download from S3 on bastion
echo -e "${BLUE}Downloading events file on bastion host...${NC}"
DOWNLOAD_COMMANDS_JSON=$(jq -n \
    --arg temp_dir "$BASTION_TEMP_DIR" \
    --arg events_file "$BASTION_EVENTS_FILE" \
    --arg s3_bucket "$S3_BUCKET" \
    --arg s3_key "$S3_KEY" \
    --arg aws_region "$AWS_REGION" \
    '[
        "mkdir -p " + $temp_dir,
        "cd " + $temp_dir,
        "aws s3 cp s3://" + $s3_bucket + "/" + $s3_key + " " + $events_file + " --region " + $aws_region
    ]')

DOWNLOAD_OUTPUT=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$DOWNLOAD_COMMANDS_JSON}" \
    --output json 2>&1)

DOWNLOAD_COMMAND_ID=$(echo "$DOWNLOAD_OUTPUT" | jq -r '.Command.CommandId' 2>/dev/null || echo "")

if [ -n "$DOWNLOAD_COMMAND_ID" ] && [ "$DOWNLOAD_COMMAND_ID" != "null" ]; then
    # Wait for download to complete
    sleep 5
    for i in {1..15}; do
        DOWNLOAD_STATUS=$(aws ssm get-command-invocation \
            --command-id "$DOWNLOAD_COMMAND_ID" \
            --instance-id "$BASTION_INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query "Status" \
            --output text 2>/dev/null || echo "InProgress")
        if [ "$DOWNLOAD_STATUS" = "Success" ] || [ "$DOWNLOAD_STATUS" = "Failed" ]; then
            break
        fi
        sleep 2
    done
fi

# Clean up S3 file after a delay (in background)
(sleep 60 && aws s3 rm "s3://$S3_BUCKET/$S3_KEY" --region "$AWS_REGION" > /dev/null 2>&1) &

# Base64 encode the Python script for transmission via SSM
VALIDATION_SCRIPT_B64=$(base64 < "$SCRIPT_DIR/validate_dsql_bastion.py")

# Now upload validation script and run validation
# First ensure Python packages are installed on bastion
COMMANDS_JSON=$(jq -n \
    --arg temp_dir "$BASTION_TEMP_DIR" \
    --arg events_file "$BASTION_EVENTS_FILE" \
    --arg script_b64 "$VALIDATION_SCRIPT_B64" \
    --arg dsql_host "$DSQL_HOST" \
    --arg dsql_port "$DSQL_PORT" \
    --arg iam_username "$IAM_USERNAME" \
    --arg aws_region "$AWS_REGION" \
    '[
        "which python3 || (dnf install -y python3 python3-pip && python3 -m pip install --upgrade pip)",
        "python3 -m pip install --user --quiet asyncpg boto3 botocore 2>&1 || (dnf install -y python3-pip && pip3 install --user --quiet asyncpg boto3 botocore 2>&1) || echo \"Package install had issues, continuing...\"",
        "cd " + $temp_dir,
        "echo \"" + $script_b64 + "\" | base64 -d > validate_dsql_bastion.py",
        "python3 validate_dsql_bastion.py " + $events_file + " \"" + $dsql_host + "\" " + $dsql_port + " \"" + $iam_username + "\" \"" + $aws_region + "\""
    ]')

# Send command to bastion host
COMMAND_OUTPUT=$(aws ssm send-command \
    --instance-ids "$BASTION_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$COMMANDS_JSON}" \
    --output json 2>&1)

COMMAND_ID=$(echo "$COMMAND_OUTPUT" | jq -r '.Command.CommandId' 2>/dev/null || echo "")

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "null" ]; then
    echo -e "${RED}Error: Failed to send command to bastion host${NC}"
    echo "$COMMAND_OUTPUT" | jq . 2>/dev/null || echo "$COMMAND_OUTPUT"
    exit 1
fi

echo "Command ID: $COMMAND_ID"
echo "Waiting for results..."

# Wait for command to complete (with timeout)
max_wait=300
elapsed=0
while [ $elapsed -lt $max_wait ]; do
    STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query "Status" \
        --output text 2>/dev/null || echo "InProgress")
    
    if [ "$STATUS" = "Success" ] || [ "$STATUS" = "Failed" ]; then
        break
    fi
    
    sleep 5
    elapsed=$((elapsed + 5))
    echo -n "."
done

echo ""

# Get results
if [ "$STATUS" = "Success" ]; then
    OUTPUT=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query "StandardOutputContent" \
        --output text 2>/dev/null)
    
    ERROR_OUTPUT=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query "StandardErrorContent" \
        --output text 2>/dev/null)
    
    # Print stderr (progress messages)
    if [ -n "$ERROR_OUTPUT" ]; then
        echo "$ERROR_OUTPUT" >&2
    fi
    
    # Parse and print results
    if [ -n "$OUTPUT" ]; then
        # Try to extract JSON from output (macOS grep doesn't support -P, use sed instead)
        # Find the first line that starts with { and extract everything from there
        JSON_START=$(echo "$OUTPUT" | grep -n "^{" | head -1 | cut -d: -f1 || echo "")
        if [ -n "$JSON_START" ]; then
            # Extract from the JSON start line to the end
            JSON_RESULT=$(echo "$OUTPUT" | sed -n "${JSON_START},\$p")
        else
            # Try to find JSON anywhere in the output
            JSON_RESULT=$(echo "$OUTPUT" | awk '/^\{/,/^\}/' | head -100 || echo "$OUTPUT")
        fi
        
        if echo "$JSON_RESULT" | jq . > /dev/null 2>&1; then
            # Valid JSON - print it (will be parsed by calling script)
            echo "$JSON_RESULT"
        else
            # Not JSON, try to find JSON in the output more carefully
            # Look for lines that look like JSON (start with { and contain "total_sent")
            JSON_LINES=$(echo "$OUTPUT" | grep -E '^\s*\{' | head -50 || echo "")
            if [ -n "$JSON_LINES" ]; then
                echo "$JSON_LINES" | jq -s '.' 2>/dev/null || echo "$OUTPUT"
            else
                echo "$OUTPUT"
            fi
        fi
    fi
else
    echo -e "${RED}Error: Command status: $STATUS${NC}" >&2
    ERROR_DETAILS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_INSTANCE_ID" \
        --region "$AWS_REGION" 2>&1)
    ERROR_OUTPUT=$(echo "$ERROR_DETAILS" | jq -r '.StandardErrorContent // empty' 2>/dev/null || echo "")
    STDERR_OUTPUT=$(echo "$ERROR_DETAILS" | jq -r '.StandardOutputContent // empty' 2>/dev/null || echo "")
    if [ -n "$ERROR_OUTPUT" ]; then
        echo "Error output:" >&2
        echo "$ERROR_OUTPUT" >&2
    fi
    if [ -n "$STDERR_OUTPUT" ]; then
        echo "Standard output:" >&2
        echo "$STDERR_OUTPUT" >&2
    fi
    # Return empty JSON so calling script can handle it
    echo '{"total_sent":0,"found":0,"missing":[],"errors":["Bastion validation command failed"]}'
    exit 1
fi
