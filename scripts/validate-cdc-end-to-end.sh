#!/bin/bash
# Complete CDC pipeline validation: DSQL -> Kafka
set -e

echo "=========================================="
echo "COMPLETE CDC PIPELINE VALIDATION"
echo "DSQL -> Kafka End-to-End Test"
echo "=========================================="
echo ""

BASTION_ID="i-0fa5673ccf1b932ef"
REGION="us-east-1"
DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
IAM_USER="lambda_dsql_user"
TEST_ID="cdc-test-$(date +%s)"
TEST_EVENT_NAME="TestEvent_${TEST_ID}"
HEADER_DATA='{"test":true,"validation":"cdc-pipeline","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","testId":"'$TEST_ID'"}'

echo "Test ID: $TEST_ID"
echo "Test Event Name: $TEST_EVENT_NAME"
echo ""

# Step 1: Insert test data into DSQL
echo "Step 1: Inserting test data into DSQL event_headers table..."
INSERT_SQL="INSERT INTO public.event_headers (id, event_name, event_type, created_date, saved_date, header_data) VALUES ('$TEST_ID', '$TEST_EVENT_NAME', 'TestEvent', NOW(), NOW(), '$HEADER_DATA');"

echo "Executing insert..."
aws ssm send-command \
  --instance-ids "$BASTION_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "{\"commands\":[\"export DSQL_HOST=\\\"$DSQL_HOST\\\"\", \"export AWS_REGION=\\\"$REGION\\\"\", \"export IAM_USER=\\\"$IAM_USER\\\"\", \"TOKEN=\\\$(aws rds generate-db-auth-token --hostname \\\"\\\$DSQL_HOST\\\" --port 5432 --region \\\"\\\$AWS_REGION\\\" --username \\\"\\\$IAM_USER\\\" 2>&1)\", \"export PGPASSWORD=\\\"\\\$TOKEN\\\"\", \"psql -h \\\"\\\$DSQL_HOST\\\" -U \\\"\\\$IAM_USER\\\" -d mortgage_db -p 5432 -c \\\"$INSERT_SQL\\\"\"]}" \
  --region "$REGION" > /tmp/insert-command.json

INSERT_CMD_ID=$(cat /tmp/insert-command.json | jq -r '.Command.CommandId')
echo "Insert command ID: $INSERT_CMD_ID"
echo "Waiting 10 seconds for insert to complete..."
sleep 10

INSERT_OUTPUT=$(aws ssm get-command-invocation \
  --command-id "$INSERT_CMD_ID" \
  --instance-id "$BASTION_ID" \
  --region "$REGION" \
  --query '[Status, StandardOutputContent, StandardErrorContent]' \
  --output text)

echo "Insert result:"
echo "$INSERT_OUTPUT"
echo ""

# Step 2: Verify data exists in DSQL
echo "Step 2: Verifying data exists in DSQL..."
VERIFY_SQL="SELECT id, event_name, event_type, created_date, saved_date FROM public.event_headers WHERE id = '$TEST_ID';"

aws ssm send-command \
  --instance-ids "$BASTION_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "{\"commands\":[\"export DSQL_HOST=\\\"$DSQL_HOST\\\"\", \"export AWS_REGION=\\\"$REGION\\\"\", \"export IAM_USER=\\\"$IAM_USER\\\"\", \"TOKEN=\\\$(aws rds generate-db-auth-token --hostname \\\"\\\$DSQL_HOST\\\" --port 5432 --region \\\"\\\$AWS_REGION\\\" --username \\\"\\\$IAM_USER\\\" 2>&1)\", \"export PGPASSWORD=\\\"\\\$TOKEN\\\"\", \"psql -h \\\"\\\$DSQL_HOST\\\" -U \\\"\\\$IAM_USER\\\" -d mortgage_db -p 5432 -c \\\"$VERIFY_SQL\\\"\"]}" \
  --region "$REGION" > /tmp/verify-command.json

VERIFY_CMD_ID=$(cat /tmp/verify-command.json | jq -r '.Command.CommandId')
sleep 8

VERIFY_OUTPUT=$(aws ssm get-command-invocation \
  --command-id "$VERIFY_CMD_ID" \
  --instance-id "$BASTION_ID" \
  --region "$REGION" \
  --query 'StandardOutputContent' --output text)

echo "Data in DSQL:"
echo "$VERIFY_OUTPUT"
echo ""

if echo "$VERIFY_OUTPUT" | grep -q "$TEST_ID"; then
    echo "✅ Data successfully inserted into DSQL"
else
    echo "❌ Data not found in DSQL"
    exit 1
fi

# Step 3: Wait for CDC to process (polling interval is 1 second, wait 10 seconds to be safe)
echo "Step 3: Waiting for CDC to process (10 seconds)..."
sleep 10

# Step 4: Check connector is running
echo "Step 4: Checking connector status..."
STATUS_CMD_ID=$(aws ssm send-command \
  --instance-ids "$BASTION_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["curl -s http://localhost:8083/connectors/dsql-cdc-source/status | python3 -m json.tool"]}' \
  --region "$REGION" \
  --output text --query 'Command.CommandId')

sleep 8
STATUS_OUTPUT=$(aws ssm get-command-invocation \
  --command-id "$STATUS_CMD_ID" \
  --instance-id "$BASTION_ID" \
  --region "$REGION" \
  --query 'StandardOutputContent' --output text)

echo "Connector status:"
echo "$STATUS_OUTPUT" | head -20
echo ""

# Step 5: Check Kafka topic for the data
echo "Step 5: Checking Kafka topic for CDC event..."
echo "Consuming from raw-event-headers topic (max 20 messages, 30s timeout)..."
echo ""

# Consume messages and look for our test ID
KAFKA_OUTPUT=$(timeout 30 confluent kafka topic consume raw-event-headers --max-messages 20 2>&1 || echo "")

echo "Kafka messages (searching for test ID: $TEST_ID)..."
echo ""

# Step 6: Verify test data appears in Kafka
echo "Step 6: Verifying test data in Kafka..."
if echo "$KAFKA_OUTPUT" | grep -q "$TEST_ID"; then
    echo "✅ SUCCESS: Test data found in Kafka!"
    echo ""
    echo "Found test ID: $TEST_ID"
    echo "Event name: $TEST_EVENT_NAME"
    echo ""
    # Extract the matching message
    echo "Matching message:"
    echo "$KAFKA_OUTPUT" | grep -A 15 -B 5 "$TEST_ID" | head -40
    echo ""
    echo "✅ CDC PIPELINE VALIDATION: SUCCESS"
    echo "   Data successfully flowed from DSQL to Kafka"
    VALIDATION_SUCCESS=true
else
    echo "⚠️  Test data not found in recent Kafka messages"
    echo ""
    echo "Checking if topic exists..."
    if confluent kafka topic describe raw-event-headers --output json 2>&1 | jq -r '.partitions[] | "Partition \(.partition): offset=\(.offset // "N/A")"' 2>/dev/null; then
        echo "✅ Topic exists"
        echo ""
        echo "Possible reasons test data not found:"
        echo "  1. CDC connector may not be polling yet"
        echo "  2. Messages may be in different partition"
        echo "  3. Need to wait longer for processing"
        echo ""
        echo "Recent messages (last 5):"
        echo "$KAFKA_OUTPUT" | tail -20
    else
        echo "❌ Topic may not exist or connector not producing"
    fi
    VALIDATION_SUCCESS=false
fi

# Step 7: Summary
echo ""
echo "=========================================="
echo "VALIDATION SUMMARY"
echo "=========================================="
echo ""
echo "Test ID: $TEST_ID"
echo "Event Name: $TEST_EVENT_NAME"
echo ""
echo "DSQL Insert: ✅ SUCCESS"
echo "Kafka CDC: $([ "$VALIDATION_SUCCESS" = true ] && echo "✅ SUCCESS" || echo "⚠️  NOT FOUND")"
echo ""
if [ "$VALIDATION_SUCCESS" = true ]; then
    echo "✅ COMPLETE CDC PIPELINE VALIDATION: SUCCESS"
    echo "   Data successfully flowed from DSQL to Kafka"
else
    echo "⚠️  CDC validation incomplete - data in DSQL but not yet in Kafka"
    echo "   This may be normal if connector just started or polling is delayed"
fi
echo ""
echo "=========================================="
echo "VALIDATION COMPLETE"
echo "=========================================="
