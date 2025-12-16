#!/bin/bash
# Delete stored offsets for a connector to fix WAL position issues
# This allows the connector to restart from a fresh position

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

# Parse arguments
CONNECTOR_ID="${1:-lcc-70rxxp}"
AUTO_YES=false

if [[ "$1" == "--yes" ]] || [[ "$1" == "-y" ]]; then
    AUTO_YES=true
    CONNECTOR_ID="${2:-lcc-70rxxp}"
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Delete Connector Offsets${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if connector exists
if ! confluent connect cluster describe "$CONNECTOR_ID" &>/dev/null; then
    echo -e "${RED}✗ Connector $CONNECTOR_ID not found${NC}"
    echo "Listing available connectors..."
    confluent connect cluster list
    exit 1
fi

# Get connector name
CONNECTOR_NAME=$(confluent connect cluster describe "$CONNECTOR_ID" --output json 2>/dev/null | jq -r '.connector.name // "unknown"' 2>/dev/null || echo "unknown")

echo -e "${CYAN}Connector Details:${NC}"
echo "  ID: $CONNECTOR_ID"
echo "  Name: $CONNECTOR_NAME"
echo ""

# Check current offsets
echo -e "${BLUE}Step 1: Checking current offsets...${NC}"
OFFSET_INFO=$(confluent connect offset describe "$CONNECTOR_ID" 2>&1 || echo "")

if [ -n "$OFFSET_INFO" ]; then
    echo -e "${CYAN}Current offsets:${NC}"
    echo "$OFFSET_INFO" | head -20
    echo ""
else
    echo -e "${YELLOW}⚠ No offsets found or unable to read offsets${NC}"
    echo ""
fi

# Confirm deletion
if [ "$AUTO_YES" = false ]; then
    echo -e "${YELLOW}⚠ WARNING: This will delete all stored offsets for this connector.${NC}"
    echo "The connector will restart from the beginning or use snapshot.mode setting."
    echo ""
    read -p "Delete offsets for connector $CONNECTOR_ID? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
else
    echo -e "${CYAN}Auto-confirming deletion (--yes flag)${NC}"
fi

# Delete offsets
echo ""
echo -e "${BLUE}Step 2: Deleting offsets...${NC}"

if confluent connect offset delete "$CONNECTOR_ID" 2>&1; then
    echo -e "${GREEN}✓ Offsets deleted successfully${NC}"
else
    echo -e "${RED}✗ Failed to delete offsets${NC}"
    echo ""
    echo "You may need to delete offsets via Confluent Cloud Console:"
    echo "  1. Navigate to: https://confluent.cloud"
    echo "  2. Go to your connector: $CONNECTOR_ID"
    echo "  3. Click 'Manage custom offsets'"
    echo "  4. Delete all offsets"
    exit 1
fi

# Wait a moment
sleep 3

# Check connector status
echo ""
echo -e "${BLUE}Step 3: Checking connector status...${NC}"

# Pause and resume to force restart
echo -e "${CYAN}Restarting connector to apply changes...${NC}"
if confluent connect cluster pause "$CONNECTOR_ID" 2>&1; then
    echo -e "${GREEN}✓ Connector paused${NC}"
    sleep 3
    
    if confluent connect cluster resume "$CONNECTOR_ID" 2>&1; then
        echo -e "${GREEN}✓ Connector resumed${NC}"
    else
        echo -e "${YELLOW}⚠ Failed to resume connector${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Failed to pause connector (may already be paused)${NC}"
    # Try to resume anyway
    confluent connect cluster resume "$CONNECTOR_ID" 2>&1 || true
fi

# Wait for connector to restart
echo ""
echo -e "${BLUE}Step 4: Waiting for connector to restart...${NC}"
sleep 10

# Check final status
CONNECTOR_STATUS=$(confluent connect cluster describe "$CONNECTOR_ID" --output json 2>/dev/null | jq -r '.status.connector.state // "unknown"' 2>/dev/null || echo "unknown")

echo ""
echo -e "${BLUE}Step 5: Final status check...${NC}"
if [ "$CONNECTOR_STATUS" = "RUNNING" ]; then
    echo -e "${GREEN}✓ Connector is RUNNING${NC}"
elif [ "$CONNECTOR_STATUS" = "FAILED" ]; then
    echo -e "${RED}✗ Connector is still FAILED${NC}"
    echo ""
    echo "Check connector logs:"
    echo "  confluent connect cluster logs $CONNECTOR_ID"
    echo ""
    echo "View connector details:"
    echo "  confluent connect cluster describe $CONNECTOR_ID"
else
    echo -e "${YELLOW}⚠ Connector status: $CONNECTOR_STATUS${NC}"
    echo "  Check logs: confluent connect cluster logs $CONNECTOR_ID"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Offset Deletion Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Monitor connector: confluent connect cluster describe $CONNECTOR_ID"
echo "  2. Check logs: confluent connect cluster logs $CONNECTOR_ID"
echo "  3. Verify events in raw-event-headers topic"
echo "  4. With snapshot.mode=when_needed, connector should re-snapshot if needed"
echo ""
