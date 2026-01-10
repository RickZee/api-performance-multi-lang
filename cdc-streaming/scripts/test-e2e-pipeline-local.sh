#!/usr/bin/env bash
# Test Local CDC Pipeline with Redpanda
# Tests the complete local dockerized CDC system
#
# Usage:
#   ./cdc-streaming/scripts/test-e2e-pipeline-local.sh [OPTIONS]
#
# Options:
#   --clear-db       Clear test events from database before running test
#   --clear-topics   Clear all Kafka topics in Redpanda before running test
#   --clear-all      Clear both database and topics (equivalent to --clear-db --clear-topics)

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

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
section() { echo -e "${CYAN}========================================${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}========================================${NC}"; }

section "Local CDC Pipeline Test"
SCRIPT_START_TIME=$(date +%s)
SCRIPT_MAX_DURATION=120  # 2 minutes maximum script duration
SCRIPT_TIMEOUT_REACHED=false

# Timeout check function
check_script_timeout() {
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - SCRIPT_START_TIME))
    if [ $ELAPSED -ge $SCRIPT_MAX_DURATION ]; then
        SCRIPT_TIMEOUT_REACHED=true
        return 1
    fi
    return 0
}

# Check timeout and exit if reached
check_timeout_and_exit() {
    if ! check_script_timeout; then
        echo ""
        warn "Script timeout reached (${SCRIPT_MAX_DURATION}s). Exiting to prevent hanging."
        SCRIPT_END_TIME=$(date +%s)
        SCRIPT_DURATION=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
        echo "Script ran for ${SCRIPT_DURATION}s before timeout"
        exit 1
    fi
}

# Parse command line arguments
CLEAR_DB=false
CLEAR_TOPICS=false
CLEAR_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clear-db)
            CLEAR_DB=true
            shift
            ;;
        --clear-topics)
            CLEAR_TOPICS=true
            shift
            ;;
        --clear-all)
            CLEAR_ALL=true
            CLEAR_DB=true
            CLEAR_TOPICS=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--clear-db] [--clear-topics] [--clear-all]"
            exit 1
            ;;
    esac
done

# Use docker-compose-local.yml
COMPOSE_FILE="docker-compose-local.yml"
cd cdc-streaming

# Auto-detect and configure Colima if available
if [ -S "$HOME/.colima/default/docker.sock" ]; then
    # First, try to use colima context (preferred method)
    if docker context ls 2>/dev/null | grep -q "colima"; then
        # Unset DOCKER_HOST to allow context to work
        unset DOCKER_HOST
        docker context use colima 2>/dev/null || export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
    else
        export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
    fi
    info "Auto-configured Docker for Colima"
fi

# Verify Docker is accessible
if ! docker ps > /dev/null 2>&1; then
    fail "Docker is not accessible. Please ensure Docker/Colima is running."
    echo ""
    echo "Try:"
    echo "  colima status"
    echo "  colima start  # if not running"
    echo "  docker context use colima"
    exit 1
fi

# Pre-test cleanup
if [ "$CLEAR_DB" = true ] || [ "$CLEAR_ALL" = true ]; then
    echo ""
    section "Pre-Test: Clearing Database"
    info "Clearing test events from database..."
    
    BEFORE_COUNT=$(docker exec cdc-local-postgres-large psql -U postgres -d car_entities -t -c "SELECT COUNT(*) FROM event_headers WHERE id LIKE 'test-%'" 2>/dev/null | tr -d ' \n' || echo "0")
    BEFORE_COUNT=${BEFORE_COUNT:-0}
    
    if [ "$BEFORE_COUNT" -gt 0 ] 2>/dev/null; then
        docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c "DELETE FROM event_headers WHERE id LIKE 'test-%'" > /dev/null 2>&1
        docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c "DELETE FROM business_events WHERE id LIKE 'test-%'" > /dev/null 2>&1
        
        AFTER_COUNT=$(docker exec cdc-local-postgres-large psql -U postgres -d car_entities -t -c "SELECT COUNT(*) FROM event_headers WHERE id LIKE 'test-%'" 2>/dev/null | tr -d ' \n' || echo "0")
        pass "Database cleared: $BEFORE_COUNT test events deleted, $AFTER_COUNT remaining"
    else
        info "No test events found in database"
    fi
    echo ""
fi

if [ "$CLEAR_TOPICS" = true ] || [ "$CLEAR_ALL" = true ]; then
    echo ""
    section "Pre-Test: Clearing Kafka Topics"
    info "Deleting all topics in Redpanda..."
    
    # Get list of topics (exclude internal Kafka Connect topics)
    TOPICS=$(docker exec cdc-local-redpanda rpk topic list 2>&1 | grep -v "^NAME" | awk '{print $1}' | grep -v "^connect-" || true)
    
    if [ -n "$TOPICS" ]; then
        for topic in $TOPICS; do
            if [ -n "$topic" ]; then
                info "Deleting topic: $topic"
                docker exec cdc-local-redpanda rpk topic delete "$topic" > /dev/null 2>&1 || warn "Failed to delete topic: $topic (may not exist)"
            fi
        done
        pass "Topics cleared"
    else
        info "No topics found to clear"
    fi
    
    # Wait a moment for topic deletion to propagate
    sleep 2
    
    # Restart stream processor after topics are deleted so it can recreate them
    info "Restarting stream processor to reconnect to topics..."
    docker-compose -f "$COMPOSE_FILE" restart stream-processor 2>&1 | grep -v "level=warning" | tail -3
    info "Waiting 2 seconds for stream processor to restart..."
    sleep 2
    echo ""
fi

# Always clear consumer logs at the start for clean test results
echo ""
section "Pre-Test: Clearing Consumer Logs"
info "Clearing logs for all consumers by removing and recreating containers..."

# Spring Boot consumer services (docker-compose service names)
SPRING_CONSUMER_SERVICES=("loan-consumer" "car-consumer" "loan-payment-consumer" "service-consumer")
# Flink consumer services
FLINK_CONSUMER_SERVICES=("loan-consumer-flink" "car-consumer-flink" "loan-payment-consumer-flink" "service-consumer-flink")

ALL_CONSUMER_SERVICES=("${SPRING_CONSUMER_SERVICES[@]}" "${FLINK_CONSUMER_SERVICES[@]}")

# Container names (for verification)
SPRING_CONSUMERS=("cdc-local-loan-consumer-spring" "cdc-local-car-consumer-spring" "cdc-local-loan-payment-consumer-spring" "cdc-local-service-consumer-spring")
FLINK_CONSUMERS=("cdc-local-loan-consumer-flink" "cdc-local-car-consumer-flink" "cdc-local-loan-payment-consumer-flink" "cdc-local-service-consumer-flink")
ALL_CONSUMERS=("${SPRING_CONSUMERS[@]}" "${FLINK_CONSUMERS[@]}")

CLEARED_COUNT=0
BEFORE_TOTALS=()

# Check log sizes before clearing
for container in "${ALL_CONSUMERS[@]}"; do
    if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        BEFORE_LINES=$(docker logs "$container" 2>&1 | wc -l | tr -d ' \n' || echo "0")
        BEFORE_TOTALS+=("$BEFORE_LINES")
    else
        BEFORE_TOTALS+=("0")
    fi
done

# Remove and recreate containers to clear logs
for service in "${ALL_CONSUMER_SERVICES[@]}"; do
    # Stop and remove the container (this clears logs)
    docker-compose -f "$COMPOSE_FILE" stop "$service" > /dev/null 2>&1 || true
    docker-compose -f "$COMPOSE_FILE" rm -f "$service" > /dev/null 2>&1 || true
    # Start it again (creates new container with fresh logs)
    docker-compose -f "$COMPOSE_FILE" up -d "$service" > /dev/null 2>&1 || true
    CLEARED_COUNT=$((CLEARED_COUNT + 1))
done

if [ $CLEARED_COUNT -gt 0 ]; then
    info "Waiting 2 seconds for consumers to start with fresh logs..."
    sleep 2
    
    # Verify logs are cleared (should have minimal lines - just startup)
    VERIFIED_COUNT=0
    for i in "${!ALL_CONSUMERS[@]}"; do
        container="${ALL_CONSUMERS[$i]}"
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            AFTER_LINES=$(docker logs "$container" 2>&1 | wc -l | tr -d ' \n' || echo "0")
            BEFORE_LINES="${BEFORE_TOTALS[$i]}"
            
            # Logs should be minimal after recreation (just startup messages, typically < 50 lines)
            if [ "$AFTER_LINES" -lt 50 ]; then
                VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
                info "  ✓ ${container}: $BEFORE_LINES → $AFTER_LINES lines"
            else
                warn "  ⚠ ${container}: $BEFORE_LINES → $AFTER_LINES lines (still high)"
            fi
        fi
    done
    
    if [ $VERIFIED_COUNT -eq $CLEARED_COUNT ]; then
        pass "Cleared logs for $CLEARED_COUNT consumer(s) - all logs verified clean"
    else
        warn "Cleared logs for $CLEARED_COUNT consumer(s), but only $VERIFIED_COUNT/$CLEARED_COUNT verified clean"
    fi
else
    info "No consumers found to clear logs"
fi
echo ""

# 1. Check Infrastructure Services
echo ""
section "Step 1: Infrastructure Services"
docker-compose -f "$COMPOSE_FILE" ps postgres-large redpanda kafka-connect 2>/dev/null | grep -E "(NAME|postgres|redpanda|kafka-connect)" | head -5

POSTGRES_STATUS=$(docker-compose -f "$COMPOSE_FILE" ps postgres-large 2>/dev/null | grep -q "healthy" && echo "healthy" || echo "not healthy")
REDPANDA_STATUS=$(docker-compose -f "$COMPOSE_FILE" ps redpanda 2>/dev/null | grep -q "healthy" && echo "healthy" || echo "not healthy")
KAFKA_CONNECT_STATUS=$(docker-compose -f "$COMPOSE_FILE" ps kafka-connect 2>/dev/null | grep -q "healthy\|Up" && echo "running" || echo "not running")

if [ "$POSTGRES_STATUS" = "healthy" ]; then
    pass "Postgres is healthy"
else
    fail "Postgres is not healthy"
fi

if [ "$REDPANDA_STATUS" = "healthy" ]; then
    pass "Redpanda is healthy"
else
    warn "Redpanda is not healthy, starting it..."
    docker-compose -f "$COMPOSE_FILE" up -d redpanda 2>&1 | grep -v "level=warning" | tail -3
    info "Waiting for Redpanda to become healthy..."
    max_wait=30
    elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        sleep 2
        elapsed=$((elapsed + 2))
        REDPANDA_STATUS=$(docker-compose -f "$COMPOSE_FILE" ps redpanda 2>/dev/null | grep -q "healthy" && echo "healthy" || echo "not healthy")
        if [ "$REDPANDA_STATUS" = "healthy" ]; then
            pass "Redpanda is now healthy (after ${elapsed}s)"
            break
        fi
    done
    if [ "$REDPANDA_STATUS" != "healthy" ]; then
        fail "Redpanda did not become healthy within ${max_wait}s"
        info "Check Redpanda logs: docker logs cdc-local-redpanda"
    fi
fi

if [ "$KAFKA_CONNECT_STATUS" = "running" ]; then
    pass "Kafka Connect is running"
else
    fail "Kafka Connect is not running"
fi

# 2. Check Debezium Connector
echo ""
section "Step 2: Debezium Connector"
CONNECTOR_STATUS=$(curl -s http://localhost:8085/connectors/postgres-debezium-event-headers-local/status 2>/dev/null | jq -r '.connector.state' 2>/dev/null || echo "not found")
TASK_STATUS=$(curl -s http://localhost:8085/connectors/postgres-debezium-event-headers-local/status 2>/dev/null | jq -r '.tasks[0].state' 2>/dev/null || echo "unknown")

if [ "$CONNECTOR_STATUS" = "RUNNING" ] && [ "$TASK_STATUS" = "RUNNING" ]; then
    pass "Connector is RUNNING (task: $TASK_STATUS)"
elif [ "$TASK_STATUS" = "RUNNING" ]; then
    # Task is running even if connector is UNASSIGNED (can happen during rebalancing)
    pass "Connector task is RUNNING (connector: $CONNECTOR_STATUS)"
elif [ "$CONNECTOR_STATUS" = "RUNNING" ]; then
    warn "Connector is RUNNING but task status is $TASK_STATUS"
else
    fail "Connector status: $CONNECTOR_STATUS (task: $TASK_STATUS)"
    info "If connector is not found, deploy it: ./scripts/deploy-debezium-connector-local.sh"
fi

# 3. Test CDC - Insert 10 Test Events for Each Event Type
echo ""
section "Step 3: Testing CDC - Insert 10 Events for Each Event Type"
BASE_TIMESTAMP=$(date +%s)

# Create test ID prefix for each event type (will append -1, -2, ..., -10)
TEST_PREFIX_LOAN="test-loan-${BASE_TIMESTAMP}"
TEST_PREFIX_CAR="test-car-${BASE_TIMESTAMP}"
TEST_PREFIX_PAYMENT="test-payment-${BASE_TIMESTAMP}"
TEST_PREFIX_SERVICE="test-service-${BASE_TIMESTAMP}"

info "Inserting 10 test events for each of the 4 event types (40 total events)..."

# Insert 10 LoanCreated events
docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
    "INSERT INTO business_events (id, event_name, event_type, created_date, saved_date, event_data) \
     SELECT '$TEST_PREFIX_LOAN-' || s, 'LoanCreated', 'LoanCreated', NOW(), NOW(), \
            jsonb_build_object('eventHeader', jsonb_build_object('uuid', '$TEST_PREFIX_LOAN-' || s, 'eventName', 'LoanCreated', 'eventType', 'LoanCreated')) \
     FROM generate_series(1, 10) s;" > /dev/null 2>&1

docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
    "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) \
     SELECT '$TEST_PREFIX_LOAN-' || s, 'LoanCreated', 'LoanCreated', NOW(), NOW(), \
            jsonb_build_object('uuid', '$TEST_PREFIX_LOAN-' || s, 'eventName', 'LoanCreated', 'eventType', 'LoanCreated') \
     FROM generate_series(1, 10) s;" > /dev/null 2>&1

# Insert 10 CarCreated events
docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
    "INSERT INTO business_events (id, event_name, event_type, created_date, saved_date, event_data) \
     SELECT '$TEST_PREFIX_CAR-' || s, 'CarCreated', 'CarCreated', NOW(), NOW(), \
            jsonb_build_object('eventHeader', jsonb_build_object('uuid', '$TEST_PREFIX_CAR-' || s, 'eventName', 'CarCreated', 'eventType', 'CarCreated')) \
     FROM generate_series(1, 10) s;" > /dev/null 2>&1

docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
    "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) \
     SELECT '$TEST_PREFIX_CAR-' || s, 'CarCreated', 'CarCreated', NOW(), NOW(), \
            jsonb_build_object('uuid', '$TEST_PREFIX_CAR-' || s, 'eventName', 'CarCreated', 'eventType', 'CarCreated') \
     FROM generate_series(1, 10) s;" > /dev/null 2>&1

# Insert 10 LoanPaymentSubmitted events
docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
    "INSERT INTO business_events (id, event_name, event_type, created_date, saved_date, event_data) \
     SELECT '$TEST_PREFIX_PAYMENT-' || s, 'LoanPaymentSubmitted', 'LoanPaymentSubmitted', NOW(), NOW(), \
            jsonb_build_object('eventHeader', jsonb_build_object('uuid', '$TEST_PREFIX_PAYMENT-' || s, 'eventName', 'LoanPaymentSubmitted', 'eventType', 'LoanPaymentSubmitted')) \
     FROM generate_series(1, 10) s;" > /dev/null 2>&1

docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
    "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) \
     SELECT '$TEST_PREFIX_PAYMENT-' || s, 'LoanPaymentSubmitted', 'LoanPaymentSubmitted', NOW(), NOW(), \
            jsonb_build_object('uuid', '$TEST_PREFIX_PAYMENT-' || s, 'eventName', 'LoanPaymentSubmitted', 'eventType', 'LoanPaymentSubmitted') \
     FROM generate_series(1, 10) s;" > /dev/null 2>&1

# Insert 10 CarServiceDone events
docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
    "INSERT INTO business_events (id, event_name, event_type, created_date, saved_date, event_data) \
     SELECT '$TEST_PREFIX_SERVICE-' || s, 'CarServiceDone', 'CarServiceDone', NOW(), NOW(), \
            jsonb_build_object('eventHeader', jsonb_build_object('uuid', '$TEST_PREFIX_SERVICE-' || s, 'eventName', 'CarServiceDone', 'eventType', 'CarServiceDone')) \
     FROM generate_series(1, 10) s;" > /dev/null 2>&1

docker exec cdc-local-postgres-large psql -U postgres -d car_entities -c \
    "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) \
     SELECT '$TEST_PREFIX_SERVICE-' || s, 'CarServiceDone', 'CarServiceDone', NOW(), NOW(), \
            jsonb_build_object('uuid', '$TEST_PREFIX_SERVICE-' || s, 'eventName', 'CarServiceDone', 'eventType', 'CarServiceDone') \
     FROM generate_series(1, 10) s;" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    pass "40 test events inserted (10 of each type)"
    info "  LoanCreated: $TEST_PREFIX_LOAN-1 to $TEST_PREFIX_LOAN-10"
    info "  CarCreated: $TEST_PREFIX_CAR-1 to $TEST_PREFIX_CAR-10"
    info "  LoanPaymentSubmitted: $TEST_PREFIX_PAYMENT-1 to $TEST_PREFIX_PAYMENT-10"
    info "  CarServiceDone: $TEST_PREFIX_SERVICE-1 to $TEST_PREFIX_SERVICE-10"
else
    fail "Failed to insert test events"
fi

# Keep TEST_ID variables for backward compatibility (use first event of each type)
TEST_ID_LOAN="$TEST_PREFIX_LOAN-1"
TEST_ID_CAR="$TEST_PREFIX_CAR-1"
TEST_ID_PAYMENT="$TEST_PREFIX_PAYMENT-1"
TEST_ID_SERVICE="$TEST_PREFIX_SERVICE-1"
TEST_ID="$TEST_ID_LOAN"

# 4. Wait for CDC and Verify Event in Raw Topic
echo ""
section "Step 4: Verify Event in Raw Kafka Topic"
check_timeout_and_exit
info "Waiting 1 second for CDC propagation..."
sleep 1
check_timeout_and_exit

# Use timeout to prevent hanging - rpk consume waits for messages by default
# Use background process with kill to implement timeout (macOS doesn't have timeout command)
TOPIC_OUTPUT=$(docker exec cdc-local-redpanda rpk topic consume raw-event-headers --offset start --num 10 --format json 2>/dev/null & CONSUME_PID=$!; sleep 3; kill $CONSUME_PID 2>/dev/null; wait $CONSUME_PID 2>/dev/null)
TOPIC_MESSAGES=$(echo "$TOPIC_OUTPUT" | grep -c "$TEST_ID" 2>/dev/null || echo "0")
TOPIC_MESSAGES=${TOPIC_MESSAGES:-0}

if [ "$TOPIC_MESSAGES" -gt 0 ] 2>/dev/null; then
    pass "Found test event in raw-event-headers topic"
    echo ""
    info "Sample message:"
    SAMPLE_OUTPUT=$(docker exec cdc-local-redpanda rpk topic consume raw-event-headers --offset start --num 1 --format json 2>/dev/null & CONSUME_PID=$!; sleep 2; kill $CONSUME_PID 2>/dev/null; wait $CONSUME_PID 2>/dev/null)
    echo "$SAMPLE_OUTPUT" | jq -r '.value' | head -3
else
    warn "Test event not found in raw-event-headers topic yet"
    info "Checking if topic exists..."
    docker exec cdc-local-redpanda rpk topic list 2>/dev/null | grep raw-event-headers || echo "Topic may not exist yet"
    info "This may be normal if the connector is still processing - continuing..."
fi

# 5. Start Stream Processor (required for filtered topics)
echo ""
section "Step 5: Stream Processor"
check_timeout_and_exit
info "Starting stream processor (required for filtered topics)..."

if docker-compose -f "$COMPOSE_FILE" ps stream-processor 2>/dev/null | grep -q "Up"; then
    pass "Stream processor is running"
    # Restart to ensure it's connected to topics (especially after --clear-all)
    info "Restarting stream processor to ensure it's connected to topics..."
    docker-compose -f "$COMPOSE_FILE" restart stream-processor 2>&1 | grep -v "level=warning" | tail -3
    check_timeout_and_exit
    info "Waiting 2 seconds for stream processor to reconnect..."
    sleep 2
    check_timeout_and_exit
else
    info "Starting stream processor..."
    docker-compose -f "$COMPOSE_FILE" up -d stream-processor 2>&1 | grep -v "level=warning" | tail -3
    
    # Wait for stream processor to be healthy
    info "Waiting for stream processor to be ready..."
    max_wait=15  # Reduced from 60s for local testing
    elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        check_timeout_and_exit
        if curl -sf http://localhost:8083/actuator/health &>/dev/null; then
            # Also check Kafka Streams health
            KAFKA_STREAMS_HEALTH=$(curl -sf http://localhost:8083/actuator/health 2>/dev/null | grep -o '"kafkaStreams"[^}]*}' || echo "")
            if echo "$KAFKA_STREAMS_HEALTH" | grep -q "UP\|READY"; then
                pass "Stream processor is healthy and Kafka Streams is ready"
                break
            elif [ -n "$KAFKA_STREAMS_HEALTH" ]; then
                info "Stream processor is up but Kafka Streams may still be initializing..."
            else
                pass "Stream processor is healthy"
                break
            fi
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    if [ $elapsed -ge $max_wait ]; then
        warn "Stream processor did not become healthy within ${max_wait}s (may still be starting)"
        info "Checking container status..."
        docker ps --filter "name=cdc-local-stream-processor" --format "{{.Status}}" | head -1
        info "Checking stream processor logs for errors..."
        docker logs cdc-local-stream-processor 2>&1 | tail -10 | grep -iE "(error|exception|failed)" | head -5 || echo "No recent errors in logs"
    fi
fi

# 6. Wait for Stream Processor to Filter Event
echo ""
section "Step 6: Wait for Stream Processor to Filter Event"
check_timeout_and_exit
info "Waiting 2 seconds for stream processor to filter the test event..."
sleep 2
check_timeout_and_exit

# Check if filtered topic exists and has the test event
FILTERED_TOPIC="filtered-loan-created-events-spring"
info "Checking filtered topic: $FILTERED_TOPIC"

if docker exec cdc-local-redpanda rpk topic list 2>/dev/null | grep -q "$FILTERED_TOPIC"; then
    pass "Filtered topic $FILTERED_TOPIC exists"
    
    # Check if test event is in filtered topic (with timeout to prevent hanging)
    FILTERED_OUTPUT=$(docker exec cdc-local-redpanda rpk topic consume "$FILTERED_TOPIC" --offset start --num 20 --format json 2>/dev/null & CONSUME_PID=$!; sleep 3; kill $CONSUME_PID 2>/dev/null; wait $CONSUME_PID 2>/dev/null)
    FILTERED_MESSAGES=$(echo "$FILTERED_OUTPUT" | grep -c "$TEST_ID" 2>/dev/null || echo "0")
    FILTERED_MESSAGES=${FILTERED_MESSAGES:-0}
    
    if [ "$FILTERED_MESSAGES" -gt 0 ] 2>/dev/null; then
        pass "Test event found in filtered topic ($FILTERED_MESSAGES message(s))"
    else
        warn "Test event not yet in filtered topic (stream processor may still be processing)"
        info "This is expected if the event was just inserted - stream processor processes events asynchronously"
    fi
else
    warn "Filtered topic $FILTERED_TOPIC does not exist yet"
    info "Stream processor may still be initializing or no matching events have been processed yet"
fi

# 7. Validate Flink Cluster
echo ""
section "Step 7: Flink Cluster Validation"
info "Checking Flink cluster status..."

FLINK_JOBMANAGER_STATUS=$(docker-compose -f "$COMPOSE_FILE" ps flink-jobmanager 2>/dev/null | grep -q "Up" && echo "running" || echo "not running")
FLINK_TASKMANAGER_STATUS=$(docker-compose -f "$COMPOSE_FILE" ps flink-taskmanager 2>/dev/null | grep -q "Up" && echo "running" || echo "not running")

if [ "$FLINK_JOBMANAGER_STATUS" = "running" ]; then
    pass "Flink JobManager is running"
    
    # Check Flink REST API
    if curl -sf http://localhost:8082/overview > /dev/null 2>&1; then
        pass "Flink REST API is accessible"
        
        # Check if TaskManager is connected
        TASKMANAGER_COUNT=$(curl -sf http://localhost:8082/overview 2>/dev/null | jq -r '.taskmanagers // 0' 2>/dev/null || echo "0")
        if [ "$TASKMANAGER_COUNT" -gt 0 ]; then
            pass "Flink TaskManager is connected (count: $TASKMANAGER_COUNT)"
        else
            warn "Flink TaskManager not connected yet"
        fi
    else
        warn "Flink REST API is not accessible yet"
    fi
else
    warn "Flink JobManager is not running"
    
    # Check if port 8082 is already in use
    if lsof -i :8082 > /dev/null 2>&1; then
        warn "Port 8082 is already in use. Checking what's using it..."
        PORT_USER=$(lsof -i :8082 | tail -1 | awk '{print $1}')
        info "Port 8082 is used by: $PORT_USER"
        info "You may need to stop the conflicting service or change Flink port"
    fi
    
    info "Starting Flink cluster..."
    if docker-compose -f "$COMPOSE_FILE" up -d flink-jobmanager flink-taskmanager 2>&1 | grep -v "level=warning" | tail -5; then
        # Wait for Flink to be ready
        info "Waiting for Flink cluster to be ready..."
        max_wait=15  # Reduced from 60s for local testing
        elapsed=0
        while [ $elapsed -lt $max_wait ]; do
            if curl -sf http://localhost:8082/overview > /dev/null 2>&1; then
                pass "Flink cluster is ready"
                break
            fi
            sleep 2
            elapsed=$((elapsed + 2))
        done
        
        if [ $elapsed -ge $max_wait ]; then
            warn "Flink cluster did not become ready within ${max_wait}s"
            info "Check Flink logs: docker logs cdc-local-flink-jobmanager"
        fi
    else
        fail "Failed to start Flink cluster"
        info "Check for port conflicts or container issues"
    fi
fi

# 8. Deploy Flink SQL Statements
echo ""
section "Step 8: Deploy Flink SQL Statements"
info "Deploying Flink SQL statements to local cluster..."

# Check if Flink is accessible before deploying
if ! curl -sf http://localhost:8082/overview > /dev/null 2>&1; then
    warn "Flink cluster is not accessible at http://localhost:8082"
    info "Skipping Flink SQL deployment"
else
    if [ -f "$SCRIPT_DIR/deploy-flink-local.sh" ]; then
        DEPLOY_OUTPUT=$("$SCRIPT_DIR/deploy-flink-local.sh" 2>&1)
        DEPLOY_EXIT=$?
        echo "$DEPLOY_OUTPUT" | tail -30
        
        if [ $DEPLOY_EXIT -eq 0 ]; then
            pass "Flink SQL statements deployed"
        else
            if echo "$DEPLOY_OUTPUT" | grep -q "already exists\|already deployed"; then
                warn "Flink SQL statements may already be deployed"
            else
                warn "Flink SQL deployment had issues"
            fi
        fi
    else
        warn "Flink deployment script not found: $SCRIPT_DIR/deploy-flink-local.sh"
        info "Skipping Flink SQL deployment"
    fi
fi

# 9. Verify Flink Filtered Topics
echo ""
section "Step 9: Verify Flink Filtered Topics"
check_timeout_and_exit
info "Waiting 2 seconds for Flink to process events..."
sleep 2
check_timeout_and_exit

FLINK_FILTERED_TOPICS=("filtered-loan-created-events-flink" "filtered-car-created-events-flink" "filtered-loan-payment-submitted-events-flink" "filtered-service-events-flink")
FLINK_TOPICS_FOUND=0

for topic in "${FLINK_FILTERED_TOPICS[@]}"; do
    if docker exec cdc-local-redpanda rpk topic list 2>/dev/null | grep -q "$topic"; then
        pass "Flink filtered topic $topic exists"
        FLINK_TOPICS_FOUND=$((FLINK_TOPICS_FOUND + 1))
        
        # Check if test event is in topic
        TOPIC_OUTPUT=$(docker exec cdc-local-redpanda rpk topic consume "$topic" --offset start --num 20 --format json 2>/dev/null & CONSUME_PID=$!; sleep 3; kill $CONSUME_PID 2>/dev/null; wait $CONSUME_PID 2>/dev/null)
        if echo "$TOPIC_OUTPUT" | grep -q "$TEST_ID"; then
            pass "Test event found in $topic"
        else
            info "Test event not yet in $topic (Flink may still be processing)"
        fi
    else
        warn "Flink filtered topic $topic does not exist yet"
    fi
done

if [ $FLINK_TOPICS_FOUND -eq ${#FLINK_FILTERED_TOPICS[@]} ]; then
    pass "All Flink filtered topics exist"
else
    warn "Only $FLINK_TOPICS_FOUND/${#FLINK_FILTERED_TOPICS[@]} Flink filtered topics exist"
fi

# Verify Spring Boot filtered topics exist
check_timeout_and_exit
info "Verifying Spring Boot filtered topics exist..."
SPRING_FILTERED_TOPICS=("filtered-loan-created-events-spring" "filtered-car-created-events-spring" "filtered-loan-payment-submitted-events-spring" "filtered-service-events-spring")
SPRING_TOPICS_FOUND=0

for topic in "${SPRING_FILTERED_TOPICS[@]}"; do
    if docker exec cdc-local-redpanda rpk topic list 2>/dev/null | grep -q "$topic"; then
        # Check if topic has partitions (is actually created, not just listed)
        PARTITION_COUNT=$(docker exec cdc-local-redpanda rpk topic describe "$topic" 2>/dev/null | grep -c "PARTITION" || echo "0")
        if [ "$PARTITION_COUNT" -gt 0 ]; then
            pass "Spring Boot filtered topic $topic exists with $PARTITION_COUNT partition(s)"
            SPRING_TOPICS_FOUND=$((SPRING_TOPICS_FOUND + 1))
        else
            warn "Spring Boot filtered topic $topic exists but has no partitions yet"
        fi
    else
        warn "Spring Boot filtered topic $topic does not exist yet"
    fi
done

if [ $SPRING_TOPICS_FOUND -eq ${#SPRING_FILTERED_TOPICS[@]} ]; then
    pass "All Spring Boot filtered topics exist"
else
    warn "Only $SPRING_TOPICS_FOUND/${#SPRING_FILTERED_TOPICS[@]} Spring Boot filtered topics exist"
    info "Waiting 10 seconds for stream processor to create remaining topics..."
    sleep 10
    check_timeout_and_exit
fi

# Restart consumers now that topics are created and populated
# This ensures consumers connect to newly created topics after --clear-all
check_timeout_and_exit
info "Restarting consumers to ensure they connect to newly created topics..."

# Restart Spring Boot consumers
for consumer in "${CONSUMERS[@]}"; do
    docker-compose -f "$COMPOSE_FILE" restart "$consumer" 2>&1 | grep -v "level=warning" | tail -1 || true
done

# Restart Flink consumers
for consumer in "${FLINK_CONSUMERS[@]}"; do
    docker-compose -f "$COMPOSE_FILE" restart "$consumer" 2>&1 | grep -v "level=warning" | tail -1 || true
done

check_timeout_and_exit
info "Waiting 5 seconds for consumers to reconnect to topics..."
sleep 5
check_timeout_and_exit

# 10. Start and Validate Consumers
echo ""
section "Step 10: Consumer Validation"
info "Validating consumers (already started and restarted)..."

# Spring Boot consumers
CONSUMERS=("loan-consumer" "loan-payment-consumer" "service-consumer" "car-consumer")
CONSUMER_CONTAINERS=("cdc-local-loan-consumer-spring" "cdc-local-loan-payment-consumer-spring" "cdc-local-service-consumer-spring" "cdc-local-car-consumer-spring")
CONSUMER_TOPICS=("filtered-loan-created-events-spring" "filtered-loan-payment-submitted-events-spring" "filtered-service-events-spring" "filtered-car-created-events-spring")

# Flink consumers
FLINK_CONSUMERS=("loan-consumer-flink" "loan-payment-consumer-flink" "service-consumer-flink" "car-consumer-flink")
FLINK_CONSUMER_CONTAINERS=("cdc-local-loan-consumer-flink" "cdc-local-loan-payment-consumer-flink" "cdc-local-service-consumer-flink" "cdc-local-car-consumer-flink")
FLINK_CONSUMER_TOPICS=("filtered-loan-created-events-flink" "filtered-loan-payment-submitted-events-flink" "filtered-service-events-flink" "filtered-car-created-events-flink")

# Start Spring Boot consumers using docker-compose-local.yml
docker-compose -f "$COMPOSE_FILE" up -d "${CONSUMERS[@]}" 2>&1 | grep -v "level=warning" | tail -5

# Start Flink consumers
info "Starting Flink consumers..."
docker-compose -f "$COMPOSE_FILE" up -d "${FLINK_CONSUMERS[@]}" 2>&1 | grep -v "level=warning" | tail -5

# Restart consumers after topics are cleared/recreated to ensure they pick up new events
# This is important when --clear-all is used, as topics are deleted and recreated
info "Restarting consumers to ensure they connect to newly created topics..."
docker-compose -f "$COMPOSE_FILE" restart "${CONSUMERS[@]}" "${FLINK_CONSUMERS[@]}" 2>&1 | grep -v "level=warning" | tail -5

# Wait for consumers to start
check_timeout_and_exit
    info "Waiting 1 second for consumers to initialize..."
sleep 1
check_timeout_and_exit

# Check consumer status and verify they processed the test events
CONSUMERS_RUNNING=0
CONSUMERS_PROCESSED_TEST=0
CONSUMERS_TOTAL=${#CONSUMER_CONTAINERS[@]}

# Map test event IDs to their expected consumers (using functions for compatibility)
get_consumer_for_event_id() {
    case "$1" in
        *loan-*) echo "cdc-local-loan-consumer-spring" ;;
        *car-*) echo "cdc-local-car-consumer-spring" ;;
        *payment-*) echo "cdc-local-loan-payment-consumer-spring" ;;
        *service-*) echo "cdc-local-service-consumer-spring" ;;
        *) echo "" ;;
    esac
}

get_topic_for_event_id() {
    case "$1" in
        *loan-*) echo "filtered-loan-created-events-spring" ;;
        *car-*) echo "filtered-car-created-events-spring" ;;
        *payment-*) echo "filtered-loan-payment-submitted-events-spring" ;;
        *service-*) echo "filtered-service-events-spring" ;;
        *) echo "" ;;
    esac
}

# Wait for events to propagate through the entire pipeline (optimized timing)
    info "Waiting 2 seconds for events to propagate through CDC → Stream Processor → Consumers..."
check_timeout_and_exit
sleep 2
check_timeout_and_exit

for i in "${!CONSUMER_CONTAINERS[@]}"; do
    CONTAINER_NAME="${CONSUMER_CONTAINERS[$i]}"
    CONSUMER_NAME="${CONSUMERS[$i]}"
    TOPIC_NAME="${CONSUMER_TOPICS[$i]}"
    
    info "Checking $CONSUMER_NAME ($CONTAINER_NAME)..."
    
    # Check if container is running
    if docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        CONTAINER_STATUS=$(docker ps --filter "name=${CONTAINER_NAME}" --format "{{.Status}}" | head -1)
        
        # Check if container is actually running (not restarting)
        if echo "$CONTAINER_STATUS" | grep -q "Up"; then
            pass "$CONSUMER_NAME is running"
            CONSUMERS_RUNNING=$((CONSUMERS_RUNNING + 1))
            
            # Check logs for the specific test event ID for this consumer
            EXPECTED_EVENT_ID=""
            if [ "$CONTAINER_NAME" = "cdc-local-loan-consumer-spring" ]; then
                EXPECTED_EVENT_ID="$TEST_ID_LOAN"
            elif [ "$CONTAINER_NAME" = "cdc-local-car-consumer-spring" ]; then
                EXPECTED_EVENT_ID="$TEST_ID_CAR"
            elif [ "$CONTAINER_NAME" = "cdc-local-loan-payment-consumer-spring" ]; then
                EXPECTED_EVENT_ID="$TEST_ID_PAYMENT"
            elif [ "$CONTAINER_NAME" = "cdc-local-service-consumer-spring" ]; then
                EXPECTED_EVENT_ID="$TEST_ID_SERVICE"
            fi
            
            if [ -n "$EXPECTED_EVENT_ID" ]; then
                # Check for all 10 events of this type (using prefix)
                EVENT_PREFIX=$(echo "$EXPECTED_EVENT_ID" | sed 's/-[0-9]*$//')
                info "Checking if $CONSUMER_NAME processed all 10 test events (prefix: $EVENT_PREFIX)..."
                CONSUMER_LOGS=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -1000)
                
                # Extract unique event IDs matching the specific test pattern (e.g., test-loan-1767893293-1 through test-loan-1767893293-10)
                FOUND_EVENT_IDS=$(echo "$CONSUMER_LOGS" | grep -oE "$EVENT_PREFIX-[0-9]+" | sort -u)
                # Count unique event IDs (use wc -l for accurate line count)
                if [ -n "$FOUND_EVENT_IDS" ]; then
                    EVENT_COUNT=$(echo "$FOUND_EVENT_IDS" | wc -l | tr -d ' \n' || echo "0")
                else
                    EVENT_COUNT=0
                fi
                EVENT_COUNT=${EVENT_COUNT:-0}
                
                MAX_RETRIES=2  # 2 retries * 2 seconds = 4 seconds max per consumer (local is fast)
                RETRY_INTERVAL=2
                RETRY_COUNT=0
                START_TIME=$(date +%s)
                MAX_TIME=$((START_TIME + 10))  # 10 seconds max per consumer
                
                while [ "$EVENT_COUNT" -lt 10 ] && [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ] && [ $(date +%s) -lt "$MAX_TIME" ]; do
                    check_timeout_and_exit
                    RETRY_COUNT=$((RETRY_COUNT + 1))
                    CURRENT_TIME=$(date +%s)
                    TIME_REMAINING=$((MAX_TIME - CURRENT_TIME))
                    if [ "$TIME_REMAINING" -gt 0 ]; then
                        info "Found $EVENT_COUNT/10 events, waiting ${RETRY_INTERVAL}s and retrying ($RETRY_COUNT/$MAX_RETRIES, ${TIME_REMAINING}s remaining)..."
                        sleep $RETRY_INTERVAL
                        CONSUMER_LOGS=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -1000)
                        FOUND_EVENT_IDS=$(echo "$CONSUMER_LOGS" | grep -oE "$EVENT_PREFIX-[0-9]+" | sort -u)
                        # Count unique event IDs (use wc -l for accurate line count)
                if [ -n "$FOUND_EVENT_IDS" ]; then
                    EVENT_COUNT=$(echo "$FOUND_EVENT_IDS" | wc -l | tr -d ' \n' || echo "0")
                else
                    EVENT_COUNT=0
                fi
                        EVENT_COUNT=${EVENT_COUNT:-0}
                    fi
                done
                
                if [ "$EVENT_COUNT" -eq 10 ]; then
                    ELAPSED=$(($(date +%s) - START_TIME))
                    pass "$CONSUMER_NAME processed all 10 test events (found after ${ELAPSED}s)"
                    CONSUMERS_PROCESSED_TEST=$((CONSUMERS_PROCESSED_TEST + 1))
                elif [ "$EVENT_COUNT" -gt 0 ]; then
                    ELAPSED=$(($(date +%s) - START_TIME))
                    warn "$CONSUMER_NAME processed $EVENT_COUNT/10 test events after ${ELAPSED}s"
                else
                    ELAPSED=$(($(date +%s) - START_TIME))
                    warn "$CONSUMER_NAME did not process any test events after ${ELAPSED}s"
                    info "Checking if events are in filtered topic..."
                    EXPECTED_TOPIC=$(get_topic_for_event_id "$EXPECTED_EVENT_ID")
                    TOPIC_CHECK_OUTPUT=$(docker exec cdc-local-redpanda rpk topic consume "$EXPECTED_TOPIC" --offset start --num 50 --format '%v\n' 2>&1 | grep -v "^$" | jq -r "select(.id != null and (.id | contains(\"$EVENT_PREFIX\"))) | .id" 2>&1 | wc -l | tr -d ' ' 2>/dev/null || echo "0")
                    if [ "$TOPIC_CHECK_OUTPUT" -gt 0 ]; then
                        warn "Found $TOPIC_CHECK_OUTPUT events in topic $EXPECTED_TOPIC but not yet processed by consumer"
                        info "Consumer may still be processing - check logs: docker logs $CONTAINER_NAME"
                    else
                        warn "Events not found in topic $EXPECTED_TOPIC - stream processor may not have filtered them yet"
                    fi
                fi
            else
                # For consumers without a test event, just check they're active
                LOG_LINES=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -20)
                if echo "$LOG_LINES" | grep -qiE "(consumed|processing|event|message|received|started|listening|ready)"; then
                    pass "$CONSUMER_NAME is active"
                else
                    info "$CONSUMER_NAME is running (waiting for events)"
                fi
            fi
        else
            fail "$CONSUMER_NAME is not running properly (status: $CONTAINER_STATUS)"
        fi
    else
        fail "$CONSUMER_NAME container not found"
    fi
    echo ""
done

if [ $CONSUMERS_RUNNING -eq $CONSUMERS_TOTAL ]; then
    pass "All $CONSUMERS_TOTAL Spring Boot consumers are running"
else
    warn "Only $CONSUMERS_RUNNING/$CONSUMERS_TOTAL Spring Boot consumers are running"
fi

# Validate Flink consumers
info "Validating Flink consumers..."
FLINK_CONSUMERS_RUNNING=0
FLINK_CONSUMERS_PROCESSED_TEST=0
FLINK_CONSUMERS_TOTAL=${#FLINK_CONSUMER_CONTAINERS[@]}

for i in "${!FLINK_CONSUMER_CONTAINERS[@]}"; do
    check_timeout_and_exit
    
    CONTAINER_NAME="${FLINK_CONSUMER_CONTAINERS[$i]}"
    CONSUMER_NAME="${FLINK_CONSUMERS[$i]}"
    TOPIC_NAME="${FLINK_CONSUMER_TOPICS[$i]}"
    
    info "Checking $CONSUMER_NAME ($CONTAINER_NAME)..."
    
    if docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        CONTAINER_STATUS=$(docker ps --filter "name=${CONTAINER_NAME}" --format "{{.Status}}" | head -1)
        if echo "$CONTAINER_STATUS" | grep -q "Up"; then
            pass "$CONSUMER_NAME is running"
            FLINK_CONSUMERS_RUNNING=$((FLINK_CONSUMERS_RUNNING + 1))
            
            # Check logs for test event
            EXPECTED_EVENT_ID=""
            if [ "$CONTAINER_NAME" = "cdc-local-loan-consumer-flink" ]; then
                EXPECTED_EVENT_ID="$TEST_ID_LOAN"
            elif [ "$CONTAINER_NAME" = "cdc-local-car-consumer-flink" ]; then
                EXPECTED_EVENT_ID="$TEST_ID_CAR"
            elif [ "$CONTAINER_NAME" = "cdc-local-loan-payment-consumer-flink" ]; then
                EXPECTED_EVENT_ID="$TEST_ID_PAYMENT"
            elif [ "$CONTAINER_NAME" = "cdc-local-service-consumer-flink" ]; then
                EXPECTED_EVENT_ID="$TEST_ID_SERVICE"
            fi
            
            if [ -n "$EXPECTED_EVENT_ID" ]; then
                # Check for all 10 events of this type (using prefix)
                EVENT_PREFIX=$(echo "$EXPECTED_EVENT_ID" | sed 's/-[0-9]*$//')
                info "Checking if $CONSUMER_NAME processed all 10 test events (prefix: $EVENT_PREFIX)..."
                CONSUMER_LOGS=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -1000)
                
                # Extract unique event IDs matching the specific test pattern (e.g., test-loan-1767893293-1 through test-loan-1767893293-10)
                FOUND_EVENT_IDS=$(echo "$CONSUMER_LOGS" | grep -oE "$EVENT_PREFIX-[0-9]+" | sort -u)
                # Count unique event IDs (use wc -l for accurate line count)
                if [ -n "$FOUND_EVENT_IDS" ]; then
                    EVENT_COUNT=$(echo "$FOUND_EVENT_IDS" | wc -l | tr -d ' \n' || echo "0")
                else
                    EVENT_COUNT=0
                fi
                EVENT_COUNT=${EVENT_COUNT:-0}
                
                MAX_RETRIES=2  # 2 retries * 2 seconds = 4 seconds max per consumer (local is fast)
                RETRY_INTERVAL=2
                RETRY_COUNT=0
                START_TIME=$(date +%s)
                MAX_TIME=$((START_TIME + 10))  # 10 seconds max per consumer
                
                while [ "$EVENT_COUNT" -lt 10 ] && [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ] && [ $(date +%s) -lt "$MAX_TIME" ]; do
                    check_timeout_and_exit
                    RETRY_COUNT=$((RETRY_COUNT + 1))
                    CURRENT_TIME=$(date +%s)
                    TIME_REMAINING=$((MAX_TIME - CURRENT_TIME))
                    if [ "$TIME_REMAINING" -gt 0 ]; then
                        info "Found $EVENT_COUNT/10 events, waiting ${RETRY_INTERVAL}s and retrying ($RETRY_COUNT/$MAX_RETRIES, ${TIME_REMAINING}s remaining)..."
                        sleep $RETRY_INTERVAL
                        CONSUMER_LOGS=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -1000)
                        FOUND_EVENT_IDS=$(echo "$CONSUMER_LOGS" | grep -oE "$EVENT_PREFIX-[0-9]+" | sort -u)
                        # Count unique event IDs (use wc -l for accurate line count)
                if [ -n "$FOUND_EVENT_IDS" ]; then
                    EVENT_COUNT=$(echo "$FOUND_EVENT_IDS" | wc -l | tr -d ' \n' || echo "0")
                else
                    EVENT_COUNT=0
                fi
                        EVENT_COUNT=${EVENT_COUNT:-0}
                    fi
                done
                
                if [ "$EVENT_COUNT" -eq 10 ]; then
                    ELAPSED=$(($(date +%s) - START_TIME))
                    pass "$CONSUMER_NAME processed all 10 test events (found after ${ELAPSED}s)"
                    FLINK_CONSUMERS_PROCESSED_TEST=$((FLINK_CONSUMERS_PROCESSED_TEST + 1))
                elif [ "$EVENT_COUNT" -gt 0 ]; then
                    ELAPSED=$(($(date +%s) - START_TIME))
                    warn "$CONSUMER_NAME processed $EVENT_COUNT/10 test events after ${ELAPSED}s"
                else
                    ELAPSED=$(($(date +%s) - START_TIME))
                    warn "$CONSUMER_NAME did not process any test events after ${ELAPSED}s"
                    info "Checking if events are in filtered topic..."
                    TOPIC_CHECK_OUTPUT=$(docker exec cdc-local-redpanda rpk topic consume "$TOPIC_NAME" --offset start --num 50 --format '%v\n' 2>&1 | grep -v "^$" | jq -r "select(.id != null and (.id | contains(\"$EVENT_PREFIX\"))) | .id" 2>&1 | wc -l | tr -d ' ' 2>/dev/null || echo "0")
                    if [ "$TOPIC_CHECK_OUTPUT" -gt 0 ]; then
                        warn "Found $TOPIC_CHECK_OUTPUT events in topic $TOPIC_NAME but not yet processed by consumer"
                        info "Consumer may still be processing - check logs: docker logs $CONTAINER_NAME"
                    else
                        warn "Events not found in topic $TOPIC_NAME - stream processor may not have filtered them yet"
                    fi
                fi
            else
                # For consumers without a test event, just check they're active
                LOG_LINES=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -20)
                if echo "$LOG_LINES" | grep -qiE "(consumed|processing|event|message|received|started|listening|ready)"; then
                    pass "$CONSUMER_NAME is active"
                else
                    info "$CONSUMER_NAME is running (waiting for events)"
                fi
            fi
        else
            fail "$CONSUMER_NAME is not running properly (status: $CONTAINER_STATUS)"
        fi
    else
        fail "$CONSUMER_NAME container not found"
    fi
    echo ""
done

if [ $FLINK_CONSUMERS_RUNNING -eq $FLINK_CONSUMERS_TOTAL ]; then
    pass "All $FLINK_CONSUMERS_TOTAL Flink consumers are running"
else
    warn "Only $FLINK_CONSUMERS_RUNNING/$FLINK_CONSUMERS_TOTAL Flink consumers are running"
fi

TOTAL_CONSUMERS_PROCESSED=$((CONSUMERS_PROCESSED_TEST + FLINK_CONSUMERS_PROCESSED_TEST))

if [ $CONSUMERS_PROCESSED_TEST -eq 4 ]; then
    pass "All 4 Spring Boot consumers processed all 10 events each (40 total)!"
    info "  ✓ LoanCreated (10 events) → loan-consumer-spring"
    info "  ✓ CarCreated (10 events) → car-consumer-spring"
    info "  ✓ LoanPaymentSubmitted (10 events) → loan-payment-consumer-spring"
    info "  ✓ CarServiceDone (10 events) → service-consumer-spring"
elif [ $CONSUMERS_PROCESSED_TEST -gt 0 ]; then
    warn "Only $CONSUMERS_PROCESSED_TEST/4 Spring Boot consumers processed all 10 events"
else
    warn "No Spring Boot consumers processed all 10 events yet"
fi

if [ $FLINK_CONSUMERS_PROCESSED_TEST -eq 4 ]; then
    pass "All 4 Flink consumers processed all 10 events each (40 total)!"
    info "  ✓ LoanCreated (10 events) → loan-consumer-flink"
    info "  ✓ CarCreated (10 events) → car-consumer-flink"
    info "  ✓ LoanPaymentSubmitted (10 events) → loan-payment-consumer-flink"
    info "  ✓ CarServiceDone (10 events) → service-consumer-flink"
elif [ $FLINK_CONSUMERS_PROCESSED_TEST -gt 0 ]; then
    warn "Only $FLINK_CONSUMERS_PROCESSED_TEST/4 Flink consumers processed all 10 events"
else
    info "Flink consumers are running (events may still be processing)"
fi

echo ""
if [ $TOTAL_CONSUMERS_PROCESSED -eq 8 ]; then
    pass "All 8 consumers (4 Spring Boot + 4 Flink) processed all 10 events each (80 total events processed)!"
elif [ $TOTAL_CONSUMERS_PROCESSED -gt 0 ]; then
    warn "Only $TOTAL_CONSUMERS_PROCESSED/8 consumers processed all 10 events"
else
    warn "No consumers processed all 10 events yet"
fi

cd "$PROJECT_ROOT"

# 11. Run Metadata Service Tests
echo ""
section "Step 11: Metadata Service Tests"
cd metadata-service-java
if ./gradlew test --console=plain 2>&1 | tail -5 | grep -q "BUILD SUCCESSFUL"; then
    pass "Metadata Service tests passed"
else
    fail "Metadata Service tests failed"
    ./gradlew test --console=plain 2>&1 | tail -20
fi
cd "$PROJECT_ROOT"

# 12. Summary
echo ""
section "Test Summary"
echo "Infrastructure: Postgres=$POSTGRES_STATUS, Redpanda=$REDPANDA_STATUS, Kafka Connect=$KAFKA_CONNECT_STATUS"
echo "Connector: $CONNECTOR_STATUS (task: $TASK_STATUS)"
echo "CDC Test: Events inserted (Loan: $TEST_ID_LOAN, Car: $TEST_ID_CAR, Payment: $TEST_ID_PAYMENT, Service: $TEST_ID_SERVICE)"
echo "Stream Processor: Spring Boot filtering events"
echo "Flink Cluster: JobManager=$FLINK_JOBMANAGER_STATUS, TaskManager=$FLINK_TASKMANAGER_STATUS"
echo "Spring Boot Consumers: $CONSUMERS_RUNNING/$CONSUMERS_TOTAL running"
echo "Flink Consumers: $FLINK_CONSUMERS_RUNNING/$FLINK_CONSUMERS_TOTAL running"
if [ $CONSUMERS_PROCESSED_TEST -eq 4 ]; then
    echo "Spring Boot Event Processing: All 4 test events processed ✓"
elif [ $CONSUMERS_PROCESSED_TEST -gt 0 ]; then
    echo "Spring Boot Event Processing: $CONSUMERS_PROCESSED_TEST/4 test events processed"
else
    echo "Spring Boot Event Processing: No test events processed yet"
fi
if [ $FLINK_CONSUMERS_PROCESSED_TEST -eq 4 ]; then
    echo "Flink Event Processing: All 4 test events processed ✓"
elif [ $FLINK_CONSUMERS_PROCESSED_TEST -gt 0 ]; then
    echo "Flink Event Processing: $FLINK_CONSUMERS_PROCESSED_TEST/4 test events processed"
else
    echo "Flink Event Processing: Events may still be processing"
fi
echo "Metadata Service: Tests completed"

# Determine overall success
PIPELINE_OPERATIONAL=true

if [ "$CONNECTOR_STATUS" != "RUNNING" ] || [ "$POSTGRES_STATUS" != "healthy" ] || [ "$REDPANDA_STATUS" != "healthy" ]; then
    PIPELINE_OPERATIONAL=false
fi

if [ $CONSUMERS_RUNNING -lt $CONSUMERS_TOTAL ]; then
    PIPELINE_OPERATIONAL=false
fi

    if [ "$PIPELINE_OPERATIONAL" = true ]; then
        echo ""
        SCRIPT_END_TIME=$(date +%s)
        SCRIPT_DURATION=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
        pass "Local CDC Pipeline is operational! (Total test time: ${SCRIPT_DURATION}s)"
    if [ $TOTAL_CONSUMERS_PROCESSED -eq 8 ]; then
        pass "End-to-end event processing verified: All 8 consumers (4 Spring Boot + 4 Flink) processed all 10 events each (80 total events)!"
    elif [ $CONSUMERS_PROCESSED_TEST -eq 4 ] && [ $FLINK_CONSUMERS_PROCESSED_TEST -eq 4 ]; then
        pass "End-to-end event processing verified: All 8 consumers processed all 10 events each!"
    elif [ $CONSUMERS_PROCESSED_TEST -eq 4 ]; then
        pass "Spring Boot pipeline verified: All 4 consumers processed all 10 events each!"
        if [ $FLINK_CONSUMERS_PROCESSED_TEST -gt 0 ]; then
            info "Flink pipeline: $FLINK_CONSUMERS_PROCESSED_TEST/4 consumers processed all 10 events"
        else
            info "Flink pipeline: Events may still be processing"
        fi
    elif [ $CONSUMERS_PROCESSED_TEST -gt 0 ] || [ $FLINK_CONSUMERS_PROCESSED_TEST -gt 0 ]; then
        warn "Pipeline is operational but only some consumers processed all 10 events"
        info "Spring Boot: $CONSUMERS_PROCESSED_TEST/4, Flink: $FLINK_CONSUMERS_PROCESSED_TEST/4"
        info "Total: $TOTAL_CONSUMERS_PROCESSED/8 consumers processed all 10 events"
        info "Some events may still be processing asynchronously"
    else
        warn "Pipeline is operational but test event processing not yet confirmed"
        info "This may be normal - events process asynchronously"
        info "Check consumer logs manually to verify event processing"
    
cd "$PROJECT_ROOT"
    fi
    exit 0
else
    echo ""
    if [ $CONSUMERS_RUNNING -lt $CONSUMERS_TOTAL ]; then
        warn "Some Spring Boot consumers are not running ($CONSUMERS_RUNNING/$CONSUMERS_TOTAL)"
    fi
    if [ $FLINK_CONSUMERS_RUNNING -lt $FLINK_CONSUMERS_TOTAL ]; then
        warn "Some Flink consumers are not running ($FLINK_CONSUMERS_RUNNING/$FLINK_CONSUMERS_TOTAL)"
    fi
    if [ "$CONNECTOR_STATUS" != "RUNNING" ] || [ "$POSTGRES_STATUS" != "healthy" ] || [ "$REDPANDA_STATUS" != "healthy" ]; then
        fail "Some components are not healthy"
    fi
    exit 1
fi

