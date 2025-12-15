#!/bin/bash

# Compare outputs from Flink and Spring Boot services
# This script helps verify functional parity

set -e

TOPIC=${1:-"filtered-car-created-events"}
MAX_EVENTS=${2:-10}

if [ -z "$CONFLUENT_BOOTSTRAP_SERVERS" ]; then
    echo "Error: CONFLUENT_BOOTSTRAP_SERVERS not set"
    exit 1
fi

echo "Comparing outputs from topic: $TOPIC"
echo "Note: This is a placeholder script. Use the ComparisonUtils Java class"
echo "or implement a CLI tool to compare event outputs."

