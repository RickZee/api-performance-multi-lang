#!/bin/bash
# Simple script to query DSQL from EC2 via SSM
# Usage: ./query-dsql-simple.sh

INSTANCE_ID="i-058cb2a0dc3fdcf3b"
AWS_REGION="us-east-1"
DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"

echo "=== Querying DSQL Database ==="

# Send simple command
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=['export DSQL_HOST=\"$DSQL_HOST\"','export AWS_REGION=\"$AWS_REGION\"','export PGPASSWORD=\$(aws dsql generate-db-connect-admin-auth-token --region \$AWS_REGION --hostname \$DSQL_HOST)','psql -h \$DSQL_HOST -U admin -d postgres -p 5432 -c \"SELECT '\''business_events'\'' as table_name, COUNT(*) as count FROM business_events UNION ALL SELECT '\''event_headers'\'', COUNT(*) FROM event_headers UNION ALL SELECT '\''car_entities'\'', COUNT(*) FROM car_entities UNION ALL SELECT '\''loan_entities'\'', COUNT(*) FROM loan_entities UNION ALL SELECT '\''loan_payment_entities'\'', COUNT(*) FROM loan_payment_entities UNION ALL SELECT '\''service_record_entities'\'', COUNT(*) FROM service_record_entities ORDER BY table_name;\"']" \
    --output json 2>&1 | jq -r '.Command.CommandId')

echo "Command ID: $COMMAND_ID"
echo "Waiting for results..."

sleep 10

# Get results
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query "StandardOutputContent" \
    --output text 2>&1
