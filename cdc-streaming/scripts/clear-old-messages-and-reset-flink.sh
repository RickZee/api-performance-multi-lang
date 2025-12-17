#!/bin/bash
# Clear Old Messages from Topics and Reset Flink Offsets
# Removes old messages that don't have __op fields and resets Flink to start fresh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

COMPUTE_POOL_ID="${FLINK_COMPUTE_POOL_ID:-lfcp-2xqo0m}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Clear Old Messages and Reset Flink Offsets${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "This will:"
echo "  1. Delete old messages from raw-business-events topic"
echo "  2. Clear filtered topic messages (if any)"
echo "  3. Stop and restart Flink statements to reset offsets"
echo ""
echo -e "${YELLOW}⚠️  WARNING: This will delete all messages in the topics!${NC}"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

echo ""

# Step 1: Stop Flink statements
echo -e "${BLUE}Step 1: Stopping Flink statements...${NC}"

STATEMENTS=(
    "insert-car-created-filter-new"
    "insert-loan-created-filter-new"
    "insert-loan-payment-submitted-filter-new"
    "insert-service-events-filter-new"
)

for stmt in "${STATEMENTS[@]}"; do
    echo -e "${CYAN}  Stopping: $stmt${NC}"
    if confluent flink statement stop "$stmt" 2>/dev/null; then
        echo -e "${GREEN}    ✓ Stopped${NC}"
    else
        echo -e "${YELLOW}    ⚠ Already stopped or not found${NC}"
    fi
done

echo ""
sleep 5

# Step 2: Delete messages from raw-business-events topic
echo -e "${BLUE}Step 2: Clearing messages from raw-business-events topic...${NC}"

# Note: Confluent Cloud doesn't support direct message deletion
# We need to delete and recreate the topic, or use retention policy
echo -e "${CYAN}  Option 1: Delete and recreate topic (recommended)${NC}"

if confluent kafka topic delete raw-business-events --force 2>/dev/null; then
    echo -e "${GREEN}    ✓ Topic deleted${NC}"
    sleep 3
    
    # Recreate topic
    echo -e "${CYAN}  Recreating topic...${NC}"
    if confluent kafka topic create raw-business-events --partitions 3 --replication-factor 3 2>/dev/null; then
        echo -e "${GREEN}    ✓ Topic recreated${NC}"
    else
        echo -e "${YELLOW}    ⚠ Topic may already exist${NC}"
    fi
else
    echo -e "${YELLOW}    ⚠ Topic deletion failed or topic doesn't exist${NC}"
    echo -e "${CYAN}  Option 2: Using retention policy (alternative)${NC}"
    echo "    Setting retention to 1 second to clear messages..."
    confluent kafka topic update raw-business-events --config retention.ms=1000 2>/dev/null || true
    sleep 5
    confluent kafka topic update raw-business-events --config retention.ms=604800000 2>/dev/null || true
    echo -e "${GREEN}    ✓ Retention policy applied${NC}"
fi

echo ""

# Step 3: Clear filtered topics
echo -e "${BLUE}Step 3: Clearing filtered topics...${NC}"

FILTERED_TOPICS=(
    "filtered-car-created-events"
    "filtered-loan-created-events"
    "filtered-loan-payment-submitted-events"
    "filtered-service-events"
)

for topic in "${FILTERED_TOPICS[@]}"; do
    if confluent kafka topic describe "$topic" &>/dev/null; then
        echo -e "${CYAN}  Deleting: $topic${NC}"
        if confluent kafka topic delete "$topic" --force 2>/dev/null; then
            echo -e "${GREEN}    ✓ Deleted${NC}"
        else
            echo -e "${YELLOW}    ⚠ Deletion failed${NC}"
        fi
    else
        echo -e "${CYAN}  $topic: doesn't exist (will be created by Flink)${NC}"
    fi
done

echo ""

# Step 4: Restart Flink statements
echo -e "${BLUE}Step 4: Restarting Flink statements...${NC}"

for stmt in "${STATEMENTS[@]}"; do
    echo -e "${CYAN}  Resuming: $stmt${NC}"
    if confluent flink statement resume "$stmt" 2>/dev/null; then
        echo -e "${GREEN}    ✓ Resumed${NC}"
    else
        echo -e "${YELLOW}    ⚠ Resume failed, trying to start...${NC}"
        # If resume fails, statement might need to be redeployed
        echo -e "${YELLOW}    Note: You may need to redeploy the statement${NC}"
    fi
done

echo ""
sleep 10

# Step 5: Verify
echo -e "${BLUE}Step 5: Verifying cleanup...${NC}"

echo -e "${CYAN}  Checking topics:${NC}"
if confluent kafka topic describe raw-business-events &>/dev/null; then
    echo -e "${GREEN}    ✓ raw-business-events exists${NC}"
else
    echo -e "${RED}    ✗ raw-business-events missing${NC}"
fi

echo -e "${CYAN}  Checking Flink statements:${NC}"
for stmt in "${STATEMENTS[@]}"; do
    STATUS=$(confluent flink statement list 2>&1 | grep "$stmt" | awk '{print $NF}' | head -1 || echo "unknown")
    if [ "$STATUS" = "RUNNING" ]; then
        echo -e "${GREEN}    ✓ $stmt: RUNNING${NC}"
    else
        echo -e "${YELLOW}    ⚠ $stmt: $STATUS${NC}"
    fi
done

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Send new test events:"
echo "     k6 run --env API_URL=\$LAMBDA_PYTHON_REST_API_URL ../../load-test/k6/send-batch-events.js"
echo "     # Or with custom count: k6 run --env API_URL=\$LAMBDA_PYTHON_REST_API_URL --env EVENTS_PER_TYPE=1000 ../../load-test/k6/send-batch-events.js"
echo ""
echo "  2. Wait 1-2 minutes for processing"
echo ""
echo "  3. Check Flink statement metrics:"
echo "     confluent flink statement list"
echo "     # Should show output > 0 for new events"
echo ""
echo "  4. Check consumer logs:"
echo "     docker-compose logs service-consumer --tail 50"
echo ""
