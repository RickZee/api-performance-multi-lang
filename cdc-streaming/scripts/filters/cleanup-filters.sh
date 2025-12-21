#!/bin/bash
# Cleanup orphaned resources (topics, Flink statements, consumer groups) after filter deletion
# This script identifies and optionally removes resources that are no longer referenced by any filter

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

FILTERS_CONFIG="$PROJECT_ROOT/cdc-streaming/config/filters.json"
COMPUTE_POOL_ID="${FLINK_COMPUTE_POOL_ID:-lfcp-2xqo0m}"
KAFKA_CLUSTER_ID="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"

# Parse arguments
LIST_ORPHANED=false
DRY_RUN=false
CLEANUP_TOPICS=false
CLEANUP_FLINK=false
CLEANUP_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --list-orphaned)
            LIST_ORPHANED=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --cleanup-topics)
            CLEANUP_TOPICS=true
            shift
            ;;
        --cleanup-flink)
            CLEANUP_FLINK=true
            shift
            ;;
        --cleanup-all)
            CLEANUP_ALL=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [--list-orphaned] [--dry-run] [--cleanup-topics] [--cleanup-flink] [--cleanup-all]"
            exit 1
            ;;
    esac
done

# If no action specified, default to list-orphaned
if [ "$LIST_ORPHANED" = false ] && [ "$CLEANUP_TOPICS" = false ] && [ "$CLEANUP_FLINK" = false ] && [ "$CLEANUP_ALL" = false ]; then
    LIST_ORPHANED=true
fi

if [ "$CLEANUP_ALL" = true ]; then
    CLEANUP_TOPICS=true
    CLEANUP_FLINK=true
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Filter Cleanup Utility${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check prerequisites
if [ "$CLEANUP_TOPICS" = true ] || [ "$CLEANUP_FLINK" = true ]; then
    if ! command -v confluent &> /dev/null; then
        echo -e "${RED}✗ Confluent CLI is not installed${NC}"
        echo -e "${BLUE}ℹ${NC} Install with: brew install confluentinc/tap/cli"
        exit 1
    fi
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗ jq is required but not installed${NC}"
    echo -e "${BLUE}ℹ${NC} Install with: brew install jq"
    exit 1
fi

# Check if filters.json exists
if [ ! -f "$FILTERS_CONFIG" ]; then
    echo -e "${RED}✗ Filters config not found: $FILTERS_CONFIG${NC}"
    exit 1
fi

# Extract active filter topics from filters.json
echo -e "${BLUE}Step 1: Scanning filters.json for active filters...${NC}"
ACTIVE_TOPICS=()
ACTIVE_FLINK_TOPICS=()
ACTIVE_SPRING_TOPICS=()

if command -v jq &> /dev/null; then
    # Get all enabled, non-deleted filters
    while IFS= read -r topic; do
        if [ -n "$topic" ]; then
            ACTIVE_TOPICS+=("$topic")
            ACTIVE_FLINK_TOPICS+=("${topic}-flink")
            ACTIVE_SPRING_TOPICS+=("${topic}-spring")
        fi
    done < <(jq -r '.filters[] | select(.enabled == true) | select(.status != "deleted") | .outputTopic' "$FILTERS_CONFIG" 2>/dev/null || true)
    
    FILTER_COUNT=$(jq '.filters | length' "$FILTERS_CONFIG" 2>/dev/null || echo "0")
    ENABLED_COUNT=$(jq '[.filters[] | select(.enabled == true) | select(.status != "deleted")] | length' "$FILTERS_CONFIG" 2>/dev/null || echo "0")
    DEPRECATED_COUNT=$(jq '[.filters[] | select(.status == "deprecated")] | length' "$FILTERS_CONFIG" 2>/dev/null || echo "0")
    
    echo -e "${GREEN}✓${NC} Found $ENABLED_COUNT active filters (out of $FILTER_COUNT total)"
    if [ "$DEPRECATED_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}⚠${NC} Found $DEPRECATED_COUNT deprecated filters"
    fi
    echo ""
else
    echo -e "${YELLOW}⚠${NC} jq not available, cannot parse filters.json"
    exit 1
fi

# Function to list orphaned topics
list_orphaned_topics() {
    echo -e "${BLUE}Step 2: Identifying orphaned Kafka topics...${NC}"
    
    if ! command -v confluent &> /dev/null; then
        echo -e "${YELLOW}⚠${NC} Confluent CLI not available, skipping topic discovery"
        return
    fi
    
    # Get all topics from Kafka cluster
    echo -e "${CYAN}Fetching topics from Kafka cluster...${NC}"
    ALL_TOPICS=$(confluent kafka topic list --cluster "$KAFKA_CLUSTER_ID" --output json 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo "")
    
    if [ -z "$ALL_TOPICS" ]; then
        echo -e "${YELLOW}⚠${NC} Could not fetch topics from Kafka cluster"
        return
    fi
    
    ORPHANED_TOPICS=()
    while IFS= read -r topic; do
        if [ -z "$topic" ]; then
            continue
        fi
        
        # Check if topic matches filter pattern (filtered-*-events-flink or filtered-*-events-spring)
        if [[ "$topic" =~ ^filtered-.*-events(-flink|-spring)?$ ]]; then
            # Check if topic is referenced by any active filter
            IS_ORPHANED=true
            for active_topic in "${ACTIVE_TOPICS[@]}" "${ACTIVE_FLINK_TOPICS[@]}" "${ACTIVE_SPRING_TOPICS[@]}"; do
                if [ "$topic" = "$active_topic" ]; then
                    IS_ORPHANED=false
                    break
                fi
            done
            
            if [ "$IS_ORPHANED" = true ]; then
                ORPHANED_TOPICS+=("$topic")
            fi
        fi
    done <<< "$ALL_TOPICS"
    
    if [ ${#ORPHANED_TOPICS[@]} -eq 0 ]; then
        echo -e "${GREEN}✓${NC} No orphaned topics found"
    else
        echo -e "${YELLOW}⚠${NC} Found ${#ORPHANED_TOPICS[@]} orphaned topic(s):"
        for topic in "${ORPHANED_TOPICS[@]}"; do
            echo -e "  - ${YELLOW}$topic${NC}"
        done
    fi
    echo ""
    
    # Store for later use
    ORPHANED_TOPICS_LIST=("${ORPHANED_TOPICS[@]}")
}

# Function to list orphaned Flink statements
list_orphaned_flink_statements() {
    echo -e "${BLUE}Step 3: Identifying orphaned Flink statements...${NC}"
    
    if ! command -v confluent &> /dev/null; then
        echo -e "${YELLOW}⚠${NC} Confluent CLI not available, skipping Flink statement discovery"
        return
    fi
    
    echo -e "${CYAN}Fetching Flink statements from compute pool...${NC}"
    ALL_STATEMENTS=$(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null | jq -r '.[] | select(.statement_name | startswith("filter_") or startswith("sink_")) | {name: .statement_name, id: .id}' 2>/dev/null || echo "")
    
    if [ -z "$ALL_STATEMENTS" ]; then
        echo -e "${GREEN}✓${NC} No Flink statements found (or could not fetch)"
        return
    fi
    
    ORPHANED_STATEMENTS=()
    while IFS= read -r statement_name; do
        if [ -z "$statement_name" ]; then
            continue
        fi
        
        # Extract topic name from statement name (e.g., "filter_filtered-car-events-flink" -> "filtered-car-events-flink")
        TOPIC_NAME=$(echo "$statement_name" | sed 's/^filter_//' | sed 's/^sink_//')
        
        # Check if topic is referenced by any active filter
        IS_ORPHANED=true
        for active_topic in "${ACTIVE_FLINK_TOPICS[@]}"; do
            if [ "$TOPIC_NAME" = "$active_topic" ]; then
                IS_ORPHANED=false
                break
            fi
        done
        
        if [ "$IS_ORPHANED" = true ]; then
            ORPHANED_STATEMENTS+=("$statement_name")
        fi
    done < <(echo "$ALL_STATEMENTS" | jq -r '.name' 2>/dev/null || true)
    
    if [ ${#ORPHANED_STATEMENTS[@]} -eq 0 ]; then
        echo -e "${GREEN}✓${NC} No orphaned Flink statements found"
    else
        echo -e "${YELLOW}⚠${NC} Found ${#ORPHANED_STATEMENTS[@]} orphaned Flink statement(s):"
        for stmt in "${ORPHANED_STATEMENTS[@]}"; do
            echo -e "  - ${YELLOW}$stmt${NC}"
        done
    fi
    echo ""
    
    # Store for later use
    ORPHANED_STATEMENTS_LIST=("${ORPHANED_STATEMENTS[@]}")
}

# Function to cleanup topics
cleanup_topics() {
    if [ ${#ORPHANED_TOPICS_LIST[@]} -eq 0 ]; then
        echo -e "${GREEN}✓${NC} No orphaned topics to clean up"
        return
    fi
    
    echo -e "${BLUE}Step 4: Cleaning up orphaned topics...${NC}"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${CYAN}[DRY RUN]${NC} Would delete the following topics:"
        for topic in "${ORPHANED_TOPICS_LIST[@]}"; do
            echo -e "  - ${YELLOW}$topic${NC}"
        done
        echo ""
        echo -e "${CYAN}[DRY RUN]${NC} Run without --dry-run to actually delete topics"
        return
    fi
    
    echo -e "${YELLOW}⚠${NC} WARNING: This will permanently delete ${#ORPHANED_TOPICS_LIST[@]} topic(s)"
    read -p "Are you sure you want to continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo -e "${YELLOW}Cancelled${NC}"
        return
    fi
    
    DELETED_COUNT=0
    FAILED_COUNT=0
    
    for topic in "${ORPHANED_TOPICS_LIST[@]}"; do
        echo -e "${CYAN}Deleting topic: $topic${NC}"
        if confluent kafka topic delete "$topic" --cluster "$KAFKA_CLUSTER_ID" --force 2>/dev/null; then
            echo -e "${GREEN}✓${NC} Deleted: $topic"
            ((DELETED_COUNT++))
        else
            echo -e "${RED}✗${NC} Failed to delete: $topic"
            ((FAILED_COUNT++))
        fi
    done
    
    echo ""
    echo -e "${GREEN}✓${NC} Deleted $DELETED_COUNT topic(s)"
    if [ $FAILED_COUNT -gt 0 ]; then
        echo -e "${RED}✗${NC} Failed to delete $FAILED_COUNT topic(s)"
    fi
}

# Function to cleanup Flink statements
cleanup_flink_statements() {
    if [ ${#ORPHANED_STATEMENTS_LIST[@]} -eq 0 ]; then
        echo -e "${GREEN}✓${NC} No orphaned Flink statements to clean up"
        return
    fi
    
    echo -e "${BLUE}Step 5: Cleaning up orphaned Flink statements...${NC}"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${CYAN}[DRY RUN]${NC} Would delete the following Flink statements:"
        for stmt in "${ORPHANED_STATEMENTS_LIST[@]}"; do
            echo -e "  - ${YELLOW}$stmt${NC}"
        done
        echo ""
        echo -e "${CYAN}[DRY RUN]${NC} Run without --dry-run to actually delete statements"
        return
    fi
    
    echo -e "${YELLOW}⚠${NC} WARNING: This will permanently delete ${#ORPHANED_STATEMENTS_LIST[@]} Flink statement(s)"
    read -p "Are you sure you want to continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo -e "${YELLOW}Cancelled${NC}"
        return
    fi
    
    DELETED_COUNT=0
    FAILED_COUNT=0
    
    for stmt in "${ORPHANED_STATEMENTS_LIST[@]}"; do
        echo -e "${CYAN}Deleting Flink statement: $stmt${NC}"
        # Get statement ID first
        STMT_ID=$(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null | jq -r ".[] | select(.statement_name == \"$stmt\") | .id" 2>/dev/null || echo "")
        
        if [ -n "$STMT_ID" ]; then
            if confluent flink statement delete "$STMT_ID" --compute-pool "$COMPUTE_POOL_ID" --force 2>/dev/null; then
                echo -e "${GREEN}✓${NC} Deleted: $stmt"
                ((DELETED_COUNT++))
            else
                echo -e "${RED}✗${NC} Failed to delete: $stmt"
                ((FAILED_COUNT++))
            fi
        else
            echo -e "${YELLOW}⚠${NC} Could not find statement ID for: $stmt"
            ((FAILED_COUNT++))
        fi
    done
    
    echo ""
    echo -e "${GREEN}✓${NC} Deleted $DELETED_COUNT Flink statement(s)"
    if [ $FAILED_COUNT -gt 0 ]; then
        echo -e "${RED}✗${NC} Failed to delete $FAILED_COUNT Flink statement(s)"
    fi
}

# Main execution
if [ "$LIST_ORPHANED" = true ]; then
    list_orphaned_topics
    list_orphaned_flink_statements
    
    echo -e "${CYAN}Summary:${NC}"
    echo -e "  Active filters: $ENABLED_COUNT"
    echo -e "  Deprecated filters: $DEPRECATED_COUNT"
    echo -e "  Orphaned topics: ${#ORPHANED_TOPICS_LIST[@]}"
    echo -e "  Orphaned Flink statements: ${#ORPHANED_STATEMENTS_LIST[@]}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  - Run with --cleanup-topics to delete orphaned topics"
    echo "  - Run with --cleanup-flink to delete orphaned Flink statements"
    echo "  - Run with --cleanup-all to clean up everything"
    echo "  - Add --dry-run to preview changes without executing"
fi

if [ "$CLEANUP_TOPICS" = true ]; then
    list_orphaned_topics
    cleanup_topics
fi

if [ "$CLEANUP_FLINK" = true ]; then
    list_orphaned_flink_statements
    cleanup_flink_statements
fi

echo ""

