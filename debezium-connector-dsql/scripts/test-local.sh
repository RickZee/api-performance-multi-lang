#!/bin/bash
# Local testing script

set -e

echo "Running local tests..."

# Run unit tests
./gradlew test

# Run integration tests (requires Docker)
if command -v docker &> /dev/null; then
    echo "Running integration tests..."
    ./gradlew test --tests "*IT"
else
    echo "Docker not found, skipping integration tests"
fi

echo "Tests complete!"

