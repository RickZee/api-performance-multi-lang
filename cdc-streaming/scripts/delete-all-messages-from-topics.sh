#!/bin/bash
# Delete All Messages from All Topics
# WARNING: This will delete all messages in all topics by deleting and recreating topics

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

CLUSTER_ID="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Delete All Messages from All Topics${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}⚠️  WARNING: This will delete ALL messages in ALL topics!${NC}"
echo -e "${YELLOW}⚠️  Topics will be deleted and recreated (empty)${NC}"
echo ""
read -p "Are you sure you want to continue? Type 'DELETE ALL' to confirm: " -r
echo ""

if [[ ! $REPLY == "DELETE ALL" ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

echo ""

# Get list of all topics
echo -e "${BLUE}Step 1: Getting list of all topics...${NC}"
TOPICS=$(confluent kafka topic list 2>&1 | tail -n +2 | awk '{print $1}' | grep -v "^$" | grep -v "^Name$")

if [ -z "$TOPICS" ]; then
    echo -e "${YELLOW}No topics found${NC}"
    exit 0
fi

TOPIC_COUNT=$(echo "$TOPICS" | wc -l | tr -d ' ')
echo -e "${CYAN}Found $TOPIC_COUNT topic(s)${NC}"
echo ""

# Stop Flink statements first to avoid issues
echo -e "${BLUE}Step 2: Stopping Flink INSERT statements...${NC}"
INSERT_STATEMENTS=(
    "insert-car-created-filter-new"
    "insert-loan-created-filter-new"
    "insert-loan-payment-submitted-filter-new"
    "insert-service-events-filter-new"
)

for stmt in "${INSERT_STATEMENTS[@]}"; do
    echo -e "${CYAN}  Stopping: $stmt${NC}"
    if confluent flink statement stop "$stmt" 2>/dev/null; then
        echo -e "${GREEN}    ✓ Stopped${NC}"
    else
        echo -e "${YELLOW}    ⚠ Already stopped or not found${NC}"
    fi
done

echo ""
sleep 5

# Delete and recreate each topic
echo -e "${BLUE}Step 3: Deleting and recreating topics...${NC}"
echo ""

TOPIC_DETAILS=$(confluent kafka topic list --output json 2>&1 | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for topic in data:
        if isinstance(topic, dict):
            name = topic.get('name', '')
            partitions = topic.get('partitions_count', 3)
            if name:
                print(f'{name}|{partitions}')
except:
    pass
" 2>/dev/null)

if [ -z "$TOPIC_DETAILS" ]; then
    # Fallback: delete topics without partition info
    echo "$TOPICS" | while read -r topic; do
        if [ -n "$topic" ]; then
            echo -e "${CYAN}  Deleting: $topic${NC}"
            if confluent kafka topic delete "$topic" --force 2>/dev/null; then
                echo -e "${GREEN}    ✓ Deleted${NC}"
                sleep 1
                # Try to recreate with default partitions
                if confluent kafka topic create "$topic" --partitions 3 2>/dev/null; then
                    echo -e "${GREEN}    ✓ Recreated${NC}"
                else
                    echo -e "${YELLOW}    ⚠ Recreation may have failed (topic may be auto-created)${NC}"
                fi
            else
                echo -e "${YELLOW}    ⚠ Deletion failed or topic doesn't exist${NC}"
            fi
        fi
    done
else
    # Use topic details to preserve partition count
    echo "$TOPIC_DETAILS" | while IFS='|' read -r topic partitions; do
        if [ -n "$topic" ] && [ -n "$partitions" ]; then
            echo -e "${CYAN}  Deleting: $topic (${partitions} partitions)${NC}"
            if confluent kafka topic delete "$topic" --force 2>/dev/null; then
                echo -e "${GREEN}    ✓ Deleted${NC}"
                sleep 1
                # Recreate with original partition count
                if confluent kafka topic create "$topic" --partitions "$partitions" 2>/dev/null; then
                    echo -e "${GREEN}    ✓ Recreated with ${partitions} partitions${NC}"
                else
                    echo -e "${YELLOW}    ⚠ Recreation may have failed (topic may be auto-created)${NC}"
                fi
            else
                echo -e "${YELLOW}    ⚠ Deletion failed or topic doesn't exist${NC}"
            fi
        fi
    done
fi

echo ""
sleep 5

# Restart Flink statements
echo -e "${BLUE}Step 4: Restarting Flink INSERT statements...${NC}"
for stmt in "${INSERT_STATEMENTS[@]}"; do
    echo -e "${CYAN}  Resuming: $stmt${NC}"
    if confluent flink statement resume "$stmt" 2>/dev/null; then
        echo -e "${GREEN}    ✓ Resumed${NC}"
    else
        echo -e "${YELLOW}    ⚠ Resume failed (may need to be recreated)${NC}"
    fi
done

echo ""
sleep 10

# Verify
echo -e "${BLUE}Step 5: Verifying cleanup...${NC}"
echo -e "${CYAN}  Topic count:${NC}"
FINAL_COUNT=$(confluent kafka topic list 2>&1 | tail -n +2 | wc -l | tr -d ' ')
echo -e "${GREEN}    ✓ $FINAL_COUNT topic(s) exist${NC}"

echo -e "${CYAN}  Flink statements:${NC}"
for stmt in "${INSERT_STATEMENTS[@]}"; do
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
echo -e "${CYAN}All messages have been deleted from all topics.${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Send new test events:"
echo "     cd cdc-streaming"
echo "     k6 run scripts/send-5-events-k6.js"
echo ""
echo "  2. Wait 1-2 minutes for processing"
echo ""
echo "  3. Check Flink statement metrics:"
echo "     confluent flink statement list"
echo ""

