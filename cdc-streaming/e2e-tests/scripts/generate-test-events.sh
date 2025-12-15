#!/bin/bash

# Generate test events and publish to Kafka
# This is a helper script for manual testing

set -e

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

EVENT_COUNT=${1:-10}
EVENT_TYPE=${2:-"mixed"}

echo "Generating $EVENT_COUNT events of type: $EVENT_TYPE"

# This script would use a Java/Kotlin utility or Python script
# to generate and publish events. For now, it's a placeholder.
echo "Note: Use the TestEventGenerator Java class or implement a CLI tool"
echo "to generate and publish test events."

