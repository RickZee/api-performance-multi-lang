#!/bin/bash
# Troubleshoot CDC Connector Issues
# Diagnoses and fixes common CDC connector problems

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
echo -e "${CYAN}CDC Connector Troubleshooting${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Issue 1: Check PostgreSQL Configuration
echo -e "${BLUE}[1/5] Checking PostgreSQL Configuration...${NC}"

if docker ps 2>/dev/null | grep -q "cdc-postgres-k6"; then
    pass "PostgreSQL container is running"
    
    # Check WAL level
    WAL_LEVEL=$(docker exec cdc-postgres-k6 psql -U postgres -d car_entities -t -A -c "SHOW wal_level;" 2>&1 | grep -v "psql:" | tr -d ' \n')
    if [ "$WAL_LEVEL" = "logical" ]; then
        pass "Logical replication enabled (wal_level=logical)"
    else
        fail "Logical replication not enabled (wal_level=$WAL_LEVEL)"
        warn "Fix: Update postgresql.conf or docker-compose.yml to set wal_level=logical"
    fi
    
    # Check replication slots
    SLOT_COUNT=$(docker exec cdc-postgres-k6 psql -U postgres -d car_entities -t -A -c "SELECT COUNT(*) FROM pg_replication_slots;" 2>&1 | grep -v "psql:" | tr -d ' \n')
    if [ "$SLOT_COUNT" = "0" ]; then
        warn "No replication slots found (connector hasn't connected yet)"
    else
        pass "Replication slots exist: $SLOT_COUNT"
    fi
    
    # Check if PostgreSQL is accessible
    PG_HOST=$(docker inspect cdc-postgres-k6 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "")
    PG_PORT="5432"
    
    info "PostgreSQL is running in Docker (internal IP: $PG_HOST)"
    warn "PostgreSQL is NOT accessible from Confluent Cloud (local Docker)"
    
else
    fail "PostgreSQL container not running"
    echo "  Start with: docker-compose -f docker-compose.k6-confluent.yml up -d postgres"
fi

# Issue 2: Check Confluent Connect Cluster
echo ""
echo -e "${BLUE}[2/5] Checking Confluent Connect Cluster...${NC}"

CONNECT_CLUSTERS=$(confluent connect cluster list --output json 2>/dev/null | jq 'length' 2>/dev/null || echo "0")

if [ "$CONNECT_CLUSTERS" = "0" ]; then
    fail "No Connect clusters found"
    warn "Confluent managed connectors may not require a Connect cluster"
    info "Trying alternative connector deployment method..."
else
    pass "Connect cluster(s) found: $CONNECT_CLUSTERS"
fi

# Issue 3: Check for Existing Connectors
echo ""
echo -e "${BLUE}[3/5] Checking for Existing Connectors...${NC}"

# Try different ways to list connectors
CONNECTOR_FOUND=false

# Method 1: Try connector list (if available)
if confluent connector list &> /dev/null 2>&1; then
    CONNECTORS=$(confluent connector list --output json 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo "")
    if [ -n "$CONNECTORS" ]; then
        pass "Found connectors via connector list"
        echo "$CONNECTORS" | while read name; do
            info "  - $name"
        done
        CONNECTOR_FOUND=true
    fi
fi

# Method 2: Check via kafka topic (connectors create topics)
if [ "$CONNECTOR_FOUND" = false ]; then
    TOPICS=$(confluent kafka topic list --output json 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo "")
    if echo "$TOPICS" | grep -q "cdc-raw\|postgres-cdc"; then
        warn "Found CDC-related topics (connector may exist but not be listed)"
        echo "$TOPICS" | grep -E "cdc-raw|postgres-cdc" | head -5 | while read topic; do
            info "  Topic: $topic"
        done
    fi
fi

if [ "$CONNECTOR_FOUND" = false ]; then
    warn "No CDC connector found"
    info "Connector needs to be deployed"
fi

# Issue 4: Check PostgreSQL Accessibility
echo ""
echo -e "${BLUE}[4/5] Checking PostgreSQL Accessibility...${NC}"

# Check if ngrok or similar tunnel is running
if command -v ngrok &> /dev/null; then
    NGROK_PID=$(pgrep -f "ngrok.*tcp.*5432" || echo "")
    if [ -n "$NGROK_PID" ]; then
        pass "ngrok tunnel detected (PID: $NGROK_PID)"
        NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | jq -r '.tunnels[0].public_url' 2>/dev/null || echo "")
        if [ -n "$NGROK_URL" ]; then
            info "ngrok URL: $NGROK_URL"
        fi
    else
        warn "ngrok not running for PostgreSQL"
        info "Start with: ngrok tcp 5432"
    fi
else
    warn "ngrok not installed"
    info "Install: brew install ngrok/ngrok/ngrok"
fi

# Check if PostgreSQL port is exposed
if docker ps --format '{{.Ports}}' | grep -q "5432"; then
    pass "PostgreSQL port 5432 is exposed"
    EXPOSED_PORT=$(docker ps --format '{{.Ports}}' | grep "5432" | head -1)
    info "Port mapping: $EXPOSED_PORT"
else
    warn "PostgreSQL port may not be exposed"
fi

# Issue 5: Check Environment Variables
echo ""
echo -e "${BLUE}[5/5] Checking Required Environment Variables...${NC}"

REQUIRED_VARS=(
    "KAFKA_API_KEY"
    "KAFKA_API_SECRET"
    "DB_HOSTNAME"
    "DB_USERNAME"
    "DB_PASSWORD"
    "DB_NAME"
    "SCHEMA_REGISTRY_API_KEY"
    "SCHEMA_REGISTRY_API_SECRET"
    "SCHEMA_REGISTRY_URL"
)

MISSING_COUNT=0
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        fail "Missing: $var"
        MISSING_COUNT=$((MISSING_COUNT + 1))
    else
        if [[ "$var" == *"SECRET"* ]] || [[ "$var" == *"PASSWORD"* ]]; then
            pass "$var is set (hidden)"
        else
            pass "$var is set"
        fi
    fi
done

if [ $MISSING_COUNT -gt 0 ]; then
    warn "$MISSING_COUNT required environment variables are missing"
fi

# Summary and Recommendations
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Troubleshooting Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

echo -e "${BLUE}Issues Found:${NC}"

ISSUES=()

# PostgreSQL accessibility
if [ -z "$NGROK_PID" ] && [ -z "$EXPOSED_PORT" ]; then
    ISSUES+=("PostgreSQL not accessible from Confluent Cloud")
fi

# Connector deployment
if [ "$CONNECTOR_FOUND" = false ]; then
    ISSUES+=("CDC connector not deployed")
fi

# Environment variables
if [ $MISSING_COUNT -gt 0 ]; then
    ISSUES+=("Missing environment variables: $MISSING_COUNT")
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
    echo -e "${GREEN}  ✓ No critical issues found${NC}"
else
    for issue in "${ISSUES[@]}"; do
        echo -e "${YELLOW}  ⚠ $issue${NC}"
    done
fi

echo ""
echo -e "${BLUE}Recommended Actions:${NC}"

# Action 1: Setup PostgreSQL access
if [ -z "$NGROK_PID" ]; then
    echo ""
    echo "1. ${CYAN}Setup PostgreSQL Access:${NC}"
    echo "   Option A: Use ngrok (recommended for development)"
    echo "     ngrok tcp 5432"
    echo "     Then set: export DB_HOSTNAME=<ngrok-hostname>"
    echo "               export DB_PORT=<ngrok-port>"
    echo ""
    echo "   Option B: Use setup script"
    echo "     ./scripts/setup-postgres-access.sh"
fi

# Action 2: Set environment variables
if [ $MISSING_COUNT -gt 0 ]; then
    echo ""
    echo "2. ${CYAN}Set Required Environment Variables:${NC}"
    echo "   export KAFKA_API_KEY='your-key'"
    echo "   export KAFKA_API_SECRET='your-secret'"
    echo "   export DB_HOSTNAME='your-db-host'"
    echo "   export DB_USERNAME='postgres'"
    echo "   export DB_PASSWORD='password'"
    echo "   export DB_NAME='car_entities'"
    echo "   export SCHEMA_REGISTRY_API_KEY='your-sr-key'"
    echo "   export SCHEMA_REGISTRY_API_SECRET='your-sr-secret'"
    echo "   export SCHEMA_REGISTRY_URL='https://psrc-xxxxx.us-east-1.aws.confluent.cloud'"
fi

# Action 3: Deploy connector
if [ "$CONNECTOR_FOUND" = false ]; then
    echo ""
    echo "3. ${CYAN}Deploy CDC Connector:${NC}"
    echo "   ./scripts/deploy-confluent-postgres-cdc-connector.sh"
fi

echo ""
echo -e "${GREEN}After fixing issues, re-run validation:${NC}"
echo "   # For validation, see cdc-streaming/scripts/validate-*.sh scripts
   # Archived validation scripts are in archive/scripts/validation/"
