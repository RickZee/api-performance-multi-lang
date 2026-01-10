#!/bin/bash
set -e

# Wait for DNS resolution of redpanda hostname (max 30 seconds)
echo "Waiting for DNS resolution of redpanda..."
MAX_DNS_WAIT=30
DNS_WAIT_INTERVAL=1
elapsed=0

while [ $elapsed -lt $MAX_DNS_WAIT ]; do
    if getent hosts redpanda > /dev/null 2>&1; then
        echo "✓ DNS resolution successful for redpanda"
        break
    fi
    if [ $((elapsed % 5)) -eq 0 ]; then
        echo "  Waiting for DNS resolution... (${elapsed}s/${MAX_DNS_WAIT}s)"
    fi
    sleep $DNS_WAIT_INTERVAL
    elapsed=$((elapsed + DNS_WAIT_INTERVAL))
done

if [ $elapsed -ge $MAX_DNS_WAIT ]; then
    echo "⚠ Warning: DNS resolution timeout after ${MAX_DNS_WAIT}s, proceeding anyway..."
fi

# Additional check: try to connect to Kafka (max 10 seconds)
BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-redpanda:9092}"
HOST=$(echo "$BOOTSTRAP_SERVERS" | cut -d':' -f1)
PORT=$(echo "$BOOTSTRAP_SERVERS" | cut -d':' -f2)

echo "Checking connectivity to ${HOST}:${PORT}..."
MAX_CONNECT_WAIT=10
CONNECT_WAIT_INTERVAL=1
elapsed=0
connected=false

while [ $elapsed -lt $MAX_CONNECT_WAIT ]; do
    # Use bash built-in TCP check (works without timeout command)
    if (exec 3<>/dev/tcp/${HOST}/${PORT}) 2>/dev/null; then
        exec 3<&-
        exec 3>&-
        echo "✓ Successfully connected to ${HOST}:${PORT}"
        connected=true
        break
    fi
    sleep $CONNECT_WAIT_INTERVAL
    elapsed=$((elapsed + CONNECT_WAIT_INTERVAL))
done

if [ "$connected" = false ]; then
    echo "⚠ Warning: Could not connect to ${HOST}:${PORT} after ${MAX_CONNECT_WAIT}s"
    echo "  Spring Boot will retry connection on startup..."
fi

# Start the Spring Boot application
echo "Starting Spring Boot application..."
echo "  Kafka Streams will auto-start when Spring Boot is ready"
exec java -jar app.jar "$@"
