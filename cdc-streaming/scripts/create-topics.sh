#!/bin/bash
# Create Kafka Topics
# This script creates the necessary Kafka topics for the CDC streaming pipeline

set -e

KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-localhost:9092}"

echo "Creating Kafka topics..."
echo "Bootstrap Servers: $KAFKA_BOOTSTRAP_SERVERS"

# Check if kafka-topics.sh is available (from Kafka installation or container)
if command -v kafka-topics.sh &> /dev/null; then
    KAFKA_TOPICS_CMD="kafka-topics.sh"
elif docker ps | grep -q cdc-kafka; then
    KAFKA_TOPICS_CMD="docker exec cdc-kafka /usr/bin/kafka-topics"
else
    echo "Error: kafka-topics.sh not found and Kafka container not running"
    echo "Please ensure Kafka is running or kafka-topics.sh is in PATH"
    exit 1
fi

# Topic configurations
# Note: Only raw-business-events needs to be created manually.
# Filtered topics (filtered-loan-events, filtered-service-events, etc.) are 
# automatically created by Flink when it writes to them for the first time.
TOPICS=(
    "raw-business-events:3:1"           # topic:partitions:replication-factor
)

# Create topics
for topic_config in "${TOPICS[@]}"; do
    IFS=':' read -r topic partitions replication <<< "$topic_config"
    
    echo "Creating topic: $topic (partitions: $partitions, replication: $replication)"
    
    if $KAFKA_TOPICS_CMD --bootstrap-server "$KAFKA_BOOTSTRAP_SERVERS" \
        --create \
        --topic "$topic" \
        --partitions "$partitions" \
        --replication-factor "$replication" \
        --if-not-exists 2>/dev/null; then
        echo "  ✓ Topic '$topic' created successfully"
    else
        # Check if topic already exists
        if $KAFKA_TOPICS_CMD --bootstrap-server "$KAFKA_BOOTSTRAP_SERVERS" \
            --list | grep -q "^${topic}$"; then
            echo "  ℹ Topic '$topic' already exists"
        else
            echo "  ✗ Failed to create topic '$topic'"
        fi
    fi
done

echo ""
echo "Topic creation complete!"
echo ""
echo "Listing all topics:"
$KAFKA_TOPICS_CMD --bootstrap-server "$KAFKA_BOOTSTRAP_SERVERS" --list

