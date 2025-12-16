#!/bin/bash
# Quick Verification Script for Event Headers CDC
# Provides focused verification that event_headers CDC is working correctly
# Checks: replication slot, connector, topics, and Flink statements

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

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

# Configuration
ENV_ID="${CONFLUENT_ENV_ID:-env-q9n81p}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"
COMPUTE_POOL_ID="${FLINK_COMPUTE_POOL_ID:-lfcp-2xqo0m}"
CONNECTOR_NAME="${CONNECTOR_NAME:-postgres-cdc-source-v2-debezium-event-headers}"
RAW_TOPIC="${RAW_TOPIC:-raw-event-headers}"

# Expected replication slot names (connector creates these)
EXPECTED_SLOTS=(
    "event_headers_cdc_slot"
    "event_headers_v2_debezium_slot"
    "event_headers_debezium_slot"
)

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Quick Verification: Event Headers CDC${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

ISSUES_FOUND=0

# 1. Check Connector Status
echo -e "${BLUE}[1/5] Checking CDC Connector...${NC}"
if confluent connect list --output json 2>/dev/null | jq -r ".[] | select(.name == \"$CONNECTOR_NAME\") | .id" | head -1 | read -r CONNECTOR_ID; then
    if [ -n "$CONNECTOR_ID" ]; then
        CONNECTOR_STATE=$(confluent connect describe "$CONNECTOR_ID" --output json 2>/dev/null | jq -r '.status.connector.state' || echo "unknown")
        
        if [ "$CONNECTOR_STATE" = "RUNNING" ]; then
            pass "Connector '$CONNECTOR_NAME' is RUNNING"
            
            # Check connector configuration
            CONNECTOR_CONFIG=$(confluent connect describe "$CONNECTOR_ID" --output json 2>/dev/null | jq -r '.config."table.include.list" // .config."dsql.tables"' || echo "")
            if echo "$CONNECTOR_CONFIG" | grep -q "event_headers"; then
                pass "Connector configured for event_headers table"
            else
                warn "Connector table config: $CONNECTOR_CONFIG (expected: event_headers)"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
        else
            fail "Connector '$CONNECTOR_NAME' is $CONNECTOR_STATE"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    else
        fail "Connector '$CONNECTOR_NAME' not found"
        info "Available connectors:"
        confluent connect list --output json 2>/dev/null | jq -r '.[].name' | head -5 | while read name; do
            info "  - $name"
        done
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    fail "Cannot list connectors (check Confluent CLI login)"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# 2. Check Kafka Topics
echo -e "${BLUE}[2/5] Checking Kafka Topics...${NC}"
if confluent kafka topic describe "$RAW_TOPIC" &>/dev/null; then
    MSG_COUNT=$(confluent kafka topic describe "$RAW_TOPIC" --output json 2>/dev/null | jq '[.partitions[].offset] | add' 2>/dev/null || echo "0")
    pass "Topic '$RAW_TOPIC' exists (messages: $MSG_COUNT)"
    
    if [ "$MSG_COUNT" = "0" ]; then
        warn "Topic has no messages (may be normal if no events sent yet)"
    fi
else
    fail "Topic '$RAW_TOPIC' does not exist"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check filtered topics
FILTERED_TOPICS=("filtered-car-created-events" "filtered-loan-created-events" "filtered-loan-payment-submitted-events" "filtered-service-events")
FILTERED_COUNT=0
for topic in "${FILTERED_TOPICS[@]}"; do
    if confluent kafka topic describe "$topic" &>/dev/null; then
        FILTERED_COUNT=$((FILTERED_COUNT + 1))
    fi
done

if [ "$FILTERED_COUNT" -gt 0 ]; then
    pass "Filtered topics exist: $FILTERED_COUNT/${#FILTERED_TOPICS[@]}"
else
    warn "No filtered topics found yet (will be created by Flink when processing events)"
fi
echo ""

# 3. Check Flink Statements
echo -e "${BLUE}[3/5] Checking Flink SQL Statements...${NC}"
STATEMENTS=$(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null | jq -r '.[] | "\(.name)|\(.status)"' || echo "")

if [ -z "$STATEMENTS" ]; then
    fail "No Flink statements found"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    RUNNING_COUNT=0
    TOTAL_COUNT=0
    echo "$STATEMENTS" | while IFS='|' read -r name status; do
        TOTAL_COUNT=$((TOTAL_COUNT + 1))
        if [ "$status" = "RUNNING" ]; then
            RUNNING_COUNT=$((RUNNING_COUNT + 1))
            pass "Statement '$name': $status"
        else
            warn "Statement '$name': $status"
        fi
    done
    
    # Note: Variables in while loop don't persist, so we check differently
    RUNNING_STATEMENTS=$(echo "$STATEMENTS" | grep -c "RUNNING" || echo "0")
    if [ "$RUNNING_STATEMENTS" -gt 0 ]; then
        pass "Flink statements running: $RUNNING_STATEMENTS"
    else
        warn "No Flink statements are RUNNING"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
fi
echo ""

# 4. Check Database Replication Slot (if database accessible)
echo -e "${BLUE}[4/5] Checking Database Replication Slot...${NC}"
if [ -n "$DB_HOSTNAME" ] && [ -n "$DB_USERNAME" ] && [ -n "$DB_PASSWORD" ] && [ -n "$DB_NAME" ]; then
    # Try to check replication slots via psql if available
    if command -v psql &> /dev/null; then
        export PGPASSWORD="$DB_PASSWORD"
        SLOTS=$(psql -h "$DB_HOSTNAME" -U "$DB_USERNAME" -d "$DB_NAME" -t -A -c "SELECT slot_name FROM pg_replication_slots WHERE slot_name LIKE '%event_headers%';" 2>/dev/null || echo "")
        
        if [ -n "$SLOTS" ]; then
            SLOT_COUNT=$(echo "$SLOTS" | grep -c . || echo "0")
            pass "Found $SLOT_COUNT replication slot(s) for event_headers"
            echo "$SLOTS" | while read slot; do
                if [ -n "$slot" ]; then
                    info "  - $slot"
                fi
            done
        else
            warn "No replication slots found for event_headers (connector may not have connected yet)"
        fi
    else
        info "psql not available - skipping replication slot check"
        info "To check manually: SELECT * FROM pg_replication_slots WHERE slot_name LIKE '%event_headers%';"
    fi
else
    info "Database credentials not set - skipping replication slot check"
    info "Set DB_HOSTNAME, DB_USERNAME, DB_PASSWORD, DB_NAME to enable this check"
fi
echo ""

# 5. Check Message Flow
echo -e "${BLUE}[5/5] Checking Message Flow...${NC}"
if confluent kafka topic describe "$RAW_TOPIC" &>/dev/null; then
    LATEST_MSG=$(confluent kafka topic consume "$RAW_TOPIC" --max-messages 1 --timeout 5 2>&1 | head -10 || echo "")
    
    if [ -n "$LATEST_MSG" ] && ! echo "$LATEST_MSG" | grep -qE "(No messages|timeout|error)"; then
        pass "Messages are flowing in $RAW_TOPIC"
        
        # Try to parse message to verify structure
        if echo "$LATEST_MSG" | jq -e '.event_type' &>/dev/null || echo "$LATEST_MSG" | jq -e '.__table' &>/dev/null; then
            pass "Message structure looks valid"
        fi
    else
        warn "No recent messages in $RAW_TOPIC"
        info "This is normal if no events have been sent recently"
    fi
else
    fail "Cannot check message flow - topic does not exist"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# Summary
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Verification Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

if [ "$ISSUES_FOUND" -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Event Headers CDC is operational.${NC}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  - Monitor pipeline: ./cdc-streaming/scripts/monitor-pipeline.sh"
    echo "  - Check connector logs: confluent connect describe $CONNECTOR_ID"
    echo "  - View messages: confluent kafka topic consume $RAW_TOPIC --max-messages 5"
else
    echo -e "${YELLOW}⚠ Found $ISSUES_FOUND issue(s)${NC}"
    echo ""
    echo -e "${CYAN}Troubleshooting:${NC}"
    echo "  - Check connector status: confluent connect list"
    echo "  - View connector logs: confluent connect describe <connector-id>"
    echo "  - Verify database replication: SELECT * FROM pg_replication_slots;"
    echo "  - Check Flink statements: confluent flink statement list --compute-pool $COMPUTE_POOL_ID"
    echo "  - Run full monitor: ./cdc-streaming/scripts/monitor-pipeline.sh"
fi
echo ""
