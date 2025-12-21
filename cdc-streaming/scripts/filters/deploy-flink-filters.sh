#!/bin/bash
# Deploy Flink SQL filters to Confluent Cloud
# This script deploys filters generated from config/filters.json

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
GENERATED_SQL_FILE="$PROJECT_ROOT/cdc-streaming/flink-jobs/generated/business-events-routing-confluent-cloud-generated.sql"
GENERATE_SCRIPT="$PROJECT_ROOT/cdc-streaming/scripts/filters/generate-filters.sh"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploy Flink SQL Filters${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Compute Pool: $COMPUTE_POOL_ID"
echo "Kafka Cluster: $KAFKA_CLUSTER_ID"
echo ""

# Check prerequisites
if ! command -v confluent &> /dev/null; then
    echo -e "${RED}✗ Confluent CLI is not installed${NC}"
    echo -e "${BLUE}ℹ${NC} Install with: brew install confluentinc/tap/cli"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗ jq is required but not installed${NC}"
    echo -e "${BLUE}ℹ${NC} Install with: brew install jq"
    exit 1
fi

# Generate filters if SQL file doesn't exist
if [ ! -f "$GENERATED_SQL_FILE" ]; then
    echo -e "${YELLOW}⚠${NC} Generated SQL file not found. Generating filters..."
    if [ -f "$GENERATE_SCRIPT" ]; then
        bash "$GENERATE_SCRIPT" --flink-only
    else
        echo -e "${RED}✗ Generate script not found: $GENERATE_SCRIPT${NC}"
        exit 1
    fi
fi

if [ ! -f "$GENERATED_SQL_FILE" ]; then
    echo -e "${RED}✗ Generated SQL file not found: $GENERATED_SQL_FILE${NC}"
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

SOURCE_SQL=$(awk '/CREATE TABLE.*raw-event-headers/,/);/{print; if(/);/) exit}' "$GENERATED_SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
if [ -n "$SOURCE_SQL" ]; then
    deploy_statement "source-raw-event-headers" "$SOURCE_SQL"
else
    echo -e "${RED}✗ Could not extract source table SQL${NC}"
    exit 1
fi

echo ""

# Extract and deploy sink tables
echo -e "${BLUE}Step 2: Deploying Sink Tables${NC}"

# Find all sink table definitions
SINK_TABLES=$(grep -n "CREATE TABLE.*filtered-.*-flink" "$GENERATED_SQL_FILE" | cut -d: -f1)

for line_num in $SINK_TABLES; do
    # Extract table name
    TABLE_LINE=$(sed -n "${line_num}p" "$GENERATED_SQL_FILE")
    TABLE_NAME=$(echo "$TABLE_LINE" | sed -n "s/.*CREATE TABLE \`\([^`]*\)\`.*/\1/p")
    
    if [ -n "$TABLE_NAME" ]; then
        # Extract SQL from CREATE TABLE to );
        SINK_SQL=$(awk "NR>=${line_num} && /CREATE TABLE/,/);/{print; if(/);/) exit}" "$GENERATED_SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
        if [ -n "$SINK_SQL" ]; then
            STATEMENT_NAME="sink-${TABLE_NAME}"
            deploy_statement "$STATEMENT_NAME" "$SINK_SQL"
        fi
    fi
done

echo ""

# Extract and deploy INSERT statements
echo -e "${BLUE}Step 3: Deploying INSERT Statements${NC}"

# Find all INSERT statements
INSERT_STATEMENTS=$(grep -n "INSERT INTO.*filtered-.*-flink" "$GENERATED_SQL_FILE" | cut -d: -f1)

for line_num in $INSERT_STATEMENTS; do
    # Extract table name
    INSERT_LINE=$(sed -n "${line_num}p" "$GENERATED_SQL_FILE")
    TABLE_NAME=$(echo "$INSERT_LINE" | sed -n "s/.*INSERT INTO \`\([^`]*\)\`.*/\1/p")
    
    if [ -n "$TABLE_NAME" ]; then
        # Extract SQL from INSERT INTO to ;
        INSERT_SQL=$(awk "NR>=${line_num} && /INSERT INTO/,/;/{print; if(/;/) exit}" "$GENERATED_SQL_FILE" | grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g')
        if [ -n "$INSERT_SQL" ]; then
            STATEMENT_NAME="insert-${TABLE_NAME//-flink/-filter-flink}"
            deploy_statement "$STATEMENT_NAME" "$INSERT_SQL"
        fi
    fi
done

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

