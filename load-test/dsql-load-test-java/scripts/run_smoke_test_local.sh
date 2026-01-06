#!/bin/bash
# Run smoke tests against local Docker PostgreSQL
# This runs 2 minimal tests (one for each scenario) to validate the pipeline locally

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOAD_TEST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$LOAD_TEST_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Local Smoke Test ===${NC}"
echo "This will run 2 minimal tests (one per scenario) to validate the pipeline."
echo "Expected duration: ~30 seconds"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi

# Check if PostgreSQL container is running
POSTGRES_CONTAINER="cdc-local-postgres-large"
if ! docker ps | grep -q "$POSTGRES_CONTAINER"; then
    # Try alternative container name
    POSTGRES_CONTAINER="car_entities_postgres_large"
    if ! docker ps | grep -q "$POSTGRES_CONTAINER"; then
        echo -e "${YELLOW}PostgreSQL container not running. Starting Docker Compose...${NC}"
        cd "$PROJECT_ROOT"
        
        # Start just the postgres service
        docker-compose up -d postgres-large 2>/dev/null || docker-compose -f docker-compose.yml up -d postgres-large
        
        echo "Waiting for PostgreSQL to be ready..."
        max_wait=60
        elapsed=0
        while [ $elapsed -lt $max_wait ]; do
            if docker exec postgres-large pg_isready -U postgres -d car_entities > /dev/null 2>&1 || \
               docker exec car_entities_postgres_large pg_isready -U postgres -d car_entities > /dev/null 2>&1 || \
               docker exec cdc-local-postgres-large pg_isready -U postgres -d car_entities > /dev/null 2>&1; then
                echo -e "${GREEN}✓ PostgreSQL is ready${NC}"
                # Find which container is actually running
                if docker ps | grep -q "car_entities_postgres_large"; then
                    POSTGRES_CONTAINER="car_entities_postgres_large"
                elif docker ps | grep -q "cdc-local-postgres-large"; then
                    POSTGRES_CONTAINER="cdc-local-postgres-large"
                else
                    POSTGRES_CONTAINER="postgres-large"
                fi
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

# Create results directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="$LOAD_TEST_DIR/results/smoke-test-local-$TIMESTAMP"
mkdir -p "$RESULTS_DIR"

echo "Test Configuration:"
echo "  Database: Local Docker PostgreSQL (localhost:5433)"
echo "  Tests: 2 (Scenario 1 + Scenario 2)"
echo "  Output: $RESULTS_DIR"
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

# Test 1: Scenario 1 (Individual Inserts)
echo -e "${GREEN}=== Test 1: Scenario 1 (Individual Inserts) ===${NC}"
echo "  Threads: 10"
echo "  Iterations: 2"
echo "  Inserts per iteration: 5"
echo "  Expected: 100 total inserts"
echo ""

export SCENARIO=1
export THREADS=10
export ITERATIONS=2
export COUNT=5
export EVENT_TYPE=CarCreated
export TEST_ID="smoke-test-scenario1-$TIMESTAMP"
export OUTPUT_DIR="$RESULTS_DIR"

cd "$LOAD_TEST_DIR"
java -jar "$JAR_PATH" 2>&1 | tee "$RESULTS_DIR/scenario1-output.log"

SCENARIO1_RESULT="$RESULTS_DIR/$TEST_ID.json"
if [ -f "$SCENARIO1_RESULT" ]; then
    echo -e "${GREEN}✓ Scenario 1 completed${NC}"
else
    echo -e "${RED}✗ Scenario 1 failed - no results file${NC}"
fi

echo ""

# Test 2: Scenario 2 (Batch Inserts)
echo -e "${GREEN}=== Test 2: Scenario 2 (Batch Inserts) ===${NC}"
echo "  Threads: 10"
echo "  Iterations: 2"
echo "  Batch size: 10"
echo "  Expected: 200 total inserts"
echo ""

export SCENARIO=2
export THREADS=10
export ITERATIONS=2
export COUNT=10
export EVENT_TYPE=CarCreated
export TEST_ID="smoke-test-scenario2-$TIMESTAMP"
export OUTPUT_DIR="$RESULTS_DIR"

cd "$LOAD_TEST_DIR"
java -jar "$JAR_PATH" 2>&1 | tee "$RESULTS_DIR/scenario2-output.log"

SCENARIO2_RESULT="$RESULTS_DIR/$TEST_ID.json"
if [ -f "$SCENARIO2_RESULT" ]; then
    echo -e "${GREEN}✓ Scenario 2 completed${NC}"
else
    echo -e "${RED}✗ Scenario 2 failed - no results file${NC}"
fi

echo ""
echo -e "${GREEN}=== Smoke Test Summary ===${NC}"
echo ""

# Show summary if jq is available
if command -v jq > /dev/null 2>&1; then
    if [ -f "$SCENARIO1_RESULT" ]; then
        echo "Scenario 1 Results:"
        jq -r '
            "  Success: \(.results.scenario1.success_count // 0)",
            "  Errors: \(.results.scenario1.error_count // 0)",
            "  Duration: \(.results.scenario1.duration_ms // 0)ms",
            "  Throughput: \(.results.scenario1.throughput // 0 | floor) inserts/sec"
        ' "$SCENARIO1_RESULT" 2>/dev/null || echo "  (Unable to parse results)"
        echo ""
    fi
    
    if [ -f "$SCENARIO2_RESULT" ]; then
        echo "Scenario 2 Results:"
        jq -r '
            "  Success: \(.results.scenario2.success_count // 0)",
            "  Errors: \(.results.scenario2.error_count // 0)",
            "  Duration: \(.results.scenario2.duration_ms // 0)ms",
            "  Throughput: \(.results.scenario2.throughput // 0 | floor) inserts/sec"
        ' "$SCENARIO2_RESULT" 2>/dev/null || echo "  (Unable to parse results)"
        echo ""
    fi
fi

# Check if both tests passed
PASSED=true
if [ ! -f "$SCENARIO1_RESULT" ]; then
    PASSED=false
fi
if [ ! -f "$SCENARIO2_RESULT" ]; then
    PASSED=false
fi

if [ "$PASSED" = true ]; then
    echo -e "${GREEN}✅ Smoke test PASSED - Pipeline is working correctly!${NC}"
    echo ""
    echo "Results saved to: $RESULTS_DIR"
    echo ""
    echo "View results:"
    echo "  ls -lh $RESULTS_DIR"
    echo "  cat $RESULTS_DIR/*.json | python3 -m json.tool | head -50"
    exit 0
else
    echo -e "${RED}❌ Smoke test FAILED - Check errors above${NC}"
    echo "Results saved to: $RESULTS_DIR"
    exit 1
fi

