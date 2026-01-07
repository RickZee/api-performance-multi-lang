#!/bin/bash
# Deploy Flink Streaming Job via JAR Submission
# Uses Java application approach for persistent streaming jobs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

FLINK_REST_API="${FLINK_REST_API:-http://localhost:8082}"
JAR_FILE="${JAR_FILE:-$PROJECT_ROOT/cdc-streaming/flink-jobs/business-events-routing-job-1.0.jar}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploy Flink Streaming Job (JAR)${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Flink REST API: $FLINK_REST_API"
echo "JAR File: $JAR_FILE"
echo ""

# Check if Flink cluster is running
echo -e "${BLUE}Checking Flink cluster status...${NC}"
if ! curl -sf "$FLINK_REST_API/overview" > /dev/null 2>&1; then
    echo -e "${RED}✗ Flink cluster is not running at $FLINK_REST_API${NC}"
    echo -e "${YELLOW}Please start Flink cluster first:${NC}"
    echo "  docker-compose -f cdc-streaming/docker-compose-local.yml up -d flink-jobmanager flink-taskmanager"
    exit 1
fi
echo -e "${GREEN}✓ Flink cluster is running${NC}"
echo ""

# Check if JAR file exists
if [ ! -f "$JAR_FILE" ]; then
    echo -e "${RED}✗ JAR file not found: $JAR_FILE${NC}"
    echo -e "${YELLOW}Please build the JAR first:${NC}"
    echo "  cd cdc-streaming/flink-java-job && mvn clean package"
    exit 1
fi

# Copy JAR file to container
JAR_FILE_IN_CONTAINER="/opt/flink/jobs/$(basename "$JAR_FILE")"
echo -e "${BLUE}Copying JAR to container...${NC}"
docker cp "$JAR_FILE" cdc-local-flink-jobmanager:"$JAR_FILE_IN_CONTAINER" > /dev/null 2>&1
echo -e "${GREEN}✓ JAR copied${NC}"
echo ""

# Check if job is already running
echo -e "${BLUE}Checking for existing jobs...${NC}"
EXISTING_JOBS_COUNT=$(docker exec cdc-local-flink-jobmanager /opt/flink/bin/flink list 2>&1 | grep -c "RUNNING" || echo "0")
EXISTING_JOBS_COUNT=$(echo "$EXISTING_JOBS_COUNT" | tr -d ' \n')
if [ -z "$EXISTING_JOBS_COUNT" ] || [ "$EXISTING_JOBS_COUNT" = "" ]; then
    EXISTING_JOBS_COUNT=0
fi
if [ "$EXISTING_JOBS_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Found $EXISTING_JOBS_COUNT running job(s)${NC}"
    echo -e "${YELLOW}Existing jobs:${NC}"
    docker exec cdc-local-flink-jobmanager /opt/flink/bin/flink list 2>&1 | grep "RUNNING" || true
    echo ""
    read -p "Cancel existing jobs and deploy new one? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Cancelling existing jobs...${NC}"
        docker exec cdc-local-flink-jobmanager /opt/flink/bin/flink list 2>&1 | grep "RUNNING" | awk '{print $4}' | xargs -I {} docker exec cdc-local-flink-jobmanager /opt/flink/bin/flink cancel {} 2>&1 || true
        sleep 2
    else
        echo -e "${YELLOW}Skipping deployment${NC}"
        exit 0
    fi
fi

# Submit JAR as detached persistent streaming job via REST API
echo -e "${BLUE}Submitting JAR as persistent streaming job...${NC}"
echo -e "${CYAN}Using REST API: $FLINK_REST_API${NC}"
echo ""

# Wait for JobManager to be fully ready
echo -e "${BLUE}Waiting for JobManager to be ready...${NC}"
for i in {1..30}; do
    if curl -sf "$FLINK_REST_API/overview" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ JobManager is ready${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}✗ JobManager not ready after 30 seconds${NC}"
        exit 1
    fi
    sleep 1
done
echo ""

# Submit via REST API (more reliable than flink run in Docker)
JAR_FILE_BASENAME=$(basename "$JAR_FILE")
SUBMIT_RESPONSE=$(curl -s -X POST \
    "$FLINK_REST_API/jars/upload" \
    -H "Content-Type: multipart/form-data" \
    -F "jarfile=@$JAR_FILE" 2>&1)

JAR_ID=$(echo "$SUBMIT_RESPONSE" | jq -r '.filename' | sed 's|.*/||' 2>/dev/null || echo "")

if [ -z "$JAR_ID" ] || [ "$JAR_ID" = "null" ]; then
    # Try alternative: upload via docker cp and submit via flink run
    echo -e "${YELLOW}REST upload failed, trying direct submission...${NC}"
    SUBMIT_OUTPUT=$(docker exec cdc-local-flink-jobmanager /opt/flink/bin/flink run \
        -m localhost:6123 \
        -c com.example.BusinessEventsRoutingJob \
        -d \
        "$JAR_FILE_IN_CONTAINER" 2>&1)
    SUBMIT_EXIT=$?
else
    # Submit the uploaded JAR
    echo -e "${GREEN}✓ JAR uploaded: $JAR_ID${NC}"
    SUBMIT_RESPONSE=$(curl -s -X POST \
        "$FLINK_REST_API/jars/$JAR_ID/run" \
        -H "Content-Type: application/json" \
        -d '{"entryClass":"com.example.BusinessEventsRoutingJob"}' 2>&1)
    
    JOB_ID=$(echo "$SUBMIT_RESPONSE" | jq -r '.jobid' 2>/dev/null | head -1 || echo "")
    if [ -n "$JOB_ID" ] && [ "$JOB_ID" != "null" ]; then
        echo -e "${GREEN}✓ Job submitted via REST API${NC}"
        SUBMIT_OUTPUT="Job has been submitted with JobID $JOB_ID"
        SUBMIT_EXIT=0
    else
        echo -e "${RED}✗ Job submission failed${NC}"
        echo "$SUBMIT_RESPONSE"
        SUBMIT_EXIT=1
    fi
fi

if [ $SUBMIT_EXIT -eq 0 ]; then
    echo "$SUBMIT_OUTPUT"
    echo ""
    
    # Extract job ID if available
    JOB_ID=$(echo "$SUBMIT_OUTPUT" | grep -oP 'Job has been submitted with JobID \K[0-9a-f]+' || echo "")
    
    if [ -n "$JOB_ID" ]; then
        echo -e "${GREEN}✓ Job submitted successfully!${NC}"
        echo -e "${GREEN}  Job ID: $JOB_ID${NC}"
    else
        echo -e "${GREEN}✓ Job submitted successfully!${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Check job status: docker exec cdc-local-flink-jobmanager /opt/flink/bin/flink list"
    echo "  2. Verify in REST API: curl -s http://localhost:8082/jobs | jq '.'"
    echo "  3. Check Flink Web UI: http://localhost:8082"
    echo "  4. Monitor job logs: docker logs cdc-local-flink-taskmanager"
    echo ""
    echo -e "${GREEN}✓ Deployment completed!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Job submission failed${NC}"
    echo "$SUBMIT_OUTPUT" | tail -30
    exit 1
fi
