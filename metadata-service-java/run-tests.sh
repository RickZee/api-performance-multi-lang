#!/bin/bash
# Run all metadata service Java tests locally
#
# Usage:
#   ./run-tests.sh [OPTIONS]
#
# Options:
#   --integration    Run only integration tests (with mock Jenkins)
#   --workflow       Run only workflow integration tests
#   --verbose        Enable verbose output

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Metadata Service Java - Test Runner${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

if ! command -v java &> /dev/null; then
    echo -e "${RED}✗ Java is not installed${NC}"
    exit 1
fi

JAVA_VERSION=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2 | sed '/^1\./s///' | cut -d'.' -f1)
if [ "$JAVA_VERSION" -lt 17 ]; then
    echo -e "${RED}✗ Java 17+ is required (found: $JAVA_VERSION)${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Java $JAVA_VERSION found${NC}"

if ! command -v git &> /dev/null; then
    echo -e "${RED}✗ Git is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Git found${NC}"

if [ ! -f "./gradlew" ]; then
    echo -e "${RED}✗ gradlew not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Gradle wrapper found${NC}"

echo ""

# Parse arguments
INTEGRATION_ONLY=false
WORKFLOW_ONLY=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --integration)
            INTEGRATION_ONLY=true
            shift
            ;;
        --workflow)
            WORKFLOW_ONLY=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo -e "${YELLOW}Unknown option: $1${NC}"
            shift
            ;;
    esac
done

# Determine test pattern
TEST_PATTERN=""
if [ "$WORKFLOW_ONLY" = true ]; then
    TEST_PATTERN="*WorkflowIntegrationTest"
    echo -e "${BLUE}Running workflow integration tests only...${NC}"
elif [ "$INTEGRATION_ONLY" = true ]; then
    TEST_PATTERN="*IntegrationTest"
    echo -e "${BLUE}Running integration tests only (with mock Jenkins)...${NC}"
else
    echo -e "${BLUE}Running all tests (unit + integration)...${NC}"
fi

echo ""

# Build gradle command
GRADLE_ARGS="test --no-daemon"
if [ "$VERBOSE" = true ]; then
    GRADLE_ARGS="$GRADLE_ARGS --info"
fi

if [ -n "$TEST_PATTERN" ]; then
    GRADLE_ARGS="$GRADLE_ARGS --tests $TEST_PATTERN"
fi

# Run tests
./gradlew $GRADLE_ARGS

TEST_EXIT_CODE=$?

echo ""
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    # Show test report location
    if [ -f "build/reports/tests/test/index.html" ]; then
        echo -e "${CYAN}Test report: file://${SCRIPT_DIR}/build/reports/tests/test/index.html${NC}"
    fi
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ Some tests failed (exit code: $TEST_EXIT_CODE)${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Check the test report for details:${NC}"
    echo -e "${CYAN}file://${SCRIPT_DIR}/build/reports/tests/test/index.html${NC}"
fi

exit $TEST_EXIT_CODE
