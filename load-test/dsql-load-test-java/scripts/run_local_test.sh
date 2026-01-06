#!/bin/bash
# Run a small load test against local Docker PostgreSQL
# This script starts Docker PostgreSQL if needed and runs a minimal test

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOAD_TEST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Local Docker Load Test ===${NC}"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi

# Check if PostgreSQL container is running
POSTGRES_CONTAINER="car_entities_postgres_large"
if ! docker ps | grep -q "$POSTGRES_CONTAINER"; then
    echo -e "${YELLOW}PostgreSQL container not running. Starting Docker Compose...${NC}"
    cd "$PROJECT_ROOT"
    
    # Start just the postgres service
    docker-compose up -d postgres-large
    
    echo "Waiting for PostgreSQL to be ready..."
    max_wait=60
    elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if docker exec "$POSTGRES_CONTAINER" pg_isready -U postgres -d car_entities > /dev/null 2>&1; then
            echo -e "${GREEN}✓ PostgreSQL is ready${NC}"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    if [ $elapsed -ge $max_wait ]; then
        echo -e "${RED}Error: PostgreSQL did not become ready in time${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ PostgreSQL container is running${NC}"
fi

# Ensure schema exists
echo "Ensuring database schema exists..."
docker exec "$POSTGRES_CONTAINER" psql -U postgres -d car_entities <<EOF > /dev/null 2>&1 || true
CREATE SCHEMA IF NOT EXISTS car_entities_schema;
CREATE TABLE IF NOT EXISTS car_entities_schema.business_events (
    id VARCHAR(255) PRIMARY KEY,
    event_name VARCHAR(255) NOT NULL,
    event_type VARCHAR(255),
    created_date TIMESTAMP WITH TIME ZONE,
    saved_date TIMESTAMP WITH TIME ZONE,
    event_data TEXT NOT NULL
);
EOF

echo -e "${GREEN}✓ Database schema ready${NC}"
echo ""

# Set environment variables for local test
export DATABASE_TYPE=local
export LOCAL_HOST=localhost
export LOCAL_PORT=5433
export LOCAL_USERNAME=postgres
export LOCAL_PASSWORD=password
export DATABASE_NAME=car_entities

# Test parameters
export SCENARIO=1
export THREADS=5
export ITERATIONS=2
export COUNT=10
export EVENT_TYPE=CarCreated
export OUTPUT_DIR="$LOAD_TEST_DIR/results/local-test-$(date +%Y%m%d_%H%M%S)"
export TEST_ID="local-test-$(date +%Y%m%d_%H%M%S)"

mkdir -p "$OUTPUT_DIR"

echo "Test Configuration:"
echo "  Database: Local Docker PostgreSQL (localhost:5433)"
echo "  Scenario: Individual Inserts"
echo "  Threads: $THREADS"
echo "  Iterations: $ITERATIONS"
echo "  Count per iteration: $COUNT"
echo "  Output: $OUTPUT_DIR"
echo ""

# Build the JAR if it doesn't exist
JAR_PATH="$LOAD_TEST_DIR/target/dsql-load-test-1.0.0.jar"
if [ ! -f "$JAR_PATH" ]; then
    echo "Building Java application..."
    cd "$LOAD_TEST_DIR"
    mvn clean package -DskipTests -q
    if [ ! -f "$JAR_PATH" ]; then
        echo -e "${RED}Error: Failed to build JAR file${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Build complete${NC}"
    echo ""
fi

# Run the test
echo -e "${GREEN}Running load test...${NC}"
echo ""

cd "$LOAD_TEST_DIR"
java -jar "$JAR_PATH" 2>&1 | tee "$OUTPUT_DIR/test-output.log"

# Check if results file was created
RESULTS_FILE="$OUTPUT_DIR/$TEST_ID.json"
if [ -f "$RESULTS_FILE" ]; then
    echo ""
    echo -e "${GREEN}✓ Test completed successfully${NC}"
    echo "Results saved to: $RESULTS_FILE"
    
    # Show summary if jq is available
    if command -v jq > /dev/null 2>&1; then
        echo ""
        echo "Test Summary:"
        jq -r '
            "  Scenario 1:",
            "    Success: \(.results.scenario1.success_count // 0)",
            "    Errors: \(.results.scenario1.error_count // 0)",
            "    Duration: \(.results.scenario1.duration_ms // 0)ms",
            "    Throughput: \(.results.scenario1.throughput // 0 | floor) inserts/sec"
        ' "$RESULTS_FILE" 2>/dev/null || echo "  (Unable to parse results)"
    fi
else
    echo ""
    echo -e "${YELLOW}Warning: Results file not found. Check test-output.log for details.${NC}"
fi

echo ""
echo -e "${GREEN}Test execution complete!${NC}"

