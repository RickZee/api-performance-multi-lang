#!/bin/bash
# Get Confluent Cloud Egress IP Ranges
# 
# This script helps discover Confluent Cloud egress IP ranges for configuring
# Aurora security groups when using public internet access.
#
# Usage:
#   ./get-confluent-cloud-ips.sh [region]
#
# Example:
#   ./get-confluent-cloud-ips.sh us-east-1
#
# Output format: Terraform-friendly list of CIDR blocks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

REGION="${1:-us-east-1}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Confluent Cloud Egress IP Range Discovery${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Purpose:${NC} Configure Aurora security group for Postgres CDC Source V2 (Debezium)"
echo -e "${CYAN}Region:${NC} $REGION"
echo ""

# Method 1: Try Confluent CLI
if command -v confluent &> /dev/null; then
    echo -e "${BLUE}Method 1: Using Confluent CLI...${NC}"
    
    if confluent network egress-ip list --region "$REGION" &> /dev/null; then
        echo -e "${GREEN}✓ Found IP ranges via Confluent CLI${NC}"
        echo ""
        echo -e "${CYAN}Confluent Cloud Egress IP Ranges for $REGION:${NC}"
        confluent network egress-ip list --region "$REGION" --output json 2>/dev/null | \
            jq -r '.[] | "\(.ip)"' | \
            while read -r ip; do
                echo "  \"$ip\","
            done
        echo ""
        echo -e "${GREEN}Copy the IP ranges above to your terraform.tfvars:${NC}"
        echo "  confluent_cloud_cidrs = ["
        confluent network egress-ip list --region "$REGION" --output json 2>/dev/null | \
            jq -r '.[] | "    \"\(.ip)\","' | sed '$ s/,$//'
        echo "  ]"
        exit 0
    else
        echo -e "${YELLOW}⚠ Confluent CLI available but command failed${NC}"
        echo "  Make sure you're logged in: confluent login"
    fi
else
    echo -e "${YELLOW}⚠ Confluent CLI not installed${NC}"
    echo "  Install with: brew install confluentinc/tap/cli"
    echo "  Or: curl -sL --http1.1 https://cnfl.io/cli | sh -s -- latest"
fi

echo ""

# Method 2: Check documentation
echo -e "${BLUE}Method 2: Manual Lookup${NC}"
echo ""
echo -e "${CYAN}To find Confluent Cloud egress IP ranges:${NC}"
echo ""
echo "1. Check Confluent Cloud Documentation:"
echo "   https://docs.confluent.io/cloud/current/networking/ip-ranges.html"
echo ""
echo "2. Contact Confluent Support:"
echo "   - Log in to https://confluent.cloud"
echo "   - Navigate to Support → Create a ticket"
echo "   - Request egress IP ranges for region: $REGION"
echo ""
echo "3. Check Confluent Cloud Console:"
echo "   - Navigate to: Network Management → Egress IPs"
echo "   - View egress IPs for your environment"
echo ""

# Method 3: Provide example format
echo -e "${BLUE}Method 3: Example Configuration${NC}"
echo ""
echo -e "${CYAN}Example terraform.tfvars configuration:${NC}"
echo ""
cat << 'EOF'
# Public Internet Access for Confluent Cloud
aurora_publicly_accessible = true

# Replace with actual Confluent Cloud egress IP ranges for your region
# Get these from: https://docs.confluent.io/cloud/current/networking/ip-ranges.html
# Or use: confluent network egress-ip list --region us-east-1
confluent_cloud_cidrs = [
  "13.57.0.0/16",  # Example - replace with actual IPs
  "52.0.0.0/16"    # Example - replace with actual IPs
]
EOF

echo ""
echo -e "${YELLOW}⚠ Important Notes:${NC}"
echo ""
echo "1. IP ranges are region-specific - use IPs for your Confluent Cloud region"
echo "2. IP ranges may change over time - update configuration periodically"
echo "3. For production, prefer AWS PrivateLink over public access"
echo "4. Always use SSL/TLS (sslmode=require) in connector configuration"
echo ""

# Method 4: Validate CIDR format if provided
if [ $# -gt 1 ]; then
    echo -e "${BLUE}Method 4: Validating CIDR Format${NC}"
    echo ""
    shift
    for cidr in "$@"; do
        if [[ $cidr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            echo -e "${GREEN}✓ Valid CIDR: $cidr${NC}"
        else
            echo -e "${RED}✗ Invalid CIDR format: $cidr${NC}"
            echo "  Expected format: X.X.X.X/XX (e.g., 13.57.0.0/16)"
        fi
    done
    echo ""
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Next Steps:${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "1. Get Confluent Cloud egress IP ranges using one of the methods above"
echo "2. Update terraform.tfvars with confluent_cloud_cidrs"
echo "3. Run: terraform plan to verify security group configuration"
echo "4. Run: terraform apply to deploy"
echo "5. Verify security group rules in AWS Console"
echo "6. Deploy Postgres CDC Source V2 (Debezium) connector in Confluent Cloud"
echo "7. Test connector connectivity from Confluent Cloud"
echo ""
echo -e "${CYAN}For detailed setup guide, see:${NC}"
echo "  terraform/PUBLIC_ACCESS_SETUP.md"
echo ""
echo -e "${CYAN}Connector Type:${NC} Postgres CDC Source V2 (Debezium)"
echo ""
