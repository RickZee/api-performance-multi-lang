#!/bin/bash
# Monitor consumer connections and check for disconnection errors
# This script helps verify that the network keepalive fixes are working

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Consumer Connection Monitor ===${NC}"
echo ""

CONSUMERS=("service-consumer" "loan-consumer" "loan-payment-consumer" "car-consumer")

for consumer in "${CONSUMERS[@]}"; do
    echo -e "${BLUE}Checking ${consumer}...${NC}"
    
    # Check if container is running
    if docker ps --format '{{.Names}}' | grep -q "^cdc-${consumer}$"; then
        echo -e "${GREEN}✓ Container is running${NC}"
        
        # Check for disconnection errors in last 5 minutes
        DISCONNECTS=$(docker logs --since 5m "cdc-${consumer}" 2>&1 | grep -c "Disconnected" || true)
        
        if [ "$DISCONNECTS" -eq 0 ]; then
            echo -e "${GREEN}✓ No disconnection errors in last 5 minutes${NC}"
        else
            echo -e "${YELLOW}⚠ Found $DISCONNECTS disconnection error(s) in last 5 minutes${NC}"
            echo "Recent disconnection errors:"
            docker logs --since 5m "cdc-${consumer}" 2>&1 | grep "Disconnected" | tail -3
        fi
        
        # Check for successful connection messages
        CONNECTED=$(docker logs --since 5m "cdc-${consumer}" 2>&1 | grep -c "Consumer started" || true)
        if [ "$CONNECTED" -gt 0 ]; then
            echo -e "${GREEN}✓ Consumer started successfully${NC}"
        fi
        
        # Show last few log lines
        echo "Recent logs:"
        docker logs --tail 5 "cdc-${consumer}" 2>&1 | tail -3
    else
        echo -e "${RED}✗ Container is not running${NC}"
    fi
    
    echo ""
done

echo -e "${BLUE}=== Summary ===${NC}"
echo "To monitor in real-time, run:"
echo "  docker-compose logs -f service-consumer loan-consumer loan-payment-consumer car-consumer"
echo ""
echo "To check for disconnection errors:"
echo "  docker-compose logs | grep -i 'disconnected'"
