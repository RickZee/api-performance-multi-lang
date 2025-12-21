#!/bin/bash
# Show differences between current and proposed filter configurations

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
FILTER_HISTORY_DIR="$PROJECT_ROOT/cdc-streaming/config/filter-history"
GENERATED_SQL="$PROJECT_ROOT/cdc-streaming/flink-jobs/generated/business-events-routing-confluent-cloud-generated.sql"
GENERATED_YAML="$PROJECT_ROOT/cdc-streaming/stream-processor-spring/src/main/resources/filters.yml"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Filter Configuration Diff${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if filters.json exists
if [ ! -f "$FILTERS_CONFIG" ]; then
    echo -e "${RED}✗ Filters config not found: $FILTERS_CONFIG${NC}"
    exit 1
fi

# Check if git is available for diff
if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${BLUE}Step 1: Comparing filters.json with git...${NC}"
    if git diff --exit-code "$FILTERS_CONFIG" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} No changes in filters.json (matches HEAD)"
    else
        echo -e "${YELLOW}⚠${NC} Changes detected in filters.json:"
        echo ""
        git diff "$FILTERS_CONFIG" | head -100
        if [ $(git diff "$FILTERS_CONFIG" | wc -l) -gt 100 ]; then
            echo -e "${BLUE}  ... (truncated, use 'git diff' for full output)${NC}"
        fi
    fi
    echo ""
fi

# Compare generated files
echo -e "${BLUE}Step 2: Comparing generated files...${NC}"

# Compare Flink SQL
if [ -f "$GENERATED_SQL" ]; then
    ORIGINAL_SQL="$PROJECT_ROOT/cdc-streaming/flink-jobs/business-events-routing-confluent-cloud.sql"
    if [ -f "$ORIGINAL_SQL" ]; then
        if diff -q "$ORIGINAL_SQL" "$GENERATED_SQL" > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Generated Flink SQL matches original"
        else
            echo -e "${YELLOW}⚠${NC} Generated Flink SQL differs from original:"
            echo ""
            diff -u "$ORIGINAL_SQL" "$GENERATED_SQL" | head -50 || true
            if [ $(diff -u "$ORIGINAL_SQL" "$GENERATED_SQL" 2>/dev/null | wc -l) -gt 50 ]; then
                echo -e "${BLUE}  ... (truncated)${NC}"
            fi
        fi
    else
        echo -e "${BLUE}ℹ${NC} Original Flink SQL not found for comparison"
    fi
else
    echo -e "${YELLOW}⚠${NC} Generated Flink SQL not found. Run generate-filters.sh first."
fi

echo ""

# Compare Spring YAML
if [ -f "$GENERATED_YAML" ]; then
    echo -e "${BLUE}ℹ${NC} Generated Spring YAML: $GENERATED_YAML"
    echo -e "${BLUE}ℹ${NC} File size: $(wc -l < "$GENERATED_YAML") lines"
    echo -e "${BLUE}ℹ${NC} Preview (first 30 lines):"
    echo ""
    head -30 "$GENERATED_YAML" | sed 's/^/  /'
    if [ $(wc -l < "$GENERATED_YAML") -gt 30 ]; then
        echo -e "${BLUE}  ... (truncated)${NC}"
    fi
else
    echo -e "${YELLOW}⚠${NC} Generated Spring YAML not found. Run generate-filters.sh first."
fi

echo ""

# Show filter summary
echo -e "${BLUE}Step 3: Current filter configuration summary...${NC}"
if command -v jq &> /dev/null; then
    FILTER_COUNT=$(jq '.filters | length' "$FILTERS_CONFIG")
    ENABLED_COUNT=$(jq '[.filters[] | select(.enabled == true)] | length' "$FILTERS_CONFIG")
    
    echo -e "${BLUE}ℹ${NC} Total filters: $FILTER_COUNT"
    echo -e "${BLUE}ℹ${NC} Enabled filters: $ENABLED_COUNT"
    echo ""
    echo -e "${BLUE}ℹ${NC} Filter details:"
    jq -r '.filters[] | "  - \(.id): \(.name) [\(if .enabled then "enabled" else "disabled" end)] -> \(.outputTopic)"' "$FILTERS_CONFIG"
else
    echo -e "${YELLOW}⚠${NC} jq not installed, skipping summary"
fi

echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Review the differences above"
echo "  2. If changes look good, generate files: ./scripts/filters/generate-filters.sh"
echo "  3. Deploy: ./scripts/filters/deploy-flink-filters.sh and ./scripts/filters/deploy-spring-filters.sh"
echo ""

