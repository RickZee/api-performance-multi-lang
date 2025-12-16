#!/bin/bash
# Fix Aurora Security Group for Confluent Cloud Connectivity
# Adds Confluent Cloud egress IPs to Aurora security group

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
echo -e "${BLUE}Fix Aurora Security Group for Confluent${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Get Aurora cluster info
CLUSTER_ID="producer-api-aurora-cluster"
REGION="${AWS_REGION:-us-east-1}"

echo -e "${CYAN}Configuration:${NC}"
echo "  Cluster: $CLUSTER_ID"
echo "  Region: $REGION"
echo ""

# Get security group ID
echo -e "${BLUE}Step 1: Getting Aurora security group...${NC}"
SG_ID=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
    --output text 2>/dev/null || echo "")

if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
    echo -e "${RED}✗ Failed to get security group ID${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Security Group ID: $SG_ID${NC}"
echo ""

# Get Confluent Cloud egress IPs
echo -e "${BLUE}Step 2: Getting Confluent Cloud egress IPs...${NC}"

if ! command -v confluent &> /dev/null; then
    echo -e "${RED}✗ Confluent CLI not installed${NC}"
    echo "  Install with: brew install confluentinc/tap/cli"
    exit 1
fi

# Get IPs for KAFKA, CONNECT services
# The output format is: Cloud | Region | IP Prefix | Address Type | Services
# Example: AWS   | us-east-1 | 100.24.204.241/32  | EGRESS       | KAFKA, CONNECT
CONFLUENT_IPS=$(confluent network ip-address list \
    --cloud AWS \
    --region "$REGION" \
    --address-type EGRESS 2>&1 | \
    grep "KAFKA, CONNECT" | \
    awk -F'|' '{print $3}' | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | \
    sort -u)

if [ -z "$CONFLUENT_IPS" ]; then
    echo -e "${RED}✗ Failed to get Confluent Cloud IPs${NC}"
    echo "  Make sure you're logged in: confluent login"
    exit 1
fi

IP_COUNT=$(echo "$CONFLUENT_IPS" | wc -l | tr -d ' ')
echo -e "${GREEN}✓ Found $IP_COUNT Confluent Cloud egress IPs${NC}"
echo ""

# Check current rules
echo -e "${BLUE}Step 3: Checking current security group rules...${NC}"
CURRENT_RULES=$(aws ec2 describe-security-groups \
    --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`5432`].IpRanges[*].CidrIp' \
    --output text 2>&1)

echo -e "${CYAN}Current rules for port 5432:${NC}"
echo "$CURRENT_RULES" | tr '\t' '\n' | while read -r cidr; do
    [ -n "$cidr" ] && echo "  - $cidr"
done
echo ""

# Check if we need to add rules
echo -e "${BLUE}Step 4: Adding Confluent Cloud IPs to security group...${NC}"

ADDED_COUNT=0
SKIPPED_COUNT=0

for ip in $CONFLUENT_IPS; do
    # Check if rule already exists
    if echo "$CURRENT_RULES" | grep -q "$ip"; then
        echo -e "${CYAN}  ⏭  $ip (already exists)${NC}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    else
        # Add rule
        if aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 5432 \
            --cidr "$ip" \
            --description "Confluent Cloud egress IP for CDC connector" \
            --region "$REGION" \
            --output text 2>&1 | grep -q "SecurityGroupRuleId"; then
            echo -e "${GREEN}  ✓ Added: $ip${NC}"
            ADDED_COUNT=$((ADDED_COUNT + 1))
        else
            echo -e "${YELLOW}  ⚠ Failed to add: $ip (may already exist)${NC}"
        fi
    fi
done

echo ""
echo -e "${BLUE}Step 5: Summary${NC}"
echo -e "${GREEN}✓ Added: $ADDED_COUNT IP(s)${NC}"
echo -e "${CYAN}⏭  Skipped: $SKIPPED_COUNT IP(s) (already exist)${NC}"
echo ""

# Verify final state
echo -e "${BLUE}Step 6: Verifying security group...${NC}"
FINAL_RULE_COUNT=$(aws ec2 describe-security-groups \
    --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`5432`].IpRanges | length(@)' \
    --output text 2>&1)

echo -e "${GREEN}✓ Total rules for port 5432: $FINAL_RULE_COUNT${NC}"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Security Group Update Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Wait a few seconds for rules to propagate"
echo "  2. Check connector status: confluent connect cluster describe lcc-70rxxp"
echo "  3. If still failing, check connector logs: confluent connect cluster logs lcc-70rxxp"
echo ""
