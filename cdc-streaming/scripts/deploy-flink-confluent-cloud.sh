#!/bin/bash
# Deploy Flink SQL Statement to Confluent Cloud
# CI/CD friendly - uses environment variables, non-interactive

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env file if it exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    echo "Loading environment variables from .env file..."
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
STATEMENT_NAME="${FLINK_STATEMENT_NAME:-event-routing-job}"
COMPUTE_POOL_ID="${FLINK_COMPUTE_POOL_ID:-lfcp-2xqo0m}"
KAFKA_CLUSTER_ID="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"
ENVIRONMENT_ID="${CONFLUENT_ENVIRONMENT_ID:-env-q9n81p}"
CLOUD="${CONFLUENT_CLOUD:-aws}"
REGION="${CONFLUENT_REGION:-us-east-1}"
ACTION="${FLINK_DEPLOY_ACTION:-deploy}"  # deploy, update, delete
FILTERS_CONFIG="${FLINK_FILTERS_CONFIG:-flink-jobs/filters.yaml}"
OUTPUT_SQL="${FLINK_OUTPUT_SQL:-flink-jobs/routing-confluent-cloud.sql}"

# Required environment variables
REQUIRED_VARS=(
    "KAFKA_BOOTSTRAP_SERVERS"
    "SCHEMA_REGISTRY_URL"
    "SCHEMA_REGISTRY_API_KEY"
    "SCHEMA_REGISTRY_API_SECRET"
)

# Check required variables
MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${RED}Error: Missing required environment variables:${NC}"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Flink SQL Deployment to Confluent Cloud${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Configuration:"
echo "  Statement Name: $STATEMENT_NAME"
echo "  Compute Pool: $COMPUTE_POOL_ID"
echo "  Kafka Cluster: $KAFKA_CLUSTER_ID"
echo "  Environment: $ENVIRONMENT_ID"
echo "  Cloud/Region: $CLOUD/$REGION"
echo "  Action: $ACTION"
echo "  Filters Config: $FILTERS_CONFIG"
echo ""

# Check if Confluent CLI is available
if ! command -v confluent &> /dev/null; then
    echo -e "${RED}Error: Confluent CLI not found${NC}"
    echo "Install it with: curl -sL --http1.1 https://cnfl.io/cli | sh -s -- latest"
    exit 1
fi

# Check if user is logged in
if ! confluent environment list > /dev/null 2>&1; then
    echo -e "${RED}Error: Not logged into Confluent Cloud${NC}"
    echo "Run: confluent login"
    exit 1
fi

# Set Flink region
echo -e "${BLUE}Setting Flink region...${NC}"
confluent flink region use --cloud "$CLOUD" --region "$REGION" > /dev/null 2>&1 || {
    echo -e "${YELLOW}Warning: Could not set Flink region automatically${NC}"
}

# Generate SQL for Confluent Cloud
echo -e "${BLUE}Step 1: Generating Confluent Cloud SQL...${NC}"
cd "$PROJECT_ROOT"

# Check if Python is available
if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
    echo -e "${RED}Error: Python not found${NC}"
    exit 1
fi

PYTHON_CMD=$(command -v python3 || command -v python)

$PYTHON_CMD "$SCRIPT_DIR/generate-flink-sql.py" \
  --config "$FILTERS_CONFIG" \
  --output "$OUTPUT_SQL" \
  --kafka-bootstrap "$KAFKA_BOOTSTRAP_SERVERS" \
  --schema-registry "$SCHEMA_REGISTRY_URL" \
  --confluent-cloud \
  --schema-registry-api-key "$SCHEMA_REGISTRY_API_KEY" \
  --schema-registry-api-secret "$SCHEMA_REGISTRY_API_SECRET" \
  --template-dir "$SCRIPT_DIR/templates" \
  --no-validate

if [ ! -f "$OUTPUT_SQL" ]; then
    echo -e "${RED}Error: Failed to generate SQL file${NC}"
    exit 1
fi

echo -e "${GREEN}✓ SQL generated: $OUTPUT_SQL${NC}"
echo ""

# Read SQL file
SQL_CONTENT=$(cat "$OUTPUT_SQL")

# Prepare SQL file for statement extraction
echo -e "${BLUE}Step 2: Preparing SQL statements...${NC}"
STATEMENTS_DIR=$(mktemp -d)
echo "$SQL_CONTENT" > "$STATEMENTS_DIR/full.sql"

# Function to extract statement from SQL content by type
extract_statements() {
    local sql_file="$1"
    local stmt_type="$2"
    
    # Extract CREATE TABLE statements
    if [ "$stmt_type" = "source_table" ]; then
        awk '/CREATE TABLE.*raw-business-events/,/;/' "$sql_file" | grep -v "^--" | tr '\n' ' ' | sed 's/;/;\n/'
    elif [ "$stmt_type" = "sink_table" ]; then
        awk '/CREATE TABLE.*filtered-/,/;/' "$sql_file" | grep -v "^--" | tr '\n' ' ' | sed 's/;/;\n/'
    elif [ "$stmt_type" = "insert" ]; then
        awk '/INSERT INTO/,/;/' "$sql_file" | grep -v "^--" | tr '\n' ' ' | sed 's/;/;\n/'
    fi
}

# Check for existing statements
echo -e "${BLUE}Step 3: Checking for existing statements...${NC}"
EXISTING_STMTS=$(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null | \
    jq -r '.[] | .name' || echo "")

# Function to deploy a single statement
deploy_statement() {
    local stmt_name="$1"
    local stmt_sql="$2"
    local stmt_type="$3"
    
    echo -e "${BLUE}  Deploying: $stmt_name ($stmt_type)...${NC}"
    
    # Check if statement exists
    local existing=$(echo "$EXISTING_STMTS" | grep -Fx "$stmt_name" || echo "")
    
    if [ -n "$existing" ] && [ "$ACTION" = "deploy" ]; then
        echo -e "${YELLOW}    Statement '$stmt_name' already exists. Skipping...${NC}"
        return 0
    fi
    
    # Delete if exists and updating
    if [ -n "$existing" ] && [ "$ACTION" = "update" ]; then
        echo -e "${YELLOW}    Deleting existing statement...${NC}"
        confluent flink statement delete "$stmt_name" --force 2>/dev/null || true
        sleep 1
    fi
    
    # Deploy statement
    if confluent flink statement create "$stmt_name" \
        --compute-pool "$COMPUTE_POOL_ID" \
        --sql "$stmt_sql" \
        --database "$KAFKA_CLUSTER_ID" \
        --wait 2>&1; then
        echo -e "${GREEN}    ✓ Deployed successfully${NC}"
        return 0
    else
        echo -e "${RED}    ✗ Deployment failed${NC}"
        return 1
    fi
}

# Deploy based on action
case "$ACTION" in
    deploy|update)
        echo -e "${BLUE}Step 4: Deploying statements separately...${NC}"
        echo -e "${YELLOW}Note: Confluent Cloud CLI requires separate statements${NC}"
        echo ""
        
        DEPLOYED_COUNT=0
        FAILED_COUNT=0
        
        # Step 1: Deploy source table
        SOURCE_SQL=$(awk '/CREATE TABLE.*raw-business-events/,/;/' "$OUTPUT_SQL" | grep -v "^--" | sed '/^$/d' | tr '\n' ' ' | sed 's/  */ /g')
        if [ -n "$SOURCE_SQL" ]; then
            if deploy_statement "${STATEMENT_NAME}-source" "$SOURCE_SQL" "source_table"; then
                ((DEPLOYED_COUNT++))
            else
                ((FAILED_COUNT++))
            fi
            echo ""
        fi
        
        # Step 2: Deploy sink tables
        SINK_TABLES=$(awk '/CREATE TABLE.*filtered-/,/;/' "$OUTPUT_SQL" | grep -v "^--" | sed '/^$/d')
        SINK_COUNT=0
        CURRENT_SINK=""
        while IFS= read -r line; do
            CURRENT_SINK="${CURRENT_SINK}${line} "
            if [[ "$line" =~ ";" ]]; then
                # Extract topic name from CREATE TABLE statement
                TOPIC_NAME=$(echo "$CURRENT_SINK" | sed -n "s/.*CREATE TABLE \`\([^`]*\)\`.*/\1/p" | head -1)
                if [ -n "$TOPIC_NAME" ]; then
                    STMT_NAME="${STATEMENT_NAME}-sink-${TOPIC_NAME}"
                    if deploy_statement "$STMT_NAME" "$CURRENT_SINK" "sink_table"; then
                        ((DEPLOYED_COUNT++))
                    else
                        ((FAILED_COUNT++))
                    fi
                    echo ""
                fi
                CURRENT_SINK=""
                ((SINK_COUNT++))
            fi
        done <<< "$SINK_TABLES"
        
        # Step 3: Deploy INSERT statements
        INSERT_STATEMENTS=$(awk '/INSERT INTO/,/;/' "$OUTPUT_SQL" | grep -v "^--" | sed '/^$/d')
        INSERT_COUNT=0
        CURRENT_INSERT=""
        while IFS= read -r line; do
            CURRENT_INSERT="${CURRENT_INSERT}${line} "
            if [[ "$line" =~ ";" ]]; then
                # Extract topic name from INSERT INTO statement
                TOPIC_NAME=$(echo "$CURRENT_INSERT" | sed -n "s/.*INSERT INTO \`\([^`]*\)\`.*/\1/p" | head -1)
                if [ -n "$TOPIC_NAME" ]; then
                    STMT_NAME="${STATEMENT_NAME}-insert-${TOPIC_NAME}"
                    if deploy_statement "$STMT_NAME" "$CURRENT_INSERT" "insert"; then
                        ((DEPLOYED_COUNT++))
                    else
                        ((FAILED_COUNT++))
                    fi
                    echo ""
                fi
                CURRENT_INSERT=""
                ((INSERT_COUNT++))
            fi
        done <<< "$INSERT_STATEMENTS"
        
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Deployment Summary${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo "  Deployed: $DEPLOYED_COUNT statements"
        if [ $FAILED_COUNT -gt 0 ]; then
            echo -e "  ${RED}Failed: $FAILED_COUNT statements${NC}"
        fi
        ;;
        
    delete)
        echo -e "${BLUE}Step 4: Deleting all related statements...${NC}"
        
        # Delete all statements with the prefix
        for stmt in $(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null | \
            jq -r ".[] | select(.name | startswith(\"$STATEMENT_NAME\")) | .name" || echo ""); do
            if [ -n "$stmt" ]; then
                echo -e "${BLUE}  Deleting: $stmt...${NC}"
                confluent flink statement delete "$stmt" --force 2>/dev/null && \
                    echo -e "${GREEN}    ✓ Deleted${NC}" || \
                    echo -e "${YELLOW}    ⚠ Failed to delete${NC}"
            fi
        done
        
        echo -e "${GREEN}✓ Cleanup complete${NC}"
        ;;
        
    *)
        echo -e "${RED}Error: Invalid ACTION. Use: deploy, update, or delete${NC}"
        exit 1
        ;;
esac

# Cleanup temp directory
rm -rf "$STATEMENTS_DIR"

# Verify deployment (skip for delete action)
if [ "$ACTION" != "delete" ]; then
    echo ""
    echo -e "${BLUE}Step 5: Verifying deployment...${NC}"
    
    # Wait a moment for status to update
    sleep 3
    
    # Check status of all deployed statements
    RUNNING_COUNT=0
    FAILED_COUNT=0
    PENDING_COUNT=0
    
    for stmt in $(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null | \
        jq -r ".[] | select(.name | startswith(\"$STATEMENT_NAME\")) | .name" || echo ""); do
        if [ -n "$stmt" ]; then
            STATUS=$(confluent flink statement describe "$stmt" \
                --compute-pool "$COMPUTE_POOL_ID" \
                --output json 2>/dev/null | jq -r '.status // "UNKNOWN"')
            
            case "$STATUS" in
                RUNNING)
                    echo -e "${GREEN}  ✓ $stmt: RUNNING${NC}"
                    ((RUNNING_COUNT++))
                    ;;
                FAILED)
                    echo -e "${RED}  ✗ $stmt: FAILED${NC}"
                    ((FAILED_COUNT++))
                    ;;
                *)
                    echo -e "${YELLOW}  ⚠ $stmt: $STATUS${NC}"
                    ((PENDING_COUNT++))
                    ;;
            esac
        fi
    done
    
    echo ""
    if [ $FAILED_COUNT -gt 0 ]; then
        echo -e "${RED}Some statements failed. Check details with:${NC}"
        echo "  confluent flink statement list --compute-pool $COMPUTE_POOL_ID"
        exit 1
    elif [ $RUNNING_COUNT -gt 0 ]; then
        echo -e "${GREEN}✓ $RUNNING_COUNT statement(s) running successfully${NC}"
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete${NC}"
echo -e "${GREEN}========================================${NC}"

