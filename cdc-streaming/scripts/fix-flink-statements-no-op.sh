#!/bin/bash
# Fix Flink Statements to Work Without __op Field from Connector
# Adds __op and __table fields in Flink SQL instead

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

DATABASE="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Fix Flink Statements - Add __op in Flink (Not from Connector)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Step 1: Create source table (without __op, __table, __ts_ms)
echo -e "${BLUE}Step 1: Creating source table (without __op fields)...${NC}"

SOURCE_SQL="CREATE TABLE \`raw-business-events\` (
    \`id\` STRING,
    \`event_name\` STRING,
    \`event_type\` STRING,
    \`created_date\` STRING,
    \`saved_date\` STRING,
    \`event_data\` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry',
    'scan.startup.mode' = 'earliest-offset'
);"

if confluent flink statement create source-raw-business-events --database "$DATABASE" --sql "$SOURCE_SQL" 2>&1; then
    echo -e "${GREEN}✓ Source table created${NC}"
else
    echo -e "${YELLOW}⚠ Source table may already exist${NC}"
fi

echo ""
sleep 5

# Step 2: Create sink tables
echo -e "${BLUE}Step 2: Creating sink tables...${NC}"

SINK_TABLES=(
    "filtered-car-created-events"
    "filtered-loan-created-events"
    "filtered-loan-payment-submitted-events"
    "filtered-service-events"
)

for table in "${SINK_TABLES[@]}"; do
    SINK_SQL="CREATE TABLE \`$table\` (
        \`id\` STRING,
        \`event_name\` STRING,
        \`event_type\` STRING,
        \`created_date\` STRING,
        \`saved_date\` STRING,
        \`event_data\` STRING,
        \`__op\` STRING,
        \`__table\` STRING
    ) WITH (
        'connector' = 'confluent',
        'value.format' = 'json-registry'
    );"
    
    echo -e "${CYAN}  Creating: $table${NC}"
    if confluent flink statement create "sink-$table" --database "$DATABASE" --sql "$SINK_SQL" 2>&1 | head -5; then
        echo -e "${GREEN}    ✓ Created${NC}"
    else
        echo -e "${YELLOW}    ⚠ May already exist${NC}"
    fi
    sleep 2
done

echo ""
sleep 5

# Step 3: Create INSERT statements (with __op added in Flink)
echo -e "${BLUE}Step 3: Creating INSERT statements (adding __op in Flink)...${NC}"

# Service events
INSERT_SERVICE_SQL="INSERT INTO \`filtered-service-events\`
SELECT 
    \`id\`,
    \`event_name\`,
    \`event_type\`,
    \`created_date\`,
    \`saved_date\`,
    \`event_data\`,
    CAST('c' AS STRING) AS \`__op\`,
    CAST('business_events' AS STRING) AS \`__table\`
FROM \`raw-business-events\`
WHERE \`event_name\` = 'CarServiceDone';"

echo -e "${CYAN}  Creating: insert-service-events-filter-new${NC}"
if confluent flink statement create insert-service-events-filter-new --database "$DATABASE" --sql "$INSERT_SERVICE_SQL" 2>&1 | head -5; then
    echo -e "${GREEN}    ✓ Created${NC}"
else
    echo -e "${YELLOW}    ⚠ May already exist${NC}"
fi

sleep 2

# Car created
INSERT_CAR_SQL="INSERT INTO \`filtered-car-created-events\`
SELECT 
    \`id\`,
    \`event_name\`,
    \`event_type\`,
    \`created_date\`,
    \`saved_date\`,
    \`event_data\`,
    CAST('c' AS STRING) AS \`__op\`,
    CAST('business_events' AS STRING) AS \`__table\`
FROM \`raw-business-events\`
WHERE \`event_type\` = 'CarCreated';"

echo -e "${CYAN}  Creating: insert-car-created-filter-new${NC}"
if confluent flink statement create insert-car-created-filter-new --database "$DATABASE" --sql "$INSERT_CAR_SQL" 2>&1 | head -5; then
    echo -e "${GREEN}    ✓ Created${NC}"
else
    echo -e "${YELLOW}    ⚠ May already exist${NC}"
fi

sleep 2

# Loan created
INSERT_LOAN_SQL="INSERT INTO \`filtered-loan-created-events\`
SELECT 
    \`id\`,
    \`event_name\`,
    \`event_type\`,
    \`created_date\`,
    \`saved_date\`,
    \`event_data\`,
    CAST('c' AS STRING) AS \`__op\`,
    CAST('business_events' AS STRING) AS \`__table\`
FROM \`raw-business-events\`
WHERE \`event_type\` = 'LoanCreated';"

echo -e "${CYAN}  Creating: insert-loan-created-filter-new${NC}"
if confluent flink statement create insert-loan-created-filter-new --database "$DATABASE" --sql "$INSERT_LOAN_SQL" 2>&1 | head -5; then
    echo -e "${GREEN}    ✓ Created${NC}"
else
    echo -e "${YELLOW}    ⚠ May already exist${NC}"
fi

sleep 2

# Loan payment
INSERT_PAYMENT_SQL="INSERT INTO \`filtered-loan-payment-submitted-events\`
SELECT 
    \`id\`,
    \`event_name\`,
    \`event_type\`,
    \`created_date\`,
    \`saved_date\`,
    \`event_data\`,
    CAST('c' AS STRING) AS \`__op\`,
    CAST('business_events' AS STRING) AS \`__table\`
FROM \`raw-business-events\`
WHERE \`event_type\` = 'LoanPaymentSubmitted';"

echo -e "${CYAN}  Creating: insert-loan-payment-submitted-filter-new${NC}"
if confluent flink statement create insert-loan-payment-submitted-filter-new --database "$DATABASE" --sql "$INSERT_PAYMENT_SQL" 2>&1 | head -5; then
    echo -e "${GREEN}    ✓ Created${NC}"
else
    echo -e "${YELLOW}    ⚠ May already exist${NC}"
fi

echo ""
sleep 10

# Step 4: Verify
echo -e "${BLUE}Step 4: Verifying statements...${NC}"

STATEMENTS=(
    "source-raw-business-events"
    "sink-filtered-service-events"
    "insert-service-events-filter-new"
    "insert-car-created-filter-new"
    "insert-loan-created-filter-new"
    "insert-loan-payment-submitted-filter-new"
)

for stmt in "${STATEMENTS[@]}"; do
    STATUS=$(confluent flink statement list 2>&1 | grep "$stmt" | awk '{print $NF}' | head -1 || echo "unknown")
    if [ "$STATUS" = "RUNNING" ]; then
        echo -e "${GREEN}  ✓ $stmt: RUNNING${NC}"
    elif [ "$STATUS" = "PENDING" ]; then
        echo -e "${YELLOW}  ⏳ $stmt: PENDING${NC}"
    else
        echo -e "${RED}  ✗ $stmt: $STATUS${NC}"
    fi
done

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Fix Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Key Changes:${NC}"
echo "  - Source table: No __op, __table, __ts_ms fields"
echo "  - INSERT statements: Add __op='c' and __table='business_events' in Flink"
echo "  - WHERE clause: Removed 'AND __op = c' condition"
echo ""
echo -e "${CYAN}Next: Send test events and verify pipeline works${NC}"
echo ""
