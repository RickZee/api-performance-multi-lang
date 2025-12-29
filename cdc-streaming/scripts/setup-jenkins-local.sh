#!/usr/bin/env bash
# Setup script for local Jenkins simulation
# Installs/verifies prerequisites for running Jenkins pipeline locally

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDC_STREAMING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$CDC_STREAMING_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
section() { echo -e "${CYAN}========================================${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}========================================${NC}"; }

section "Jenkins Local Simulation Setup"

echo ""
info "This script will verify prerequisites for running Jenkins pipeline locally"
echo ""

MISSING=0

# Check Docker
section "Checking Docker"
if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version)
    pass "Docker: $DOCKER_VERSION"
    
    if docker ps &>/dev/null; then
        pass "Docker daemon is running"
    else
        fail "Docker daemon is not running"
        info "Please start Docker Desktop and try again"
        MISSING=1
    fi
else
    fail "Docker not found"
    info "Install Docker Desktop from: https://www.docker.com/products/docker-desktop"
    MISSING=1
fi

# Check Docker Compose
section "Checking Docker Compose"
if command -v docker-compose &>/dev/null; then
    COMPOSE_VERSION=$(docker-compose --version)
    pass "Docker Compose: $COMPOSE_VERSION"
elif docker compose version &>/dev/null; then
    COMPOSE_VERSION=$(docker compose version)
    pass "Docker Compose (v2): $COMPOSE_VERSION"
else
    fail "Docker Compose not found"
    MISSING=1
fi

# Check Java
section "Checking Java"
if command -v java &>/dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -1)
    JAVA_MAJOR=$(java -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')
    if [ "$JAVA_MAJOR" -ge 17 ]; then
        pass "Java: $JAVA_VERSION (Java $JAVA_MAJOR)"
    else
        warn "Java: $JAVA_VERSION (Java $JAVA_MAJOR - Java 17+ recommended)"
    fi
else
    fail "Java not found"
    info "Install Java 17+ from: https://adoptium.net/"
    MISSING=1
fi

# Check Gradle Wrapper
section "Checking Gradle"
if [ -f "$CDC_STREAMING_DIR/e2e-tests/gradlew" ]; then
    pass "Gradle wrapper found"
    chmod +x "$CDC_STREAMING_DIR/e2e-tests/gradlew" 2>/dev/null || true
else
    fail "Gradle wrapper not found at $CDC_STREAMING_DIR/e2e-tests/gradlew"
    MISSING=1
fi

# Check required directories
section "Checking Project Structure"
if [ -f "$CDC_STREAMING_DIR/docker-compose.integration-test.yml" ]; then
    pass "Docker Compose file found"
else
    fail "Docker Compose file not found"
    MISSING=1
fi

if [ -d "$CDC_STREAMING_DIR/e2e-tests/src/test/java" ]; then
    pass "Test source directory found"
else
    fail "Test source directory not found"
    MISSING=1
fi

# Check ports availability
section "Checking Port Availability"
PORTS=(8080 8081 8082 8083 9092)
PORT_CONFLICTS=0

for port in "${PORTS[@]}"; do
    if lsof -Pi :$port -sTCP:LISTEN -t &>/dev/null; then
        warn "Port $port is in use"
        PORT_CONFLICTS=1
    else
        pass "Port $port is available"
    fi
done

if [ $PORT_CONFLICTS -eq 1 ]; then
    warn "Some ports are in use. You may need to stop conflicting services."
    info "Required ports: 8080 (Metadata Service), 8081 (Schema Registry), 8082 (Mock API), 8083 (Stream Processor), 9092 (Kafka)"
fi

# Summary
echo ""
section "Setup Summary"

if [ $MISSING -eq 0 ]; then
    pass "All prerequisites are met!"
    echo ""
    info "You can now run the Jenkins pipeline simulation:"
    echo ""
    echo "  cd $CDC_STREAMING_DIR"
    echo "  ./scripts/jenkins-local-simulate.sh"
    echo ""
    echo "Or run specific stages:"
    echo "  ./scripts/jenkins-local-simulate.sh --stage build"
    echo "  ./scripts/jenkins-local-simulate.sh --test-suite local"
    echo ""
else
    fail "Some prerequisites are missing. Please install them and run this script again."
    exit 1
fi

