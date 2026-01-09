#!/bin/bash
set -e

# Wait for DNS resolution of redpanda hostname
echo "Waiting for DNS resolution of redpanda:9092..."
MAX_DNS_WAIT=60
DNS_WAIT_INTERVAL=2
elapsed=0

while [ $elapsed -lt $MAX_DNS_WAIT ]; do
    if getent hosts redpanda > /dev/null 2>&1; then
        echo "✓ DNS resolution successful for redpanda"
        break
    fi
    echo "  Waiting for DNS resolution... (${elapsed}s/${MAX_DNS_WAIT}s)"
    sleep $DNS_WAIT_INTERVAL
    elapsed=$((elapsed + DNS_WAIT_INTERVAL))
done

if [ $elapsed -ge $MAX_DNS_WAIT ]; then
    echo "⚠ Warning: DNS resolution timeout after ${MAX_DNS_WAIT}s, proceeding anyway..."
fi

# Additional check: try to resolve the bootstrap server
BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-redpanda:9092}"
HOST=$(echo "$BOOTSTRAP_SERVERS" | cut -d':' -f1)
PORT=$(echo "$BOOTSTRAP_SERVERS" | cut -d':' -f2)

echo "Checking connectivity to ${HOST}:${PORT}..."
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/${HOST}/${PORT}" 2>/dev/null; then
    echo "✓ Successfully connected to ${HOST}:${PORT}"
else
    echo "⚠ Warning: Could not connect to ${HOST}:${PORT}, but proceeding with startup..."
fi

# Start the Spring Boot application
echo "Starting Spring Boot application..."
exec java -jar app.jar "$@"
