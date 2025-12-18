#!/usr/bin/env bash
# Validate events in Aurora PostgreSQL database
# Wrapper script that calls the Python validation script
#
# Usage:
#   ./cdc-streaming/scripts/validate-database-events.sh <AURORA_ENDPOINT> <DB_NAME> <DB_USER> <DB_PASSWORD> <EVENTS_FILE>
#
# Example:
#   ./cdc-streaming/scripts/validate-database-events.sh cluster.xxxxx.us-east-1.rds.amazonaws.com car_entities postgres password /tmp/events.json
#
# Note: This script is a compatibility wrapper. For direct usage, call validate-database-events.py directly.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

AURORA_ENDPOINT="$1"
DB_NAME="$2"
DB_USER="$3"
DB_PASSWORD="$4"
EVENTS_FILE="$5"

# If password not provided, try to read from .env.aurora file
if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "" ]; then
    # Read password directly from .env.aurora file (more reliable than sourcing)
    # Handle both "export AURORA_PASSWORD=..." and "AURORA_PASSWORD=..." formats
    if [ -f "$PROJECT_ROOT/.env.aurora" ]; then
        RAW_PASSWORD=$(grep -E "^export[[:space:]]+AURORA_PASSWORD=|^AURORA_PASSWORD=|^export[[:space:]]+DB_PASSWORD=|^DB_PASSWORD=|^export[[:space:]]+DATABASE_PASSWORD=|^DATABASE_PASSWORD=" "$PROJECT_ROOT/.env.aurora" 2>/dev/null | head -1 | sed 's/^export[[:space:]]*//' | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs || echo "")
        if [ -n "$RAW_PASSWORD" ]; then
            DB_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\n\r')
        fi
    elif [ -f "$PROJECT_ROOT/cdc-streaming/.env.aurora" ]; then
        RAW_PASSWORD=$(grep -E "^export[[:space:]]+AURORA_PASSWORD=|^AURORA_PASSWORD=|^export[[:space:]]+DB_PASSWORD=|^DB_PASSWORD=|^export[[:space:]]+DATABASE_PASSWORD=|^DATABASE_PASSWORD=" "$PROJECT_ROOT/cdc-streaming/.env.aurora" 2>/dev/null | head -1 | sed 's/^export[[:space:]]*//' | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs || echo "")
        if [ -n "$RAW_PASSWORD" ]; then
            DB_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\n\r')
        fi
    fi
fi

if [ -z "$AURORA_ENDPOINT" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$EVENTS_FILE" ]; then
    fail "Required parameters missing"
    echo "Usage: $0 <AURORA_ENDPOINT> <DB_NAME> <DB_USER> [DB_PASSWORD] <EVENTS_FILE>"
    echo "  DB_PASSWORD is optional if AURORA_PASSWORD is set in .env.aurora"
    exit 1
fi

if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "" ]; then
    fail "Database password required"
    echo "  Set DB_PASSWORD parameter, or"
    echo "  Set AURORA_PASSWORD in .env.aurora file, or"
    echo "  Set AURORA_PASSWORD environment variable"
    exit 1
fi

if [ ! -f "$EVENTS_FILE" ]; then
    fail "Events file not found: $EVENTS_FILE"
    exit 1
fi

# Check if Python script exists
PYTHON_SCRIPT="$SCRIPT_DIR/validate-database-events.py"
if [ ! -f "$PYTHON_SCRIPT" ]; then
    fail "Python validation script not found: $PYTHON_SCRIPT"
    exit 1
fi

# Check if Python has required modules
if ! python3 -c "import psycopg2" 2>/dev/null; then
    fail "Python psycopg2 module not found"
    fail "Install with: pip install psycopg2-binary"
    exit 1
fi

# Call Python script (more robust and efficient than shell-based validation)
info "Using Python validation script"
python3 "$PYTHON_SCRIPT" \
    --aurora-endpoint "$AURORA_ENDPOINT" \
    --aurora-password "$DB_PASSWORD" \
    --db-name "$DB_NAME" \
    --db-user "$DB_USER" \
    --events-file "$EVENTS_FILE"
