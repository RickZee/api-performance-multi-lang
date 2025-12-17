#!/bin/bash
# Comprehensive Connector Connection Diagnosis
# Checks all aspects that could cause "pg_hba.conf" errors

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

CONNECTOR_ID="${1:-lcc-70rxxp}"
CLUSTER_ID="${2:-producer-api-aurora-cluster}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Connector Connection Diagnosis${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Get connector config
echo -e "${BLUE}Step 1: Checking Connector Configuration...${NC}"
CONNECTOR_CONFIG=$(confluent connect cluster describe "$CONNECTOR_ID" --output json 2>/dev/null)

if [ -z "$CONNECTOR_CONFIG" ]; then
    echo -e "${RED}✗ Failed to get connector configuration${NC}"
    exit 1
fi

get_config() {
    echo "$CONNECTOR_CONFIG" | jq -r ".configs[] | select(.config == \"$1\") | .value // empty"
}

DB_HOSTNAME=$(get_config "database.hostname")
DB_USER=$(get_config "database.user")
DB_NAME=$(get_config "database.dbname")
DB_PORT=$(get_config "database.port")
DB_SSLMODE=$(get_config "database.sslmode")
DB_PASSWORD_LEN=$(get_config "database.password" | wc -c)

echo -e "${CYAN}Connector Settings:${NC}"
echo "  Hostname: $DB_HOSTNAME"
echo "  User: $DB_USER"
echo "  Database: $DB_NAME"
echo "  Port: $DB_PORT"
echo "  SSL Mode: $DB_SSLMODE"
echo "  Password length: $DB_PASSWORD_LEN"
echo ""

# Get expected password length
if [ -f "$PROJECT_ROOT/.env.aurora" ]; then
    EXPECTED_PASSWORD=$(grep "^export DB_PASSWORD=" "$PROJECT_ROOT/.env.aurora" 2>/dev/null | cut -d'"' -f2 || echo "")
    EXPECTED_LEN=${#EXPECTED_PASSWORD}
    
    if [ "$DB_PASSWORD_LEN" -ne "$EXPECTED_LEN" ]; then
        echo -e "${RED}✗ Password length mismatch!${NC}"
        echo "  Connector: $DB_PASSWORD_LEN characters"
        echo "  Expected: $EXPECTED_LEN characters"
        echo "  Run: ./cdc-streaming/scripts/update-connector-password.sh"
    else
        echo -e "${GREEN}✓ Password length matches expected${NC}"
    fi
fi
echo ""

# Check Aurora cluster
echo -e "${BLUE}Step 2: Checking Aurora Cluster...${NC}"
CLUSTER_INFO=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --query 'DBClusters[0]' \
    --output json 2>/dev/null)

ENDPOINT=$(echo "$CLUSTER_INFO" | jq -r '.Endpoint')
STATUS=$(echo "$CLUSTER_INFO" | jq -r '.Status')

echo -e "${CYAN}Cluster Status:${NC}"
echo "  Endpoint: $ENDPOINT"
echo "  Status: $STATUS"

if [ "$ENDPOINT" != "$DB_HOSTNAME" ]; then
    echo -e "${RED}✗ Endpoint mismatch!${NC}"
    echo "  Connector uses: $DB_HOSTNAME"
    echo "  Cluster endpoint: $ENDPOINT"
else
    echo -e "${GREEN}✓ Endpoint matches${NC}"
fi
echo ""

# Check security group
echo -e "${BLUE}Step 3: Checking Security Group...${NC}"
SG_ID=$(echo "$CLUSTER_INFO" | jq -r '.VpcSecurityGroups[0].VpcSecurityGroupId // empty')

if [ -n "$SG_ID" ] && [ "$SG_ID" != "null" ]; then
    SG_RULES=$(aws ec2 describe-security-groups \
        --group-ids "$SG_ID" \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`5432`].IpRanges[*].CidrIp' \
        --output text 2>/dev/null)
    
    echo -e "${CYAN}Security Group Rules:${NC}"
    echo "$SG_RULES" | tr '\t' '\n' | while read -r cidr; do
        [ -n "$cidr" ] && echo "  - $cidr"
    done
    
    if echo "$SG_RULES" | grep -q "0.0.0.0/0"; then
        echo -e "${GREEN}✓ Security group allows all IPs (0.0.0.0/0)${NC}"
    else
        echo -e "${YELLOW}⚠ Security group may not allow all IPs${NC}"
        echo "  Consider running: ./cdc-streaming/scripts/fix-aurora-security-group-for-confluent.sh"
    fi
else
    echo -e "${YELLOW}⚠ Could not determine security group${NC}"
fi
echo ""

# Check replication role
echo -e "${BLUE}Step 4: Checking Replication Role...${NC}"
if [ -f "$PROJECT_ROOT/.env.aurora" ]; then
    DB_PASSWORD=$(grep "^export DB_PASSWORD=" "$PROJECT_ROOT/.env.aurora" 2>/dev/null | cut -d'"' -f2 || echo "")
    
    if [ -n "$DB_PASSWORD" ]; then
        HAS_ROLE=$(python3 << EOF
import asyncio
import asyncpg
import sys

async def check_role():
    try:
        conn = await asyncpg.connect(
            host="$ENDPOINT",
            user="$DB_USER",
            password="$DB_PASSWORD",
            database="$DB_NAME",
            ssl='require',
            timeout=10
        )
        has_role = await conn.fetchval(
            "SELECT COUNT(*) > 0 FROM pg_roles r1, pg_roles r2, pg_auth_members m "
            "WHERE r1.rolname = '$DB_USER' AND m.member = r1.oid AND m.roleid = r2.oid "
            "AND r2.rolname = 'rds_replication'"
        )
        await conn.close()
        print("true" if has_role else "false")
    except Exception as e:
        print(f"error: {e}")
        sys.exit(1)

asyncio.run(check_role())
EOF
)
        
        if [ "$HAS_ROLE" = "true" ]; then
            echo -e "${GREEN}✓ User has rds_replication role${NC}"
        elif [ "$HAS_ROLE" = "false" ]; then
            echo -e "${RED}✗ User does NOT have rds_replication role${NC}"
            echo "  Run: python3 cdc-streaming/scripts/fix-postgres-replication-privileges.py"
        else
            echo -e "${YELLOW}⚠ Could not check replication role: $HAS_ROLE${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ DB_PASSWORD not found - skipping replication role check${NC}"
    fi
else
    echo -e "${YELLOW}⚠ .env.aurora not found - skipping replication role check${NC}"
fi
echo ""

# Check connector status
echo -e "${BLUE}Step 5: Checking Connector Status...${NC}"
CONNECTOR_STATUS=$(echo "$CONNECTOR_CONFIG" | jq -r '.status.connector.state // "unknown"')
TASK_STATE=$(echo "$CONNECTOR_CONFIG" | jq -r '.status.tasks[0].state // "unknown"')
TRACE=$(echo "$CONNECTOR_CONFIG" | jq -r '.status.tasks[0].trace // "N/A"')

echo -e "${CYAN}Connector Status:${NC}"
echo "  State: $CONNECTOR_STATUS"
echo "  Task State: $TASK_STATE"

if [ "$TRACE" != "N/A" ] && [ -n "$TRACE" ]; then
    echo "  Error: $TRACE"
fi
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Diagnosis Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

ISSUES=0

if [ "$DB_PASSWORD_LEN" != "$EXPECTED_LEN" ] 2>/dev/null; then
    echo -e "${RED}✗ Issue: Password mismatch${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [ "$HAS_ROLE" = "false" ] 2>/dev/null; then
    echo -e "${RED}✗ Issue: Missing rds_replication role${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [ "$CONNECTOR_STATUS" = "FAILED" ]; then
    echo -e "${RED}✗ Issue: Connector is FAILED${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [ "$ISSUES" -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed${NC}"
    echo ""
    echo "If connector still fails, possible causes:"
    echo "  1. Network routing from Confluent Cloud IPs"
    echo "  2. Connection timeout (connector may have shorter timeout)"
    echo "  3. SSL/TLS negotiation differences"
    echo "  4. Aurora parameter group blocking connections"
    echo ""
    echo "Next steps:"
    echo "  1. Check connector logs in Confluent Cloud Console"
    echo "  2. Verify Confluent Cloud IPs are allowed (even with 0.0.0.0/0)"
    echo "  3. Try restarting connector: confluent connect cluster pause/resume $CONNECTOR_ID"
else
    echo ""
    echo -e "${CYAN}Fix the issues above and restart the connector${NC}"
fi

echo ""
