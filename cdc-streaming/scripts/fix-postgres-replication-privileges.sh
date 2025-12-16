#!/bin/bash
# Fix PostgreSQL User Replication Privileges for CDC
# Grants REPLICATION privilege to the postgres user for Debezium CDC connector

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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Fix PostgreSQL Replication Privileges${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Get connection details
AURORA_ENDPOINT="${AURORA_ENDPOINT:-producer-api-aurora-cluster.cluster-chjum3h144b6.us-east-1.rds.amazonaws.com}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-car_entities}"

# Try to get password from .env.aurora file
if [ -z "$DB_PASSWORD" ] && [ -f "$PROJECT_ROOT/.env.aurora" ]; then
    DB_PASSWORD=$(grep "^export DB_PASSWORD=" "$PROJECT_ROOT/.env.aurora" 2>/dev/null | cut -d'"' -f2 || echo "")
fi

# Try to get from AURORA_PASSWORD
if [ -z "$DB_PASSWORD" ]; then
    DB_PASSWORD="${AURORA_PASSWORD:-}"
fi

echo -e "${CYAN}Configuration:${NC}"
echo "  Endpoint: $AURORA_ENDPOINT"
echo "  User: $DB_USER"
echo "  Database: $DB_NAME"
echo ""

# Check if psql is available
if ! command -v psql &> /dev/null; then
    echo -e "${YELLOW}⚠ psql not available locally${NC}"
    if command -v docker &> /dev/null && docker info &>/dev/null; then
        echo "  Using Docker to run psql..."
        USE_DOCKER=true
    else
        echo -e "${RED}✗ Docker is not running or psql not available${NC}"
        echo "  Please install psql or start Docker"
        echo "  Install psql: brew install postgresql@16"
        USE_DOCKER=false
        exit 1
    fi
else
    USE_DOCKER=false
fi

# Get password if not set
if [ -z "$DB_PASSWORD" ]; then
    echo -e "${YELLOW}⚠ Database password not set${NC}"
    echo "  Trying to get from terraform.tfvars..."
    if [ -f "$PROJECT_ROOT/terraform/terraform.tfvars" ]; then
        DB_PASSWORD=$(grep -E "^database_password\s*=" "$PROJECT_ROOT/terraform/terraform.tfvars" 2>/dev/null | cut -d'"' -f2 | head -1 || echo "")
    fi
    
    if [ -z "$DB_PASSWORD" ]; then
        read -sp "Enter database password: " DB_PASSWORD
        echo ""
        if [ -z "$DB_PASSWORD" ]; then
            echo -e "${RED}✗ Password is required${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}✓ Password found in terraform.tfvars${NC}"
    fi
fi

# Step 1: Check current privileges
echo -e "${BLUE}Step 1: Checking current user privileges...${NC}"

if [ "$USE_DOCKER" = true ]; then
    CURRENT_PRIVS=$(docker run --rm -i \
        -e PGPASSWORD="$DB_PASSWORD" \
        postgres:15-alpine \
        psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -A \
        -c "SELECT rolreplication FROM pg_roles WHERE rolname = '$DB_USER';" 2>&1 || echo "error")
else
    CURRENT_PRIVS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -A \
        -c "SELECT rolreplication FROM pg_roles WHERE rolname = '$DB_USER';" 2>&1 || echo "error")
fi

if echo "$CURRENT_PRIVS" | grep -q "error\|could not connect\|timeout"; then
    echo -e "${RED}✗ Failed to connect to database${NC}"
    echo "  Error: $CURRENT_PRIVS"
    exit 1
fi

CURRENT_PRIVS=$(echo "$CURRENT_PRIVS" | tr -d ' \n')

if [ "$CURRENT_PRIVS" = "t" ] || [ "$CURRENT_PRIVS" = "true" ]; then
    echo -e "${GREEN}✓ User already has REPLICATION privilege${NC}"
    echo ""
    echo -e "${CYAN}User privileges are correct.${NC}"
    echo "  If connector still fails, check:"
    echo "    1. Connector logs: confluent connect cluster logs <connector-id>"
    echo "    2. Security group allows Confluent Cloud IPs"
    echo "    3. Database is accessible from Confluent Cloud"
    exit 0
else
    echo -e "${YELLOW}⚠ User does NOT have REPLICATION privilege (current: $CURRENT_PRIVS)${NC}"
fi
echo ""

# Step 2: Grant REPLICATION privilege
echo -e "${BLUE}Step 2: Granting REPLICATION privilege...${NC}"

if [ "$USE_DOCKER" = true ]; then
    GRANT_RESULT=$(docker run --rm -i \
        -e PGPASSWORD="$DB_PASSWORD" \
        postgres:15-alpine \
        psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
        -c "ALTER USER $DB_USER WITH REPLICATION;" 2>&1 || echo "error")
else
    GRANT_RESULT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
        -c "ALTER USER $DB_USER WITH REPLICATION;" 2>&1 || echo "error")
fi

if echo "$GRANT_RESULT" | grep -q "error\|could not connect\|timeout\|permission denied"; then
    echo -e "${RED}✗ Failed to grant REPLICATION privilege${NC}"
    echo "  Error: $GRANT_RESULT"
    echo ""
    echo -e "${CYAN}Troubleshooting:${NC}"
    echo "  1. Verify database credentials are correct"
    echo "  2. Check if user has ALTER USER privilege (may need superuser)"
    echo "  3. Try connecting manually: psql -h $AURORA_ENDPOINT -U $DB_USER -d $DB_NAME"
    exit 1
fi

if echo "$GRANT_RESULT" | grep -q "ALTER ROLE"; then
    echo -e "${GREEN}✓ REPLICATION privilege granted successfully${NC}"
else
    echo -e "${YELLOW}⚠ Unexpected result: $GRANT_RESULT${NC}"
fi
echo ""

# Step 3: Verify privileges
echo -e "${BLUE}Step 3: Verifying privileges...${NC}"

if [ "$USE_DOCKER" = true ]; then
    VERIFY_PRIVS=$(docker run --rm -i \
        -e PGPASSWORD="$DB_PASSWORD" \
        postgres:15-alpine \
        psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -A \
        -c "SELECT rolreplication FROM pg_roles WHERE rolname = '$DB_USER';" 2>&1 || echo "error")
else
    VERIFY_PRIVS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -A \
        -c "SELECT rolreplication FROM pg_roles WHERE rolname = '$DB_USER';" 2>&1 || echo "error")
fi

VERIFY_PRIVS=$(echo "$VERIFY_PRIVS" | tr -d ' \n')

if [ "$VERIFY_PRIVS" = "t" ] || [ "$VERIFY_PRIVS" = "true" ]; then
    echo -e "${GREEN}✓ Verified: User has REPLICATION privilege${NC}"
else
    echo -e "${RED}✗ Verification failed: User still does not have REPLICATION privilege${NC}"
    echo "  Result: $VERIFY_PRIVS"
    exit 1
fi
echo ""

# Step 4: Check other required privileges
echo -e "${BLUE}Step 4: Checking additional privileges...${NC}"

if [ "$USE_DOCKER" = true ]; then
    ALL_PRIVS=$(docker run --rm -i \
        -e PGPASSWORD="$DB_PASSWORD" \
        postgres:15-alpine \
        psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -A \
        -c "SELECT rolname, rolreplication, rolsuper FROM pg_roles WHERE rolname = '$DB_USER';" 2>&1 || echo "error")
else
    ALL_PRIVS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t -A \
        -c "SELECT rolname, rolreplication, rolsuper FROM pg_roles WHERE rolname = '$DB_USER';" 2>&1 || echo "error")
fi

echo -e "${CYAN}User privileges:${NC}"
echo "$ALL_PRIVS" | awk -F'|' '{print "  User: " $1; print "  REPLICATION: " $2; print "  SUPERUSER: " $3}'
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Replication Privileges Fixed!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Restart the connector:"
echo "     confluent connect cluster pause $CONNECTOR_ID"
echo "     confluent connect cluster resume $CONNECTOR_ID"
echo ""
echo "  2. Wait a few seconds and check connector status:"
echo "     confluent connect cluster describe $CONNECTOR_ID"
echo ""
echo "  3. If still failing, check connector logs:"
echo "     confluent connect cluster logs $CONNECTOR_ID"
echo ""
echo -e "${CYAN}Note:${NC}"
echo "  The 'pg_hba.conf' error in Aurora PostgreSQL is misleading."
echo "  It typically means the user lacks REPLICATION privilege,"
echo "  which is now fixed. The connector should be able to connect."
echo ""
