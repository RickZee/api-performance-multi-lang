#!/bin/bash
# Script to run tests with Docker properly configured for Testcontainers
# This is needed on macOS where Docker socket is at a custom location

set -e

# Detect Docker socket location with priority order:
# 1. Use DOCKER_HOST if already set
# 2. Check for default Docker socket at /var/run/docker.sock (Docker Desktop default socket enabled)
# 3. Check for macOS Docker Desktop socket at ~/.docker/run/docker.sock
# 4. Show error if not found

if [ -n "$DOCKER_HOST" ]; then
    echo "Using existing DOCKER_HOST: $DOCKER_HOST"
elif [ -S "/var/run/docker.sock" ]; then
    export DOCKER_HOST="unix:///var/run/docker.sock"
    echo "✓ Found Docker socket at /var/run/docker.sock (Docker Desktop default socket enabled)"
    echo "Using DOCKER_HOST: $DOCKER_HOST"
elif [ -S "$HOME/.docker/run/docker.sock" ]; then
    export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"
    echo "✓ Found Docker socket at $HOME/.docker/run/docker.sock (macOS Docker Desktop)"
    echo "Using DOCKER_HOST: $DOCKER_HOST"
else
    echo "✗ Docker socket not found!"
    echo ""
    echo "Please ensure Docker Desktop is running and configure one of the following:"
    echo ""
    echo "Option 1: Enable default Docker socket in Docker Desktop (Recommended)"
    echo "  - Open Docker Desktop"
    echo "  - Go to Settings → Advanced"
    echo "  - Enable 'Enable default Docker socket'"
    echo "  - Click 'Apply & Restart'"
    echo ""
    echo "Option 2: Run setup script"
    echo "  ./setup-testcontainers.sh"
    echo ""
    echo "Option 3: Set DOCKER_HOST manually"
    echo "  export DOCKER_HOST=unix://\$HOME/.docker/run/docker.sock"
    echo ""
    exit 1
fi

echo ""
echo "Running tests..."
echo ""

cd "$(dirname "$0")"
./gradlew test "$@"
