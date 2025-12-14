#!/bin/bash
# Query DSQL database from EC2 instance
# Usage: ./query-dsql-from-ec2.sh [instance-id]

set -e

INSTANCE_ID=${1:-"i-058cb2a0dc3fdcf3b"}
AWS_REGION="us-east-1"
DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"

echo "=== Querying DSQL Database from EC2 ==="
echo "Instance ID: $INSTANCE_ID"
echo "DSQL Host: $DSQL_HOST"
echo ""

# Create a query script
QUERY_SCRIPT=$(cat << 'EOF'
#!/bin/bash
export DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
export AWS_REGION="us-east-1"
export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST 2>&1)

echo "=== Table Counts ==="
psql -h $DSQL_HOST -U admin -d postgres -p 5432 << 'PSQL_EOF'
SELECT 'business_events' as table_name, COUNT(*) as count FROM business_events
UNION ALL SELECT 'event_headers', COUNT(*) FROM event_headers
UNION ALL SELECT 'car_entities', COUNT(*) FROM car_entities
UNION ALL SELECT 'loan_entities', COUNT(*) FROM loan_entities
UNION ALL SELECT 'loan_payment_entities', COUNT(*) FROM loan_payment_entities
UNION ALL SELECT 'service_record_entities', COUNT(*) FROM service_record_entities
ORDER BY table_name;
PSQL_EOF

echo ""
echo "=== Events by Event Name ==="
psql -h $DSQL_HOST -U admin -d postgres -p 5432 << 'PSQL_EOF'
SELECT event_name, COUNT(*) as count 
FROM business_events 
GROUP BY event_name 
ORDER BY event_name;
PSQL_EOF

echo ""
echo "=== Entities by Type ==="
psql -h $DSQL_HOST -U admin -d postgres -p 5432 << 'PSQL_EOF'
SELECT 'Car' as entity_type, COUNT(*) as count FROM car_entities
UNION ALL
SELECT 'Loan', COUNT(*) FROM loan_entities
UNION ALL
SELECT 'LoanPayment', COUNT(*) FROM loan_payment_entities
UNION ALL
SELECT 'ServiceRecord', COUNT(*) FROM service_record_entities
ORDER BY entity_type;
PSQL_EOF

echo ""
echo "=== Recent Events (last 5) ==="
psql -h $DSQL_HOST -U admin -d postgres -p 5432 << 'PSQL_EOF'
SELECT id, event_name, created_date 
FROM business_events 
ORDER BY created_date DESC 
LIMIT 5;
PSQL_EOF
EOF
)

# Send command to EC2
echo "Sending query command to EC2..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[$(echo "$QUERY_SCRIPT" | jq -Rs .)]" \
    --output json 2>&1 | jq -r '.Command.CommandId')

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "null" ]; then
    echo "Error: Failed to send command"
    exit 1
fi

echo "Command ID: $COMMAND_ID"
echo "Waiting for command to complete..."

# Wait for command to complete
sleep 5
for i in {1..30}; do
    STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query "Status" \
        --output text 2>&1)
    
    if [ "$STATUS" = "Success" ] || [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Cancelled" ] || [ "$STATUS" = "TimedOut" ]; then
        break
    fi
    
    sleep 2
done

# Get results
echo ""
echo "=== Command Status: $STATUS ==="
echo ""

if [ "$STATUS" = "Success" ]; then
    aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query "StandardOutputContent" \
        --output text 2>&1
else
    echo "Command failed or timed out"
    aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$AWS_REGION" 2>&1 | jq -r '.StandardErrorContent' 2>&1
fi

