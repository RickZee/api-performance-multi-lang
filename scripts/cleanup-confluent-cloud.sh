#!/bin/bash
# Cleanup all Confluent Cloud resources
# This script deletes all topics, Flink statements, and connectors
#
# NOTE: Compute pools are NOT deleted - only Flink statements within them are removed
#
# WARNING: This will permanently delete all resources. Use with caution!
#
# Prerequisites:
# - Confluent CLI installed and logged in
# - Appropriate permissions to delete resources

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Confluent Cloud Resource Cleanup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check prerequisites
if ! command -v confluent &> /dev/null; then
    echo -e "${RED}✗ Confluent CLI is not installed${NC}"
    echo "  Install with: brew install confluentinc/tap/cli"
    exit 1
fi

# Check if logged in
if ! confluent environment list &> /dev/null; then
    echo -e "${RED}✗ Not logged in to Confluent Cloud${NC}"
    echo "  Login with: confluent login"
    exit 1
fi

# Get current context
ENV_ID="${CONFLUENT_ENV_ID:-$(confluent environment list --output json 2>/dev/null | jq -r '.[0].id' 2>/dev/null || echo '')}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-$(confluent kafka cluster list --output json 2>/dev/null | jq -r '.[0].id' 2>/dev/null || echo '')}"

if [ -z "$ENV_ID" ]; then
    echo -e "${RED}✗ No Confluent environment found${NC}"
    exit 1
fi

if [ -z "$CLUSTER_ID" ]; then
    echo -e "${RED}✗ No Kafka cluster found${NC}"
    exit 1
fi

echo -e "${CYAN}Environment ID: $ENV_ID${NC}"
echo -e "${CYAN}Cluster ID: $CLUSTER_ID${NC}"
echo ""

# Confirmation prompt
read -p "$(echo -e ${YELLOW}Are you sure you want to delete ALL Confluent Cloud resources? [y/N]: ${NC})" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

# ============================================================================
# 1. Delete Flink Statements (NOT compute pools)
# ============================================================================
echo -e "${BLUE}Step 1: Deleting Flink Statements...${NC}"
echo -e "${CYAN}  Note: Compute pools will NOT be deleted${NC}"

# Get all compute pools
COMPUTE_POOLS=$(confluent flink compute-pool list --output json 2>/dev/null | jq -r '.[].id' 2>/dev/null || echo "")

if [ -n "$COMPUTE_POOLS" ]; then
    for POOL_ID in $COMPUTE_POOLS; do
        POOL_NAME=$(confluent flink compute-pool describe "$POOL_ID" --output json 2>/dev/null | jq -r '.display_name' 2>/dev/null || echo "$POOL_ID")
        echo -e "${CYAN}  Checking compute pool: $POOL_NAME ($POOL_ID)${NC}"
        
        # Set compute pool context (required for delete command)
        confluent flink compute-pool use "$POOL_ID" &>/dev/null || true
        
        # Get all statements in this compute pool
        STATEMENTS=$(confluent flink statement list --compute-pool "$POOL_ID" --output json 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo "")
        
        if [ -n "$STATEMENTS" ]; then
            for STATEMENT_NAME in $STATEMENTS; do
                echo -e "${YELLOW}    Deleting statement: $STATEMENT_NAME${NC}"
                
                # Delete statement using its name (compute pool context must be set first)
                if confluent flink statement delete "$STATEMENT_NAME" --force 2>/dev/null; then
                    echo -e "${GREEN}      ✓ Deleted statement: $STATEMENT_NAME${NC}"
                else
                    echo -e "${RED}      ✗ Failed to delete statement: $STATEMENT_NAME${NC}"
                fi
            done
        else
            echo -e "${CYAN}    No statements found in compute pool${NC}"
        fi
    done
else
    echo -e "${CYAN}  No compute pools found${NC}"
fi

echo ""

# ============================================================================
# 2. Delete Connectors
# ============================================================================
echo -e "${BLUE}Step 2: Deleting Connectors...${NC}"

# Get all connectors
CONNECTORS=$(confluent connector list --output json 2>/dev/null | jq -r '.[].id' 2>/dev/null || echo "")

if [ -n "$CONNECTORS" ]; then
    for CONNECTOR_ID in $CONNECTORS; do
        # Get connector name
        CONNECTOR_NAME=$(confluent connector describe "$CONNECTOR_ID" --output json 2>/dev/null | jq -r '.name' 2>/dev/null || echo "$CONNECTOR_ID")
        echo -e "${YELLOW}  Deleting connector: $CONNECTOR_NAME${NC}"
        
        if confluent connector delete "$CONNECTOR_ID" --force 2>/dev/null; then
            echo -e "${GREEN}    ✓ Deleted connector: $CONNECTOR_NAME${NC}"
        else
            echo -e "${RED}    ✗ Failed to delete connector: $CONNECTOR_NAME${NC}"
        fi
    done
else
    echo -e "${CYAN}  No connectors found${NC}"
fi

echo ""

# ============================================================================
# 3. Delete Topics
# ============================================================================
echo -e "${BLUE}Step 3: Deleting Topics...${NC}"

# Set cluster context
confluent kafka cluster use "$CLUSTER_ID" &>/dev/null || true

# Get all topics
TOPICS=$(confluent kafka topic list --output json 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo "")

if [ -n "$TOPICS" ]; then
    for TOPIC in $TOPICS; do
        # Skip internal topics (they start with _)
        if [[ "$TOPIC" =~ ^_ ]]; then
            echo -e "${CYAN}  Skipping internal topic: $TOPIC${NC}"
            continue
        fi
        
        echo -e "${YELLOW}  Deleting topic: $TOPIC${NC}"
        
        if confluent kafka topic delete "$TOPIC" --force 2>/dev/null; then
            echo -e "${GREEN}    ✓ Deleted topic: $TOPIC${NC}"
        else
            echo -e "${RED}    ✗ Failed to delete topic: $TOPIC${NC}"
        fi
    done
else
    echo -e "${CYAN}  No topics found${NC}"
fi

echo ""

# ============================================================================
# Summary
# ============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Remaining resources:${NC}"
echo ""

# List remaining resources
echo -e "${CYAN}Topics:${NC}"
REMAINING_TOPICS=$(confluent kafka topic list --output json 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo "")
if [ -n "$REMAINING_TOPICS" ]; then
    echo "$REMAINING_TOPICS" | grep -v "^_" | while read -r topic; do
        echo "  - $topic"
    done
else
    echo "  (none)"
fi

echo ""
echo -e "${CYAN}Connectors:${NC}"
REMAINING_CONNECTORS=$(confluent connector list --output json 2>/dev/null | jq -r '.[].id' 2>/dev/null || echo "")
if [ -n "$REMAINING_CONNECTORS" ]; then
    echo "$REMAINING_CONNECTORS" | while read -r conn_id; do
        conn_name=$(confluent connector describe "$conn_id" --output json 2>/dev/null | jq -r '.name' 2>/dev/null || echo "$conn_id")
        echo "  - $conn_name"
    done
else
    echo "  (none)"
fi

echo ""
echo -e "${CYAN}Flink Statements:${NC}"
if [ -n "$COMPUTE_POOLS" ]; then
    HAS_STATEMENTS=false
    for POOL_ID in $COMPUTE_POOLS; do
        POOL_NAME=$(confluent flink compute-pool describe "$POOL_ID" --output json 2>/dev/null | jq -r '.display_name' 2>/dev/null || echo "$POOL_ID")
        REMAINING_STATEMENTS=$(confluent flink statement list --compute-pool "$POOL_ID" --output json 2>/dev/null | jq -r '.[].statement_name' 2>/dev/null || echo "")
        if [ -n "$REMAINING_STATEMENTS" ]; then
            HAS_STATEMENTS=true
            echo "$REMAINING_STATEMENTS" | while read -r stmt_name; do
                echo "  - $stmt_name (pool: $POOL_NAME)"
            done
        fi
    done
    if [ "$HAS_STATEMENTS" = false ]; then
        echo "  (none)"
    fi
    echo ""
    echo -e "${CYAN}Compute Pools (preserved):${NC}"
    for POOL_ID in $COMPUTE_POOLS; do
        POOL_NAME=$(confluent flink compute-pool describe "$POOL_ID" --output json 2>/dev/null | jq -r '.display_name' 2>/dev/null || echo "$POOL_ID")
        echo "  - $POOL_NAME ($POOL_ID)"
    done
else
    echo "  (none)"
fi

echo ""
