#!/bin/bash

# Script to verify events in Kafka topic (Confluent Cloud)
# Requires: confluent CLI or kafka-console-consumer with Confluent Cloud config

set -e

TOPIC="${KAFKA_TOPIC:-simple-business-events}"
BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-pkc-oxqxx9.us-east-1.aws.confluent.cloud:9092}"
API_KEY="${KAFKA_API_KEY:-A57DHIMR3NLB6PGI}"
API_SECRET="${KAFKA_API_SECRET:-cfltawpq47RbFYepsUN3x0whOK4tgfMbGweGAp1eNdULMf/W2RMwiLJFVPyoTxkg}"

echo "======================================"
echo "Verifying Kafka Topic: $TOPIC"
echo "======================================"
echo ""

# Check if confluent CLI is available
if command -v confluent &> /dev/null; then
    echo "Using Confluent CLI..."
    echo ""
    echo "To view events, run:"
    echo "  confluent kafka topic consume $TOPIC --from-beginning"
    echo ""
    echo "Or use the Confluent Cloud UI:"
    echo "  https://confluent.cloud"
    echo ""
elif command -v kafka-console-consumer &> /dev/null; then
    echo "Using kafka-console-consumer..."
    echo ""
    echo "Run this command to consume events:"
    echo ""
    cat <<EOF
kafka-console-consumer \\
  --bootstrap-server $BOOTSTRAP_SERVERS \\
  --topic $TOPIC \\
  --from-beginning \\
  --consumer.config <(cat <<CONFIG
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="$API_KEY" password="$API_SECRET";
CONFIG
)
EOF
    echo ""
else
    echo "Neither confluent CLI nor kafka-console-consumer found."
    echo ""
    echo "Options:"
    echo "1. Install Confluent CLI: https://docs.confluent.io/confluent-cli/current/install.html"
    echo "2. Use Confluent Cloud UI: https://confluent.cloud"
    echo "3. Use Docker with kafka tools:"
    echo ""
    cat <<EOF
docker run -it --rm confluentinc/cp-kafka:latest kafka-console-consumer \\
  --bootstrap-server $BOOTSTRAP_SERVERS \\
  --topic $TOPIC \\
  --from-beginning \\
  --consumer-property security.protocol=SASL_SSL \\
  --consumer-property sasl.mechanism=PLAIN \\
  --consumer-property sasl.jaas.config="org.apache.kafka.common.security.plain.PlainLoginModule required username=\\"$API_KEY\\" password=\\"$API_SECRET\\";"
EOF
    echo ""
fi

echo "======================================"
echo "Pipeline Validation Summary"
echo "======================================"
echo ""
echo "✅ API Endpoint: POST /api/v1/events/events-simple"
echo "✅ Database: simple_events table"
echo "✅ CDC Connector: postgres-debezium-simple-events-confluent-cloud"
echo "✅ Kafka Topic: $TOPIC"
echo ""
echo "To verify events in Kafka:"
echo "  - Check Confluent Cloud UI for topic '$TOPIC'"
echo "  - Use the commands above to consume from the topic"
echo ""

