#!/bin/bash
# Setup PostgreSQL access for Confluent Cloud connector
# Provides options for making local PostgreSQL accessible from Confluent Cloud

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PostgreSQL Access Setup for Confluent${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Confluent Managed Connectors need to connect to your PostgreSQL database.${NC}"
echo -e "${CYAN}Since PostgreSQL is running in Docker locally, you need to make it accessible.${NC}"
echo ""

echo -e "${BLUE}Options:${NC}"
echo ""
echo "1. ${GREEN}ngrok${NC} - Create a secure tunnel (recommended for development)"
echo "   - Free tier available"
echo "   - Easy setup"
echo "   - Secure"
echo ""
echo "2. ${GREEN}Public IP${NC} - Expose PostgreSQL publicly (development only)"
echo "   - Simple but less secure"
echo "   - Requires firewall configuration"
echo ""
echo "3. ${GREEN}Confluent PrivateLink${NC} - Private connection (production)"
echo "   - Most secure"
echo "   - Requires AWS/Azure/GCP setup"
echo "   - See CONFLUENT_CLOUD_SETUP_GUIDE.md"
echo ""
echo "4. ${GREEN}Cloud-hosted PostgreSQL${NC} - Use managed database"
echo "   - AWS RDS, Azure Database, etc."
echo "   - Already accessible from Confluent Cloud"
echo ""

read -p "Select option (1-4): " option

case $option in
    1)
        echo ""
        echo -e "${BLUE}Setting up ngrok tunnel...${NC}"
        echo ""
        
        # Check if ngrok is installed
        if ! command -v ngrok &> /dev/null; then
            echo -e "${RED}✗ ngrok is not installed${NC}"
            echo ""
            echo "Install ngrok:"
            echo "  macOS: brew install ngrok/ngrok/ngrok"
            echo "  Linux: https://ngrok.com/download"
            echo ""
            echo "Or sign up at https://ngrok.com and get your authtoken"
            exit 1
        fi
        
        echo -e "${GREEN}✓ ngrok is installed${NC}"
        echo ""
        echo "Starting ngrok tunnel for PostgreSQL (port 5432)..."
        echo ""
        echo -e "${YELLOW}Note: Keep this terminal open while using the connector${NC}"
        echo ""
        echo "Run this command in a separate terminal:"
        echo -e "${CYAN}  ngrok tcp 5432${NC}"
        echo ""
        echo "Then use the ngrok hostname (e.g., 0.tcp.ngrok.io) and port as DB_HOSTNAME"
        echo "Example:"
        echo "  export DB_HOSTNAME=0.tcp.ngrok.io"
        echo "  export DB_PORT=12345  # Port from ngrok output"
        echo ""
        echo "Then deploy connector:"
        echo "  ./run-k6-docker-compose.sh deploy-connector"
        ;;
    
    2)
        echo ""
        echo -e "${YELLOW}⚠ Warning: Exposing PostgreSQL publicly is not recommended for production${NC}"
        echo ""
        echo "To expose PostgreSQL:"
        echo "1. Get your public IP:"
        echo "   curl ifconfig.me"
        echo ""
        echo "2. Update docker-compose to bind to 0.0.0.0:"
        echo "   ports:"
        echo "     - \"0.0.0.0:5432:5432\""
        echo ""
        echo "3. Configure firewall to allow Confluent Cloud IPs:"
        echo "   See: https://docs.confluent.io/cloud/current/connectors/ip-addresses.html"
        echo ""
        echo "4. Use public IP as DB_HOSTNAME when deploying connector"
        ;;
    
    3)
        echo ""
        echo -e "${BLUE}Confluent PrivateLink Setup${NC}"
        echo ""
        echo "For production, use Confluent PrivateLink:"
        echo "1. See CONFLUENT_CLOUD_SETUP_GUIDE.md for detailed instructions"
        echo "2. Set up AWS PrivateLink, Azure Private Link, or GCP Private Service Connect"
        echo "3. Configure network in Confluent Cloud"
        echo "4. Use private endpoint as DB_HOSTNAME"
        echo ""
        echo "This requires:"
        echo "  - Confluent Cloud Enterprise account"
        echo "  - VPC/network configuration"
        echo "  - PrivateLink service setup"
        ;;
    
    4)
        echo ""
        echo -e "${BLUE}Using Cloud-Hosted PostgreSQL${NC}"
        echo ""
        echo "If using AWS RDS, Azure Database, or similar:"
        echo "1. Ensure database allows connections from Confluent Cloud"
        echo "2. Configure security groups/firewall rules"
        echo "3. Use database endpoint as DB_HOSTNAME"
        echo "4. Deploy connector normally"
        ;;
    
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Setup instructions displayed above${NC}"
