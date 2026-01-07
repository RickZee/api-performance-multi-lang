#!/bin/bash
# Deploy Flink SQL Statements to Local Flink Cluster
# Uses Flink REST API to submit SQL statements

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
SQL_FILE="${SQL_FILE:-$PROJECT_ROOT/cdc-streaming/flink-jobs/business-events-routing-local-docker.sql}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploy Flink SQL to Local Cluster${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Flink REST API: $FLINK_REST_API"
echo "SQL File: $SQL_FILE"
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

# Check if SQL file exists
if [ ! -f "$SQL_FILE" ]; then
    echo -e "${RED}✗ SQL file not found: $SQL_FILE${NC}"
    exit 1
fi

# Function to parse SQL file and extract statements
extract_statements() {
    local sql_file=$1
    local in_statement=false
    local current_statement=""
    local statements=()
    local in_comment=false
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and full-line comments
        if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*-- ]]; then
            continue
        fi
        
        # Remove inline comments
        line=$(echo "$line" | sed 's/--.*$//')
        
        # Append to current statement
        if [ -n "$current_statement" ]; then
            current_statement="${current_statement} ${line}"
        else
            current_statement="$line"
        fi
        
        # Check if statement is complete (ends with semicolon)
        if [[ "$current_statement" =~ \;[[:space:]]*$ ]]; then
            # Remove semicolon and trim
            current_statement=$(echo "$current_statement" | sed 's/;[[:space:]]*$//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            if [ -n "$current_statement" ]; then
                statements+=("$current_statement")
            fi
            current_statement=""
        fi
    done < "$sql_file"
    
    # Add last statement if any (without semicolon)
    if [ -n "$current_statement" ]; then
        current_statement=$(echo "$current_statement" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        if [ -n "$current_statement" ]; then
            statements+=("$current_statement")
        fi
    fi
    
    printf '%s\n' "${statements[@]}"
}

# Function to get statement name from SQL
get_statement_name() {
    local sql=$1
    
    # Extract table name from CREATE TABLE
    if [[ "$sql" =~ CREATE[[:space:]]+TABLE[[:space:]]+[\`\"]?([^\`\"[:space:]]+)[\`\"]? ]]; then
        echo "${BASH_REMATCH[1]}"
    # Extract from INSERT INTO
    elif [[ "$sql" =~ INSERT[[:space:]]+INTO[[:space:]]+[\`\"]?([^\`\"[:space:]]+)[\`\"]? ]]; then
        echo "insert-${BASH_REMATCH[1]}"
    else
        echo "statement-$(date +%s)-$RANDOM"
    fi
}

# Function to deploy SQL file using Flink SQL Client
deploy_sql_file() {
    local sql_file=$1
    
    echo -e "${BLUE}Deploying SQL file: $(basename "$sql_file")${NC}"
    
    # Check if SQL file is accessible from Flink container
    # The file should be mounted at /opt/flink/jobs/
    SQL_FILE_IN_CONTAINER="/opt/flink/jobs/$(basename "$sql_file")"
    
    # Execute via SQL Client in embedded mode with -f flag
    # This executes all statements in the file sequentially
    echo -e "${BLUE}Executing SQL statements via Flink SQL Client...${NC}"
    DEPLOY_OUTPUT=$(docker exec cdc-local-flink-jobmanager /opt/flink/bin/sql-client.sh embedded -f "$SQL_FILE_IN_CONTAINER" 2>&1)
    DEPLOY_EXIT=$?
    
    if [ $DEPLOY_EXIT -eq 0 ]; then
        echo -e "${GREEN}✓ SQL file deployed successfully${NC}"
        # Show summary of what was executed
        echo "$DEPLOY_OUTPUT" | grep -E "(CREATE TABLE|INSERT INTO|Table.*created|Job.*submitted)" | head -10 || true
        return 0
    else
        # Check for common errors
        if echo "$DEPLOY_OUTPUT" | grep -qiE "already exists|Table.*already exists"; then
            echo -e "${YELLOW}⚠ Some tables/statements already exist (this is OK if redeploying)${NC}"
            echo "$DEPLOY_OUTPUT" | grep -i "already exists" | head -5
            return 0
        else
            echo -e "${RED}✗ SQL file deployment failed${NC}"
            echo "$DEPLOY_OUTPUT" | tail -20
            return 1
        fi
    fi
}

# Deploy SQL file using Flink SQL Client
# Note: Local Flink doesn't have a REST API for individual statements like Confluent Cloud
# We execute the entire SQL file using the SQL Client
if deploy_sql_file "$SQL_FILE"; then
    echo ""
    echo -e "${GREEN}✓ SQL file deployed successfully!${NC}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Check Flink jobs: curl -s http://localhost:8082/jobs | jq '.'"
    echo "  2. Verify topics in Redpanda: docker exec cdc-local-redpanda rpk topic list | grep filtered"
    echo "  3. Check Flink Web UI: http://localhost:8082"
    echo "  4. Monitor job status: docker logs cdc-local-flink-jobmanager | grep -i 'job\|table'"
    echo ""
    exit 0
else
    echo ""
    echo -e "${RED}✗ SQL file deployment failed${NC}"
    echo -e "${YELLOW}Note: If tables already exist, this is normal when redeploying${NC}"
    echo -e "${YELLOW}Check Flink logs for details: docker logs cdc-local-flink-jobmanager${NC}"
    exit 1
fi

