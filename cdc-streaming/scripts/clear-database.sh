#!/usr/bin/env bash
# Clear tables in Aurora PostgreSQL database
#
# Usage:
#   ./cdc-streaming/scripts/clear-database.sh [OPTIONS] [TABLE_NAME...]
#
# Examples:
#   ./cdc-streaming/scripts/clear-database.sh --all
#   ./cdc-streaming/scripts/clear-database.sh event_headers business_events
#   ./cdc-streaming/scripts/clear-database.sh --all --confirm
#   ./cdc-streaming/scripts/clear-database.sh --tables event_headers --dry-run
#
# Options:
#   --all              Clear all tables (requires confirmation unless --confirm)
#   --tables TABLE...  Clear specific tables (space-separated)
#   --confirm          Skip confirmation prompt (use with caution)
#   --dry-run          Show what would be cleared without actually clearing
#   --show-counts      Show row counts before and after clearing
#
# Safety:
#   - Always prompts for confirmation unless --confirm is used
#   - Shows row counts before clearing (if --show-counts)
#   - Lists tables that will be cleared
#   - Dry-run mode available for testing

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

# Parse arguments
CLEAR_ALL=false
CONFIRM=false
DRY_RUN=false
SHOW_COUNTS=true
TABLES_TO_CLEAR=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            CLEAR_ALL=true
            shift
            ;;
        --tables)
            shift
            while [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; do
                TABLES_TO_CLEAR+=("$1")
                shift
            done
            ;;
        --confirm)
            CONFIRM=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --show-counts)
            SHOW_COUNTS=true
            shift
            ;;
        --no-counts)
            SHOW_COUNTS=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] [TABLE_NAME...]"
            echo ""
            echo "Options:"
            echo "  --all              Clear all tables (requires confirmation unless --confirm)"
            echo "  --tables TABLE...  Clear specific tables (space-separated)"
            echo "  --confirm          Skip confirmation prompt (use with caution)"
            echo "  --dry-run          Show what would be cleared without actually clearing"
            echo "  --show-counts      Show row counts before and after clearing (default)"
            echo "  --no-counts        Don't show row counts"
            echo ""
            echo "Examples:"
            echo "  $0 --all"
            echo "  $0 event_headers business_events"
            echo "  $0 --all --confirm"
            echo "  $0 --tables event_headers --dry-run"
            exit 0
            ;;
        -*)
            fail "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            TABLES_TO_CLEAR+=("$1")
            shift
            ;;
    esac
done

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

# Determine which tables to clear
FINAL_TABLES=()

if [ "$CLEAR_ALL" = true ]; then
    # Get all table names
    ALL_TABLES=$(PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename" 2>/dev/null | tr -d ' ' || echo "")
    
    if [ -z "$ALL_TABLES" ]; then
        warn "No tables found in database"
        exit 0
    fi
    
    while IFS= read -r table; do
        if [ -n "$table" ]; then
            FINAL_TABLES+=("$table")
        fi
    done <<< "$ALL_TABLES"
elif [ ${#TABLES_TO_CLEAR[@]} -gt 0 ]; then
    # Use specified tables
    FINAL_TABLES=("${TABLES_TO_CLEAR[@]}")
else
    fail "No tables specified"
    info "Use --all to clear all tables, or specify table names"
    info "Example: $0 event_headers business_events"
    exit 1
fi

if [ ${#FINAL_TABLES[@]} -eq 0 ]; then
    warn "No tables to clear"
    exit 0
fi

# Show what will be cleared
section "Database Table Clearing"
echo ""
info "Database: $DB_NAME"
info "Endpoint: $AURORA_ENDPOINT"
info "User: $DB_USER"
[ "$DRY_RUN" = true ] && warn "DRY RUN MODE - No changes will be made"
echo ""

info "Tables to clear (${#FINAL_TABLES[@]}):"
for table in "${FINAL_TABLES[@]}"; do
    echo "  - $table"
done
echo ""

# Show row counts before clearing
if [ "$SHOW_COUNTS" = true ]; then
    info "Row counts before clearing:"
    echo ""
    printf "%-40s %10s\n" "TABLE_NAME" "ROW_COUNT"
    echo "---------------------------------------- ----------"
    
    BEFORE_TOTALS=()
    for table in "${FINAL_TABLES[@]}"; do
        COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM $table" 2>/dev/null | tr -d ' \n' || echo "0")
        printf "%-40s %10s\n" "$table" "$COUNT"
        BEFORE_TOTALS+=("$COUNT")
    done
    echo ""
fi

# Confirmation
if [ "$DRY_RUN" = true ]; then
    warn "DRY RUN: Would clear ${#FINAL_TABLES[@]} table(s)"
    exit 0
fi

if [ "$CONFIRM" != true ]; then
    warn "WARNING: This will DELETE ALL DATA from the specified tables!"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    echo ""
    if [ "$REPLY" != "yes" ]; then
        info "Operation cancelled"
        exit 0
    fi
fi

# Clear tables
section "Clearing Tables"
echo ""

CLEARED_COUNT=0
FAILED_COUNT=0
FAILED_TABLES=()

for table in "${FINAL_TABLES[@]}"; do
    info "Clearing table: $table"
    
    if PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -c "DELETE FROM $table" > /dev/null 2>&1; then
        pass "Cleared: $table"
        ((CLEARED_COUNT++))
    else
        fail "Failed to clear: $table"
        FAILED_TABLES+=("$table")
        ((FAILED_COUNT++))
    fi
done

echo ""

# Show row counts after clearing
if [ "$SHOW_COUNTS" = true ]; then
    info "Row counts after clearing:"
    echo ""
    printf "%-40s %10s\n" "TABLE_NAME" "ROW_COUNT"
    echo "---------------------------------------- ----------"
    
    for i in "${!FINAL_TABLES[@]}"; do
        table="${FINAL_TABLES[$i]}"
        COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM $table" 2>/dev/null | tr -d ' \n' || echo "0")
        BEFORE="${BEFORE_TOTALS[$i]}"
        printf "%-40s %10s (was %s)\n" "$table" "$COUNT" "$BEFORE"
    done
    echo ""
fi

# Summary
section "Summary"
echo ""

if [ $CLEARED_COUNT -eq ${#FINAL_TABLES[@]} ]; then
    pass "Successfully cleared $CLEARED_COUNT table(s)"
else
    warn "Cleared $CLEARED_COUNT of ${#FINAL_TABLES[@]} table(s)"
    if [ $FAILED_COUNT -gt 0 ]; then
        fail "Failed to clear $FAILED_COUNT table(s):"
        for table in "${FAILED_TABLES[@]}"; do
            echo "  - $table"
        done
    fi
fi

