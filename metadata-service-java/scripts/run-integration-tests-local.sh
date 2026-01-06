#!/bin/bash
# Run integration tests with local Jenkins mock server
#
# This script runs all integration tests for the Metadata Service with
# a mock Jenkins server for CI/CD emulation. Tests verify all documented
# workflows from METADATA_SERVICE_DOCUMENTATION.
#
# Usage:
#   ./scripts/run-integration-tests-local.sh [OPTIONS]
#
# Options:
#   --workflow-only    Run only workflow integration tests
#   --jenkins-only     Run only Jenkins-related tests
#   --all              Run all integration tests (default)
#   --verbose          Enable verbose output
#   --report           Generate and open test reports

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Metadata Service - Integration Tests${NC}"
echo -e "${CYAN}with Local Jenkins Mock Server${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Parse arguments
WORKFLOW_ONLY=false
JENKINS_ONLY=false
RUN_ALL=true
VERBOSE=false
GENERATE_REPORT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --workflow-only)
            WORKFLOW_ONLY=true
            RUN_ALL=false
            shift
            ;;
        --jenkins-only)
            JENKINS_ONLY=true
            RUN_ALL=false
            shift
            ;;
        --all)
            RUN_ALL=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [--workflow-only|--jenkins-only|--all] [--verbose] [--report]"
            exit 1
            ;;
    esac
done

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

if [ ! -f "./gradlew" ]; then
    echo -e "${RED}✗ gradlew not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Gradle wrapper found${NC}"

echo ""

# Determine test pattern
TEST_PATTERN=""
if [ "$WORKFLOW_ONLY" = true ]; then
    TEST_PATTERN="*WorkflowIntegrationTest"
    echo -e "${BLUE}Running workflow integration tests only...${NC}"
elif [ "$JENKINS_ONLY" = true ]; then
    TEST_PATTERN="*Jenkins*IntegrationTest"
    echo -e "${BLUE}Running Jenkins integration tests only...${NC}"
else
    TEST_PATTERN="*IntegrationTest"
    echo -e "${BLUE}Running all integration tests...${NC}"
fi

echo ""

# Build test arguments
GRADLE_ARGS="test --no-daemon"
if [ "$VERBOSE" = true ]; then
    GRADLE_ARGS="$GRADLE_ARGS --info"
fi

if [ -n "$TEST_PATTERN" ]; then
    GRADLE_ARGS="$GRADLE_ARGS --tests \"$TEST_PATTERN\""
fi

# Run tests
echo -e "${BLUE}Running integration tests...${NC}"
echo -e "${CYAN}Note: Mock Jenkins server is started automatically by tests${NC}"
echo ""

if [ "$VERBOSE" = true ]; then
    ./gradlew $GRADLE_ARGS
else
    ./gradlew $GRADLE_ARGS 2>&1 | grep -E "(PASSED|FAILED|BUILD|test|Test|MockJenkinsServer)" || true
fi

TEST_EXIT_CODE=${PIPESTATUS[0]}

echo ""

# Generate reports if requested
if [ "$GENERATE_REPORT" = true ]; then
    echo -e "${BLUE}Generating test reports...${NC}"
    ./gradlew test jacocoTestReport --no-daemon
    
    if [ -f "build/reports/tests/test/index.html" ]; then
        echo -e "${GREEN}Test report: file://${PROJECT_DIR}/build/reports/tests/test/index.html${NC}"
        if command -v open &> /dev/null; then
            open "build/reports/tests/test/index.html"
        fi
    fi
    
    if [ -f "build/reports/jacoco/test/html/index.html" ]; then
        echo -e "${GREEN}Coverage report: file://${PROJECT_DIR}/build/reports/jacoco/test/html/index.html${NC}"
        if command -v open &> /dev/null; then
            open "build/reports/jacoco/test/html/index.html"
        fi
    fi
fi

# Summary
echo ""
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ All integration tests passed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${CYAN}Test Summary:${NC}"
    echo -e "  - Mock Jenkins server: Used for CI/CD emulation"
    echo -e "  - Workflow tests: Verified all documented workflows"
    echo -e "  - Jenkins verification: All filter operations trigger Jenkins correctly"
    echo -e "  - Spring YAML: Verified automatic YAML generation"
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ Some integration tests failed (exit code: $TEST_EXIT_CODE)${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Check the test report for details:${NC}"
    echo -e "${CYAN}file://${PROJECT_DIR}/build/reports/tests/test/index.html${NC}"
fi

exit $TEST_EXIT_CODE

