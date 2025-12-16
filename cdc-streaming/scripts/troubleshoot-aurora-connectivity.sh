#!/bin/bash
# Comprehensive Aurora PostgreSQL Connectivity Troubleshooting
# Based on CONFLUENT_CLOUD_SETUP_GUIDE.md and Terraform documentation

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
echo -e "${BLUE}Aurora PostgreSQL Connectivity Troubleshooting${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

CLUSTER_ID="${1:-producer-api-aurora-cluster}"
CONNECTOR_ID="${2:-lcc-70rxxp}"

echo -e "${CYAN}Configuration:${NC}"
echo "  Aurora Cluster: $CLUSTER_ID"
echo "  Connector ID: $CONNECTOR_ID"
echo ""

# Step 1: Check Aurora Cluster Status
echo -e "${BLUE}Step 1: Checking Aurora Cluster Status...${NC}"
CLUSTER_INFO=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --query 'DBClusters[0]' \
    --output json 2>/dev/null)

if [ -z "$CLUSTER_INFO" ] || [ "$CLUSTER_INFO" = "null" ]; then
    echo -e "${RED}✗ Cluster not found${NC}"
    exit 1
fi

ENDPOINT=$(echo "$CLUSTER_INFO" | jq -r '.Endpoint')
STATUS=$(echo "$CLUSTER_INFO" | jq -r '.Status')
PUBLICLY_ACCESSIBLE=$(aws rds describe-db-instances \
    --filters "Name=db-cluster-id,Values=$CLUSTER_ID" \
    --query 'DBInstances[0].PubliclyAccessible' \
    --output text 2>/dev/null)

echo -e "${GREEN}✓ Cluster Status: $STATUS${NC}"
echo -e "${GREEN}✓ Endpoint: $ENDPOINT${NC}"
echo -e "${GREEN}✓ Publicly Accessible: $PUBLICLY_ACCESSIBLE${NC}"
echo ""

# Step 2: Check Security Group
echo -e "${BLUE}Step 2: Checking Security Group Configuration...${NC}"
SG_ID=$(echo "$CLUSTER_INFO" | jq -r '.VpcSecurityGroups[0].VpcSecurityGroupId')

if [ -n "$SG_ID" ] && [ "$SG_ID" != "null" ]; then
    SG_RULES=$(aws ec2 describe-security-groups \
        --group-ids "$SG_ID" \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`5432`]' \
        --output json 2>/dev/null)
    
    RULE_COUNT=$(echo "$SG_RULES" | jq 'length')
    echo -e "${GREEN}✓ Security Group: $SG_ID${NC}"
    echo -e "${GREEN}✓ Rules for port 5432: $RULE_COUNT${NC}"
    
    # Check if 0.0.0.0/0 is allowed
    if echo "$SG_RULES" | jq -e '.[].IpRanges[] | select(.CidrIp == "0.0.0.0/0")' > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Allows all IPs (0.0.0.0/0)${NC}"
    else
        echo -e "${YELLOW}⚠ Does not allow 0.0.0.0/0 - checking specific IPs...${NC}"
        echo "$SG_RULES" | jq -r '.[].IpRanges[]?.CidrIp' | while read -r cidr; do
            [ -n "$cidr" ] && echo "  - $cidr"
        done
    fi
else
    echo -e "${RED}✗ No security group found${NC}"
fi
echo ""

# Step 3: Check Subnet Configuration
echo -e "${BLUE}Step 3: Checking Subnet Configuration...${NC}"
SUBNET_GROUP=$(echo "$CLUSTER_INFO" | jq -r '.DBSubnetGroup')
SUBNET_IDS=$(aws rds describe-db-subnet-groups \
    --db-subnet-group-name "$SUBNET_GROUP" \
    --query 'DBSubnetGroups[0].Subnets[*].SubnetIdentifier' \
    --output json 2>/dev/null | jq -r '.[]')

PUBLIC_COUNT=0
for subnet_id in $SUBNET_IDS; do
    IS_PUBLIC=$(aws ec2 describe-subnets \
        --subnet-ids "$subnet_id" \
        --query 'Subnets[0].MapPublicIpOnLaunch' \
        --output text 2>/dev/null)
    
    if [ "$IS_PUBLIC" = "True" ]; then
        PUBLIC_COUNT=$((PUBLIC_COUNT + 1))
        # Check for internet gateway route
        HAS_IGW=$(aws ec2 describe-route-tables \
            --filters "Name=association.subnet-id,Values=$subnet_id" \
            --query 'RouteTables[0].Routes[?GatewayId!=`null` && GatewayId!=`local`] | length(@)' \
            --output text 2>/dev/null)
        
        if [ "$HAS_IGW" -gt 0 ]; then
            echo -e "${GREEN}✓ Subnet $subnet_id: Public with Internet Gateway${NC}"
        else
            echo -e "${YELLOW}⚠ Subnet $subnet_id: Public but no Internet Gateway route${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Subnet $subnet_id: Private${NC}"
    fi
done

if [ "$PUBLIC_COUNT" -eq 0 ] && [ "$PUBLICLY_ACCESSIBLE" = "True" ]; then
    echo -e "${RED}✗ WARNING: Instance is publicly accessible but subnets are private!${NC}"
    echo "  Aurora instances must be in public subnets to be publicly accessible."
fi
echo ""

# Step 4: Check Connector Configuration
echo -e "${BLUE}Step 4: Checking Connector Configuration...${NC}"
if confluent connect cluster describe "$CONNECTOR_ID" &>/dev/null; then
    CONNECTOR_HOSTNAME=$(confluent connect cluster describe "$CONNECTOR_ID" --output json 2>/dev/null | \
        jq -r '.configs[] | select(.config == "database.hostname") | .value')
    CONNECTOR_SSLMODE=$(confluent connect cluster describe "$CONNECTOR_ID" --output json 2>/dev/null | \
        jq -r '.configs[] | select(.config == "database.sslmode") | .value // "not set"')
    
    echo -e "${GREEN}✓ Connector Hostname: $CONNECTOR_HOSTNAME${NC}"
    echo -e "${CYAN}  SSL Mode: $CONNECTOR_SSLMODE${NC}"
    
    if [ "$CONNECTOR_HOSTNAME" != "$ENDPOINT" ]; then
        echo -e "${YELLOW}⚠ WARNING: Connector hostname doesn't match cluster endpoint!${NC}"
        echo "  Connector: $CONNECTOR_HOSTNAME"
        echo "  Cluster:   $ENDPOINT"
    else
        echo -e "${GREEN}✓ Connector using correct cluster endpoint${NC}"
    fi
    
    if [ "$CONNECTOR_SSLMODE" = "not set" ] || [ "$CONNECTOR_SSLMODE" = "null" ]; then
        echo -e "${YELLOW}⚠ SSL mode not set - should be 'require' for Aurora${NC}"
    elif [ "$CONNECTOR_SSLMODE" != "require" ]; then
        echo -e "${YELLOW}⚠ SSL mode is '$CONNECTOR_SSLMODE' - 'require' is recommended${NC}"
    else
        echo -e "${GREEN}✓ SSL mode correctly set to 'require'${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Connector not found or not accessible${NC}"
fi
echo ""

# Step 5: Check Parameter Group Settings
echo -e "${BLUE}Step 5: Checking Parameter Group Settings...${NC}"
PARAM_GROUP=$(echo "$CLUSTER_INFO" | jq -r '.DBClusterParameterGroup')

if [ -n "$PARAM_GROUP" ] && [ "$PARAM_GROUP" != "null" ]; then
    FORCE_SSL=$(aws rds describe-db-cluster-parameters \
        --db-cluster-parameter-group-name "$PARAM_GROUP" \
        --query 'Parameters[?ParameterName==`rds.force_ssl`].ParameterValue' \
        --output text 2>/dev/null)
    
    echo -e "${CYAN}  Parameter Group: $PARAM_GROUP${NC}"
    echo -e "${CYAN}  Force SSL: ${FORCE_SSL:-not set}${NC}"
    
    if [ "$FORCE_SSL" = "1" ]; then
        echo -e "${YELLOW}⚠ Force SSL is enabled - connector MUST use SSL${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Could not determine parameter group${NC}"
fi
echo ""

# Step 6: Test Connectivity (if psql available)
echo -e "${BLUE}Step 6: Testing Connectivity...${NC}"
if command -v psql &> /dev/null; then
    DB_USER=$(confluent connect cluster describe "$CONNECTOR_ID" --output json 2>/dev/null | \
        jq -r '.configs[] | select(.config == "database.user") | .value' 2>/dev/null || echo "postgres")
    DB_NAME=$(confluent connect cluster describe "$CONNECTOR_ID" --output json 2>/dev/null | \
        jq -r '.configs[] | select(.config == "database.dbname") | .value' 2>/dev/null || echo "car_entities")
    
    echo -e "${CYAN}  Testing connection to $ENDPOINT...${NC}"
    echo -e "${CYAN}  (This requires database password - will skip if not available)${NC}"
    
    if [ -n "$DB_PASSWORD" ]; then
        if PGPASSWORD="$DB_PASSWORD" timeout 5 psql \
            -h "$ENDPOINT" \
            -U "$DB_USER" \
            -d "$DB_NAME" \
            -c "SELECT 1;" \
            &>/dev/null; then
            echo -e "${GREEN}✓ Direct connection test successful${NC}"
        else
            echo -e "${RED}✗ Direct connection test failed${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ DB_PASSWORD not set - skipping connection test${NC}"
        echo "  Set DB_PASSWORD environment variable to test connectivity"
    fi
else
    echo -e "${YELLOW}⚠ psql not available - skipping connection test${NC}"
fi
echo ""

# Step 7: Check Confluent Cloud IPs
echo -e "${BLUE}Step 7: Checking Confluent Cloud Egress IPs...${NC}"
if command -v confluent &> /dev/null; then
    CONFLUENT_IPS=$(confluent network ip-address list \
        --cloud AWS \
        --region us-east-1 \
        --address-type EGRESS 2>&1 | \
        grep "KAFKA, CONNECT" | \
        awk -F'|' '{print $3}' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        wc -l | tr -d ' ')
    
    if [ "$CONFLUENT_IPS" -gt 0 ]; then
        echo -e "${GREEN}✓ Found $CONFLUENT_IPS Confluent Cloud egress IPs${NC}"
        echo -e "${CYAN}  Use: ./cdc-streaming/scripts/fix-aurora-security-group-for-confluent.sh${NC}"
        echo -e "${CYAN}  To add these IPs to the security group${NC}"
    else
        echo -e "${YELLOW}⚠ Could not retrieve Confluent Cloud IPs${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Confluent CLI not available${NC}"
fi
echo ""

# Summary and Recommendations
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Troubleshooting Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

ISSUES=0

# Check for common issues
if [ "$PUBLICLY_ACCESSIBLE" != "True" ]; then
    echo -e "${RED}✗ Issue: Instance is not publicly accessible${NC}"
    echo "  Solution: Set publicly_accessible = true in Terraform"
    ISSUES=$((ISSUES + 1))
fi

if [ "$PUBLIC_COUNT" -eq 0 ] && [ "$PUBLICLY_ACCESSIBLE" = "True" ]; then
    echo -e "${RED}✗ Issue: Instance is in private subnets but marked as publicly accessible${NC}"
    echo "  Solution: Use public subnets for Aurora when publicly_accessible = true"
    ISSUES=$((ISSUES + 1))
fi

if [ "$CONNECTOR_SSLMODE" != "require" ] && [ "$CONNECTOR_SSLMODE" != "not set" ] && [ -n "$CONNECTOR_SSLMODE" ]; then
    echo -e "${YELLOW}⚠ Issue: SSL mode may not be optimal${NC}"
    echo "  Recommendation: Set database.sslmode = require"
    ISSUES=$((ISSUES + 1))
fi

if [ "$ISSUES" -eq 0 ]; then
    echo -e "${GREEN}✓ No obvious configuration issues found${NC}"
    echo ""
    echo -e "${CYAN}If connector still fails with 'pg_hba.conf' error:${NC}"
    echo "  1. Verify database credentials are correct"
    echo "  2. Check connector logs: confluent connect cluster logs $CONNECTOR_ID"
    echo "  3. Try restarting the connector:"
    echo "     confluent connect cluster pause $CONNECTOR_ID"
    echo "     confluent connect cluster resume $CONNECTOR_ID"
    echo "  4. Check if database user has replication privileges:"
    echo "     psql -h $ENDPOINT -U postgres -d car_entities -c '\\du'"
    echo "  5. Verify replication slot exists:"
    echo "     psql -h $ENDPOINT -U postgres -d car_entities -c 'SELECT * FROM pg_replication_slots;'"
fi

echo ""
echo -e "${CYAN}Useful Commands:${NC}"
echo "  Check connector status: confluent connect cluster describe $CONNECTOR_ID"
echo "  View connector logs: confluent connect cluster logs $CONNECTOR_ID"
echo "  Check security group: aws ec2 describe-security-groups --group-ids $SG_ID"
echo "  Test connection: psql -h $ENDPOINT -U postgres -d car_entities"
echo ""
