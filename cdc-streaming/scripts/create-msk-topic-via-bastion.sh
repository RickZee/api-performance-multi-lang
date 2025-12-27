#!/usr/bin/env bash
# Create MSK topic via bastion host
# This ensures topic creation happens from within the VPC

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
section() { echo -e "${CYAN}========================================${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}========================================${NC}"; }

# Get Terraform outputs
cd "$PROJECT_ROOT/terraform"
TERRAFORM_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")
MSK_BOOTSTRAP=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.msk_bootstrap_brokers.value // ""' 2>/dev/null || echo "")
AWS_REGION=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.aws_region.value // "us-east-1"' 2>/dev/null || echo "us-east-1")
BASTION_ID=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.bastion_host_instance_id.value // ""' 2>/dev/null || echo "")
S3_BUCKET=$(echo "$TERRAFORM_OUTPUTS" | jq -r '.s3_bucket_name.value // ""' 2>/dev/null || echo "")
cd "$PROJECT_ROOT"

if [ -z "$MSK_BOOTSTRAP" ]; then
    fail "MSK bootstrap servers not found. Make sure MSK is deployed."
    exit 1
fi

if [ -z "$BASTION_ID" ]; then
    fail "Bastion host instance ID not found. Make sure bastion host is deployed."
    exit 1
fi

# Parse arguments
TOPIC_NAME="${1:-raw-event-headers}"
PARTITIONS="${2:-1}"
REPLICATION_FACTOR="${3:-1}"

section "Create MSK Topic via Bastion Host"
info "Topic: $TOPIC_NAME"
info "Partitions: $PARTITIONS"
info "Replication Factor: $REPLICATION_FACTOR"
info "MSK Bootstrap: $MSK_BOOTSTRAP"
info "Bastion Host: $BASTION_ID"
echo ""

# Upload create-msk-topic.py to S3 if bucket is available
if [ -n "$S3_BUCKET" ] && [ -f "$PROJECT_ROOT/scripts/create-msk-topic.py" ]; then
    info "Uploading create-msk-topic.py to S3..."
    aws s3 cp "$PROJECT_ROOT/scripts/create-msk-topic.py" "s3://${S3_BUCKET}/scripts/create-msk-topic.py" --region "$AWS_REGION" 2>&1 | grep -v "Completed" || true
    pass "Script uploaded to S3"
fi

# Build Python script to create topic (expand variables first)
PYTHON_SCRIPT=$(cat << PYEOF
import sys
import os
sys.path.insert(0, '/home/ec2-user/.local/lib/python3.9/site-packages')

from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import TopicAlreadyExistsError
import boto3
from aws_msk_iam_sasl_signer.MSKAuthTokenProvider import generate_auth_token

class MSKTokenProvider:
    def __init__(self, region):
        self.region = region
    def token(self):
        return generate_auth_token(region=self.region)

session = boto3.Session()
region = session.region_name or 'us-east-1'
auth_provider = MSKTokenProvider(region=region)
bootstrap = '$MSK_BOOTSTRAP'
topic_name = '$TOPIC_NAME'
partitions = $PARTITIONS
replication_factor = $REPLICATION_FACTOR

try:
    admin_client = KafkaAdminClient(
        bootstrap_servers=bootstrap,
        security_protocol='SASL_SSL',
        sasl_mechanism='AWS_MSK_IAM',
        sasl_oauth_token_provider=auth_provider,
        api_version=(2, 6, 0),
        request_timeout_ms=10000
    )
    
    topic = NewTopic(name=topic_name, num_partitions=partitions, replication_factor=replication_factor)
    
    try:
        admin_client.create_topics([topic])
        print(f'SUCCESS: Created topic {topic_name}', file=sys.stderr)
        print('OK')
    except TopicAlreadyExistsError:
        print(f'INFO: Topic {topic_name} already exists', file=sys.stderr)
        print('EXISTS')
    except Exception as e:
        print(f'ERROR: {e}', file=sys.stderr)
        sys.exit(1)
    
    admin_client.close()
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF
)

# Build command array using base64 encoding to avoid escaping issues
PYTHON_SCRIPT_B64=$(echo "$PYTHON_SCRIPT" | base64 | tr -d '\n')

COMMANDS_ARRAY=$(jq -n \
    --arg script_b64 "$PYTHON_SCRIPT_B64" \
    '[
        "echo " + $script_b64 + " | base64 -d > /tmp/create_msk_topic.py",
        "chmod +x /tmp/create_msk_topic.py",
        "sudo -u ec2-user python3 /tmp/create_msk_topic.py"
    ]')

# Execute on bastion
info "Creating topic on bastion host..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$BASTION_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":$COMMANDS_ARRAY}" \
    --output json --query 'Command.CommandId' --output text 2>/dev/null || echo "")

if [ -z "$COMMAND_ID" ]; then
    fail "Failed to send command to bastion host."
    exit 1
fi

info "Command ID: $COMMAND_ID"
info "Waiting for command to complete (max 120s)..."

max_wait=120
elapsed=0
check_interval=5

while true; do
    invocation=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$BASTION_ID" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null || echo "{}")
    
    status=$(echo "$invocation" | jq -r '.Status' 2>/dev/null || echo "InProgress")
    
    if [ "$status" = "Success" ] || [ "$status" = "Failed" ] || [ "$status" = "Cancelled" ] || [ "$status" = "TimedOut" ]; then
        break
    fi
    
    if [ $elapsed -ge $max_wait ]; then
        warn "Timeout: Command did not complete within ${max_wait}s. Current status: $status"
        break
    fi
    
    if [ $((elapsed % 30)) -eq 0 ]; then
        info "Current status: $status (waiting... ${elapsed}s)"
    fi
    
    sleep "$check_interval"
    elapsed=$((elapsed + check_interval))
done

stdout=$(echo "$invocation" | jq -r '.StandardOutputContent // ""' 2>/dev/null || echo "")
stderr=$(echo "$invocation" | jq -r '.StandardErrorContent // ""' 2>/dev/null || echo "")

echo ""
if [ "$status" = "Success" ]; then
    if echo "$stdout" | grep -q "OK"; then
        pass "Topic '$TOPIC_NAME' created successfully"
    elif echo "$stdout" | grep -q "EXISTS"; then
        warn "Topic '$TOPIC_NAME' already exists"
    else
        info "Output: $stdout"
    fi
    if [ -n "$stderr" ]; then
        echo "$stderr" | grep -E "(SUCCESS|INFO|ERROR)" || true
    fi
else
    fail "Command failed with status: $status"
    if [ -n "$stderr" ]; then echo "$stderr" >&2; fi
    if [ -n "$stdout" ]; then echo "$stdout"; fi
    exit 1
fi

