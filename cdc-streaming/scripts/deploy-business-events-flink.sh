#!/bin/bash
# Deploy Flink SQL Statements for Business Events Processing
# Based on archive/cdc-streaming/scripts/deploy-confluent-cloud-statements.sh

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

COMPUTE_POOL_ID="${FLINK_COMPUTE_POOL_ID:-lfcp-2xqo0m}"
KAFKA_CLUSTER_ID="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"
SQL_FILE="$PROJECT_ROOT/cdc-streaming/flink-jobs/business-events-routing-confluent-cloud.sql"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploy Flink SQL to Confluent Cloud${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Compute Pool: $COMPUTE_POOL_ID"
echo "Kafka Cluster: $KAFKA_CLUSTER_ID"
echo "SQL File: $SQL_FILE"
echo ""

# Check if SQL file exists
if [ ! -f "$SQL_FILE" ]; then
    echo -e "${RED}✗ SQL file not found: $SQL_FILE${NC}"
    exit 1
fi

# Function to deploy a statement
deploy_statement() {
    local name=$1
    local sql=$2
    
    echo -e "${BLUE}Deploying: $name${NC}"
    
    # Check if statement already exists
    EXISTING=$(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null | \
        jq -r ".[] | select(.name == \"$name\") | .name" | head -1 || echo "")
    
    if [ -n "$EXISTING" ]; then
        echo -e "${YELLOW}⚠ Statement '$name' already exists. Deleting...${NC}"
        confluent flink statement delete "$name" --force 2>/dev/null || true
        sleep 2
    fi
    
    # Deploy statement
    if confluent flink statement create "$name" \
        --compute-pool "$COMPUTE_POOL_ID" \
        --database "$KAFKA_CLUSTER_ID" \
        --sql "$sql" \
        --wait 2>&1 | tee /tmp/flink-deploy-$name.log; then
        echo -e "${GREEN}✓ $name deployed${NC}"
        return 0
    else
        if grep -q "already exists\|duplicate\|Conflict" /tmp/flink-deploy-$name.log 2>/dev/null; then
            echo -e "${YELLOW}⚠ $name already exists (skipping)${NC}"
            return 0
        else
            echo -e "${RED}✗ $name deployment failed${NC}"
            cat /tmp/flink-deploy-$name.log 2>/dev/null | tail -5
            return 1
        fi
    fi
}

# Extract source table SQL
echo -e "${BLUE}Step 1: Deploying Source Table${NC}"
SOURCE_SQL=$(awk '/CREATE TABLE.*raw-business-events/,/);/{print; if(/);/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$SOURCE_SQL" ]; then
    deploy_statement "source-raw-business-events" "$SOURCE_SQL"
else
    echo -e "${RED}✗ Could not extract source table SQL${NC}"
    exit 1
fi

echo ""

# Extract and deploy sink tables
echo -e "${BLUE}Step 2: Deploying Sink Tables${NC}"

SINK_CAR_SQL=$(awk '/CREATE TABLE.*filtered-car-created-events/,/);/{print; if(/);/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$SINK_CAR_SQL" ]; then
    deploy_statement "sink-filtered-car-created-events" "$SINK_CAR_SQL"
fi

SINK_LOAN_SQL=$(awk '/CREATE TABLE.*filtered-loan-created-events/,/);/{print; if(/);/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$SINK_LOAN_SQL" ]; then
    deploy_statement "sink-filtered-loan-created-events" "$SINK_LOAN_SQL"
fi

SINK_PAYMENT_SQL=$(awk '/CREATE TABLE.*filtered-loan-payment-submitted-events/,/);/{print; if(/);/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$SINK_PAYMENT_SQL" ]; then
    deploy_statement "sink-filtered-loan-payment-submitted-events" "$SINK_PAYMENT_SQL"
fi

SINK_SERVICE_SQL=$(awk '/CREATE TABLE.*filtered-service-events/,/);/{print; if(/);/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$SINK_SERVICE_SQL" ]; then
    deploy_statement "sink-filtered-service-events" "$SINK_SERVICE_SQL"
fi

echo ""

# Extract and deploy INSERT statements
echo -e "${BLUE}Step 3: Deploying INSERT Statements${NC}"

INSERT_CAR_SQL=$(awk '/INSERT INTO.*filtered-car-created-events/,/;/{print; if(/;/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$INSERT_CAR_SQL" ]; then
    deploy_statement "insert-car-created-filter" "$INSERT_CAR_SQL"
fi

INSERT_LOAN_SQL=$(awk '/INSERT INTO.*filtered-loan-created-events/,/;/{print; if(/;/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$INSERT_LOAN_SQL" ]; then
    deploy_statement "insert-loan-created-filter" "$INSERT_LOAN_SQL"
fi

INSERT_PAYMENT_SQL=$(awk '/INSERT INTO.*filtered-loan-payment-submitted-events/,/;/{print; if(/;/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$INSERT_PAYMENT_SQL" ]; then
    deploy_statement "insert-loan-payment-submitted-filter" "$INSERT_PAYMENT_SQL"
fi

INSERT_SERVICE_SQL=$(awk '/INSERT INTO.*filtered-service-events/,/;/{print; if(/;/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$INSERT_SERVICE_SQL" ]; then
    deploy_statement "insert-service-events-filter" "$INSERT_SERVICE_SQL"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Validate deployment
echo -e "${BLUE}Validating Deployment...${NC}"
echo ""
confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" 2>&1 | head -30

echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Check statement status: confluent flink statement list --compute-pool $COMPUTE_POOL_ID"
echo "  2. Verify topics: confluent kafka topic list | grep filtered"
echo "  3. Check topic messages: confluent kafka topic consume filtered-car-created-events --max-messages 10"
echo ""
