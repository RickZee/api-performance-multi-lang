#!/bin/bash
# Verify Event Headers Replication Slot
# Specifically checks replication slot for event_headers table CDC
# Validates slot exists, is active, and matches connector configuration

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

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Event Headers Replication Slot Check${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Expected slot names based on connector configurations
EXPECTED_SLOT_NAMES=(
    "event_headers_cdc_slot"
    "event_headers_v2_debezium_slot"
    "event_headers_debezium_slot"
)

# Check if database credentials are provided
if [ -z "$DB_HOSTNAME" ] || [ -z "$DB_USERNAME" ] || [ -z "$DB_PASSWORD" ] || [ -z "$DB_NAME" ]; then
    fail "Database credentials not set"
    echo ""
    echo -e "${CYAN}Required environment variables:${NC}"
    echo "  export DB_HOSTNAME='your-db-host'"
    echo "  export DB_USERNAME='postgres'"
    echo "  export DB_PASSWORD='password'"
    echo "  export DB_NAME='car_entities'"
    echo ""
    echo -e "${CYAN}For DSQL databases, also set:${NC}"
    echo "  export DSQL_HOST='your-dsql-host'"
    echo "  export AWS_REGION='us-east-1'"
    echo ""
    echo -e "${CYAN}For Aurora/PostgreSQL via bastion:${NC}"
    echo "  Use: ./scripts/query-dsql.sh \"SELECT * FROM pg_replication_slots;\""
    exit 1
fi

# Check if psql is available
if ! command -v psql &> /dev/null; then
    fail "psql not found"
    echo ""
    echo -e "${CYAN}Install psql:${NC}"
    echo "  macOS: brew install postgresql@16"
    echo "  Linux: apt-get install postgresql-client"
    echo ""
    echo -e "${CYAN}Alternative: Use query script via bastion host${NC}"
    echo "  ./scripts/query-dsql.sh \"SELECT * FROM pg_replication_slots WHERE slot_name LIKE '%event_headers%';\""
    exit 1
fi

export PGPASSWORD="$DB_PASSWORD"

echo -e "${BLUE}[1/3] Checking WAL Level...${NC}"
WAL_LEVEL=$(psql -h "$DB_HOSTNAME" -U "$DB_USERNAME" -d "$DB_NAME" -t -A -c "SHOW wal_level;" 2>/dev/null | tr -d ' \n' || echo "")

if [ "$WAL_LEVEL" = "logical" ]; then
    pass "WAL level is 'logical' (required for CDC)"
else
    fail "WAL level is '$WAL_LEVEL' (expected 'logical')"
    echo ""
    echo -e "${CYAN}To fix:${NC}"
    echo "  1. Update postgresql.conf: wal_level = logical"
    echo "  2. Restart PostgreSQL"
    echo "  3. Or for Aurora: Modify parameter group to set wal_level = logical"
    exit 1
fi
echo ""

echo -e "${BLUE}[2/3] Checking Replication Slots...${NC}"
ALL_SLOTS=$(psql -h "$DB_HOSTNAME" -U "$DB_USERNAME" -d "$DB_NAME" -t -A -c "SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as lag FROM pg_replication_slots WHERE slot_name LIKE '%event_headers%' ORDER BY slot_name;" 2>/dev/null || echo "")

if [ -z "$ALL_SLOTS" ]; then
    warn "No replication slots found for event_headers"
    echo ""
    echo -e "${CYAN}Expected slot names:${NC}"
    for slot in "${EXPECTED_SLOT_NAMES[@]}"; do
        echo "  - $slot"
    done
    echo ""
    echo -e "${CYAN}Possible reasons:${NC}"
    echo "  1. Connector hasn't connected yet (slots are created when connector starts)"
    echo "  2. Connector is using a different slot name"
    echo "  3. Connector configuration issue"
    echo ""
    echo -e "${CYAN}All replication slots:${NC}"
    psql -h "$DB_HOSTNAME" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT slot_name, plugin, active FROM pg_replication_slots;" 2>/dev/null || true
    exit 1
fi

# Parse slot information
SLOT_COUNT=0
FOUND_SLOTS=()
while IFS='|' read -r slot_name active lag; do
    if [ -n "$slot_name" ]; then
        SLOT_COUNT=$((SLOT_COUNT + 1))
        FOUND_SLOTS+=("$slot_name|$active|$lag")
    fi
done <<< "$ALL_SLOTS"

pass "Found $SLOT_COUNT replication slot(s) for event_headers:"
echo ""

for slot_info in "${FOUND_SLOTS[@]}"; do
    IFS='|' read -r slot_name active lag <<< "$slot_info"
    
    echo -e "${CYAN}  Slot: $slot_name${NC}"
    
    # Check if slot name matches expected
    MATCHED=false
    for expected in "${EXPECTED_SLOT_NAMES[@]}"; do
        if [ "$slot_name" = "$expected" ]; then
            pass "    Name matches expected: $expected"
            MATCHED=true
            break
        fi
    done
    
    if [ "$MATCHED" = false ]; then
        warn "    Name doesn't match expected slot names"
        info "    Expected: ${EXPECTED_SLOT_NAMES[*]}"
    fi
    
    # Check if slot is active
    if [ "$active" = "t" ] || [ "$active" = "true" ]; then
        pass "    Status: Active"
    else
        warn "    Status: Inactive (connector may not be running)"
    fi
    
    # Check lag
    if [ -n "$lag" ] && [ "$lag" != "0 bytes" ]; then
        if echo "$lag" | grep -qE "(MB|GB)"; then
            warn "    Lag: $lag (may indicate connector is behind)"
        else
            info "    Lag: $lag"
        fi
    else
        pass "    Lag: Minimal/None"
    fi
    
    echo ""
done

echo -e "${BLUE}[3/3] Checking Replication Slot Configuration...${NC}"
MAX_SLOTS=$(psql -h "$DB_HOSTNAME" -U "$DB_USERNAME" -d "$DB_NAME" -t -A -c "SHOW max_replication_slots;" 2>/dev/null | tr -d ' \n' || echo "")
MAX_SENDERS=$(psql -h "$DB_HOSTNAME" -U "$DB_USERNAME" -d "$DB_NAME" -t -A -c "SHOW max_wal_senders;" 2>/dev/null | tr -d ' \n' || echo "")

if [ -n "$MAX_SLOTS" ]; then
    if [ "$MAX_SLOTS" -ge 4 ]; then
        pass "max_replication_slots: $MAX_SLOTS (sufficient)"
    else
        warn "max_replication_slots: $MAX_SLOTS (may need to increase for multiple connectors)"
    fi
fi

if [ -n "$MAX_SENDERS" ]; then
    if [ "$MAX_SENDERS" -ge 4 ]; then
        pass "max_wal_senders: $MAX_SENDERS (sufficient)"
    else
        warn "max_wal_senders: $MAX_SENDERS (may need to increase for multiple connectors)"
    fi
fi
echo ""

# Summary
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

if [ "$SLOT_COUNT" -gt 0 ]; then
    ACTIVE_COUNT=0
    for slot_info in "${FOUND_SLOTS[@]}"; do
        IFS='|' read -r slot_name active lag <<< "$slot_info"
        if [ "$active" = "t" ] || [ "$active" = "true" ]; then
            ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
        fi
    done
    
    if [ "$ACTIVE_COUNT" -eq "$SLOT_COUNT" ]; then
        echo -e "${GREEN}✓ All replication slots are active${NC}"
        echo -e "${GREEN}✓ Event Headers CDC replication is configured correctly${NC}"
    else
        echo -e "${YELLOW}⚠ $ACTIVE_COUNT/$SLOT_COUNT slots are active${NC}"
        echo -e "${YELLOW}⚠ Some connectors may not be running${NC}"
    fi
else
    echo -e "${RED}✗ No replication slots found for event_headers${NC}"
    echo -e "${YELLOW}⚠ Connector may not have connected yet${NC}"
fi
echo ""

echo -e "${CYAN}Next steps:${NC}"
echo "  - Check connector status: confluent connect list"
echo "  - Verify connector is running: ./cdc-streaming/scripts/quick-verify-event-headers-cdc.sh"
echo "  - Monitor pipeline: ./cdc-streaming/scripts/monitor-pipeline.sh"
echo ""
