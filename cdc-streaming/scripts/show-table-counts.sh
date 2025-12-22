#!/usr/bin/env bash
# Show row counts for all tables in Aurora PostgreSQL database
#
# Usage:
#   ./cdc-streaming/scripts/show-table-counts.sh [TABLE_NAME]
#
# Examples:
#   ./cdc-streaming/scripts/show-table-counts.sh
#   ./cdc-streaming/scripts/show-table-counts.sh event_headers
#
# If TABLE_NAME is provided, shows count for that table only.
# Otherwise, shows counts for all tables.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Source environment files if they exist
if [ -f "$PROJECT_ROOT/.env.aurora" ]; then
    source "$PROJECT_ROOT/.env.aurora"
fi

if [ -f "$PROJECT_ROOT/cdc-streaming/.env" ]; then
    source "$PROJECT_ROOT/cdc-streaming/.env"
fi

if [ -f "$PROJECT_ROOT/cdc-streaming/.env.aurora" ]; then
    source "$PROJECT_ROOT/cdc-streaming/.env.aurora"
fi

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
section() { echo -e "${CYAN}========================================${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}========================================${NC}"; }

# Get Aurora details from Terraform
cd "$PROJECT_ROOT/terraform"
AURORA_ENDPOINT=$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")
DB_NAME=$(terraform output -raw database_name 2>/dev/null || echo "car_entities")
DB_USER=$(terraform output -raw database_user 2>/dev/null || echo "postgres")
TERRAFORM_DB_PASSWORD=$(terraform output -raw database_password 2>/dev/null || echo "")
cd "$PROJECT_ROOT"

if [ -z "$AURORA_ENDPOINT" ]; then
    fail "Aurora endpoint not found in Terraform outputs"
    info "Run: cd terraform && terraform output aurora_endpoint"
    exit 1
fi

# Get password (same logic as test-e2e-pipeline.sh)
DB_PASSWORD=""
if [ -f "$PROJECT_ROOT/terraform/terraform.tfvars" ]; then
    RAW_PASSWORD=$(grep database_password "$PROJECT_ROOT/terraform/terraform.tfvars" | cut -d'"' -f2 || echo "")
    DB_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\n\r' | head -c 32)
fi

# Fallback to .env.aurora file if terraform.tfvars not found
if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "" ]; then
    if [ -f "$PROJECT_ROOT/.env.aurora" ]; then
        RAW_PASSWORD=$(grep -E "^export[[:space:]]+AURORA_PASSWORD=|^AURORA_PASSWORD=|^export[[:space:]]+DB_PASSWORD=|^DB_PASSWORD=|^export[[:space:]]+DATABASE_PASSWORD=|^DATABASE_PASSWORD=" "$PROJECT_ROOT/.env.aurora" 2>/dev/null | head -1 | sed 's/^export[[:space:]]*//' | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs || echo "")
        if [ -n "$RAW_PASSWORD" ]; then
            DB_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\n\r' | head -c 32)
        fi
    elif [ -f "$PROJECT_ROOT/cdc-streaming/.env.aurora" ]; then
        RAW_PASSWORD=$(grep -E "^export[[:space:]]+AURORA_PASSWORD=|^AURORA_PASSWORD=|^export[[:space:]]+DB_PASSWORD=|^DB_PASSWORD=|^export[[:space:]]+DATABASE_PASSWORD=|^DATABASE_PASSWORD=" "$PROJECT_ROOT/cdc-streaming/.env.aurora" 2>/dev/null | head -1 | sed 's/^export[[:space:]]*//' | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs || echo "")
        if [ -n "$RAW_PASSWORD" ]; then
            DB_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\n\r' | head -c 32)
        fi
    fi
fi

# Final fallback to Terraform output or environment variables
if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "" ]; then
    if [ -n "$TERRAFORM_DB_PASSWORD" ] && [ "$TERRAFORM_DB_PASSWORD" != "" ]; then
        DB_PASSWORD=$(echo "$TERRAFORM_DB_PASSWORD" | tr -d '\n\r' | head -c 32)
    elif [ -n "${DATABASE_PASSWORD:-}" ]; then
        DB_PASSWORD=$(echo "$DATABASE_PASSWORD" | tr -d '\n\r' | head -c 32)
    elif [ -n "${AURORA_PASSWORD:-}" ]; then
        DB_PASSWORD=$(echo "$AURORA_PASSWORD" | tr -d '\n\r' | head -c 32)
    else
        fail "Database password not found"
        info "Expected in terraform/terraform.tfvars as database_password"
        info "Or set in .env.aurora file as AURORA_PASSWORD, DB_PASSWORD, or DATABASE_PASSWORD"
        info "Or set DATABASE_PASSWORD, DB_PASSWORD, or AURORA_PASSWORD environment variable"
        exit 1
    fi
fi

# Verify password is set
if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "" ]; then
    fail "Database password is empty after checking all sources"
    exit 1
fi

# Optional table name argument
TABLE_NAME="${1:-}"

section "Database Table Row Counts"
echo ""
info "Database: $DB_NAME"
info "Endpoint: $AURORA_ENDPOINT"
info "User: $DB_USER"
echo ""

# Check if psql is available
if ! command -v psql &> /dev/null; then
    fail "psql not found"
    info "Install with: brew install postgresql (macOS) or apt-get install postgresql-client (Linux)"
    exit 1
fi

# Test connection
if ! PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    fail "Failed to connect to database"
    info "Verify:"
    info "  - Aurora endpoint is correct: $AURORA_ENDPOINT"
    info "  - Database credentials are correct"
    info "  - Network connectivity to Aurora"
    exit 1
fi

pass "Database connection successful"
echo ""

# Show counts
if [ -n "$TABLE_NAME" ]; then
    # Single table
    info "Showing row count for table: $TABLE_NAME"
    echo ""
    
    COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM $TABLE_NAME" 2>/dev/null | tr -d ' \n' || echo "ERROR")
    
    if [ "$COUNT" = "ERROR" ]; then
        fail "Table '$TABLE_NAME' not found or error querying"
        exit 1
    fi
    
    printf "%-40s %10s\n" "$TABLE_NAME" "$COUNT"
else
    # All tables
    info "Showing row counts for all tables"
    echo ""
    
    # Get all table names
    TABLES=$(PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename" 2>/dev/null | tr -d ' ' || echo "")
    
    if [ -z "$TABLES" ]; then
        warn "No tables found in database"
        exit 0
    fi
    
    # Print header
    printf "%-40s %10s\n" "TABLE_NAME" "ROW_COUNT"
    echo "---------------------------------------- ----------"
    
    TOTAL_ROWS=0
    
    # Count rows for each table
    while IFS= read -r table; do
        if [ -n "$table" ]; then
            COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM $table" 2>/dev/null | tr -d ' \n' || echo "0")
            printf "%-40s %10s\n" "$table" "$COUNT"
            TOTAL_ROWS=$((TOTAL_ROWS + COUNT))
        fi
    done <<< "$TABLES"
    
    echo "---------------------------------------- ----------"
    printf "%-40s %10s\n" "TOTAL" "$TOTAL_ROWS"
fi

echo ""
pass "Query completed"

