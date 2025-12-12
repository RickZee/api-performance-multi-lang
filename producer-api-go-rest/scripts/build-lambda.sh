#!/bin/bash
set -e

# Build script for Lambda deployment
# This script uses the shared build script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHARED_SCRIPT="$PROJECT_ROOT/../scripts/shared/build-go-lambda.sh"

if [ ! -f "$SHARED_SCRIPT" ]; then
    echo "Error: Shared build script not found: $SHARED_SCRIPT"
    exit 1
fi

exec "$SHARED_SCRIPT" "producer-api-go-rest"

