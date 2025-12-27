#!/usr/bin/env bash
# Create Kafka topics for integration tests

KAFKA_BOOTSTRAP_SERVER=${KAFKA_BOOTSTRAP_SERVER:-kafka:9092}

echo "Creating topics with bootstrap server: $KAFKA_BOOTSTRAP_SERVER"

# Wait for Kafka to be ready
echo "Waiting for Kafka to be ready..."
for i in {1..30}; do
  if kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP_SERVER" --list &>/dev/null; then
    echo "Kafka is ready"
    break
  fi
  echo "Waiting for Kafka... ($i/30)"
  sleep 2
done

# Create V1 topics
echo "Creating V1 topics..."
kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP_SERVER" --create --if-not-exists --topic raw-event-headers --partitions 3 --replication-factor 1
kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP_SERVER" --create --if-not-exists --topic filtered-car-created-events-spring --partitions 3 --replication-factor 1
kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP_SERVER" --create --if-not-exists --topic filtered-loan-created-events-spring --partitions 3 --replication-factor 1
kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP_SERVER" --create --if-not-exists --topic filtered-loan-payment-submitted-events-spring --partitions 3 --replication-factor 1
kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP_SERVER" --create --if-not-exists --topic filtered-service-events-spring --partitions 3 --replication-factor 1

# Create V2 topics (for breaking schema changes)
if [ "${CREATE_V2_TOPICS:-false}" = "true" ]; then
  echo "Creating V2 topics..."
  kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP_SERVER" --create --if-not-exists --topic raw-event-headers-v2 --partitions 3 --replication-factor 1
  kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP_SERVER" --create --if-not-exists --topic filtered-car-created-events-v2-spring --partitions 3 --replication-factor 1
  kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP_SERVER" --create --if-not-exists --topic filtered-loan-created-events-v2-spring --partitions 3 --replication-factor 1
  kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP_SERVER" --create --if-not-exists --topic filtered-loan-payment-submitted-events-v2-spring --partitions 3 --replication-factor 1
  kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP_SERVER" --create --if-not-exists --topic filtered-service-events-v2-spring --partitions 3 --replication-factor 1
fi

echo "Topics created successfully"

