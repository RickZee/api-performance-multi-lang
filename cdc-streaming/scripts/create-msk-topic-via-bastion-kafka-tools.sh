#!/usr/bin/env bash
# Create MSK Topic via Bastion Host using kafka-topics.sh
# This script executes kafka-topics.sh on the bastion host via SSM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Source shared utilities
if [ -f "$PROJECT_ROOT/scripts/shared/color-output.sh" ]; then
    source "$PROJECT_ROOT/scripts/shared/color-output.sh"
fi

# Define helper functions if not already defined
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

# Function to execute commands on bastion
execute_on_bastion() {
    local commands_json="$1"
    local command_id=""
    local status="Unknown"
    local stdout=""
    local stderr=""

    cd "$PROJECT_ROOT/terraform"
    BASTION_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
    AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
    cd "$PROJECT_ROOT"

    if [ -z "$BASTION_ID" ]; then
        fail "Bastion host instance ID not found."
        return 1
    fi

    command_id=$(aws ssm send-command \
        --instance-ids "$BASTION_ID" \
        --region "$AWS_REGION" \
        --document-name "AWS-RunShellScript" \
        --parameters "{\"commands\":$commands_json}" \
        --output json --query 'Command.CommandId' --output text 2>/dev/null || echo "")

    if [ -z "$command_id" ]; then
        fail "Failed to send command to bastion host."
        return 1
    fi

    info "Command ID: $command_id"
    info "Waiting for command to complete (max 180s)..."

    local max_wait=180
    local elapsed=0
    local check_interval=5

    while true; do
        local invocation=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
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

    if [ "$status" = "Success" ]; then
        echo "$stdout"
        if [ -n "$stderr" ]; then
            echo "$stderr" >&2
        fi
        return 0
    else
        fail "Command failed with status: $status"
        if [ -n "$stderr" ]; then echo "$stderr" >&2; fi
        if [ -n "$stdout" ]; then echo "$stdout"; fi
        return 1
    fi
}

TOPIC_NAME="${1:-raw-event-headers}"
PARTITIONS="${2:-1}"

cd "$PROJECT_ROOT/terraform"
MSK_BOOTSTRAP=$(terraform output -raw msk_bootstrap_brokers 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
BASTION_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
cd "$PROJECT_ROOT"

if [ -z "$MSK_BOOTSTRAP" ]; then
    fail "MSK bootstrap servers not found. Make sure MSK is deployed."
    exit 1
fi

if [ -z "$BASTION_ID" ]; then
    fail "Bastion host instance ID not found. Make sure bastion host is deployed."
    exit 1
fi

section "Create MSK Topic via Bastion (kafka-topics.sh)"
info "Topic: $TOPIC_NAME"
info "Partitions: $PARTITIONS"
info "MSK Bootstrap: $MSK_BOOTSTRAP"
info "Bastion Host: $BASTION_ID"
echo ""

# Create a script that will be executed on the bastion
BASTION_SCRIPT=$(cat <<BASTIONSCRIPT
#!/bin/bash
set -e
export AWS_DEFAULT_REGION=${AWS_REGION}
cd /home/ec2-user

# Install Kafka tools if not present
if ! command -v kafka-topics.sh &> /dev/null; then
  echo "Installing Kafka tools..."
  sudo yum install -y java-11-amazon-corretto-headless || sudo yum install -y java-1.8.0-openjdk-headless || true
  KAFKA_VERSION=3.6.1
  if [ ! -d kafka_2.13-\$KAFKA_VERSION ]; then
    echo "Downloading Kafka \$KAFKA_VERSION..."
    # Use archive.apache.org as fallback if downloads.apache.org fails
    if ! curl -L -f -o kafka.tgz https://downloads.apache.org/kafka/\$KAFKA_VERSION/kafka_2.13-\$KAFKA_VERSION.tgz 2>/dev/null; then
      echo "Trying archive.apache.org..."
      curl -L -f -o kafka.tgz https://archive.apache.org/dist/kafka/\$KAFKA_VERSION/kafka_2.13-\$KAFKA_VERSION.tgz
    fi
    if [ -f kafka.tgz ] && [ \$(stat -c%s kafka.tgz 2>/dev/null || stat -f%z kafka.tgz 2>/dev/null || echo 0) -gt 1000000 ]; then
      tar -xzf kafka.tgz
      rm kafka.tgz
      echo "Kafka tools installed successfully"
    else
      echo "ERROR: Failed to download Kafka (file too small or missing)"
      rm -f kafka.tgz
      exit 1
    fi
  fi
  export PATH=\$PATH:/home/ec2-user/kafka_2.13-\$KAFKA_VERSION/bin
fi

# Download AWS MSK IAM auth library if needed
AWS_MSK_JAR=/home/ec2-user/.local/lib/aws-msk-iam-auth.jar
mkdir -p \$(dirname \$AWS_MSK_JAR)
if [ ! -f \$AWS_MSK_JAR ]; then
  echo "Downloading AWS MSK IAM auth library..."
  curl -L -o \$AWS_MSK_JAR https://github.com/aws/aws-msk-iam-auth/releases/download/v1.1.9/aws-msk-iam-auth-1.1.9-all.jar
fi

# Find kafka-topics.sh
KAFKA_TOPICS_SH=\$(which kafka-topics.sh 2>/dev/null || find /home/ec2-user/kafka_2.13-* -name kafka-topics.sh 2>/dev/null | head -1)
if [ -z "\$KAFKA_TOPICS_SH" ]; then
  echo "ERROR: kafka-topics.sh not found"
  exit 1
fi

# Get Kafka lib directory
KAFKA_LIB_DIR=\$(dirname \$(dirname \$KAFKA_TOPICS_SH))/libs
if [ ! -d "\$KAFKA_LIB_DIR" ]; then
  KAFKA_LIB_DIR=\$(dirname \$(dirname \$(dirname \$KAFKA_TOPICS_SH)))/lib
fi

# Create JAAS config
JAAS_CONFIG=\$(mktemp)
cat > \$JAAS_CONFIG <<'JAASEOF'
KafkaClient {
    software.amazon.msk.auth.iam.IAMLoginModule required;
};
JAASEOF

# Create command config file
COMMAND_CONFIG=\$(mktemp)
cat > \$COMMAND_CONFIG <<'CONFIGEOF'
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
CONFIGEOF

# Check if topic already exists
if CLASSPATH="\$AWS_MSK_JAR:\$KAFKA_LIB_DIR/*" \$KAFKA_TOPICS_SH --list --bootstrap-server ${MSK_BOOTSTRAP} --command-config \$COMMAND_CONFIG 2>/dev/null | grep -q "^${TOPIC_NAME}\$"; then
  echo "INFO: Topic ${TOPIC_NAME} already exists"
  echo "EXISTS"
else
  # Create topic
  if CLASSPATH="\$AWS_MSK_JAR:\$KAFKA_LIB_DIR/*" KAFKA_OPTS="-Djava.security.auth.login.config=\$JAAS_CONFIG" \$KAFKA_TOPICS_SH \\
    --create \\
    --bootstrap-server ${MSK_BOOTSTRAP} \\
    --topic ${TOPIC_NAME} \\
    --partitions ${PARTITIONS} \\
    --command-config \$COMMAND_CONFIG 2>&1; then
    echo "SUCCESS: Topic ${TOPIC_NAME} created"
    echo "OK"
  else
    echo "ERROR: Failed to create topic"
    exit 1
  fi
fi

# Cleanup
rm -f \$JAAS_CONFIG \$COMMAND_CONFIG
BASTIONSCRIPT
)

# Base64 encode the script to avoid escaping issues
BASTION_SCRIPT_B64=$(echo "$BASTION_SCRIPT" | base64 | tr -d '\n')

COMMANDS_ARRAY=$(jq -n \
    --arg script_b64 "$BASTION_SCRIPT_B64" \
    '[
        "echo " + $script_b64 + " | base64 -d > /tmp/create_topic.sh",
        "chmod +x /tmp/create_topic.sh",
        "sudo -u ec2-user bash /tmp/create_topic.sh"
    ]')

info "Creating topic on bastion host using kafka-topics.sh..."
RESULT=$(execute_on_bastion "$COMMANDS_ARRAY" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    if echo "$RESULT" | grep -q "OK"; then
        pass "Topic '$TOPIC_NAME' created successfully!"
    elif echo "$RESULT" | grep -q "EXISTS"; then
        warn "Topic '$TOPIC_NAME' already exists."
    else
        echo "$RESULT"
        fail "Unexpected output from topic creation"
        exit 1
    fi
else
    fail "Failed to create topic"
    echo "$RESULT"
    exit 1
fi
