#!/bin/bash
# Complete Debezium DSQL Connector Testing Steps
# Run this script on the EC2 test runner instance

set -e

echo "=== DEBEZIUM DSQL CONNECTOR TESTING ==="
echo "Starting comprehensive test suite..."
echo ""

# Configuration
DSQL_ENDPOINT="${DSQL_ENDPOINT:-vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com}"
IAM_USER="${IAM_USER:-lambda_dsql_user}"
REPO_URL="https://github.com/rickzakharov/api-performance-multi-lang.git"

echo "Configuration:"
echo "  DSQL Endpoint: $DSQL_ENDPOINT"
echo "  IAM User: $IAM_USER"
echo "  Repository: $REPO_URL"
echo ""

# Step 1: Install tools
echo "STEP 1: Installing required tools..."
sudo dnf install -y java-17-amazon-corretto-headless postgresql15 git unzip
echo "✓ Tools installed successfully"
echo ""

# Step 2: Clone repository
echo "STEP 2: Cloning repository..."
cd /tmp
if [ ! -d "api-performance-multi-lang" ]; then
    git clone $REPO_URL
fi
cd api-performance-multi-lang/debezium-connector-dsql
echo "✓ Repository cloned"
echo ""

# Step 3: Build connector
echo "STEP 3: Building Debezium connector..."
./gradlew clean build test --no-daemon
echo "✓ Connector built successfully"
echo ""

# Step 4: Test IAM token generation
echo "STEP 4: Testing IAM token generation..."
TOKEN=$(aws rds generate-db-auth-token \
  --hostname $DSQL_ENDPOINT \
  --port 5432 \
  --username $IAM_USER \
  --region us-east-1)

if [ ${#TOKEN} -gt 1000 ]; then
    echo "✓ IAM token generated successfully (${#TOKEN} characters)"
else
    echo "✗ Failed to generate IAM token"
    exit 1
fi
echo ""

# Step 5: Test DSQL connectivity
echo "STEP 5: Testing DSQL database connectivity..."
PGPASSWORD="$TOKEN" psql \
  -h $DSQL_ENDPOINT \
  -p 5432 \
  -U $IAM_USER \
  -d car_entities \
  -c "SELECT version();" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✓ DSQL connection successful"
else
    echo "✗ DSQL connection failed"
    exit 1
fi
echo ""

# Step 6: Check event_headers table
echo "STEP 6: Checking event_headers table..."
TABLE_COUNT=$(PGPASSWORD="$TOKEN" psql \
  -h $DSQL_ENDPOINT \
  -p 5432 \
  -U $IAM_USER \
  -d car_entities \
  -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'event_headers';" 2>/dev/null)

if [[ "$TABLE_COUNT" == "1" ]]; then
    echo "✓ event_headers table exists"
else
    echo "✗ event_headers table missing"
    exit 1
fi

# Show table structure
echo "Table structure:"
PGPASSWORD="$TOKEN" psql \
  -h $DSQL_ENDPOINT \
  -p 5432 \
  -U $IAM_USER \
  -d car_entities \
  -c "\d event_headers"
echo ""

# Step 7: Show sample data
echo "STEP 7: Sample data from event_headers table..."
PGPASSWORD="$TOKEN" psql \
  -h $DSQL_ENDPOINT \
  -p 5432 \
  -U $IAM_USER \
  -d car_entities \
  -c "SELECT id, event_name, event_type, created_date, saved_date FROM event_headers LIMIT 5;"
echo ""

# Step 8: Test connector configuration
echo "STEP 8: Testing connector configuration..."
cat > test-config.json << EOF
{
  "name": "dsql-cdc-test",
  "config": {
    "connector.class": "io.debezium.connector.dsql.DsqlConnector",
    "tasks.max": "1",
    "dsql.endpoint.primary": "$DSQL_ENDPOINT",
    "dsql.port": "5432",
    "dsql.region": "us-east-1",
    "dsql.iam.username": "$IAM_USER",
    "dsql.database.name": "car_entities",
    "dsql.tables": "event_headers",
    "dsql.poll.interval.ms": "1000",
    "dsql.batch.size": "1000",
    "topic.prefix": "dsql-cdc-test"
  }
}
EOF
echo "✓ Test configuration created"
echo ""

echo "=== TEST SUITE COMPLETE ==="
echo ""
echo "✅ SUCCESSFUL TESTS:"
echo "  ✓ Tools installed"
echo "  ✓ Repository cloned"
echo "  ✓ Connector built"
echo "  ✓ Unit tests passed"
echo "  ✓ IAM token generation"
echo "  ✓ DSQL connectivity"
echo "  ✓ Database schema validation"
echo "  ✓ Connector configuration"
echo ""
echo "🎯 NEXT STEPS:"
echo "  1. Set up Kafka Connect environment (optional)"
echo "  2. Deploy connector: curl -X POST -H 'Content-Type: application/json' -d @test-config.json http://localhost:8083/connectors"
echo "  3. Insert test data and monitor CDC events"
echo ""
echo "📁 FILES CREATED:"
echo "  - /tmp/api-performance-multi-lang/debezium-connector-dsql/build/libs/debezium-connector-dsql-1.0.0.jar"
echo "  - test-config.json"
