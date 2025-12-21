#!/bin/bash
# Complete pipeline validation - end to end
set -e

echo "=========================================="
echo "COMPLETE PIPELINE VALIDATION"
echo "=========================================="
echo ""

BASTION_ID="i-0fa5673ccf1b932ef"
REGION="us-east-1"
LAMBDA_NAME="producer-api-dsql-iam-grant"
DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
IAM_USER="lambda_dsql_user"
BASTION_ROLE="arn:aws:iam::978300727880:role/producer-api-bastion-role"

# Step 1: Execute IAM Grant
echo "Step 1: Executing IAM grant via Lambda..."
echo '{"dsql_host":"'$DSQL_HOST'","iam_user":"'$IAM_USER'","role_arn":"'$BASTION_ROLE'","region":"'$REGION'"}' > /tmp/lambda-payload-validate.json
aws lambda invoke \
  --function-name "$LAMBDA_NAME" \
  --cli-binary-format raw-in-base64-out \
  --payload file:///tmp/lambda-payload-validate.json \
  --region "$REGION" \
  /tmp/lambda-response-validate.json > /dev/null 2>&1

RESPONSE=$(cat /tmp/lambda-response-validate.json)
STATUS=$(echo "$RESPONSE" | jq -r '.statusCode // "error"' 2>/dev/null || echo "error")

if [ "$STATUS" = "200" ]; then
    echo "✅ IAM grant successful"
    echo "$RESPONSE" | jq -r '.body' 2>/dev/null | jq . 2>/dev/null || echo ""
else
    echo "⚠️  IAM grant status: $STATUS"
    echo "Response: $RESPONSE"
fi

# Step 2: Restart Connector
echo ""
echo "Step 2: Restarting connector..."
aws ssm send-command \
  --instance-ids "$BASTION_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["curl -X POST http://localhost:8083/connectors/dsql-cdc-source/restart"]}' \
  --region "$REGION" > /dev/null 2>&1
echo "Waiting 30 seconds for restart..."
sleep 30

# Step 3: Check Connector Status
echo ""
echo "Step 3: Checking connector status..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$BASTION_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["curl -s http://localhost:8083/connectors/dsql-cdc-source/status | python3 -m json.tool"]}' \
  --region "$REGION" \
  --output text --query 'Command.CommandId')

sleep 8
STATUS_OUTPUT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$BASTION_ID" \
  --region "$REGION" \
  --query 'StandardOutputContent' \
  --output text)

echo "$STATUS_OUTPUT"

CONNECTOR_STATE=$(echo "$STATUS_OUTPUT" | grep -o '"state": "[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
TASK_STATE=$(echo "$STATUS_OUTPUT" | grep -o '"state": "[^"]*"' | tail -1 | cut -d'"' -f4 || echo "")

if [ "$CONNECTOR_STATE" = "RUNNING" ]; then
    echo "✅ Connector: RUNNING"
else
    echo "❌ Connector: $CONNECTOR_STATE"
fi

if [ "$TASK_STATE" = "RUNNING" ]; then
    echo "✅ Task: RUNNING"
elif [ "$TASK_STATE" = "FAILED" ]; then
    echo "❌ Task: FAILED"
else
    echo "⚠️  Task: $TASK_STATE"
fi

# Step 4: Check Connection Logs
echo ""
echo "Step 4: Checking connection logs..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$BASTION_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["docker logs kafka-connect-dsql --tail 300 2>&1 | grep -iE \"(connected|error|exception|polled|success|running|fatal|access denied|INFO.*polled|INFO.*Connected|INFO.*Successfully|initialized|schema|polled.*records)\" | tail -50"]}' \
  --region "$REGION" \
  --output text --query 'Command.CommandId')

sleep 8
LOG_OUTPUT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$BASTION_ID" \
  --region "$REGION" \
  --query 'StandardOutputContent' \
  --output text)

echo "$LOG_OUTPUT"

# Check for errors
if echo "$LOG_OUTPUT" | grep -qi "access denied\|fatal.*unable"; then
    echo ""
    echo "❌ ERROR: Access denied detected"
    ACCESS_DENIED=true
else
    ACCESS_DENIED=false
fi

if echo "$LOG_OUTPUT" | grep -qi "connected\|successfully\|initialized"; then
    echo ""
    echo "✅ Connection successful"
    CONNECTION_SUCCESS=true
else
    CONNECTION_SUCCESS=false
fi

if echo "$LOG_OUTPUT" | grep -qi "polled.*records\|INFO.*polled"; then
    echo "✅ Polling activity detected"
    POLLING_ACTIVE=true
else
    echo "⚠️  No polling activity in recent logs"
    POLLING_ACTIVE=false
fi

# Step 5: Check Kafka Topics
echo ""
echo "Step 5: Checking Kafka topics in Confluent Cloud..."
echo ""

echo "Listing DSQL-related topics:"
TOPICS=$(confluent kafka topic list 2>&1 | grep -iE "(raw-event|dsql)" || echo "")
if [ -n "$TOPICS" ]; then
    echo "$TOPICS"
    TOPICS_EXIST=true
else
    echo "No DSQL topics found"
    TOPICS_EXIST=false
fi

echo ""
echo "Checking raw-event-headers topic:"
if confluent kafka topic describe raw-event-headers --output json 2>&1 | jq -r '.partitions[] | "Partition \(.partition): offset=\(.offset // "N/A")"' 2>/dev/null; then
    echo "✅ Topic exists"
    TOPIC_EXISTS=true
    
    # Get topic details
    TOPIC_INFO=$(confluent kafka topic describe raw-event-headers --output json 2>&1 | jq '{name: .name, partitions: (.partitions | length), total_offset: [.partitions[].offset // 0] | add}' 2>/dev/null || echo "")
    if [ -n "$TOPIC_INFO" ]; then
        echo "Topic info:"
        echo "$TOPIC_INFO" | jq .
    fi
else
    echo "⚠️  Topic may not exist yet"
    TOPIC_EXISTS=false
fi

# Step 6: Attempt to Consume Messages
echo ""
echo "Step 6: Attempting to consume sample messages..."
echo "Consuming from raw-event-headers (max 3 messages, 15s timeout):"
timeout 15 confluent kafka topic consume raw-event-headers --max-messages 3 2>&1 | head -100 || echo "No messages or timeout"

# Step 7: Summary
echo ""
echo "=========================================="
echo "VALIDATION SUMMARY"
echo "=========================================="
echo ""

echo "IAM Grant: $([ "$STATUS" = "200" ] && echo "✅ SUCCESS" || echo "❌ FAILED")"
echo "Connector State: $([ "$CONNECTOR_STATE" = "RUNNING" ] && echo "✅ RUNNING" || echo "❌ $CONNECTOR_STATE")"
echo "Task State: $([ "$TASK_STATE" = "RUNNING" ] && echo "✅ RUNNING" || echo "⚠️  $TASK_STATE")"
echo "Connection: $([ "$CONNECTION_SUCCESS" = true ] && echo "✅ SUCCESS" || echo "❌ FAILED")"
echo "Access Denied: $([ "$ACCESS_DENIED" = true ] && echo "❌ YES" || echo "✅ NO")"
echo "Polling Activity: $([ "$POLLING_ACTIVE" = true ] && echo "✅ ACTIVE" || echo "⚠️  NONE")"
echo "Kafka Topics: $([ "$TOPICS_EXIST" = true ] && echo "✅ EXIST" || echo "⚠️  NOT FOUND")"
echo "Topic (raw-event-headers): $([ "$TOPIC_EXISTS" = true ] && echo "✅ EXISTS" || echo "⚠️  NOT FOUND")"

echo ""
if [ "$STATUS" = "200" ] && [ "$CONNECTOR_STATE" = "RUNNING" ] && [ "$CONNECTION_SUCCESS" = true ] && [ "$ACCESS_DENIED" = false ]; then
    echo "✅ PIPELINE STATUS: OPERATIONAL"
    if [ "$POLLING_ACTIVE" = true ]; then
        echo "✅ CDC is actively polling and producing records"
    else
        echo "⚠️  CDC is connected but no polling activity detected (may need data in event_headers table)"
    fi
else
    echo "❌ PIPELINE STATUS: ISSUES DETECTED"
    echo ""
    echo "Issues to address:"
    [ "$STATUS" != "200" ] && echo "  - IAM grant failed"
    [ "$CONNECTOR_STATE" != "RUNNING" ] && echo "  - Connector not running"
    [ "$CONNECTION_SUCCESS" = false ] && echo "  - Connection failed"
    [ "$ACCESS_DENIED" = true ] && echo "  - Access denied errors detected"
fi

echo ""
echo "=========================================="
echo "VALIDATION COMPLETE"
echo "=========================================="
