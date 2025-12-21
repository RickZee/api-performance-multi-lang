#!/bin/bash
# Generate Flink SQL and Spring Boot YAML from filters.json

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

GENERATOR_SCRIPT="$PROJECT_ROOT/cdc-streaming/scripts/filters/generate-filters.py"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Generate Filter Configurations${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if generator script exists
if [ ! -f "$GENERATOR_SCRIPT" ]; then
    echo -e "${RED}✗ Generator script not found: $GENERATOR_SCRIPT${NC}"
    exit 1
fi

# Check dependencies
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ python3 is required but not installed${NC}"
    exit 1
fi

# Parse arguments
FLINK_ONLY=false
SPRING_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --flink-only)
            FLINK_ONLY=true
            shift
            ;;
        --spring-only)
            SPRING_ONLY=true
            shift
            ;;
        *)
            echo -e "${YELLOW}⚠${NC} Unknown option: $1"
            shift
            ;;
    esac
done

# Build Python command
PYTHON_ARGS=""
if [ "$FLINK_ONLY" = true ]; then
    PYTHON_ARGS="--flink-only"
elif [ "$SPRING_ONLY" = true ]; then
    PYTHON_ARGS="--spring-only"
fi

# Run generator
if python3 "$GENERATOR_SCRIPT" $PYTHON_ARGS; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Generation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Review generated files"
    echo "  2. Deploy Flink filters: ./scripts/filters/deploy-flink-filters.sh"
    echo "  3. Deploy Spring filters: ./scripts/filters/deploy-spring-filters.sh"
    echo ""
else
    echo -e "${RED}✗ Generation failed${NC}"
    exit 1
fi

