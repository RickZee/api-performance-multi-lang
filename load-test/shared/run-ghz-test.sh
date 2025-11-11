#!/bin/bash

# Script to run ghz gRPC load tests
# Usage: run-ghz-test.sh <api_name> <host> <port> <proto_file> <method> <duration> <concurrency> <total_requests>

set -e

API_NAME=$1
HOST=$2
PORT=$3
PROTO_FILE=$4
METHOD=$5
DURATION=${6:-30s}
CONCURRENCY=${7:-10}
TOTAL_REQUESTS=${8:-0}

RESULTS_DIR="/jmeter/results/throughput-sequential/${API_NAME}"
mkdir -p "$RESULTS_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${RESULTS_DIR}/${API_NAME}-ghz-${TIMESTAMP}.json"
SUMMARY_FILE="${RESULTS_DIR}/${API_NAME}-ghz-${TIMESTAMP}.txt"

# Generate request payload JSON
# The payload structure matches our EventRequest proto
REQUEST_PAYLOAD='{
  "eventHeader": {
    "uuid": "{{.RequestNumber}}",
    "eventName": "TestEvent",
    "createdDate": "{{.Timestamp}}",
    "savedDate": "{{.Timestamp}}",
    "eventType": "TestEvent"
  },
  "eventBody": {
    "entities": [{
      "entityType": "TestEntity",
      "entityId": "test-{{.RequestNumber}}",
      "updatedAttributes": {
        "id": "test-{{.RequestNumber}}",
        "timestamp": "{{.Timestamp}}"
      }
    }]
  }
}'

echo "Running ghz test for ${API_NAME}..."
echo "  Host: ${HOST}:${PORT}"
echo "  Method: ${METHOD}"
echo "  Duration: ${DURATION}"
echo "  Concurrency: ${CONCURRENCY}"

# Build ghz command
GHZ_CMD="ghz"
GHZ_CMD="${GHZ_CMD} --proto ${PROTO_FILE}"
GHZ_CMD="${GHZ_CMD} --call ${METHOD}"
GHZ_CMD="${GHZ_CMD} --insecure"
GHZ_CMD="${GHZ_CMD} --host ${HOST}:${PORT}"
GHZ_CMD="${GHZ_CMD} --concurrency ${CONCURRENCY}"
GHZ_CMD="${GHZ_CMD} --data '${REQUEST_PAYLOAD}'"
GHZ_CMD="${GHZ_CMD} --format json"
GHZ_CMD="${GHZ_CMD} --output ${OUTPUT_FILE}"

# Add duration or total requests
if [ "$TOTAL_REQUESTS" -gt 0 ]; then
    GHZ_CMD="${GHZ_CMD} --total ${TOTAL_REQUESTS}"
else
    GHZ_CMD="${GHZ_CMD} --duration ${DURATION}"
fi

# Run ghz and capture output
echo "Executing: ${GHZ_CMD}"
eval ${GHZ_CMD} 2>&1 | tee "${SUMMARY_FILE}"

# Check if test was successful
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "ghz test completed successfully"
    echo "Results saved to: ${OUTPUT_FILE}"
    echo "Summary saved to: ${SUMMARY_FILE}"
    exit 0
else
    echo "ghz test failed"
    exit 1
fi

