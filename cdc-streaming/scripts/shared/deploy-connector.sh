#!/bin/bash
# Shared connector deployment script for Confluent Cloud
# Usage: deploy-connector.sh <config-file> [options]

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/scripts/shared/color-output.sh" 2>/dev/null || true

CONNECTOR_CONFIG="${1:-}"

if [ -z "$CONNECTOR_CONFIG" ]; then
    print_error "Connector config file is required"
    echo "Usage: $0 <config-file> [--env-id ENV_ID] [--cluster-id CLUSTER_ID] [--force]"
    exit 1
fi

# Parse arguments
shift
ENV_ID="${CONFLUENT_ENV_ID:-}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-}"
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --env-id)
            ENV_ID="$2"
            shift 2
            ;;
        --cluster-id)
            CLUSTER_ID="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Resolve config file path
if [[ "$CONNECTOR_CONFIG" != /* ]]; then
    # Relative path - assume it's relative to cdc-streaming/connectors
    CONNECTOR_CONFIG="$PROJECT_ROOT/cdc-streaming/connectors/$CONNECTOR_CONFIG"
fi

print_header "Deploy CDC Connector"

# Check prerequisites
if ! command -v confluent &> /dev/null; then
    print_error "Confluent CLI is not installed"
    echo "  Install with: brew install confluentinc/tap/cli"
    exit 1
fi

# Check if logged in
if ! confluent environment list &> /dev/null; then
    print_error "Not logged in to Confluent Cloud"
    echo "  Login with: confluent login"
    exit 1
fi

# Get environment and cluster from context or environment variables
if [ -z "$ENV_ID" ]; then
    ENV_ID=$(confluent environment list --output json 2>/dev/null | jq -r '.[0].id' 2>/dev/null || echo 'env-q9n81p')
fi

if [ -z "$CLUSTER_ID" ]; then
    CLUSTER_ID=$(confluent kafka cluster list --output json 2>/dev/null | jq -r '.[0].id' 2>/dev/null || echo 'lkc-rno3vp')
fi

if [ -z "$ENV_ID" ]; then
    print_error "No environment found"
    exit 1
fi

if [ -z "$CLUSTER_ID" ]; then
    print_error "No Kafka cluster found"
    exit 1
fi

print_status "Configuration:"
echo "  Environment ID: $ENV_ID"
echo "  Cluster ID: $CLUSTER_ID"
echo "  Connector Config: $CONNECTOR_CONFIG"
echo ""

# Check if connector config exists
if [ ! -f "$CONNECTOR_CONFIG" ]; then
    print_error "Connector configuration not found: $CONNECTOR_CONFIG"
    exit 1
fi

# Read connector name
if ! command -v jq &> /dev/null; then
    print_error "jq is required but not installed"
    exit 1
fi

CONNECTOR_NAME=$(jq -r '.name' "$CONNECTOR_CONFIG" 2>/dev/null || echo "")

if [ -z "$CONNECTOR_NAME" ] || [ "$CONNECTOR_NAME" = "null" ]; then
    print_error "Invalid connector configuration: missing 'name' field"
    exit 1
fi

# Check for existing connector
print_status "Checking if connector already exists..."
EXISTING_CONNECTOR=$(confluent connect list --output json 2>/dev/null | jq -r ".[] | select(.name == \"$CONNECTOR_NAME\") | .id" | head -1 || echo "")

if [ -n "$EXISTING_CONNECTOR" ]; then
    print_warning "Connector '$CONNECTOR_NAME' already exists (ID: $EXISTING_CONNECTOR)"
    if [ "$FORCE" = true ]; then
        print_status "Deleting existing connector (--force)..."
        confluent connect delete "$EXISTING_CONNECTOR" --force 2>/dev/null || true
        sleep 3
    else
        read -p "Delete and recreate? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deleting existing connector..."
            confluent connect delete "$EXISTING_CONNECTOR" --force 2>/dev/null || true
            sleep 3
        else
            print_status "Aborted."
            exit 0
        fi
    fi
fi

# Prepare connector configuration
print_status "Preparing connector configuration..."

# Check for required environment variables
REQUIRED_VARS=("KAFKA_API_KEY" "KAFKA_API_SECRET" "DB_HOSTNAME" "DB_USERNAME" "DB_PASSWORD" "DB_NAME")

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    print_error "Missing required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
    print_status "Example:"
    echo "  export KAFKA_API_KEY='your-key'"
    echo "  export KAFKA_API_SECRET='your-secret'"
    echo "  export DB_HOSTNAME='your-db-host'"
    echo "  export DB_USERNAME='postgres'"
    echo "  export DB_PASSWORD='password'"
    echo "  export DB_NAME='car_entities'"
    exit 1
fi

# Set defaults
export TABLE_INCLUDE_LIST="${TABLE_INCLUDE_LIST:-public.business_events}"
export TOPIC_PREFIX="${TOPIC_PREFIX:-aurora-cdc}"
export SLOT_NAME="${SLOT_NAME:-business_events_cdc_slot}"
export DB_SERVER_NAME="${DB_SERVER_NAME:-aurora-postgres-cdc}"
export DB_PORT="${DB_PORT:-5432}"

# Create a temporary config file with environment variables substituted
TEMP_CONFIG=$(mktemp)
if command -v envsubst &> /dev/null; then
    envsubst < "$CONNECTOR_CONFIG" > "$TEMP_CONFIG"
else
    # Fallback: simple substitution
    sed -e "s|\${DB_HOSTNAME}|${DB_HOSTNAME}|g" \
        -e "s|\${DB_USERNAME}|${DB_USERNAME}|g" \
        -e "s|\${DB_PASSWORD}|${DB_PASSWORD}|g" \
        -e "s|\${DB_NAME}|${DB_NAME}|g" \
        -e "s|\${DB_PORT}|${DB_PORT}|g" \
        -e "s|\${TABLE_INCLUDE_LIST}|${TABLE_INCLUDE_LIST}|g" \
        -e "s|\${TOPIC_PREFIX}|${TOPIC_PREFIX}|g" \
        -e "s|\${SLOT_NAME}|${SLOT_NAME}|g" \
        -e "s|\${DB_SERVER_NAME}|${DB_SERVER_NAME}|g" \
        "$CONNECTOR_CONFIG" > "$TEMP_CONFIG"
fi

print_success "Configuration prepared"

# Display configuration (without secrets)
echo ""
print_status "Connector Configuration (secrets hidden):"
jq -r '.config | to_entries | map(select(.key | contains("password") or contains("secret")) | .value = "***") | .[] | "\(.key)=\(.value)"' "$TEMP_CONFIG" 2>/dev/null | head -15 || true

echo ""
print_status "Deploying connector..."

# Try to create connector
if confluent connect create --config-file "$TEMP_CONFIG" --kafka-cluster "$CLUSTER_ID" 2>&1; then
    print_success "Connector deployed successfully!"
else
    print_warning "CLI deployment failed. Using alternative method..."
    echo ""
    print_status "Please deploy via Confluent Cloud Console:"
    echo "  1. Visit: https://confluent.cloud/environments/$ENV_ID/connectors"
    echo "  2. Click 'Add connector'"
    echo "  3. Select 'PostgresCdcSource'"
    echo "  4. Use configuration from: $CONNECTOR_CONFIG"
    echo ""
    rm -f "$TEMP_CONFIG"
    exit 1
fi

# Clean up temp files
rm -f "$TEMP_CONFIG"

echo ""
print_status "Checking connector status..."
sleep 5

# Check connector status
CONNECTOR_ID=$(confluent connect list --output json 2>/dev/null | jq -r ".[] | select(.name == \"$CONNECTOR_NAME\") | .id" | head -1 || echo "")

if [ -n "$CONNECTOR_ID" ]; then
    CONNECTOR_STATUS=$(confluent connect describe "$CONNECTOR_ID" --output json 2>/dev/null | jq -r '.status.connector.state' || echo "unknown")
    
    if [ "$CONNECTOR_STATUS" = "RUNNING" ]; then
        print_success "Connector is RUNNING"
    else
        print_warning "Connector status: $CONNECTOR_STATUS"
        echo "  Check logs: confluent connect logs $CONNECTOR_ID"
    fi
else
    print_warning "Could not find connector after deployment"
fi

echo ""
print_header "Deployment Complete!"
echo ""
print_status "Useful commands:"
echo "  List connectors: confluent connect list"
echo "  Check status:    confluent connect describe <connector-id>"
echo "  View logs:       confluent connect logs <connector-id>"
echo ""
