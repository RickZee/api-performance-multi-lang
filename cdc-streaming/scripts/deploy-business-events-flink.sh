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

# Validate SQL file - prevent using deprecated no-op file
if [[ "$SQL_FILE" == *"no-op"* ]]; then
    echo -e "${RED}✗ ERROR: Do not use the no-op SQL file!${NC}"
    echo -e "${RED}✗ It creates topics without -flink suffix${NC}"
    echo -e "${YELLOW}Use: business-events-routing-confluent-cloud.sql instead${NC}"
    exit 1
fi

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

# Check if schema exists in Schema Registry (required for json-registry format)
echo -e "${BLUE}ℹ${NC} Checking if schema exists for raw-event-headers-value..."
if confluent schema-registry subject list 2>/dev/null | grep -q "raw-event-headers-value"; then
    echo -e "${GREEN}✓${NC} Schema exists for raw-event-headers-value"
else
    echo -e "${YELLOW}⚠${NC} Schema not found for raw-event-headers-value"
    echo -e "${BLUE}ℹ${NC} Schema is required for json-registry format. Register it first:"
    echo "   ./cdc-streaming/scripts/register-raw-event-headers-schema.sh"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deployment cancelled. Please register schema first.${NC}"
        exit 1
    fi
    echo -e "${YELLOW}⚠${NC} Proceeding without schema verification - deployment may fail"
fi

SOURCE_SQL=$(awk '/CREATE TABLE.*raw-event-headers/,/);/{print; if(/);/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$SOURCE_SQL" ]; then
    deploy_statement "source-raw-event-headers" "$SOURCE_SQL"
else
    echo -e "${RED}✗ Could not extract source table SQL${NC}"
    exit 1
fi

echo ""

# Extract and deploy sink tables
echo -e "${BLUE}Step 2: Deploying Sink Tables${NC}"

SINK_CAR_SQL=$(awk '/CREATE TABLE.*filtered-car-created-events-flink/,/);/{print; if(/);/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$SINK_CAR_SQL" ]; then
    deploy_statement "sink-filtered-car-created-events-flink" "$SINK_CAR_SQL"
fi

SINK_LOAN_SQL=$(awk '/CREATE TABLE.*filtered-loan-created-events-flink/,/);/{print; if(/);/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$SINK_LOAN_SQL" ]; then
    deploy_statement "sink-filtered-loan-created-events-flink" "$SINK_LOAN_SQL"
fi

SINK_PAYMENT_SQL=$(awk '/CREATE TABLE.*filtered-loan-payment-submitted-events-flink/,/);/{print; if(/);/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$SINK_PAYMENT_SQL" ]; then
    deploy_statement "sink-filtered-loan-payment-submitted-events-flink" "$SINK_PAYMENT_SQL"
fi

SINK_SERVICE_SQL=$(awk '/CREATE TABLE.*filtered-service-events-flink/,/);/{print; if(/);/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$SINK_SERVICE_SQL" ]; then
    deploy_statement "sink-filtered-service-events-flink" "$SINK_SERVICE_SQL"
fi

echo ""

# Extract and deploy INSERT statements
echo -e "${BLUE}Step 3: Deploying INSERT Statements${NC}"

INSERT_CAR_SQL=$(awk '/INSERT INTO.*filtered-car-created-events-flink/,/;/{print; if(/;/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$INSERT_CAR_SQL" ]; then
    deploy_statement "insert-car-created-filter-flink" "$INSERT_CAR_SQL"
fi

INSERT_LOAN_SQL=$(awk '/INSERT INTO.*filtered-loan-created-events-flink/,/;/{print; if(/;/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$INSERT_LOAN_SQL" ]; then
    deploy_statement "insert-loan-created-filter-flink" "$INSERT_LOAN_SQL"
fi

INSERT_PAYMENT_SQL=$(awk '/INSERT INTO.*filtered-loan-payment-submitted-events-flink/,/;/{print; if(/;/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$INSERT_PAYMENT_SQL" ]; then
    deploy_statement "insert-loan-payment-submitted-filter-flink" "$INSERT_PAYMENT_SQL"
fi

INSERT_SERVICE_SQL=$(awk '/INSERT INTO.*filtered-service-events-flink/,/;/{print; if(/;/) exit}' "$SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$INSERT_SERVICE_SQL" ]; then
    deploy_statement "insert-service-events-filter-flink" "$INSERT_SERVICE_SQL"
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
echo "  3. Check topic messages: confluent kafka topic consume filtered-car-created-events-flink --max-messages 10"
echo ""
echo -e "${YELLOW}Note: Topics now use -flink suffix to distinguish from Spring Boot processor${NC}"
echo ""
