#!/bin/bash
# Validate Flink Jobs
# This script checks Flink job status, metrics, and validates job execution

set -e

# Configuration
FLINK_REST_URL="${FLINK_REST_URL:-http://localhost:8082}"
JOB_NAME="${1:-}"  # Optional: specific job name to check

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Flink Job Validation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Flink is accessible
if ! curl -f -s "${FLINK_REST_URL}/overview" > /dev/null 2>&1; then
    echo -e "${RED}Error: Flink is not accessible at ${FLINK_REST_URL}${NC}"
    echo "Make sure Flink JobManager is running:"
    echo "  docker-compose up -d flink-jobmanager flink-taskmanager"
    exit 1
fi

echo -e "${BLUE}Flink REST URL: ${FLINK_REST_URL}${NC}"
echo ""

# Get Flink cluster overview
echo -e "${YELLOW}Cluster Overview:${NC}"
OVERVIEW=$(curl -s "${FLINK_REST_URL}/overview")
echo "$OVERVIEW" | jq -r '
    "  Task Managers: " + (.taskmanagers | tostring) + "\n" +
    "  Slots Total: " + (."slots-total" | tostring) + "\n" +
    "  Slots Available: " + (."slots-available" | tostring) + "\n" +
    "  Jobs Running: " + (."jobs-running" | tostring) + "\n" +
    "  Jobs Finished: " + (."jobs-finished" | tostring) + "\n" +
    "  Jobs Cancelled: " + (."jobs-cancelled" | tostring) + "\n" +
    "  Jobs Failed: " + (."jobs-failed" | tostring)
'

echo ""

# Get all jobs
echo -e "${YELLOW}Jobs:${NC}"
JOBS=$(curl -s "${FLINK_REST_URL}/jobs")

if [ -n "$JOB_NAME" ]; then
    # Filter by job name
    JOB_ID=$(echo "$JOBS" | jq -r --arg name "$JOB_NAME" '.jobs[] | select(.name == $name) | .id')
    if [ -z "$JOB_ID" ] || [ "$JOB_ID" = "null" ]; then
        echo -e "${RED}  Job '${JOB_NAME}' not found${NC}"
        echo ""
        echo "Available jobs:"
        echo "$JOBS" | jq -r '.jobs[] | "  - \(.name) (\(.status))"'
        exit 1
    fi
else
    # Show all jobs
    JOB_COUNT=$(echo "$JOBS" | jq '.jobs | length')
    if [ "$JOB_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}  No jobs found${NC}"
        echo ""
        echo "To submit a Flink job, use:"
        echo "  docker exec -it cdc-flink-jobmanager ./bin/flink run /opt/flink/jobs/routing.sql"
        exit 0
    fi
    
    echo "$JOBS" | jq -r '.jobs[] | "  - \(.name) (ID: \(.id), Status: \(.status))"'
    echo ""
    
    # Get first running job for detailed validation
    JOB_ID=$(echo "$JOBS" | jq -r '.jobs[] | select(.status == "RUNNING") | .id' | head -1)
    
    if [ -z "$JOB_ID" ] || [ "$JOB_ID" = "null" ]; then
        echo -e "${YELLOW}  No running jobs found${NC}"
        exit 0
    fi
fi

echo ""

# Get job details
if [ -n "$JOB_ID" ]; then
    echo -e "${YELLOW}Job Details (ID: ${JOB_ID}):${NC}"
    JOB_DETAILS=$(curl -s "${FLINK_REST_URL}/jobs/${JOB_ID}")
    
    JOB_NAME=$(echo "$JOB_DETAILS" | jq -r '.name')
    JOB_STATUS=$(echo "$JOB_DETAILS" | jq -r '.state')
    START_TIME=$(echo "$JOB_DETAILS" | jq -r '."start-time"')
    END_TIME=$(echo "$JOB_DETAILS" | jq -r '."end-time" // "N/A"')
    DURATION=$(echo "$JOB_DETAILS" | jq -r '.duration // "N/A"')
    
    echo "  Name: ${JOB_NAME}"
    echo "  Status: ${JOB_STATUS}"
    echo "  Start Time: ${START_TIME}"
    echo "  End Time: ${END_TIME}"
    echo "  Duration: ${DURATION}"
    echo ""
    
    # Get job metrics
    echo -e "${YELLOW}Job Metrics:${NC}"
    METRICS=$(curl -s "${FLINK_REST_URL}/jobs/${JOB_ID}/metrics")
    
    # Extract key metrics
    NUM_RECORDS_IN=$(echo "$METRICS" | jq -r '.[] | select(.id == "numRecordsIn") | .value // "N/A"')
    NUM_RECORDS_OUT=$(echo "$METRICS" | jq -r '.[] | select(.id == "numRecordsOut") | .value // "N/A"')
    NUM_RECORDS_IN_PER_SEC=$(echo "$METRICS" | jq -r '.[] | select(.id == "numRecordsInPerSecond") | .value // "N/A"')
    NUM_RECORDS_OUT_PER_SEC=$(echo "$METRICS" | jq -r '.[] | select(.id == "numRecordsOutPerSecond") | .value // "N/A"')
    
    echo "  Records In: ${NUM_RECORDS_IN}"
    echo "  Records Out: ${NUM_RECORDS_OUT}"
    echo "  Records In/sec: ${NUM_RECORDS_IN_PER_SEC}"
    echo "  Records Out/sec: ${NUM_RECORDS_OUT_PER_SEC}"
    echo ""
    
    # Get vertices (operators)
    echo -e "${YELLOW}Operators:${NC}"
    VERTICES=$(curl -s "${FLINK_REST_URL}/jobs/${JOB_ID}/vertices")
    echo "$VERTICES" | jq -r '.[] | "  - \(.name) (Parallelism: \(.parallelism), Status: \(.status))"'
    echo ""
    
    # Check for errors
    if [ "$JOB_STATUS" = "FAILED" ] || [ "$JOB_STATUS" = "CANCELED" ]; then
        echo -e "${RED}Job Status: ${JOB_STATUS}${NC}"
        echo ""
        echo "Check job exceptions:"
        EXCEPTIONS=$(curl -s "${FLINK_REST_URL}/jobs/${JOB_ID}/exceptions")
        echo "$EXCEPTIONS" | jq -r '.root-exception // .all-exceptions[]?.exception // "No exceptions found"'
    elif [ "$JOB_STATUS" = "RUNNING" ]; then
        echo -e "${GREEN}Job is running successfully${NC}"
        
        # Validate metrics
        if [ "$NUM_RECORDS_IN" != "N/A" ] && [ "$NUM_RECORDS_IN" != "0" ]; then
            echo -e "${GREEN}  ✓ Processing records (${NUM_RECORDS_IN} in)${NC}"
        else
            echo -e "${YELLOW}  ⚠ No records processed yet${NC}"
        fi
        
        if [ "$NUM_RECORDS_OUT" != "N/A" ] && [ "$NUM_RECORDS_OUT" != "0" ]; then
            echo -e "${GREEN}  ✓ Producing records (${NUM_RECORDS_OUT} out)${NC}"
        else
            echo -e "${YELLOW}  ⚠ No records produced yet${NC}"
        fi
    fi
fi

echo ""
echo -e "${GREEN}Validation complete!${NC}"

