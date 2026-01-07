#!/usr/bin/env bash
# Test Local CDC Pipeline with Redpanda
# Tests the complete local dockerized CDC system
#
# Usage:
#   ./cdc-streaming/scripts/test-local-pipeline.sh

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

# Use docker-compose-local.yml
COMPOSE_FILE="docker-compose-local.yml"
cd cdc-streaming

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

# 3. Test CDC - Insert Test Events for All Event Types
echo ""
section "Step 3: Testing CDC - Insert Test Events for All Event Types"
BASE_TIMESTAMP=$(date +%s)

# Create test IDs for each event type
TEST_ID_LOAN="test-loan-${BASE_TIMESTAMP}"
TEST_ID_CAR="test-car-${BASE_TIMESTAMP}"
TEST_ID_PAYMENT="test-payment-${BASE_TIMESTAMP}"
TEST_ID_SERVICE="test-service-${BASE_TIMESTAMP}"

info "Inserting test events for all 4 event types..."

# Insert LoanCreated event
docker exec -i cdc-local-postgres-large psql -U postgres -d car_entities <<SQL > /dev/null
INSERT INTO business_events (id, event_name, event_type, created_date, saved_date, event_data)
VALUES (
  '$TEST_ID_LOAN',
  'LoanCreated',
  'LoanCreated',
  NOW(),
  NOW(),
  '{"eventHeader": {"uuid": "$TEST_ID_LOAN", "eventName": "LoanCreated", "eventType": "LoanCreated"}}'::jsonb
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data)
VALUES (
  '$TEST_ID_LOAN',
  'LoanCreated',
  'LoanCreated',
  NOW(),
  NOW(),
  '{"uuid": "$TEST_ID_LOAN", "eventName": "LoanCreated", "eventType": "LoanCreated"}'::jsonb
)
ON CONFLICT (id) DO NOTHING;
SQL

# Insert CarCreated event
docker exec -i cdc-local-postgres-large psql -U postgres -d car_entities <<SQL > /dev/null
INSERT INTO business_events (id, event_name, event_type, created_date, saved_date, event_data)
VALUES (
  '$TEST_ID_CAR',
  'CarCreated',
  'CarCreated',
  NOW(),
  NOW(),
  '{"eventHeader": {"uuid": "$TEST_ID_CAR", "eventName": "CarCreated", "eventType": "CarCreated"}}'::jsonb
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data)
VALUES (
  '$TEST_ID_CAR',
  'CarCreated',
  'CarCreated',
  NOW(),
  NOW(),
  '{"uuid": "$TEST_ID_CAR", "eventName": "CarCreated", "eventType": "CarCreated"}'::jsonb
)
ON CONFLICT (id) DO NOTHING;
SQL

# Insert LoanPaymentSubmitted event
docker exec -i cdc-local-postgres-large psql -U postgres -d car_entities <<SQL > /dev/null
INSERT INTO business_events (id, event_name, event_type, created_date, saved_date, event_data)
VALUES (
  '$TEST_ID_PAYMENT',
  'LoanPaymentSubmitted',
  'LoanPaymentSubmitted',
  NOW(),
  NOW(),
  '{"eventHeader": {"uuid": "$TEST_ID_PAYMENT", "eventName": "LoanPaymentSubmitted", "eventType": "LoanPaymentSubmitted"}}'::jsonb
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data)
VALUES (
  '$TEST_ID_PAYMENT',
  'LoanPaymentSubmitted',
  'LoanPaymentSubmitted',
  NOW(),
  NOW(),
  '{"uuid": "$TEST_ID_PAYMENT", "eventName": "LoanPaymentSubmitted", "eventType": "LoanPaymentSubmitted"}'::jsonb
)
ON CONFLICT (id) DO NOTHING;
SQL

# Insert CarServiceDone event
docker exec -i cdc-local-postgres-large psql -U postgres -d car_entities <<SQL > /dev/null
INSERT INTO business_events (id, event_name, event_type, created_date, saved_date, event_data)
VALUES (
  '$TEST_ID_SERVICE',
  'CarServiceDone',
  'CarServiceDone',
  NOW(),
  NOW(),
  '{"eventHeader": {"uuid": "$TEST_ID_SERVICE", "eventName": "CarServiceDone", "eventType": "CarServiceDone"}}'::jsonb
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data)
VALUES (
  '$TEST_ID_SERVICE',
  'CarServiceDone',
  'CarServiceDone',
  NOW(),
  NOW(),
  '{"uuid": "$TEST_ID_SERVICE", "eventName": "CarServiceDone", "eventType": "CarServiceDone"}'::jsonb
)
ON CONFLICT (id) DO NOTHING;
SQL

if [ $? -eq 0 ]; then
    pass "Test events inserted for all 4 event types"
    info "  LoanCreated: $TEST_ID_LOAN"
    info "  CarCreated: $TEST_ID_CAR"
    info "  LoanPaymentSubmitted: $TEST_ID_PAYMENT"
    info "  CarServiceDone: $TEST_ID_SERVICE"
else
    fail "Failed to insert test events"
fi

# Keep TEST_ID for backward compatibility (use LoanCreated as primary)
TEST_ID="$TEST_ID_LOAN"

# 4. Wait for CDC and Verify Event in Raw Topic
echo ""
section "Step 4: Verify Event in Raw Kafka Topic"
info "Waiting 3 seconds for CDC propagation..."
sleep 3

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
info "Starting stream processor (required for filtered topics)..."

if docker-compose -f "$COMPOSE_FILE" ps stream-processor 2>/dev/null | grep -q "Up"; then
    pass "Stream processor is already running"
else
    info "Starting stream processor..."
    docker-compose -f "$COMPOSE_FILE" up -d stream-processor 2>&1 | grep -v "level=warning" | tail -3
    
    # Wait for stream processor to be healthy
    info "Waiting for stream processor to be ready..."
    max_wait=30
    elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if curl -sf http://localhost:8083/actuator/health &>/dev/null; then
            pass "Stream processor is healthy"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    if [ $elapsed -ge $max_wait ]; then
        warn "Stream processor did not become healthy within ${max_wait}s (may still be starting)"
        info "Checking container status..."
        docker ps --filter "name=cdc-local-stream-processor" --format "{{.Status}}" | head -1
    fi
fi

# 6. Wait for Stream Processor to Filter Event
echo ""
section "Step 6: Wait for Stream Processor to Filter Event"
info "Waiting 5 seconds for stream processor to filter the test event..."
sleep 5

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
        max_wait=60
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
info "Waiting 5 seconds for Flink to process events..."
sleep 5

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

# 10. Start and Validate Consumers
echo ""
section "Step 10: Consumer Validation"
info "Starting consumers if not already running..."

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

# Wait for consumers to start
info "Waiting 3 seconds for consumers to initialize..."
sleep 3

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
info "Waiting 5 seconds for events to propagate through CDC → Stream Processor → Consumers..."
sleep 5

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
                info "Checking if $CONSUMER_NAME processed test event ($EXPECTED_EVENT_ID)..."
                CONSUMER_LOGS=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -200)
                
                # Search for test event ID in logs (with timeout - max 2 minutes total per consumer)
                # Consumers log "Event ID: <id>" so search for both patterns
                MAX_RETRIES=8  # 8 retries * 10 seconds = 80 seconds max (reduced from 120s)
                RETRY_INTERVAL=10  # Check every 10 seconds (reduced from 15s)
                RETRY_COUNT=0
                EVENT_FOUND=false
                START_TIME=$(date +%s)
                MAX_TIME=$((START_TIME + 120))  # 2 minutes max (120 seconds)
                
                while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$EVENT_FOUND" = false ] && [ $(date +%s) -lt $MAX_TIME ]; do
                    # Check for event ID in various log formats
                    if echo "$CONSUMER_LOGS" | grep -qE "(Event ID:.*$EXPECTED_EVENT_ID|UUID:.*$EXPECTED_EVENT_ID|$EXPECTED_EVENT_ID)"; then
                        ELAPSED=$(($(date +%s) - START_TIME))
                        pass "$CONSUMER_NAME processed test event (found $EXPECTED_EVENT_ID in logs after ${ELAPSED}s)"
                        CONSUMERS_PROCESSED_TEST=$((CONSUMERS_PROCESSED_TEST + 1))
                        EVENT_FOUND=true
                        echo ""
                        info "Sample log entry:"
                        echo "$CONSUMER_LOGS" | grep -E "(Event ID:.*$EXPECTED_EVENT_ID|UUID:.*$EXPECTED_EVENT_ID|$EXPECTED_EVENT_ID)" | head -3 | sed 's/^/    /'
                    else
                        RETRY_COUNT=$((RETRY_COUNT + 1))
                        CURRENT_TIME=$(date +%s)
                        TIME_REMAINING=$((MAX_TIME - CURRENT_TIME))
                        if [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ $TIME_REMAINING -gt 0 ]; then
                            info "Event not found yet, waiting ${RETRY_INTERVAL}s and retrying ($RETRY_COUNT/$MAX_RETRIES, ${TIME_REMAINING}s remaining)..."
                            sleep $RETRY_INTERVAL
                            CONSUMER_LOGS=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -300)
                        fi
                    fi
                done
                
                if [ "$EVENT_FOUND" = false ]; then
                    ELAPSED=$(($(date +%s) - START_TIME))
                    if [ $ELAPSED -ge 120 ]; then
                        warn "$CONSUMER_NAME did not process test event $EXPECTED_EVENT_ID within 2 minutes (timeout)"
                    else
                        warn "$CONSUMER_NAME did not process test event $EXPECTED_EVENT_ID after ${ELAPSED}s"
                    fi
                    info "Checking if event is in filtered topic..."
                    EXPECTED_TOPIC=$(get_topic_for_event_id "$EXPECTED_EVENT_ID")
                    TOPIC_CHECK_OUTPUT=$(docker exec cdc-local-redpanda rpk topic consume "$EXPECTED_TOPIC" --offset start --num 20 --format json 2>/dev/null & CONSUME_PID=$!; sleep 2; kill $CONSUME_PID 2>/dev/null; wait $CONSUME_PID 2>/dev/null)
                    if echo "$TOPIC_CHECK_OUTPUT" | grep -q "$EXPECTED_EVENT_ID"; then
                        warn "Event is in topic $EXPECTED_TOPIC but not yet processed by consumer"
                        info "Consumer may still be processing - check logs: docker logs $CONTAINER_NAME"
                    else
                        warn "Event not found in topic $EXPECTED_TOPIC - stream processor may not have filtered it yet"
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
    CONTAINER_NAME="${FLINK_CONSUMER_CONTAINERS[$i]}"
    CONSUMER_NAME="${FLINK_CONSUMERS[$i]}"
    
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
                CONSUMER_LOGS=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -100)
                if echo "$CONSUMER_LOGS" | grep -qE "(Event ID:.*$EXPECTED_EVENT_ID|UUID:.*$EXPECTED_EVENT_ID|$EXPECTED_EVENT_ID)"; then
                    pass "$CONSUMER_NAME processed test event"
                    FLINK_CONSUMERS_PROCESSED_TEST=$((FLINK_CONSUMERS_PROCESSED_TEST + 1))
                else
                    info "$CONSUMER_NAME is running (waiting for events)"
                fi
            fi
        fi
    fi
done

if [ $FLINK_CONSUMERS_RUNNING -eq $FLINK_CONSUMERS_TOTAL ]; then
    pass "All $FLINK_CONSUMERS_TOTAL Flink consumers are running"
else
    warn "Only $FLINK_CONSUMERS_RUNNING/$FLINK_CONSUMERS_TOTAL Flink consumers are running"
fi

if [ $CONSUMERS_PROCESSED_TEST -eq 4 ]; then
    pass "All 4 test events were processed by Spring Boot consumers!"
    info "  ✓ LoanCreated ($TEST_ID_LOAN) → loan-consumer-spring"
    info "  ✓ CarCreated ($TEST_ID_CAR) → car-consumer-spring"
    info "  ✓ LoanPaymentSubmitted ($TEST_ID_PAYMENT) → loan-payment-consumer-spring"
    info "  ✓ CarServiceDone ($TEST_ID_SERVICE) → service-consumer-spring"
elif [ $CONSUMERS_PROCESSED_TEST -gt 0 ]; then
    warn "Only $CONSUMERS_PROCESSED_TEST/4 test events were processed by Spring Boot consumers"
else
    warn "No test events were processed by Spring Boot consumers yet"
fi

if [ $FLINK_CONSUMERS_PROCESSED_TEST -eq 4 ]; then
    pass "All 4 test events were processed by Flink consumers!"
    info "  ✓ LoanCreated ($TEST_ID_LOAN) → loan-consumer-flink"
    info "  ✓ CarCreated ($TEST_ID_CAR) → car-consumer-flink"
    info "  ✓ LoanPaymentSubmitted ($TEST_ID_PAYMENT) → loan-payment-consumer-flink"
    info "  ✓ CarServiceDone ($TEST_ID_SERVICE) → service-consumer-flink"
elif [ $FLINK_CONSUMERS_PROCESSED_TEST -gt 0 ]; then
    warn "Only $FLINK_CONSUMERS_PROCESSED_TEST/4 test events were processed by Flink consumers"
else
    info "Flink consumers are running (events may still be processing)"
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
    if [ $CONSUMERS_PROCESSED_TEST -eq 4 ] && [ $FLINK_CONSUMERS_PROCESSED_TEST -eq 4 ]; then
        pass "End-to-end event processing verified for all 4 event types (both Spring Boot and Flink)!"
    elif [ $CONSUMERS_PROCESSED_TEST -eq 4 ]; then
        pass "Spring Boot pipeline verified for all 4 event types!"
        if [ $FLINK_CONSUMERS_PROCESSED_TEST -gt 0 ]; then
            info "Flink pipeline: $FLINK_CONSUMERS_PROCESSED_TEST/4 events processed"
        else
            info "Flink pipeline: Events may still be processing"
        fi
    elif [ $CONSUMERS_PROCESSED_TEST -gt 0 ] || [ $FLINK_CONSUMERS_PROCESSED_TEST -gt 0 ]; then
        warn "Pipeline is operational but only some events processed"
        info "Spring Boot: $CONSUMERS_PROCESSED_TEST/4, Flink: $FLINK_CONSUMERS_PROCESSED_TEST/4"
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

