#!/bin/bash
# Clear all rows from both Aurora PostgreSQL and DSQL databases
# Usage: ./scripts/clear-both-databases.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Clearing Both Databases${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Get Aurora credentials from terraform
AURORA_ENDPOINT=""
AURORA_PASSWORD=""
AURORA_USER="postgres"
AURORA_DATABASE="car_entities"

if [ -f "$PROJECT_ROOT/terraform/terraform.tfvars" ]; then
    AURORA_ENDPOINT=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw aurora_endpoint 2>/dev/null || echo "")
    RAW_PASSWORD=$(grep database_password "$PROJECT_ROOT/terraform/terraform.tfvars" | cut -d'"' -f2 || echo "")
    AURORA_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\n\r' | head -c 32)
fi

# Clear Aurora PostgreSQL
if [ -n "$AURORA_ENDPOINT" ] && [ -n "$AURORA_PASSWORD" ]; then
    echo -e "${BLUE}Clearing Aurora PostgreSQL...${NC}"
    echo "Endpoint: $AURORA_ENDPOINT"
    
    # SQL to truncate all tables in correct order
    CLEAR_SQL="
    TRUNCATE TABLE 
        loan_payment_entities,
        service_record_entities,
        loan_entities,
        car_entities,
        event_headers,
        business_events
    CASCADE;
    
    -- Reset sequences if any
    ALTER SEQUENCE IF EXISTS service_record_entities_id_seq RESTART WITH 1;
    "
    
    if command -v psql &> /dev/null; then
        PGPASSWORD="$AURORA_PASSWORD" psql \
            -h "$AURORA_ENDPOINT" \
            -U "$AURORA_USER" \
            -d "$AURORA_DATABASE" \
            -c "$CLEAR_SQL" && {
            echo -e "${GREEN}✅ Aurora PostgreSQL cleared successfully${NC}"
        } || {
            echo -e "${RED}❌ Failed to clear Aurora PostgreSQL${NC}"
            exit 1
        }
    else
        # Use Python if psql is not available
        python3 << EOF
import psycopg2
import sys

try:
    conn = psycopg2.connect(
        host="$AURORA_ENDPOINT",
        port=5432,
        database="$AURORA_DATABASE",
        user="$AURORA_USER",
        password="$AURORA_PASSWORD",
        connect_timeout=10
    )
    cur = conn.cursor()
    
    # Truncate all tables
    cur.execute("""
        TRUNCATE TABLE 
            loan_payment_entities,
            service_record_entities,
            loan_entities,
            car_entities,
            event_headers,
            business_events
        CASCADE;
    """)
    
    # Reset sequences
    cur.execute("ALTER SEQUENCE IF EXISTS service_record_entities_id_seq RESTART WITH 1;")
    
    conn.commit()
    cur.close()
    conn.close()
    print("✅ Aurora PostgreSQL cleared successfully")
except Exception as e:
    print(f"❌ Failed to clear Aurora PostgreSQL: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    fi
else
    echo -e "${YELLOW}⚠️  Skipping Aurora PostgreSQL (endpoint/password not found)${NC}"
fi

echo ""

# Clear DSQL
if [ -f "$PROJECT_ROOT/scripts/query-dsql.sh" ]; then
    echo -e "${BLUE}Clearing DSQL...${NC}"
    
    # Get DSQL host from terraform
    cd "$PROJECT_ROOT/terraform" || exit 1
    DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
    
    if [ -z "$DSQL_HOST" ]; then
        echo -e "${YELLOW}⚠️  DSQL host not found, skipping DSQL clear${NC}"
    else
        echo "DSQL Host: $DSQL_HOST"
        
        # DSQL doesn't support TRUNCATE, so we use DELETE
        # Delete in order to respect foreign key constraints
        # Execute each DELETE in a separate command to avoid transaction row limit
        cd "$PROJECT_ROOT"
        
        # Get bastion host instance ID
        BASTION_INSTANCE_ID=$(cd terraform && terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
        AWS_REGION=$(cd terraform && terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
        
        if [ -z "$BASTION_INSTANCE_ID" ]; then
            echo -e "${YELLOW}⚠️  Bastion host not found, cannot clear DSQL${NC}"
        else
            # Tables to clear in order (respecting foreign key constraints)
            TABLES=("loan_payment_entities" "service_record_entities" "loan_entities" "car_entities" "event_headers" "business_events")
            
            for TABLE in "${TABLES[@]}"; do
                echo "  Clearing $TABLE..."
                
                # Build command for this table
                COMMANDS_JSON=$(jq -n \
                    --arg dsql_host "$DSQL_HOST" \
                    --arg aws_region "$AWS_REGION" \
                    --arg table "$TABLE" \
                    '[
                        "export DSQL_HOST=" + $dsql_host,
                        "export AWS_REGION=" + $aws_region,
                        "TOKEN=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)",
                        "export PGPASSWORD=$TOKEN",
                        "psql -h $DSQL_HOST -U admin -d postgres -p 5432 -c \"DELETE FROM " + $table + ";\""
                    ]')
                
                # Send command to bastion host
                COMMAND_ID=$(aws ssm send-command \
                    --instance-ids "$BASTION_INSTANCE_ID" \
                    --region "$AWS_REGION" \
                    --document-name "AWS-RunShellScript" \
                    --parameters "{\"commands\":$COMMANDS_JSON}" \
                    --output json 2>&1 | jq -r '.Command.CommandId' 2>&1)
                
                if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "null" ]; then
                    echo -e "${RED}❌ Failed to send command for $TABLE${NC}"
                    continue
                fi
                
                # Wait for command to complete
                sleep 10
                
                # Get command status
                STATUS=$(aws ssm get-command-invocation \
                    --command-id "$COMMAND_ID" \
                    --instance-id "$BASTION_INSTANCE_ID" \
                    --region "$AWS_REGION" \
                    --query "Status" \
                    --output text 2>&1)
                
                if [ "$STATUS" = "Success" ]; then
                    OUTPUT=$(aws ssm get-command-invocation \
                        --command-id "$COMMAND_ID" \
                        --instance-id "$BASTION_INSTANCE_ID" \
                        --region "$AWS_REGION" \
                        --query "StandardOutputContent" \
                        --output text 2>&1)
                    # Extract DELETE count if available (using sed instead of grep -P for macOS compatibility)
                    DELETE_COUNT=$(echo "$OUTPUT" | sed -n 's/.*DELETE \([0-9]*\).*/\1/p' | head -1 || echo "unknown")
                    echo "    ✅ Cleared $TABLE ($DELETE_COUNT rows)"
                else
                    ERROR=$(aws ssm get-command-invocation \
                        --command-id "$COMMAND_ID" \
                        --instance-id "$BASTION_INSTANCE_ID" \
                        --region "$AWS_REGION" 2>&1 | jq -r '.StandardErrorContent // .Status' 2>&1)
                    # Check if it's the transaction row limit error
                    if echo "$ERROR" | grep -q "transaction row limit exceeded"; then
                        echo -e "    ${YELLOW}⚠️  $TABLE has too many rows, deleting in batches...${NC}"
                        # Delete in batches of 1000 rows
                        BATCH_SIZE=1000
                        TOTAL_DELETED=0
                        while true; do
                            BATCH_COMMANDS_JSON=$(jq -n \
                                --arg dsql_host "$DSQL_HOST" \
                                --arg aws_region "$AWS_REGION" \
                                --arg table "$TABLE" \
                                --arg batch_size "$BATCH_SIZE" \
                                '[
                                    "export DSQL_HOST=" + $dsql_host,
                                    "export AWS_REGION=" + $aws_region,
                                    "TOKEN=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)",
                                    "export PGPASSWORD=$TOKEN",
                                    "psql -h $DSQL_HOST -U admin -d postgres -p 5432 -c \"DELETE FROM " + $table + " WHERE ctid IN (SELECT ctid FROM " + $table + " LIMIT " + $batch_size + ");\""
                                ]')
                            
                            BATCH_COMMAND_ID=$(aws ssm send-command \
                                --instance-ids "$BASTION_INSTANCE_ID" \
                                --region "$AWS_REGION" \
                                --document-name "AWS-RunShellScript" \
                                --parameters "{\"commands\":$BATCH_COMMANDS_JSON}" \
                                --output json 2>&1 | jq -r '.Command.CommandId' 2>&1)
                            
                            if [ -z "$BATCH_COMMAND_ID" ] || [ "$BATCH_COMMAND_ID" = "null" ]; then
                                echo -e "      ${RED}❌ Failed to send batch delete command${NC}"
                                break
                            fi
                            
                            sleep 10
                            
                            BATCH_STATUS=$(aws ssm get-command-invocation \
                                --command-id "$BATCH_COMMAND_ID" \
                                --instance-id "$BASTION_INSTANCE_ID" \
                                --region "$AWS_REGION" \
                                --query "Status" \
                                --output text 2>&1)
                            
                            if [ "$BATCH_STATUS" = "Success" ]; then
                                BATCH_OUTPUT=$(aws ssm get-command-invocation \
                                    --command-id "$BATCH_COMMAND_ID" \
                                    --instance-id "$BASTION_INSTANCE_ID" \
                                    --region "$AWS_REGION" \
                                    --query "StandardOutputContent" \
                                    --output text 2>&1)
                                BATCH_DELETED=$(echo "$BATCH_OUTPUT" | sed -n 's/.*DELETE \([0-9]*\).*/\1/p' | head -1 || echo "0")
                                if [ "$BATCH_DELETED" = "0" ]; then
                                    break  # No more rows to delete
                                fi
                                TOTAL_DELETED=$((TOTAL_DELETED + BATCH_DELETED))
                                echo "      Deleted batch: $BATCH_DELETED rows (total: $TOTAL_DELETED)"
                            else
                                BATCH_ERROR=$(aws ssm get-command-invocation \
                                    --command-id "$BATCH_COMMAND_ID" \
                                    --instance-id "$BASTION_INSTANCE_ID" \
                                    --region "$AWS_REGION" 2>&1 | jq -r '.StandardErrorContent // .Status' 2>&1)
                                if echo "$BATCH_ERROR" | grep -q "transaction row limit exceeded"; then
                                    echo -e "      ${YELLOW}⚠️  Batch too large, reducing batch size...${NC}"
                                    BATCH_SIZE=$((BATCH_SIZE / 2))
                                    if [ "$BATCH_SIZE" -lt 100 ]; then
                                        echo -e "      ${RED}❌ Cannot clear $TABLE (batch size too small)${NC}"
                                        break
                                    fi
                                    continue
                                else
                                    echo -e "      ${RED}❌ Batch delete failed: $BATCH_ERROR${NC}"
                                    break
                                fi
                            fi
                        done
                        if [ "$TOTAL_DELETED" -gt 0 ]; then
                            echo -e "    ${GREEN}✅ Cleared $TABLE ($TOTAL_DELETED total rows)${NC}"
                        fi
                    else
                        echo -e "    ${RED}❌ Failed to clear $TABLE: $ERROR${NC}"
                    fi
                fi
            done
            
            echo -e "${GREEN}✅ DSQL clear operations completed${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠️  query-dsql.sh not found, skipping DSQL clear${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Database Clear Complete${NC}"
echo -e "${GREEN}========================================${NC}"
