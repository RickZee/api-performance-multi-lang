#!/bin/bash
# Deploy Flink SQL Job
# This script submits a Flink SQL job to the Flink cluster

set -e

FLINK_REST_URL="${FLINK_REST_URL:-http://localhost:8082}"
SQL_FILE="${1:-./flink-jobs/routing-local-docker.sql}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploy Flink SQL Job${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Flink is accessible
if ! curl -f -s "${FLINK_REST_URL}/overview" > /dev/null 2>&1; then
    echo -e "${RED}Error: Flink is not accessible at ${FLINK_REST_URL}${NC}"
    exit 1
fi

# Check if SQL file exists
if [ ! -f "$SQL_FILE" ]; then
    echo -e "${RED}Error: SQL file not found: $SQL_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}Flink REST URL: ${FLINK_REST_URL}${NC}"
echo -e "${BLUE}SQL File: ${SQL_FILE}${NC}"
echo ""

# Get absolute path
SQL_FILE_ABS=$(cd "$(dirname "$SQL_FILE")" && pwd)/$(basename "$SQL_FILE")
SQL_FILE_IN_CONTAINER="/opt/flink/jobs/$(basename "$SQL_FILE")"

echo -e "${YELLOW}Submitting Flink SQL job...${NC}"

# Submit job using Flink SQL Client
if docker exec cdc-flink-jobmanager /opt/flink/bin/sql-client.sh embedded -f "$SQL_FILE_IN_CONTAINER" 2>&1 | tee /tmp/flink-job-output.log; then
    echo ""
    echo -e "${GREEN}✓ Flink SQL job submitted successfully!${NC}"
    echo ""
    echo -e "${BLUE}Check job status:${NC}"
    echo "  curl ${FLINK_REST_URL}/jobs | jq"
    echo ""
    echo -e "${BLUE}View Flink Web UI:${NC}"
    echo "  http://localhost:8082"
else
    echo ""
    echo -e "${RED}✗ Failed to submit Flink SQL job${NC}"
    echo ""
    echo "Check logs:"
    echo "  docker logs cdc-flink-jobmanager"
    echo "  docker logs cdc-flink-taskmanager"
    exit 1
fi






