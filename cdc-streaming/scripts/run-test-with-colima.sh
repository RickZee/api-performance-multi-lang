#!/bin/bash
# Wrapper script to run the test with Colima Docker context

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== Setting up Docker for Colima ==="

# Try to use colima context
if docker context use colima 2>/dev/null; then
    echo "✓ Using colima context"
elif docker context ls 2>/dev/null | grep -q colima; then
    echo "⚠ Colima context exists but couldn't switch"
    echo "Trying with DOCKER_HOST..."
    export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
else
    echo "⚠ Colima context not found, using DOCKER_HOST"
    export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
fi

# Export for docker-compose as well
export COMPOSE_DOCKER_CLI_BUILD=1
export DOCKER_BUILDKIT=1

# Verify Docker is accessible
if ! docker ps > /dev/null 2>&1; then
    echo "✗ Docker is not accessible"
    echo ""
    echo "Please ensure Colima is running:"
    echo "  colima status"
    echo "  colima start  # if not running"
    echo ""
    echo "Then try:"
    echo "  docker context use colima"
    echo "  cd cdc-streaming && ./scripts/test-e2e-pipeline-local.sh --clear-all"
    exit 1
fi

echo "✓ Docker is accessible"
echo ""

# Run the test
echo "=== Running Full End-to-End Test ==="
./scripts/test-e2e-pipeline-local.sh --clear-all
