#!/bin/bash
# Validate filter configuration against schema and perform dry-run generation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FILTERS_CONFIG="$PROJECT_ROOT/cdc-streaming/config/filters.json"
FILTER_SCHEMA="$PROJECT_ROOT/cdc-streaming/schemas/filter-schema.json"
GENERATOR_SCRIPT="$PROJECT_ROOT/cdc-streaming/scripts/filters/generate-filters.py"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Filter Configuration Validation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if files exist
if [ ! -f "$FILTERS_CONFIG" ]; then
    echo -e "${RED}✗ Filters config not found: $FILTERS_CONFIG${NC}"
    exit 1
fi

if [ ! -f "$FILTER_SCHEMA" ]; then
    echo -e "${RED}✗ Filter schema not found: $FILTER_SCHEMA${NC}"
    exit 1
fi

if [ ! -f "$GENERATOR_SCRIPT" ]; then
    echo -e "${RED}✗ Generator script not found: $GENERATOR_SCRIPT${NC}"
    exit 1
fi

# Check dependencies
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ python3 is required but not installed${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠ jq is recommended for JSON validation but not installed${NC}"
    echo -e "${BLUE}ℹ${NC} Installing jq is recommended: brew install jq"
    echo ""
fi

# Step 1: Basic JSON syntax validation
echo -e "${BLUE}Step 1: Validating JSON syntax...${NC}"
if python3 -m json.tool "$FILTERS_CONFIG" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} JSON syntax is valid"
else
    echo -e "${RED}✗${NC} Invalid JSON syntax"
    python3 -m json.tool "$FILTERS_CONFIG" 2>&1 | head -20
    exit 1
fi

# Step 2: Schema validation (if jsonschema is available)
echo -e "${BLUE}Step 2: Validating against schema...${NC}"
if python3 -c "import jsonschema" 2>/dev/null; then
    if python3 <<EOF
import json
import jsonschema
import sys

try:
    with open("$FILTERS_CONFIG", "r") as f:
        config = json.load(f)
    with open("$FILTER_SCHEMA", "r") as f:
        schema = json.load(f)
    jsonschema.validate(instance=config, schema=schema)
    print("✓ Configuration is valid against schema")
except jsonschema.ValidationError as e:
    print(f"✗ Schema validation failed: {e.message}")
    print(f"  Path: {'.'.join(str(p) for p in e.path)}")
    sys.exit(1)
except Exception as e:
    print(f"✗ Error during validation: {e}")
    sys.exit(1)
EOF
    then
        echo -e "${GREEN}✓${NC} Schema validation passed"
    else
        echo -e "${RED}✗${NC} Schema validation failed"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠${NC} jsonschema package not installed, skipping schema validation"
    echo -e "${BLUE}ℹ${NC} Install with: pip3 install jsonschema"
    echo -e "${BLUE}ℹ${NC} Continuing with basic validation..."
fi

# Step 3: Basic structure validation with jq (if available)
if command -v jq &> /dev/null; then
    echo -e "${BLUE}Step 3: Validating filter structure...${NC}"
    
    # Check required fields
    FILTER_COUNT=$(jq '.filters | length' "$FILTERS_CONFIG")
    echo -e "${BLUE}ℹ${NC} Found $FILTER_COUNT filter(s)"
    
    # Check for enabled filters
    ENABLED_COUNT=$(jq '[.filters[] | select(.enabled == true)] | length' "$FILTERS_CONFIG")
    echo -e "${BLUE}ℹ${NC} $ENABLED_COUNT filter(s) enabled"
    
    # Validate each filter
    INVALID_FILTERS=0
    while IFS= read -r filter_id; do
        if [ -n "$filter_id" ]; then
            # Check required fields
            if ! jq -e ".filters[] | select(.id == \"$filter_id\") | .outputTopic" "$FILTERS_CONFIG" > /dev/null 2>&1; then
                echo -e "${RED}✗${NC} Filter '$filter_id' missing required field: outputTopic"
                INVALID_FILTERS=$((INVALID_FILTERS + 1))
            fi
            if ! jq -e ".filters[] | select(.id == \"$filter_id\") | .conditions" "$FILTERS_CONFIG" > /dev/null 2>&1; then
                echo -e "${RED}✗${NC} Filter '$filter_id' missing required field: conditions"
                INVALID_FILTERS=$((INVALID_FILTERS + 1))
            fi
        fi
    done < <(jq -r '.filters[].id' "$FILTERS_CONFIG")
    
    if [ $INVALID_FILTERS -eq 0 ]; then
        echo -e "${GREEN}✓${NC} All filters have required fields"
    else
        echo -e "${RED}✗${NC} Found $INVALID_FILTERS filter(s) with missing required fields"
        exit 1
    fi
fi

# Step 4: Dry-run generation
echo ""
echo -e "${BLUE}Step 4: Dry-run generation...${NC}"
if python3 "$GENERATOR_SCRIPT" --dry-run > /tmp/filter-generation-dry-run.log 2>&1; then
    echo -e "${GREEN}✓${NC} Dry-run generation successful"
    echo -e "${BLUE}ℹ${NC} Generated output preview (first 50 lines):"
    echo ""
    head -50 /tmp/filter-generation-dry-run.log | sed 's/^/  /'
    if [ $(wc -l < /tmp/filter-generation-dry-run.log) -gt 50 ]; then
        echo -e "${BLUE}  ... (truncated)${NC}"
    fi
else
    echo -e "${RED}✗${NC} Dry-run generation failed"
    cat /tmp/filter-generation-dry-run.log
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Validation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Review the dry-run output above"
echo "  2. If validation passed, generate files: ./scripts/filters/generate-filters.sh"
echo "  3. Review generated files before deployment"
echo ""

