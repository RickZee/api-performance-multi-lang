#!/bin/bash
# Script to connect to DSQL database via bastion host
# Usage: ./scripts/connect-dsql.sh

set -e

# Get Terraform outputs
cd "$(dirname "$0")/../terraform" || exit 1

# Get bastion host instance ID
BASTION_INSTANCE_ID=$(terraform output -raw bastion_host_instance_id 2>/dev/null || echo "")
if [ -z "$BASTION_INSTANCE_ID" ]; then
    echo "Error: Bastion host not found. Make sure Terraform has been applied and bastion host is enabled."
    exit 1
fi

# Get DSQL host
DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
if [ -z "$DSQL_HOST" ]; then
    echo "Error: DSQL host not found. Make sure Terraform has been applied and DSQL cluster is enabled."
    exit 1
fi

# Get AWS region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

echo "=== Connecting to DSQL Database ==="
echo "Bastion Host: $BASTION_INSTANCE_ID"
echo "DSQL Host: $DSQL_HOST"
echo "Region: $AWS_REGION"
echo ""
echo "Connecting via SSM Session Manager..."
echo "Once connected, run these commands on the bastion host:"
echo ""
echo "  export DSQL_HOST=$DSQL_HOST"
echo "  export AWS_REGION=$AWS_REGION"
echo "  export PGPASSWORD=\$(aws dsql generate-db-connect-admin-auth-token --region \$AWS_REGION --hostname \$DSQL_HOST)"
echo "  psql -h \$DSQL_HOST -U admin -d postgres -p 5432"
echo ""
echo "Or run a quick query:"
echo "  export DSQL_HOST=$DSQL_HOST"
echo "  export AWS_REGION=$AWS_REGION"
echo "  export PGPASSWORD=\$(aws dsql generate-db-connect-admin-auth-token --region \$AWS_REGION --hostname \$DSQL_HOST)"
echo "  psql -h \$DSQL_HOST -U admin -d postgres -p 5432 -c \"SELECT 'business_events' as table_name, COUNT(*) as count FROM business_events UNION ALL SELECT 'event_headers', COUNT(*) FROM event_headers UNION ALL SELECT 'car_entities', COUNT(*) FROM car_entities UNION ALL SELECT 'loan_entities', COUNT(*) FROM loan_entities UNION ALL SELECT 'loan_payment_entities', COUNT(*) FROM loan_payment_entities UNION ALL SELECT 'service_record_entities', COUNT(*) FROM service_record_entities ORDER BY table_name;\""
echo ""
echo "Press Ctrl+D to exit the SSM session"
echo ""

# Connect via SSM
aws ssm start-session --target "$BASTION_INSTANCE_ID" --region "$AWS_REGION"
