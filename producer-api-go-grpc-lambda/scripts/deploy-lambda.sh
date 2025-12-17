#!/bin/bash
set -e

# Deployment script for Lambda using SAM CLI
# This script uses the shared deploy script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHARED_SCRIPT="$PROJECT_ROOT/../scripts/shared/deploy-lambda.sh"

if [ ! -f "$SHARED_SCRIPT" ]; then
    echo "Error: Shared deploy script not found: $SHARED_SCRIPT"
    exit 1
fi

exec "$SHARED_SCRIPT" "producer-api-go-grpc-lambda" "$@"
