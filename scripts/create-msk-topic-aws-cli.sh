#!/bin/bash
# Script to create MSK Serverless topic using AWS CLI and Kafka tools
# This script uses kafka-topics.sh with IAM authentication

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}ℹ️  $1${NC}"
}

print_note() {
    echo -e "${YELLOW}📝 Note: $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check if required tools are available
check_requirements() {
    local missing_tools=()
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    if ! command -v kafka-topics.sh &> /dev/null; then
        missing_tools+=("kafka-topics.sh (Apache Kafka tools)")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Installation instructions:"
        echo "  AWS CLI: https://aws.amazon.com/cli/"
        echo "  Kafka tools:"
        echo "    - Download from: https://kafka.apache.org/downloads"
        echo "    - Or install via package manager (brew install kafka, apt-get install kafka, etc.)"
        exit 1
    fi
}

# Get MSK cluster ARN and bootstrap servers from Terraform
get_msk_info() {
    local terraform_dir="${1:-terraform}"
    
    if [ ! -d "$terraform_dir" ]; then
        print_error "Terraform directory not found: $terraform_dir"
        exit 1
    fi
    
    print_info "Getting MSK cluster information from Terraform..."
    
    cd "$terraform_dir"
    
    MSK_CLUSTER_ARN=$(terraform output -raw msk_cluster_arn 2>/dev/null || echo "")
    MSK_BOOTSTRAP=$(terraform output -raw msk_bootstrap_brokers 2>/dev/null || echo "")
    
    cd - > /dev/null
    
    if [ -z "$MSK_CLUSTER_ARN" ] || [ -z "$MSK_BOOTSTRAP" ]; then
        print_error "Failed to get MSK cluster information from Terraform"
        print_warning "Make sure Terraform has been applied and MSK cluster exists"
        exit 1
    fi
    
    print_info "MSK Cluster ARN: $MSK_CLUSTER_ARN"
    print_info "Bootstrap Servers: $MSK_BOOTSTRAP"
}

# Create topic using kafka-topics.sh with IAM auth
create_topic() {
    local bootstrap_servers="$1"
    local topic_name="$2"
    local partitions="${3:-3}"
    
    print_info "Creating topic '$topic_name' with $partitions partitions..."
    
    # Create JAAS config file for IAM authentication
    local jaas_config_file=$(mktemp)
    cat > "$jaas_config_file" <<EOF
KafkaClient {
    software.amazon.msk.auth.iam.IAMLoginModule required;
};
EOF
    
    # Set KAFKA_OPTS for IAM authentication
    export KAFKA_OPTS="-Djava.security.auth.login.config=$jaas_config_file"
    
    # Download AWS MSK IAM auth library if not present
    local aws_msk_jar="$HOME/.local/lib/aws-msk-iam-auth.jar"
    if [ ! -f "$aws_msk_jar" ]; then
        print_info "Downloading AWS MSK IAM auth library..."
        mkdir -p "$(dirname "$aws_msk_jar")"
        if ! curl -L -o "$aws_msk_jar" \
            https://github.com/aws/aws-msk-iam-auth/releases/download/v1.1.9/aws-msk-iam-auth-1.1.9-all.jar 2>/dev/null; then
            print_error "Failed to download AWS MSK IAM auth library"
            print_warning "You can download it manually from:"
            print_warning "  https://github.com/aws/aws-msk-iam-auth/releases/download/v1.1.9/aws-msk-iam-auth-1.1.9-all.jar"
            print_warning "  Save to: $aws_msk_jar"
            return 1
        fi
    fi
    
    # Find kafka-topics.sh
    local kafka_topics_sh=$(which kafka-topics.sh 2>/dev/null || \
        find /opt/homebrew -name "kafka-topics.sh" 2>/dev/null | head -1 || \
        find /usr/local -name "kafka-topics.sh" 2>/dev/null | head -1 || \
        find /opt -name "kafka-topics.sh" 2>/dev/null | head -1)
    
    if [ -z "$kafka_topics_sh" ]; then
        print_error "kafka-topics.sh not found. Please install Kafka tools."
        return 1
    fi
    
    # Get Kafka lib directory for classpath
    local kafka_lib_dir=$(dirname "$(dirname "$kafka_topics_sh")")/libs
    if [ ! -d "$kafka_lib_dir" ]; then
        # Try alternative location
        kafka_lib_dir=$(dirname "$(dirname "$(dirname "$kafka_topics_sh")")")/lib
    fi
    
    # Create topic with AWS MSK IAM auth library in classpath
    if CLASSPATH="$aws_msk_jar:$kafka_lib_dir/*" "$kafka_topics_sh" \
        --create \
        --bootstrap-server "$bootstrap_servers" \
        --topic "$topic_name" \
        --partitions "$partitions" \
        --command-config <(cat <<EOF
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
EOF
) 2>&1; then
        print_info "✅ Topic '$topic_name' created successfully!"
        rm -f "$jaas_config_file"
        return 0
    else
        local exit_code=$?
        print_error "Failed to create topic '$topic_name'"
        rm -f "$jaas_config_file"
        return $exit_code
    fi
}

# Main function
main() {
    local topic_name="${1:-raw-event-headers}"
    local partitions="${2:-3}"
    local terraform_dir="${3:-terraform}"
    
    echo "=========================================="
    echo "MSK Topic Creation Script"
    echo "=========================================="
    echo ""
    
    check_requirements
    get_msk_info "$terraform_dir"
    
    echo ""
    print_info "Topic name: $topic_name"
    print_info "Partitions: $partitions"
    echo ""
    print_note "MSK Serverless requires network access from within the VPC."
    print_note "If running from outside the VPC, you may need to:"
    print_note "  1. Run from an EC2 instance in the VPC"
    print_note "  2. Use AWS Systems Manager Session Manager"
    print_note "  3. Use AWS Console (easiest method)"
    echo ""
    
    # Find kafka-topics.sh and setup classpath
    local kafka_topics_sh=$(which kafka-topics.sh 2>/dev/null || \
        find /opt/homebrew -name "kafka-topics.sh" 2>/dev/null | head -1 || \
        find /usr/local -name "kafka-topics.sh" 2>/dev/null | head -1 || \
        find /opt -name "kafka-topics.sh" 2>/dev/null | head -1)
    
    if [ -z "$kafka_topics_sh" ]; then
        print_error "kafka-topics.sh not found. Please install Kafka tools."
        exit 1
    fi
    
    local aws_msk_jar="$HOME/.local/lib/aws-msk-iam-auth.jar"
    local kafka_lib_dir=$(dirname "$(dirname "$kafka_topics_sh")")/libs
    if [ ! -d "$kafka_lib_dir" ]; then
        kafka_lib_dir=$(dirname "$(dirname "$(dirname "$kafka_topics_sh")")")/lib
    fi
    
    # Check if topic already exists
    print_info "Checking if topic already exists..."
    if CLASSPATH="$aws_msk_jar:$kafka_lib_dir/*" "$kafka_topics_sh" \
        --list \
        --bootstrap-server "$MSK_BOOTSTRAP" \
        --command-config <(cat <<EOF
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
EOF
) 2>/dev/null | grep -q "^${topic_name}$"; then
        print_warning "Topic '$topic_name' already exists"
        echo ""
        read -p "Do you want to continue anyway? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Exiting..."
            exit 0
        fi
    fi
    
    # Create topic
    if create_topic "$MSK_BOOTSTRAP" "$topic_name" "$partitions"; then
        echo ""
        print_info "Verifying topic creation..."
        if CLASSPATH="$aws_msk_jar:$kafka_lib_dir/*" "$kafka_topics_sh" \
            --describe \
            --bootstrap-server "$MSK_BOOTSTRAP" \
            --topic "$topic_name" \
            --command-config <(cat <<EOF
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
EOF
) 2>/dev/null; then
            print_info "✅ Topic verified successfully!"
        else
            print_warning "Could not verify topic (it may still have been created)"
        fi
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"

