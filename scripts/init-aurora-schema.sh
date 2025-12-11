#!/bin/bash
# Initialize Aurora RDS schema
# This script runs the schema from data/schema.sql on Aurora

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEMA_FILE="$REPO_ROOT/data/schema.sql"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Initialize Aurora RDS Schema${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Get Aurora endpoint from Terraform
cd "$REPO_ROOT/terraform"
AURORA_ENDPOINT=$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")
DB_NAME=$(terraform output -raw database_name 2>/dev/null || echo "car_entities")
DB_USER=$(terraform output -raw database_user 2>/dev/null || echo "postgres")
DB_PASSWORD=$(terraform output -raw database_password 2>/dev/null || echo "")

if [ -z "$AURORA_ENDPOINT" ]; then
    echo -e "${RED}✗ Aurora endpoint not found${NC}"
    echo "  Run: cd terraform && terraform output aurora_endpoint"
    exit 1
fi

if [ -z "$DB_PASSWORD" ]; then
    # Try to get from environment variable
    DB_PASSWORD="${DATABASE_PASSWORD:-}"
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${YELLOW}⚠ Database password not found${NC}"
        echo "  Set DATABASE_PASSWORD environment variable or provide password:"
        read -s DB_PASSWORD
        echo ""
    fi
fi

if [ ! -f "$SCHEMA_FILE" ]; then
    echo -e "${RED}✗ Schema file not found: $SCHEMA_FILE${NC}"
    exit 1
fi

echo -e "${CYAN}Aurora Endpoint: $AURORA_ENDPOINT${NC}"
echo -e "${CYAN}Database: $DB_NAME${NC}"
echo -e "${CYAN}User: $DB_USER${NC}"
echo ""

# Check if psql is available
if ! command -v psql &> /dev/null; then
    echo -e "${RED}✗ psql is not installed${NC}"
    echo "  Install PostgreSQL client tools"
    exit 1
fi

echo -e "${BLUE}Running schema migration...${NC}"

# Run schema
export PGPASSWORD="$DB_PASSWORD"
psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Schema initialized successfully${NC}"
else
    echo -e "${RED}✗ Schema initialization failed${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Verifying tables...${NC}"
psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -c "\dt" 2>&1

echo ""
echo -e "${GREEN}Schema initialization complete!${NC}"
