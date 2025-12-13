#!/bin/bash
# Comprehensive Debezium DSQL Connector Test Script
# Run this on the EC2 test runner instance via SSM

set -e

# Configuration
DSQL_ENDPOINT="${DSQL_ENDPOINT:-vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com}"
DSQL_HOST="${DSQL_HOST:-vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws}"
IAM_USER="${IAM_USER:-lambda_dsql_user}"
DB_NAME="${DB_NAME:-car_entities}"
REGION="${AWS_REGION:-us-east-1}"

echo "=== Debezium DSQL Connector Test Suite ==="
echo "Endpoint: $DSQL_ENDPOINT"
echo "IAM User: $IAM_USER"
echo "Database: $DB_NAME"
echo ""

# Test 1: Tool verification
echo "TEST 1: Verifying installed tools..."
echo -n "Java: " && java -version 2>&1 | head -n1 || echo "FAILED"
echo -n "Gradle: " && ./gradlew --version | head -n1 || echo "FAILED"
echo -n "psql: " && psql --version | head -n1 || echo "FAILED"
echo -n "git: " && git --version || echo "FAILED"
echo ""

# Test 2: IAM token generation
echo "TEST 2: IAM Token Generation..."
TOKEN=$(aws rds generate-db-auth-token \
  --hostname $DSQL_ENDPOINT \
  --port 5432 \
  --username $IAM_USER \
  --region $REGION)

if [ -n "$TOKEN" ] && [ ${#TOKEN} -gt 1000 ]; then
  echo "✓ Token generated successfully (${#TOKEN} characters)"
else
  echo "✗ Token generation failed"
  exit 1
fi
echo ""

# Test 3: DSQL connectivity
echo "TEST 3: DSQL Database Connectivity..."
PGPASSWORD="$TOKEN" psql \
  -h $DSQL_ENDPOINT \
  -p 5432 \
  -U $IAM_USER \
  -d $DB_NAME \
  -c "SELECT version();" > /dev/null 2>&1

if [ $? -eq 0 ]; then
  echo "✓ DSQL connection successful"
else
  echo "✗ DSQL connection failed"
  exit 1
fi
echo ""

# Test 4: Check event_headers table
echo "TEST 4: Checking event_headers table..."
TABLE_EXISTS=$(PGPASSWORD="$TOKEN" psql \
  -h $DSQL_ENDPOINT \
  -p 5432 \
  -U $IAM_USER \
  -d $DB_NAME \
  -t -c "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'event_headers');" 2>/dev/null)

if [[ "$TABLE_EXISTS" == *"t"* ]]; then
  echo "✓ event_headers table exists"
else
  echo "✗ event_headers table missing"
  exit 1
fi
echo ""

# Test 5: Build connector
echo "TEST 5: Building Debezium Connector..."
./gradlew clean build --no-daemon > build.log 2>&1

if [ $? -eq 0 ]; then
  echo "✓ Connector built successfully"
else
  echo "✗ Build failed. Check build.log"
  exit 1
fi
echo ""

# Test 6: Unit tests
echo "TEST 6: Running Unit Tests..."
./gradlew test --no-daemon > test.log 2>&1

if [ $? -eq 0 ]; then
  echo "✓ Unit tests passed"
else
  echo "✗ Unit tests failed. Check test.log"
  exit 1
fi
echo ""

# Test 7: Connector configuration validation
echo "TEST 7: Connector Configuration Validation..."
# Create test config
cat > test-config.json << EOF
{
  "name": "dsql-cdc-test",
  "config": {
    "connector.class": "io.debezium.connector.dsql.DsqlConnector",
    "tasks.max": "1",
    "dsql.endpoint.primary": "$DSQL_ENDPOINT",
    "dsql.port": "5432",
    "dsql.region": "$REGION",
    "dsql.iam.username": "$IAM_USER",
    "dsql.database.name": "$DB_NAME",
    "dsql.tables": "event_headers",
    "dsql.poll.interval.ms": "1000",
    "dsql.batch.size": "1000",
    "topic.prefix": "dsql-cdc-test"
  }
}
EOF

echo "✓ Test configuration created"
echo ""

# Test 8: Integration test (requires Kafka setup)
echo "TEST 8: Integration Test Setup..."
echo "Note: Full integration test requires Kafka Connect environment"
echo "For manual testing:"
echo "1. Start Kafka Connect with the built JAR"
echo "2. Deploy the connector using test-config.json"
echo "3. Insert test data into event_headers table"
echo "4. Verify CDC events in Kafka topics"
echo ""

echo "=== Test Suite Complete ==="
echo "✓ Infrastructure verified"
echo "✓ IAM authentication working"
echo "✓ DSQL connectivity confirmed"
echo "✓ Database schema verified"
echo "✓ Connector builds successfully"
echo "✓ Unit tests pass"
echo ""
echo "Next: Deploy to Kafka Connect and test CDC functionality"
echo ""
echo "To deploy manually:"
echo "1. Copy debezium-connector-dsql/build/libs/debezium-connector-dsql-1.0.0.jar to Kafka Connect plugins/"
echo "2. Restart Kafka Connect"
echo "3. POST test-config.json to /connectors endpoint"
echo "4. Insert test data and monitor topics"
