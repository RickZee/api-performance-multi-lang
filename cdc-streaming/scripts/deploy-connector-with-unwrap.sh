#!/bin/bash
# Deploy CDC Connector with ExtractNewRecordState Transform
# This script deploys the PostgresCdcSource connector with the ExtractNewRecordState
# transform configured to produce flat structure with __op, __table, __ts_ms fields

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
CONNECTOR_CONFIG_FILE="$PROJECT_ROOT/cdc-streaming/connectors/postgres-cdc-source-business-events-confluent-cloud-fixed.json"
ENV_ID="${CONFLUENT_ENV_ID:-env-q9n81p}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Deploy CDC Connector with ExtractNewRecordState Transform${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check prerequisites
echo -e "${BLUE}Step 1: Checking prerequisites...${NC}"

if ! command -v confluent &> /dev/null; then
    echo -e "${RED}✗ Confluent CLI not found${NC}"
    echo "  Install: https://docs.confluent.io/confluent-cli/current/install.html"
    exit 1
fi

if [ ! -f "$CONNECTOR_CONFIG_FILE" ]; then
    echo -e "${RED}✗ Connector config file not found: $CONNECTOR_CONFIG_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites met${NC}"
echo ""

# Check if connector config has ExtractNewRecordState
echo -e "${BLUE}Step 2: Validating connector configuration...${NC}"

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠ jq not found, skipping config validation${NC}"
else
    TRANSFORMS=$(jq -r '.config.transforms' "$CONNECTOR_CONFIG_FILE" 2>/dev/null || echo "")
    UNWRAP_TYPE=$(jq -r '.config."transforms.unwrap.type"' "$CONNECTOR_CONFIG_FILE" 2>/dev/null || echo "")
    ADD_FIELDS=$(jq -r '.config."transforms.unwrap.add.fields"' "$CONNECTOR_CONFIG_FILE" 2>/dev/null || echo "")
    PREFIX=$(jq -r '.config."transforms.unwrap.add.fields.prefix"' "$CONNECTOR_CONFIG_FILE" 2>/dev/null || echo "")
    
    if [[ "$TRANSFORMS" == *"unwrap"* ]] && [[ "$UNWRAP_TYPE" == "io.debezium.transforms.ExtractNewRecordState" ]]; then
        echo -e "${GREEN}✓ ExtractNewRecordState transform configured${NC}"
        echo "  Transforms: $TRANSFORMS"
        echo "  Add fields: $ADD_FIELDS"
        echo "  Prefix: $PREFIX"
    else
        echo -e "${YELLOW}⚠ ExtractNewRecordState transform may not be configured${NC}"
        echo "  Please verify the config file has the unwrap transform"
    fi
fi
echo ""

# Check for existing connector
echo -e "${BLUE}Step 3: Checking for existing connector...${NC}"

EXISTING_CONNECTOR=$(confluent connect cluster list --output json 2>/dev/null | \
    jq -r '.data[] | select(.name | contains("business-events")) | .id' 2>/dev/null | head -1 || echo "")

if [ -n "$EXISTING_CONNECTOR" ]; then
    CONNECTOR_NAME=$(confluent connect cluster describe "$EXISTING_CONNECTOR" --output json 2>/dev/null | \
        jq -r '.connector.name' 2>/dev/null || echo "unknown")
    echo -e "${YELLOW}⚠ Found existing connector: $CONNECTOR_NAME (ID: $EXISTING_CONNECTOR)${NC}"
    echo ""
    read -p "Delete existing connector and create new one? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Deleting existing connector...${NC}"
        confluent connect cluster pause "$EXISTING_CONNECTOR" 2>/dev/null || true
        sleep 3
        confluent connect cluster delete "$EXISTING_CONNECTOR" --force 2>/dev/null || true
        echo -e "${GREEN}✓ Existing connector deleted${NC}"
        EXISTING_CONNECTOR=""
    else
        echo -e "${YELLOW}Keeping existing connector. Exiting.${NC}"
        exit 0
    fi
else
    echo -e "${GREEN}✓ No existing connector found${NC}"
fi
echo ""

# Prepare config file
echo -e "${BLUE}Step 4: Preparing connector configuration...${NC}"

TEMP_CONFIG=$(mktemp)
cp "$CONNECTOR_CONFIG_FILE" "$TEMP_CONFIG"

# Ensure config has correct structure
if command -v jq &> /dev/null; then
    # Validate and fix transforms if needed
    TRANSFORMS_VAL=$(jq -r '.config.transforms' "$TEMP_CONFIG")
    if [[ "$TRANSFORMS_VAL" == *"unwrap"* ]]; then
        # Check for duplicates
        TRANSFORMS_LIST=$(echo "$TRANSFORMS_VAL" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort -u | tr '\n' ',' | sed 's/,$//')
        if [ "$TRANSFORMS_VAL" != "$TRANSFORMS_LIST" ]; then
            echo -e "${YELLOW}⚠ Removing duplicate transforms${NC}"
            jq ".config.transforms = \"$TRANSFORMS_LIST\"" "$TEMP_CONFIG" > "${TEMP_CONFIG}.tmp" && mv "${TEMP_CONFIG}.tmp" "$TEMP_CONFIG"
        fi
    fi
fi

echo -e "${GREEN}✓ Configuration prepared${NC}"
echo ""

# Try to deploy via CLI
echo -e "${BLUE}Step 5: Deploying connector via CLI...${NC}"

DEPLOY_SUCCESS=false
CLI_ERROR=""

# Capture both stdout and stderr
if confluent connect cluster create --config-file "$TEMP_CONFIG" > /tmp/connector-deploy.log 2>&1; then
    # Check if output contains error messages
    if grep -qi "error\|invalid\|failed" /tmp/connector-deploy.log; then
        DEPLOY_SUCCESS=false
        CLI_ERROR=$(cat /tmp/connector-deploy.log)
        echo -e "${YELLOW}⚠ CLI deployment failed${NC}"
        cat /tmp/connector-deploy.log
    else
        DEPLOY_SUCCESS=true
        echo -e "${GREEN}✓ Connector deployed successfully via CLI!${NC}"
        cat /tmp/connector-deploy.log
    fi
else
    DEPLOY_SUCCESS=false
    CLI_ERROR=$(cat /tmp/connector-deploy.log 2>/dev/null || echo "")
    echo -e "${YELLOW}⚠ CLI deployment failed${NC}"
    cat /tmp/connector-deploy.log
    
    # Check for specific errors
    if echo "$CLI_ERROR" | grep -q "Duplicate alias"; then
        echo -e "${YELLOW}⚠ Duplicate transform error detected${NC}"
        echo "  This is a known issue with PostgresCdcSource connector"
        echo "  Please use Confluent Cloud Console for deployment"
    elif echo "$CLI_ERROR" | grep -q "unable to find connector plugin"; then
        echo -e "${YELLOW}⚠ Connector plugin not found${NC}"
        echo "  Please ensure PostgresCdcSource is available in your environment"
    fi
fi

echo ""

# If CLI failed, provide Console instructions
if [ "$DEPLOY_SUCCESS" = false ]; then
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Manual Deployment via Confluent Cloud Console${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}Step 1: Open Confluent Cloud Console${NC}"
    echo "  https://confluent.cloud/environments/$ENV_ID/connectors"
    echo ""
    echo -e "${BLUE}Step 2: Click 'Add connector'${NC}"
    echo ""
    echo -e "${BLUE}Step 3: Select 'PostgresCdcSource'${NC}"
    echo "  (Managed PostgreSQL CDC connector)"
    echo ""
    echo -e "${BLUE}Step 4: Configure the connector${NC}"
    echo "  Use the configuration from:"
    echo "  $CONNECTOR_CONFIG_FILE"
    echo ""
    echo -e "${BLUE}Step 5: Key Configuration Values:${NC}"
    
    if command -v jq &> /dev/null; then
        echo "  Database hostname: $(jq -r '.config."database.hostname"' "$CONNECTOR_CONFIG_FILE")"
        echo "  Database name: $(jq -r '.config."database.dbname"' "$CONNECTOR_CONFIG_FILE")"
        echo "  Table include list: $(jq -r '.config."table.include.list"' "$CONNECTOR_CONFIG_FILE")"
        echo "  Output format: $(jq -r '.config."output.data.format"' "$CONNECTOR_CONFIG_FILE")"
        echo ""
        echo -e "${BLUE}Step 6: Transform Configuration (CRITICAL):${NC}"
        echo "  transforms: $(jq -r '.config.transforms' "$CONNECTOR_CONFIG_FILE")"
        echo "  transforms.unwrap.type: $(jq -r '.config."transforms.unwrap.type"' "$CONNECTOR_CONFIG_FILE")"
        echo "  transforms.unwrap.add.fields: $(jq -r '.config."transforms.unwrap.add.fields"' "$CONNECTOR_CONFIG_FILE")"
        echo "  transforms.unwrap.add.fields.prefix: $(jq -r '.config."transforms.unwrap.add.fields.prefix"' "$CONNECTOR_CONFIG_FILE")"
        echo "  transforms.route.type: $(jq -r '.config."transforms.route.type"' "$CONNECTOR_CONFIG_FILE")"
        echo "  transforms.route.regex: $(jq -r '.config."transforms.route.regex"' "$CONNECTOR_CONFIG_FILE")"
        echo "  transforms.route.replacement: $(jq -r '.config."transforms.route.replacement"' "$CONNECTOR_CONFIG_FILE")"
    else
        echo "  (Install jq to see formatted config values)"
        echo "  Config file: $CONNECTOR_CONFIG_FILE"
    fi
    echo ""
    echo -e "${YELLOW}⚠ IMPORTANT: Ensure all transform settings are configured correctly${NC}"
    echo "  The ExtractNewRecordState transform is required for Flink compatibility"
    echo ""
    
    # Display full config (without secrets)
    echo -e "${BLUE}Full Configuration (secrets hidden):${NC}"
    if command -v jq &> /dev/null; then
        jq '.config | to_entries | map(select(.key | contains("password") or contains("secret")) | .value = "***") | from_entries' "$CONNECTOR_CONFIG_FILE" 2>/dev/null | head -30
    fi
    echo ""
    
    read -p "Press Enter after deploying the connector via Console to verify..."
    echo ""
fi

# Verify deployment
echo -e "${BLUE}Step 6: Verifying connector deployment...${NC}"

sleep 5

NEW_CONNECTOR=$(confluent connect cluster list --output json 2>/dev/null | \
    jq -r '.data[] | select(.name | contains("business-events")) | .id' 2>/dev/null | head -1 || echo "")

if [ -z "$NEW_CONNECTOR" ]; then
    echo -e "${YELLOW}⚠ Connector not found. It may still be starting...${NC}"
    echo "  Please check the Confluent Cloud Console"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

echo -e "${GREEN}✓ Connector found: $NEW_CONNECTOR${NC}"

# Get connector details
CONNECTOR_DETAILS=$(confluent connect cluster describe "$NEW_CONNECTOR" --output json 2>/dev/null || echo "{}")

if command -v jq &> /dev/null; then
    CONNECTOR_NAME=$(echo "$CONNECTOR_DETAILS" | jq -r '.connector.name' 2>/dev/null || echo "unknown")
    CONNECTOR_STATUS=$(echo "$CONNECTOR_DETAILS" | jq -r '.status.connector.state' 2>/dev/null || echo "unknown")
    TASK_STATUS=$(echo "$CONNECTOR_DETAILS" | jq -r '.status.tasks[0].state' 2>/dev/null || echo "unknown")
    
    echo "  Name: $CONNECTOR_NAME"
    echo "  Status: $CONNECTOR_STATUS"
    echo "  Task Status: $TASK_STATUS"
    echo ""
    
    # Verify transform configuration
    echo -e "${BLUE}Verifying transform configuration...${NC}"
    
    CONFIGS=$(echo "$CONNECTOR_DETAILS" | jq -r '.configs[] | "\(.config)=\(.value)"' 2>/dev/null)
    TRANSFORMS=$(echo "$CONFIGS" | grep "^transforms=" | cut -d'=' -f2- || echo "")
    UNWRAP_TYPE=$(echo "$CONFIGS" | grep "^transforms.unwrap.type=" | cut -d'=' -f2- || echo "")
    ADD_FIELDS=$(echo "$CONFIGS" | grep "^transforms.unwrap.add.fields=" | cut -d'=' -f2- || echo "")
    PREFIX=$(echo "$CONFIGS" | grep "^transforms.unwrap.add.fields.prefix=" | cut -d'=' -f2- || echo "")
    
    if [[ "$UNWRAP_TYPE" == "io.debezium.transforms.ExtractNewRecordState" ]]; then
        echo -e "${GREEN}✓ ExtractNewRecordState transform is configured${NC}"
        echo "  Transforms: $TRANSFORMS"
        echo "  Add fields: $ADD_FIELDS"
        echo "  Prefix: $PREFIX"
        
        if [ "$PREFIX" = "__" ]; then
            echo -e "${GREEN}✓ Prefix is correctly set to '__'${NC}"
            echo ""
            echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}✅ Connector deployed successfully!${NC}"
            echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
            echo ""
            echo "The connector is configured to produce flat structure with:"
            echo "  - __op (operation code: 'c'=create, 'u'=update, 'd'=delete)"
            echo "  - __table (source table name)"
            echo "  - __ts_ms (CDC capture timestamp)"
            echo ""
            echo "This matches Flink's expected schema and should resolve the processing issue."
        else
            echo -e "${YELLOW}⚠ Prefix is not set to '__' (current: '$PREFIX')${NC}"
            echo "  Flink expects fields with '__' prefix"
        fi
    else
        echo -e "${RED}✗ ExtractNewRecordState transform is NOT configured${NC}"
        echo "  Please verify the connector configuration"
    fi
else
    echo -e "${YELLOW}⚠ jq not found, skipping detailed verification${NC}"
    echo "  Connector ID: $NEW_CONNECTOR"
    echo "  Please verify configuration in Confluent Cloud Console"
fi

# Cleanup
rm -f "$TEMP_CONFIG" /tmp/connector-deploy.log

echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Wait for connector to reach RUNNING status"
echo "  2. Verify messages in raw-business-events topic have flat structure"
echo "  3. Check Flink statements to see if they process messages"
echo "  4. Monitor filtered topics for events"
