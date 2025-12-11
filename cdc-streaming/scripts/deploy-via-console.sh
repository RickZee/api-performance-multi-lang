#!/bin/bash
# Complete deployment guide for Business Events CDC Pipeline
# Uses Confluent Cloud Console (recommended method)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ENV_ID="${CONFLUENT_ENV_ID:-env-q9n81p}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"
COMPUTE_POOL_ID="${FLINK_COMPUTE_POOL_ID:-lfcp-2xqo0m}"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Business Events Pipeline Deployment${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "Environment: $ENV_ID"
echo "Kafka Cluster: $CLUSTER_ID"
echo "Compute Pool: $COMPUTE_POOL_ID"
echo ""

# Step 1: Connector Deployment
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 1: Deploy CDC Connector${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Open Confluent Cloud Console:${NC}"
echo "  https://confluent.cloud/environments/$ENV_ID/connectors"
echo ""
echo -e "${CYAN}Instructions:${NC}"
echo "  1. Click 'Add connector'"
echo "  2. Select 'PostgresCdcSource' (managed connector)"
echo "  3. Configure with these key settings:"
echo ""
CONFIG_FILE="$PROJECT_ROOT/cdc-streaming/connectors/postgres-cdc-source-business-events-confluent-cloud.json"
cat "$CONFIG_FILE" | jq -r '.config | to_entries | .[] | "     \(.key): \(.value)"' | head -15
echo ""
echo -e "${CYAN}Important:${NC}"
echo "  - Table include list: public.business_events (ONLY this table)"
echo "  - Output format: JSON"
echo "  - Add RegexRouter transform to route to 'raw-business-events' topic"
echo ""
read -p "Press Enter after connector is deployed and RUNNING..."
echo ""

# Step 2: Verify Connector
echo -e "${BLUE}Verifying connector status...${NC}"
confluent connect cluster list
echo ""

# Step 3: Flink Deployment
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 2: Deploy Flink SQL Statements${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Open Flink SQL Workspace:${NC}"
echo "  https://confluent.cloud/environments/$ENV_ID/flink"
echo ""
echo "  1. Click 'Open SQL Workspace'"
echo "  2. Select compute pool: $COMPUTE_POOL_ID"
echo "  3. Copy statements from:"
echo "     $PROJECT_ROOT/cdc-streaming/flink-jobs/business-events-routing-confluent-cloud.sql"
echo ""
echo -e "${CYAN}Deploy in this order:${NC}"
echo ""
echo -e "${GREEN}1. Source Table (lines 23-37):${NC}"
cat "$PROJECT_ROOT/cdc-streaming/flink-jobs/business-events-routing-confluent-cloud.sql" | sed -n '23,37p'
echo ""
echo -e "${GREEN}2. Sink Tables (one at a time, lines 45-116):${NC}"
echo "   - filtered-car-created-events (lines 45-56)"
echo "   - filtered-loan-created-events (lines 59-72)"
echo "   - filtered-loan-payment-submitted-events (lines 75-88)"
echo "   - filtered-service-events (lines 91-104)"
echo ""
echo -e "${GREEN}3. INSERT Statements (one at a time, lines 125-182):${NC}"
echo "   - Car Created filter (lines 125-137)"
echo "   - Loan Created filter (lines 140-152)"
echo "   - Loan Payment Submitted filter (lines 155-167)"
echo "   - Service Events filter (lines 170-182)"
echo ""
read -p "Press Enter after Flink statements are deployed..."
echo ""

# Step 4: Verify Deployment
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 3: Verify Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${CYAN}Checking Flink statements...${NC}"
confluent flink statement list --compute-pool "$COMPUTE_POOL_ID"
echo ""

echo -e "${CYAN}Checking topics...${NC}"
confluent kafka topic list | grep -E "(raw-business|filtered)" || echo "Filtered topics will be created by Flink when processing starts"
echo ""

# Step 5: Monitor
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 4: Monitor Pipeline${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Run monitoring script:"
echo "  cd $PROJECT_ROOT/cdc-streaming/scripts"
echo "  ./monitor-pipeline.sh"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Send test events (see SEND_SAMPLE_EVENTS.md)"
echo "  2. Monitor pipeline: ./monitor-pipeline.sh"
echo "  3. Verify filtered topics have messages"
echo ""
