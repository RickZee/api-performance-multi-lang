#!/bin/bash

# Setup test environment for e2e tests
# This script ensures the Spring Boot stream processor is running

set -e

echo "Setting up e2e test environment..."

# Check required environment variables
if [ -z "$CONFLUENT_BOOTSTRAP_SERVERS" ]; then
    echo "Error: CONFLUENT_BOOTSTRAP_SERVERS not set"
    exit 1
fi

if [ -z "$CONFLUENT_API_KEY" ]; then
    echo "Error: CONFLUENT_API_KEY not set"
    exit 1
fi

if [ -z "$CONFLUENT_API_SECRET" ]; then
    echo "Error: CONFLUENT_API_SECRET not set"
    exit 1
fi

# Start Spring Boot stream processor
echo "Starting Spring Boot stream processor..."
cd "$(dirname "$0")/.."
docker-compose -f docker-compose.test.yml up -d stream-processor-spring

# Wait for service to be healthy
echo "Waiting for stream processor to be healthy..."
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if docker-compose -f docker-compose.test.yml ps stream-processor-spring | grep -q "healthy"; then
        echo "Stream processor is healthy"
        exit 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

echo "Warning: Stream processor did not become healthy within $timeout seconds"
exit 1
