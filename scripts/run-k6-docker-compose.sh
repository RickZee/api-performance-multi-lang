#!/bin/bash
# Run k6 tests using Docker Compose
# This script manages the full stack: PostgreSQL, API, k6, and Confluent connector

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/archive/docker-compose.k6-confluent.yml"
COMPOSE_DIR="$REPO_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default configuration
TEST_TYPE="${TEST_TYPE:-confluent}"  # confluent or sample-events
TEST_MODE="${TEST_MODE:-smoke}"
ACTION="${1:-up}"  # up, down, test, logs, status

usage() {
    echo "Usage: $0 [ACTION] [OPTIONS]"
    echo ""
    echo "Actions:"
    echo "  up              Start all services (default)"
    echo "  down            Stop all services"
    echo "  test            Run k6 test"
    echo "  sample-events   Run k6 sample events test"
    echo "  logs            View logs"
    echo "  status          Check service status"
    echo "  deploy-connector Deploy Confluent connector"
    echo ""
    echo "Options:"
    echo "  --mode MODE     Test mode: smoke, full, saturation (default: smoke)"
    echo "  --test-type TYPE Test type: confluent or sample-events"
    echo ""
    echo "Environment Variables:"
    echo "  KAFKA_BOOTSTRAP_SERVERS    Confluent Cloud Kafka bootstrap servers"
    echo "  KAFKA_API_KEY              Kafka API key"
    echo "  KAFKA_API_SECRET           Kafka API secret"
    echo "  SCHEMA_REGISTRY_URL        Schema Registry URL"
    echo "  SCHEMA_REGISTRY_API_KEY    Schema Registry API key"
    echo "  SCHEMA_REGISTRY_API_SECRET Schema Registry API secret"
    echo ""
    echo "Examples:"
    echo "  $0 up                      # Start all services"
    echo "  $0 test --mode smoke       # Run smoke test"
    echo "  $0 sample-events           # Send sample events"
    echo "  $0 logs                    # View logs"
    echo "  $0 down                    # Stop all services"
}

check_env() {
    local missing=0
    
    if [ -z "$KAFKA_BOOTSTRAP_SERVERS" ]; then
        echo -e "${RED}✗ KAFKA_BOOTSTRAP_SERVERS is not set${NC}"
        missing=1
    fi
    
    if [ -z "$KAFKA_API_KEY" ]; then
        echo -e "${RED}✗ KAFKA_API_KEY is not set${NC}"
        missing=1
    fi
    
    if [ -z "$KAFKA_API_SECRET" ]; then
        echo -e "${RED}✗ KAFKA_API_SECRET is not set${NC}"
        missing=1
    fi
    
    if [ -z "$SCHEMA_REGISTRY_URL" ]; then
        echo -e "${RED}✗ SCHEMA_REGISTRY_URL is not set${NC}"
        missing=1
    fi
    
    if [ -z "$SCHEMA_REGISTRY_API_KEY" ]; then
        echo -e "${RED}✗ SCHEMA_REGISTRY_API_KEY is not set${NC}"
        missing=1
    fi
    
    if [ -z "$SCHEMA_REGISTRY_API_SECRET" ]; then
        echo -e "${RED}✗ SCHEMA_REGISTRY_API_SECRET is not set${NC}"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        echo ""
        echo -e "${CYAN}Create a .env file or export these variables:${NC}"
        echo "  export KAFKA_BOOTSTRAP_SERVERS='pkc-xxxxx.us-east-1.aws.confluent.cloud:9092'"
        echo "  export KAFKA_API_KEY='your-key'"
        echo "  export KAFKA_API_SECRET='your-secret'"
        echo "  export SCHEMA_REGISTRY_URL='https://psrc-xxxxx.us-east-1.aws.confluent.cloud'"
        echo "  export SCHEMA_REGISTRY_API_KEY='your-sr-key'"
        echo "  export SCHEMA_REGISTRY_API_SECRET='your-sr-secret'"
        echo ""
        echo "Or copy .env.example.k6 to .env and fill in values"
        return 1
    fi
    
    return 0
}

case "$ACTION" in
    up)
        echo -e "${BLUE}Starting k6 Confluent testing stack...${NC}"
        
        if ! check_env; then
            exit 1
        fi
        
        cd "$COMPOSE_DIR"
        docker-compose -f "$COMPOSE_FILE" up -d postgres producer-api-java-rest
        
        echo ""
        echo -e "${GREEN}Waiting for services to be ready...${NC}"
        echo "  Waiting for PostgreSQL..."
        sleep 5
        
        echo "  Waiting for Java REST API (may take 30-60 seconds)..."
        for i in {1..60}; do
            if curl -sf http://localhost:8081/api/v1/events/health > /dev/null 2>&1; then
                echo -e "${GREEN}✓ Java REST API is ready${NC}"
                break
            fi
            if [ $i -eq 60 ]; then
                echo -e "${YELLOW}⚠ Java REST API not ready after 60 seconds, continuing anyway...${NC}"
            else
                echo "  Attempt $i/60..."
                sleep 2
            fi
        done
        
        echo "  Services ready!"
        
        echo ""
        echo -e "${CYAN}Service Status:${NC}"
        docker-compose -f "$COMPOSE_FILE" ps
        
        echo ""
        echo -e "${GREEN}Services started!${NC}"
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo "  1. Ensure PostgreSQL is accessible from Confluent Cloud"
        echo "     - For local: Use ngrok or expose public IP"
        echo "     - For production: Use Confluent PrivateLink"
        echo "  2. Deploy connector: $0 deploy-connector"
        echo "  3. Run test: $0 test"
        echo "  4. View logs: $0 logs"
        ;;
    
    down)
        echo -e "${BLUE}Stopping k6 Confluent testing stack...${NC}"
        cd "$COMPOSE_DIR"
        docker-compose -f "$COMPOSE_FILE" down
        echo -e "${GREEN}Services stopped${NC}"
        ;;
    
    test)
        echo -e "${BLUE}Running k6 test...${NC}"
        
        if ! check_env; then
            exit 1
        fi
        
        cd "$COMPOSE_DIR"
        
        # Export k6 environment variables
        export HOST=producer-api-java-rest
        export PORT=8081
        export ENDPOINT=/api/v1/events
        export TEST_MODE="$TEST_MODE"
        
        docker-compose -f "$COMPOSE_FILE" run --rm \
            -e HOST="$HOST" \
            -e PORT="$PORT" \
            -e ENDPOINT="$ENDPOINT" \
            -e TEST_MODE="$TEST_MODE" \
            k6-test
        ;;
    
    sample-events)
        echo -e "${BLUE}Running k6 sample events test...${NC}"
        
        if ! check_env; then
            exit 1
        fi
        
        cd "$COMPOSE_DIR"
        
        export HOST=producer-api-java-rest
        export PORT=8081
        
        docker-compose -f "$COMPOSE_FILE" run --rm \
            -e HOST="$HOST" \
            -e PORT="$PORT" \
            k6-sample-events
        ;;
    
    deploy-connector)
        echo -e "${BLUE}Deploying Confluent Managed Connector...${NC}"
        
        if ! check_env; then
            exit 1
        fi
        
        # Check Confluent CLI
        if ! command -v confluent &> /dev/null; then
            echo -e "${RED}✗ Confluent CLI is not installed${NC}"
            echo "  Install with: brew install confluentinc/tap/cli"
            exit 1
        fi
        
        # Check if logged in
        if ! confluent environment list &> /dev/null; then
            echo -e "${RED}✗ Not logged in to Confluent Cloud${NC}"
            echo "  Login with: confluent login"
            exit 1
        fi
        
        # Get PostgreSQL hostname
        # For local Docker, we need to determine the accessible hostname
        # Options: localhost, public IP, or use DB_HOSTNAME env var
        DB_HOSTNAME="${DB_HOSTNAME:-localhost}"
        DB_PORT="${DB_PORT:-5432}"
        DB_USERNAME="${DB_USERNAME:-postgres}"
        DB_PASSWORD="${DB_PASSWORD:-password}"
        DB_NAME="${DB_NAME:-car_entities}"
        TABLE_INCLUDE_LIST="${TABLE_INCLUDE_LIST:-public.simple_events}"
        
        echo ""
        echo -e "${CYAN}Connector Configuration:${NC}"
        echo "  Database Host: $DB_HOSTNAME"
        echo "  Database Port: $DB_PORT"
        echo "  Database Name: $DB_NAME"
        echo "  Tables: $TABLE_INCLUDE_LIST"
        echo ""
        echo -e "${YELLOW}⚠ Important: PostgreSQL must be accessible from Confluent Cloud${NC}"
        echo "  - For local Docker: Use a tunnel (ngrok) or public IP"
        echo "  - For production: Use Confluent PrivateLink"
        echo ""
        read -p "Continue with deployment? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
        
        # Use the Confluent managed connector deployment script (archived)
        CONNECTOR_CONFIG="$REPO_ROOT/archive/cdc-streaming/connectors/postgres-cdc-source-simple-events-confluent-cloud.json"
        
        if [ ! -f "$CONNECTOR_CONFIG" ]; then
            echo -e "${RED}✗ Connector config not found: $CONNECTOR_CONFIG${NC}"
            exit 1
        fi
        
        # Set environment variables for connector deployment
        export DB_HOSTNAME
        export DB_PORT
        export DB_USERNAME
        export DB_PASSWORD
        export DB_NAME
        export TABLE_INCLUDE_LIST
        export DB_SERVER_NAME="${DB_SERVER_NAME:-postgres-cdc-simple}"
        export SLOT_NAME="${SLOT_NAME:-confluent_cdc_simple_slot}"
        
        # Also need Confluent Cloud credentials
        if [ -z "$KAFKA_API_KEY" ] || [ -z "$KAFKA_API_SECRET" ]; then
            echo -e "${RED}✗ KAFKA_API_KEY and KAFKA_API_SECRET must be set${NC}"
            exit 1
        fi
        
        if [ -z "$SCHEMA_REGISTRY_API_KEY" ] || [ -z "$SCHEMA_REGISTRY_API_SECRET" ] || [ -z "$SCHEMA_REGISTRY_URL" ]; then
            echo -e "${RED}✗ Schema Registry credentials must be set${NC}"
            exit 1
        fi
        
        export KAFKA_API_KEY
        export KAFKA_API_SECRET
        export SCHEMA_REGISTRY_API_KEY
        export SCHEMA_REGISTRY_API_SECRET
        export SCHEMA_REGISTRY_URL
        
        # Deploy using the Confluent connector deployment script (archived)
        "$REPO_ROOT/archive/cdc-streaming/scripts/deploy-confluent-postgres-cdc-connector.sh" "$CONNECTOR_CONFIG"
        ;;
    
    logs)
        SERVICE="${2:-}"
        if [ -n "$SERVICE" ]; then
            docker-compose -f "$COMPOSE_FILE" logs -f "$SERVICE"
        else
            docker-compose -f "$COMPOSE_FILE" logs -f
        fi
        ;;
    
    status)
        echo -e "${BLUE}Service Status:${NC}"
        cd "$COMPOSE_DIR"
        docker-compose -f "$COMPOSE_FILE" ps
        
        echo ""
        echo -e "${BLUE}Health Checks:${NC}"
        
        # Check PostgreSQL
        if docker exec cdc-postgres-k6 pg_isready -U postgres > /dev/null 2>&1; then
            echo -e "${GREEN}✓ PostgreSQL is healthy${NC}"
        else
            echo -e "${RED}✗ PostgreSQL is not healthy${NC}"
        fi
        
        # Check API
        if curl -sf http://localhost:8081/api/v1/events/health > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Java REST API is healthy${NC}"
        else
            echo -e "${RED}✗ Java REST API is not healthy${NC}"
        fi
        
        # Check Confluent connector (if deployed)
        if command -v confluent &> /dev/null && confluent environment list &> /dev/null; then
            CONNECTOR_NAME="postgres-cdc-source-simple-events-confluent-cloud"
            if confluent connector describe "$CONNECTOR_NAME" &> /dev/null 2>&1; then
                echo -e "${GREEN}✓ Confluent connector is deployed${NC}"
                STATUS=$(confluent connector describe "$CONNECTOR_NAME" --output json 2>/dev/null | jq -r '.status.connector.state' 2>/dev/null || echo "unknown")
                echo "  Status: $STATUS"
            else
                echo -e "${YELLOW}⚠ Confluent connector not deployed${NC}"
                echo "  Deploy with: $0 deploy-connector"
            fi
        else
            echo -e "${YELLOW}⚠ Confluent CLI not available${NC}"
        fi
        ;;
    
    --help|-h)
        usage
        ;;
    
    *)
        echo -e "${RED}Unknown action: $ACTION${NC}"
        usage
        exit 1
        ;;
esac
