#!/bin/bash
# Deploy Spring Boot filters
# This script rebuilds and deploys Spring Boot with updated filter configuration

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

SPRING_DIR="$PROJECT_ROOT/cdc-streaming/stream-processor-spring"
GENERATE_SCRIPT="$PROJECT_ROOT/cdc-streaming/scripts/filters/generate-filters.sh"
FILTERS_YAML="$SPRING_DIR/src/main/resources/filters.yml"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploy Spring Boot Filters${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check prerequisites
if [ ! -d "$SPRING_DIR" ]; then
    echo -e "${RED}✗ Spring Boot directory not found: $SPRING_DIR${NC}"
    exit 1
fi

# Generate filters if YAML file doesn't exist
if [ ! -f "$FILTERS_YAML" ]; then
    echo -e "${YELLOW}⚠${NC} Filters YAML not found. Generating filters..."
    if [ -f "$GENERATE_SCRIPT" ]; then
        bash "$GENERATE_SCRIPT" --spring-only
    else
        echo -e "${RED}✗ Generate script not found: $GENERATE_SCRIPT${NC}"
        exit 1
    fi
fi

if [ ! -f "$FILTERS_YAML" ]; then
    echo -e "${RED}✗ Filters YAML not found: $FILTERS_YAML${NC}"
    exit 1
fi

echo -e "${BLUE}ℹ${NC} Filters YAML found: $FILTERS_YAML"
echo ""

# Check if Gradle wrapper exists
if [ ! -f "$SPRING_DIR/gradlew" ]; then
    echo -e "${RED}✗ Gradle wrapper not found${NC}"
    exit 1
fi

# Build Spring Boot application
echo -e "${BLUE}Step 1: Building Spring Boot application...${NC}"
cd "$SPRING_DIR"

if ./gradlew clean build -x test; then
    echo -e "${GREEN}✓${NC} Build successful"
else
    echo -e "${RED}✗${NC} Build failed"
    exit 1
fi

echo ""

# Check deployment method
DEPLOY_METHOD="${DEPLOY_METHOD:-docker}"

case "$DEPLOY_METHOD" in
    docker)
        echo -e "${BLUE}Step 2: Building Docker image...${NC}"
        if docker build -t stream-processor-spring:latest .; then
            echo -e "${GREEN}✓${NC} Docker image built"
            echo ""
            echo -e "${CYAN}Next steps:${NC}"
            echo "  1. Run container: docker run -p 8080:8080 stream-processor-spring:latest"
            echo "  2. Or use docker-compose if available"
        else
            echo -e "${RED}✗${NC} Docker build failed"
            exit 1
        fi
        ;;
    
    kubernetes|helm)
        echo -e "${BLUE}Step 2: Deploying to Kubernetes/Helm...${NC}"
        if [ -d "$SPRING_DIR/helm/stream-processor" ]; then
            echo -e "${BLUE}ℹ${NC} Helm chart found"
            echo -e "${CYAN}Next steps:${NC}"
            echo "  1. Update Helm values if needed"
            echo "  2. Deploy: helm upgrade --install stream-processor ./helm/stream-processor"
        else
            echo -e "${YELLOW}⚠${NC} Helm chart not found"
        fi
        ;;
    
    local)
        echo -e "${BLUE}Step 2: Running locally...${NC}"
        echo -e "${CYAN}Next steps:${NC}"
        echo "  1. Run: ./gradlew bootRun"
        echo "  2. Or: java -jar build/libs/stream-processor-spring-1.0.0.jar"
        ;;
    
    *)
        echo -e "${YELLOW}⚠${NC} Unknown deployment method: $DEPLOY_METHOD"
        echo -e "${BLUE}ℹ${NC} Set DEPLOY_METHOD to: docker, kubernetes, helm, or local"
        echo ""
        echo -e "${CYAN}Build complete. Manual deployment required.${NC}"
        ;;
esac

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}ℹ${NC} Verify filters are loaded by checking application logs"
echo -e "${BLUE}ℹ${NC} Look for: '[STREAM-PROCESSOR] Loading X filter(s) from configuration'"
echo ""

