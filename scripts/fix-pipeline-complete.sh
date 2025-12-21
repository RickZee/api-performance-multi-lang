#!/bin/bash
set -e

echo "=========================================="
echo "COMPLETE PIPELINE FIX AND VALIDATION"
echo "=========================================="
echo ""

BASTION_ID="i-0fa5673ccf1b932ef"
REGION="us-east-1"
LAMBDA_NAME="producer-api-dsql-iam-grant"
DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
IAM_USER="lambda_dsql_user"
BASTION_ROLE="arn:aws:iam::978300727880:role/producer-api-bastion-role"

# Step 1: Create Lambda package
echo "Step 1: Creating Lambda package with psycopg2-binary..."
PACKAGE_DIR="/tmp/dsql-iam-pkg-$$"
mkdir -p "$PACKAGE_DIR"
cat > "$PACKAGE_DIR/lambda_function.py" << 'PYTHON'
import json
import boto3
import psycopg2

def lambda_handler(event, context):
    dsql_host = event.get('dsql_host')
    iam_user = event.get('iam_user')
    role_arn = event.get('role_arn')
    region = event.get('region', 'us-east-1')
    
    if not all([dsql_host, iam_user, role_arn]):
        return {'statusCode': 400, 'body': json.dumps({'error': 'Missing required parameters'})}
    
    try:
        rds_client = boto3.client('rds', region_name=region)
        token = rds_client.generate_db_auth_token(DBHostname=dsql_host, Port=5432, DBUsername='postgres', Region=region)
        conn = psycopg2.connect(host=dsql_host, port=5432, database='postgres', user='postgres', password=token, sslmode='require')
        cur = conn.cursor()
        grant_sql = f"AWS IAM GRANT {iam_user} TO '{role_arn}';"
        cur.execute(grant_sql)
        cur.execute("SELECT pg_role_name, arn FROM sys.iam_pg_role_mappings WHERE pg_role_name = %s", (iam_user,))
        result = cur.fetchall()
        cur.close()
        conn.close()
        return {'statusCode': 200, 'body': json.dumps({'message': 'IAM role mapping granted successfully', 'mappings': [{'role': r[0], 'arn': r[1]} for r in result]})}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
PYTHON

pip3 install --target "$PACKAGE_DIR" psycopg2-binary --quiet --disable-pip-version-check 2>&1 | grep -v "WARNING" || true
cd "$PACKAGE_DIR"
zip -r /tmp/dsql-iam-grant-lambda.zip . > /dev/null 2>&1
rm -rf "$PACKAGE_DIR"
echo "✅ Package created: $(ls -lh /tmp/dsql-iam-grant-lambda.zip | awk '{print $5}')"

# Step 2: Update Lambda
echo ""
echo "Step 2: Updating Lambda function..."
UPDATE_STATUS=$(aws lambda update-function-code --function-name "$LAMBDA_NAME" --zip-file fileb:///tmp/dsql-iam-grant-lambda.zip --region "$REGION" --output text --query 'LastUpdateStatus')
echo "Update status: $UPDATE_STATUS"
echo "Waiting for update to complete..."
sleep 15

# Step 3: Invoke Lambda
echo ""
echo "Step 3: Granting IAM access via Lambda..."
echo "{\"dsql_host\":\"$DSQL_HOST\",\"iam_user\":\"$IAM_USER\",\"role_arn\":\"$BASTION_ROLE\",\"region\":\"$REGION\"}" > /tmp/lambda-payload.json
aws lambda invoke --function-name "$LAMBDA_NAME" --cli-binary-format raw-in-base64-out --payload file:///tmp/lambda-payload.json --region "$REGION" /tmp/lambda-response.json > /dev/null
RESPONSE=$(cat /tmp/lambda-response.json)
echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"

STATUS=$(echo "$RESPONSE" | jq -r '.statusCode // .errorMessage // "error"' 2>/dev/null || echo "error")
if [[ "$STATUS" == "200" ]]; then
    echo "✅ IAM grant successful!"
    echo "$RESPONSE" | jq -r '.body' 2>/dev/null | jq . 2>/dev/null || echo ""
else
    echo "⚠️  IAM grant status: $STATUS"
fi

# Step 4: Restart connector
echo ""
echo "Step 4: Restarting connector..."
RESTART_CMD_ID=$(aws ssm send-command --instance-ids "$BASTION_ID" --document-name "AWS-RunShellScript" --parameters "{\"commands\":[\"curl -X POST http://localhost:8083/connectors/dsql-cdc-source/restart\"]}" --region "$REGION" --output text --query 'Command.CommandId')
echo "Restart command ID: $RESTART_CMD_ID"
echo "Waiting 25 seconds for restart..."
sleep 25

# Step 5: Check status
echo ""
echo "Step 5: Checking connector status..."
STATUS_CMD_ID=$(aws ssm send-command --instance-ids "$BASTION_ID" --document-name "AWS-RunShellScript" --parameters '{"commands":["curl -s http://localhost:8083/connectors/dsql-cdc-source/status | python3 -m json.tool"]}' --region "$REGION" --output text --query 'Command.CommandId')
sleep 6
LATEST_CMD=$(aws ssm list-commands --instance-id "$BASTION_ID" --region "$REGION" --max-items 1 --query 'Commands[0].CommandId' --output text)
STATUS_OUTPUT=$(aws ssm get-command-invocation --command-id "$LATEST_CMD" --instance-id "$BASTION_ID" --region "$REGION" --query 'StandardOutputContent' --output text)
echo "$STATUS_OUTPUT"

if echo "$STATUS_OUTPUT" | grep -q '"state": "RUNNING"'; then
    echo ""
    echo "✅ Connector is RUNNING"
    if echo "$STATUS_OUTPUT" | grep -q '"state": "FAILED"'; then
        echo "⚠️  But task may have failed - check logs"
    fi
else
    echo ""
    echo "⚠️  Connector may not be running properly"
fi

# Step 6: Check logs
echo ""
echo "Step 6: Checking connector logs..."
LOG_CMD_ID=$(aws ssm send-command --instance-ids "$BASTION_ID" --document-name "AWS-RunShellScript" --parameters '{"commands":["docker logs kafka-connect-dsql --tail 400 2>&1 | grep -iE \"(connected|error|exception|polled|success|running|fatal|access denied|hikaricp|dsql|initialized|schema|polled.*records|INFO.*polled|INFO.*Connected|INFO.*Successfully)\" | tail -50"]}' --region "$REGION" --output text --query 'Command.CommandId')
sleep 6
LATEST_CMD=$(aws ssm list-commands --instance-id "$BASTION_ID" --region "$REGION" --max-items 1 --query 'Commands[0].CommandId' --output text)
LOG_OUTPUT=$(aws ssm get-command-invocation --command-id "$LATEST_CMD" --instance-id "$BASTION_ID" --region "$REGION" --query 'StandardOutputContent' --output text)
echo "$LOG_OUTPUT"

# Step 7: Full pipeline monitoring
echo ""
echo "Step 7: Full pipeline status..."
cd /Users/rickzakharov/dev/github/api-performance-multi-lang/debezium-connector-dsql
./scripts/monitor-pipeline.sh 2>&1 | tail -80

echo ""
echo "=========================================="
echo "COMPLETE"
echo "=========================================="
