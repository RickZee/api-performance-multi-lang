#!/usr/bin/env bash
# CI/CD Demo Script
# Demonstrates the complete CI/CD pipeline locally
#
# Usage:
#   ./cdc-streaming/scripts/demo-ci-cd.sh [OPTIONS]
#
# Options:
#   --fast              Skip builds and use cached images
#   --test-suite SUITE  Run specific test suite (all, local, schema, breaking)
#   --verbose           Enable verbose output
#   --no-cleanup        Keep containers running after demo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDC_STREAMING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${CYAN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║         CI/CD Pipeline Demo - Local Jenkins Simulation     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Parse arguments
SKIP_BUILD=false
TEST_SUITE="all"
VERBOSE=false
CLEANUP=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --fast)
            SKIP_BUILD=true
            shift
            ;;
        --test-suite)
            TEST_SUITE="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            set -x
            shift
            ;;
        --no-cleanup)
            CLEANUP=false
            shift
            ;;
        *)
            warn "Unknown option: $1"
            shift
            ;;
    esac
done

# Run setup check
echo ""
echo -e "${BLUE}Step 1: Verifying prerequisites...${NC}"
"$SCRIPT_DIR/setup-jenkins-local.sh" || {
    echo -e "${RED}Prerequisites check failed. Please fix issues and try again.${NC}"
    exit 1
}

# Run Jenkins simulation
echo ""
echo -e "${BLUE}Step 2: Running Jenkins pipeline simulation...${NC}"
echo ""

BUILD_ARGS=""
[ "$SKIP_BUILD" = true ] && BUILD_ARGS="--skip-build"
[ "$CLEANUP" = false ] && BUILD_ARGS="$BUILD_ARGS --no-cleanup"
[ "$VERBOSE" = true ] && BUILD_ARGS="$BUILD_ARGS --verbose"

"$SCRIPT_DIR/jenkins-local-simulate.sh" --test-suite "$TEST_SUITE" $BUILD_ARGS

# Show results
echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║              CI/CD Demo Complete!                         ║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ -f "$CDC_STREAMING_DIR/e2e-tests/build/reports/tests/test/index.html" ]; then
    echo -e "${GREEN}✓${NC} Test reports generated:"
    echo "  $CDC_STREAMING_DIR/e2e-tests/build/reports/tests/test/index.html"
    echo ""
    echo "Open the report in your browser to view detailed test results."
fi

if [ "$CLEANUP" = false ]; then
    echo ""
    echo -e "${YELLOW}⚠${NC} Containers are still running (--no-cleanup was used)"
    echo "To clean up manually:"
    echo "  cd $CDC_STREAMING_DIR"
    echo "  docker-compose -f docker-compose.integration-test.yml down"
fi

