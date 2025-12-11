#!/bin/bash
# Deploy Flink SQL Statements for Business Events Processing
# Deploys statements to process all 4 event types

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

ENV_ID="${CONFLUENT_ENV_ID:-env-q9n81p}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"
COMPUTE_POOL_ID="${FLINK_COMPUTE_POOL_ID:-lfcp-2xqo0m}"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Deploy Flink SQL Statements${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "Environment: $ENV_ID"
echo "Kafka Cluster: $CLUSTER_ID"
echo "Compute Pool: $COMPUTE_POOL_ID"
echo ""

# Set context
confluent environment use "$ENV_ID"
confluent kafka cluster use "$CLUSTER_ID"
confluent flink compute-pool use "$COMPUTE_POOL_ID"

FLINK_SQL_FILE="$PROJECT_ROOT/cdc-streaming/flink-jobs/business-events-routing-confluent-cloud.sql"

if [ ! -f "$FLINK_SQL_FILE" ]; then
    echo -e "${RED}✗ Flink SQL file not found: $FLINK_SQL_FILE${NC}"
    exit 1
fi

echo -e "${YELLOW}⚠ IMPORTANT: Confluent Cloud Flink requires deploying statements via Web Console${NC}"
echo "The CLI has limitations for complex multi-statement deployments."
echo ""
echo -e "${CYAN}Recommended Approach:${NC}"
echo "1. Go to: https://confluent.cloud/environments/$ENV_ID/flink"
echo "2. Click 'Open SQL Workspace'"
echo "3. Select compute pool: $COMPUTE_POOL_ID"
echo "4. Copy and paste each statement from: $FLINK_SQL_FILE"
echo ""
echo "The SQL file contains:"
echo "  - Source table definition (raw-business-events)"
echo "  - 4 sink table definitions (one per event type)"
echo "  - 4 INSERT statements (one per filter)"
echo ""
echo -e "${CYAN}Alternative: Deploy via CLI (one statement at a time)${NC}"
echo ""
read -p "Continue with CLI deployment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Exiting. Use Web Console for deployment."
    exit 0
fi

# Extract and deploy source table
echo ""
echo -e "${BLUE}Deploying source table...${NC}"
SOURCE_SQL=$(sed -n '18,38p' "$FLINK_SQL_FILE")
echo "$SOURCE_SQL" > /tmp/source_table.sql

confluent flink statement create \
    --statement-name "business-events-source" \
    --statement-file /tmp/source_table.sql \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}⚠ Source table may already exist${NC}"

# Extract and deploy sink tables (one at a time)
echo ""
echo -e "${BLUE}Deploying sink tables...${NC}"

# Car Created sink
echo "  - Car Created sink..."
CAR_SINK_SQL=$(sed -n '43,56p' "$FLINK_SQL_FILE")
echo "$CAR_SINK_SQL" > /tmp/car_sink.sql
confluent flink statement create \
    --statement-name "car-created-sink" \
    --statement-file /tmp/car_sink.sql \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}    ⚠ May already exist${NC}"

# Loan Created sink
echo "  - Loan Created sink..."
LOAN_SINK_SQL=$(sed -n '59,72p' "$FLINK_SQL_FILE")
echo "$LOAN_SINK_SQL" > /tmp/loan_sink.sql
confluent flink statement create \
    --statement-name "loan-created-sink" \
    --statement-file /tmp/loan_sink.sql \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}    ⚠ May already exist${NC}"

# Loan Payment Submitted sink
echo "  - Loan Payment Submitted sink..."
PAYMENT_SINK_SQL=$(sed -n '75,88p' "$FLINK_SQL_FILE")
echo "$PAYMENT_SINK_SQL" > /tmp/payment_sink.sql
confluent flink statement create \
    --statement-name "loan-payment-submitted-sink" \
    --statement-file /tmp/payment_sink.sql \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}    ⚠ May already exist${NC}"

# Service Events sink
echo "  - Service Events sink..."
SERVICE_SINK_SQL=$(sed -n '91,104p' "$FLINK_SQL_FILE")
echo "$SERVICE_SINK_SQL" > /tmp/service_sink.sql
confluent flink statement create \
    --statement-name "service-events-sink" \
    --statement-file /tmp/service_sink.sql \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}    ⚠ May already exist${NC}"

# Deploy INSERT statements
echo ""
echo -e "${BLUE}Deploying INSERT statements...${NC}"

# Car Created filter
echo "  - Car Created filter..."
CAR_INSERT_SQL=$(sed -n '125,137p' "$FLINK_SQL_FILE")
echo "$CAR_INSERT_SQL" > /tmp/car_insert.sql
confluent flink statement create \
    --statement-name "car-created-filter" \
    --statement-file /tmp/car_insert.sql \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}    ⚠ May already exist${NC}"

# Loan Created filter
echo "  - Loan Created filter..."
LOAN_INSERT_SQL=$(sed -n '140,152p' "$FLINK_SQL_FILE")
echo "$LOAN_INSERT_SQL" > /tmp/loan_insert.sql
confluent flink statement create \
    --statement-name "loan-created-filter" \
    --statement-file /tmp/loan_insert.sql \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}    ⚠ May already exist${NC}"

# Loan Payment Submitted filter
echo "  - Loan Payment Submitted filter..."
PAYMENT_INSERT_SQL=$(sed -n '155,167p' "$FLINK_SQL_FILE")
echo "$PAYMENT_INSERT_SQL" > /tmp/payment_insert.sql
confluent flink statement create \
    --statement-name "loan-payment-submitted-filter" \
    --statement-file /tmp/payment_insert.sql \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}    ⚠ May already exist${NC}"

# Service Events filter
echo "  - Service Events filter..."
SERVICE_INSERT_SQL=$(sed -n '170,182p' "$FLINK_SQL_FILE")
echo "$SERVICE_INSERT_SQL" > /tmp/service_insert.sql
confluent flink statement create \
    --statement-name "service-events-filter" \
    --statement-file /tmp/service_insert.sql \
    --database "$CLUSTER_ID" \
    --wait || echo -e "${YELLOW}    ⚠ May already exist${NC}"

# Cleanup temp files
rm -f /tmp/*_table.sql /tmp/*_sink.sql /tmp/*_insert.sql

echo ""
echo -e "${GREEN}✓ Deployment complete!${NC}"
echo ""
echo -e "${CYAN}Verify deployment:${NC}"
echo "  confluent flink statement list --compute-pool $COMPUTE_POOL_ID"
echo ""
