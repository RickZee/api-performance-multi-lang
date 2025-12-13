#!/bin/bash
# Setup Event Headers CDC Pipeline
# Configures Confluent Connect for CDC from event_headers table only
# Deploys Flink SQL statements for all 4 event types
# Monitors the entire pipeline

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

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Event Headers CDC Pipeline Setup${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Check if confluent CLI is available
if ! command -v confluent &> /dev/null; then
    echo -e "${RED}✗ Confluent CLI not installed${NC}"
    echo "Install: brew install confluentinc/tap/cli"
    exit 1
fi

# Get environment and cluster info
ENV_ID="${CONFLUENT_ENV_ID:-env-q9n81p}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"
COMPUTE_POOL_ID="${FLINK_COMPUTE_POOL_ID:-lfcp-2xqo0m}"

echo -e "${CYAN}Configuration:${NC}"
echo "  Environment ID: $ENV_ID"
echo "  Kafka Cluster ID: $CLUSTER_ID"
echo "  Flink Compute Pool ID: $COMPUTE_POOL_ID"
echo ""

# Step 1: Create raw-event-headers topic
echo -e "${BLUE}Step 1: Creating raw-event-headers topic...${NC}"
if confluent kafka topic describe raw-event-headers &>/dev/null; then
    echo -e "${YELLOW}⚠ Topic raw-event-headers already exists${NC}"
else
    confluent kafka topic create raw-event-headers \
        --partitions 6 \
        --config retention.ms=604800000
    echo -e "${GREEN}✓ Topic raw-event-headers created${NC}"
fi
echo ""

# Step 2: Delete old connector if it exists
echo -e "${BLUE}Step 2: Checking for existing connectors...${NC}"
OLD_CONNECTOR="postgres-debezium-aurora-confluent-cloud"
if confluent connect cluster describe "$OLD_CONNECTOR" &>/dev/null; then
    echo -e "${YELLOW}⚠ Found existing connector: $OLD_CONNECTOR${NC}"
    read -p "Delete old connector? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        confluent connect cluster delete "$OLD_CONNECTOR" --force
        echo -e "${GREEN}✓ Old connector deleted${NC}"
    fi
fi
echo ""

# Step 3: Deploy new connector for event_headers table
echo -e "${BLUE}Step 3: Deploying CDC connector for event_headers table...${NC}"
CONNECTOR_CONFIG="$PROJECT_ROOT/cdc-streaming/connectors/postgres-debezium-event-headers-confluent-cloud.json"

if [ ! -f "$CONNECTOR_CONFIG" ]; then
    echo -e "${RED}✗ Connector config not found: $CONNECTOR_CONFIG${NC}"
    exit 1
fi

CONNECTOR_NAME=$(jq -r '.name' "$CONNECTOR_CONFIG")

# Check if connector already exists
if confluent connect cluster describe "$CONNECTOR_NAME" &>/dev/null; then
    echo -e "${YELLOW}⚠ Connector $CONNECTOR_NAME already exists${NC}"
    echo "Updating connector configuration..."
    confluent connect cluster update "$CONNECTOR_NAME" --config-file "$CONNECTOR_CONFIG"
    echo -e "${GREEN}✓ Connector updated${NC}"
else
    echo "Creating connector..."
    confluent connect cluster create "$CONNECTOR_NAME" --config-file "$CONNECTOR_CONFIG"
    echo -e "${GREEN}✓ Connector created${NC}"
fi

echo ""
echo -e "${BLUE}Waiting for connector to start...${NC}"
sleep 10

# Check connector status
CONNECTOR_STATUS=$(confluent connect cluster describe "$CONNECTOR_NAME" --output json | jq -r '.status.connector.state' 2>/dev/null || echo "unknown")
echo -e "${CYAN}Connector Status: $CONNECTOR_STATUS${NC}"

if [ "$CONNECTOR_STATUS" != "RUNNING" ]; then
    echo -e "${YELLOW}⚠ Connector is not RUNNING. Check logs:${NC}"
    echo "  confluent connect cluster describe $CONNECTOR_NAME"
    echo "  confluent connect cluster logs $CONNECTOR_NAME"
fi
echo ""

# Step 4: Deploy Flink SQL statements
echo -e "${BLUE}Step 4: Deploying Flink SQL statements...${NC}"
FLINK_SQL_FILE="$PROJECT_ROOT/cdc-streaming/flink-jobs/business-events-routing-confluent-cloud.sql"

if [ ! -f "$FLINK_SQL_FILE" ]; then
    echo -e "${RED}✗ Flink SQL file not found: $FLINK_SQL_FILE${NC}"
    exit 1
fi

# Set compute pool context
confluent flink compute-pool use "$COMPUTE_POOL_ID"

# Deploy source table
echo "Deploying source table..."
confluent flink statement create \
    --statement-name "event-headers-source-table" \
    --statement-file <(head -n 38 "$FLINK_SQL_FILE" | tail -n +18) \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}⚠ Source table may already exist${NC}"

# Deploy sink tables
echo "Deploying sink tables..."
confluent flink statement create \
    --statement-name "event-headers-sink-tables" \
    --statement-file <(sed -n '41,116p' "$FLINK_SQL_FILE") \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}⚠ Sink tables may already exist${NC}"

# Deploy INSERT statements for each filter
echo "Deploying INSERT statements..."

# Car Created filter
echo "  - Car Created filter..."
confluent flink statement create \
    --statement-name "car-created-filter" \
    --statement-file <(sed -n '125,137p' "$FLINK_SQL_FILE") \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}    ⚠ May already exist${NC}"

# Loan Created filter
echo "  - Loan Created filter..."
confluent flink statement create \
    --statement-name "loan-created-filter" \
    --statement-file <(sed -n '140,152p' "$FLINK_SQL_FILE") \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}    ⚠ May already exist${NC}"

# Loan Payment Submitted filter
echo "  - Loan Payment Submitted filter..."
confluent flink statement create \
    --statement-name "loan-payment-submitted-filter" \
    --statement-file <(sed -n '155,167p' "$FLINK_SQL_FILE") \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}    ⚠ May already exist${NC}"

# Service Events filter
echo "  - Service Events filter..."
confluent flink statement create \
    --statement-name "service-events-filter" \
    --statement-file <(sed -n '170,182p' "$FLINK_SQL_FILE") \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}    ⚠ May already exist${NC}"

echo -e "${GREEN}✓ Flink statements deployed${NC}"
echo ""

# Step 5: Monitor pipeline
echo -e "${BLUE}Step 5: Monitoring pipeline...${NC}"
echo ""

# List Flink statements
echo -e "${CYAN}Flink Statements:${NC}"
confluent flink statement list --compute-pool "$COMPUTE_POOL_ID"
echo ""

# Check topics
echo -e "${CYAN}Topics:${NC}"
confluent kafka topic list | grep -E "(raw-event-headers|filtered)" || echo "No filtered topics yet (will be created by Flink)"
echo ""

# Check connector status
echo -e "${CYAN}Connector Status:${NC}"
confluent connect cluster describe "$CONNECTOR_NAME" --output json | jq '{
    name: .name,
    state: .status.connector.state,
    tasks: .status.tasks
}'
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Wait a few minutes for connector to process existing data"
echo "  2. Check topics: confluent kafka topic list | grep -E '(raw-event-headers|filtered)'"
echo "  3. Verify messages: confluent kafka topic consume raw-event-headers --max-messages 5"
echo "  4. Monitor Flink: confluent flink statement list --compute-pool $COMPUTE_POOL_ID"
echo "  5. Check filtered topics: confluent kafka topic consume filtered-car-created-events --max-messages 5"
echo ""
