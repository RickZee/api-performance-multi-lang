#!/usr/bin/env bash
# Register Schema for raw-event-headers topic
# Uses the same approach as raw-business-events

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

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

section() { 
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

section "Register Schema for raw-event-headers-value"

# Step 1: Set compatibility mode to NONE (allows schema registration)
info "Setting compatibility mode to NONE for raw-event-headers-value..."
if confluent schema-registry subject update raw-event-headers-value --compatibility NONE 2>/dev/null; then
    pass "Compatibility mode set to NONE"
elif confluent schema-registry subject describe raw-event-headers-value --output json 2>/dev/null | jq -e '.compatibility' >/dev/null 2>&1; then
    # Subject exists but update failed, try to get current compatibility
    CURRENT_COMPAT=$(confluent schema-registry subject describe raw-event-headers-value --output json 2>/dev/null | jq -r '.compatibility // "NONE"')
    if [ "$CURRENT_COMPAT" = "NONE" ]; then
        pass "Compatibility mode already set to NONE"
    else
        warn "Could not update compatibility mode (subject may not exist yet, will be set on creation)"
    fi
else
    warn "Subject does not exist yet (will be created with schema registration)"
fi

echo ""

# Create JSON Schema for raw-event-headers-value
# Based on the structure from raw-business-events, but with header_data instead of event_data
SCHEMA_FILE=$(mktemp)
cat > "$SCHEMA_FILE" << 'EOF'
{
  "type": "object",
  "properties": {
    "id": {"type": "string"},
    "event_name": {"type": "string"},
    "event_type": {"type": "string"},
    "created_date": {"type": "string"},
    "saved_date": {"type": "string"},
    "header_data": {"type": "string"},
    "__op": {"type": "string"},
    "__table": {"type": "string"},
    "__ts_ms": {"type": "number"}
  }
}
EOF

echo ""
info "Registering schema for subject: raw-event-headers-value"
info "Schema:"
cat "$SCHEMA_FILE" | jq .

# Register schema using CLI (handles authentication automatically)
if SCHEMA_OUTPUT=$(confluent schema-registry schema create \
  --subject raw-event-headers-value \
  --schema "$SCHEMA_FILE" \
  --type JSON \
  --output json 2>&1); then
    
    SCHEMA_ID=$(echo "$SCHEMA_OUTPUT" | jq -r '.id // empty' 2>/dev/null || echo "$SCHEMA_OUTPUT" | grep -oP 'ID "\K[^"]+' || echo "N/A")
    pass "Schema registered successfully"
    echo "$SCHEMA_OUTPUT" | jq . 2>/dev/null || echo "$SCHEMA_OUTPUT"
    echo ""
    info "Schema ID: $SCHEMA_ID"
    
    # Ensure compatibility mode is set to NONE after schema creation
    if confluent schema-registry subject update raw-event-headers-value --compatibility NONE 2>/dev/null; then
        pass "Compatibility mode set to NONE"
    fi
elif echo "$SCHEMA_OUTPUT" | grep -qi "already exists\|already registered\|SubjectAlreadyExistsException"; then
    warn "Schema already exists for raw-event-headers-value"
    pass "Schema is registered"
    
    # Verify compatibility mode
    if confluent schema-registry subject update raw-event-headers-value --compatibility NONE 2>/dev/null; then
        pass "Compatibility mode set to NONE"
    fi
else
    fail "Failed to register schema"
    echo "Error: $SCHEMA_OUTPUT"
    rm -f "$SCHEMA_FILE"
    exit 1
fi

# Clean up temp file
rm -f "$SCHEMA_FILE"

echo ""
section "Verification"

# Verify schema exists
if confluent schema-registry subject list 2>/dev/null | grep -q "raw-event-headers-value"; then
    pass "Schema subject exists: raw-event-headers-value"
    
    # Get schema details
    SCHEMA_INFO=$(confluent schema-registry subject describe raw-event-headers-value --output json 2>/dev/null)
    if [ -n "$SCHEMA_INFO" ]; then
        info "Schema version: $(echo "$SCHEMA_INFO" | jq -r '.version // "N/A"')"
        info "Compatibility: $(echo "$SCHEMA_INFO" | jq -r '.compatibility // "N/A"')"
    fi
else
    warn "Could not verify schema (may need to wait a moment)"
fi

echo ""
section "Next Steps"

info "1. Redeploy source table:"
echo "   confluent flink statement delete source-raw-event-headers --force"
echo "   ./scripts/deploy-business-events-flink.sh"
echo ""
info "2. Verify INSERT statements are RUNNING (confirms table is accessible):"
echo "   confluent flink statement list --compute-pool <compute-pool-id> | grep insert-.*-flink"
echo ""
info "Note: Source table may show FAILED status, but this is expected."
info "If INSERT statements are RUNNING, the table is working correctly."
