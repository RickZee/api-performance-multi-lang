#!/bin/bash

# Cleanup test environment

set -e

echo "Cleaning up e2e test environment..."

cd "$(dirname "$0")/.."
docker-compose -f docker-compose.test.yml down

echo "Test environment cleaned up"

