#!/bin/bash
# Complete setup script for Confluent Cloud CDC with DSQL Debezium connector

set -e

echo "=== CONFLUENT CLOUD CDC SETUP FOR DSQL ==="
echo ""

# Check if Confluent CLI is installed
if ! command -v confluent &> /dev/null; then
    echo "❌ Confluent CLI not found. Install from: https://docs.confluent.io/confluent-cli/current/install.html"
    exit 1
fi

echo "✅ Confluent CLI found"
echo ""

# Check if logged in
echo "Checking Confluent Cloud authentication..."
if ! confluent environment list &> /dev/null; then
    echo "❌ Not logged in to Confluent Cloud. Run: confluent login"
    exit 1
fi

echo "✅ Authenticated to Confluent Cloud"
echo ""

# Get current environment and cluster
echo "Current Confluent Cloud setup:"
confluent environment list
echo ""
confluent kafka cluster list
echo ""

# Prompt for cluster selection
echo "Enter your Confluent Cloud cluster ID:"
read -r CLUSTER_ID

if [ -z "$CLUSTER_ID" ]; then
    echo "❌ No cluster ID provided"
    exit 1
fi

# Use the cluster
confluent kafka cluster use "$CLUSTER_ID"
echo ""

# Create topic
echo "Creating topic 'dsql-cdc-event-headers'..."
confluent kafka topic create dsql-cdc-event-headers \
  --partitions 3 \
  --retention-ms -1 \
  --if-not-exists

echo "✅ Topic created"
echo ""

# Get cluster details
echo "Cluster details:"
CLUSTER_DETAILS=$(confluent kafka cluster describe)
BOOTSTRAP_SERVERS=$(echo "$CLUSTER_DETAILS" | grep "Endpoint:" | awk '{print $2}')
echo "Bootstrap servers: $BOOTSTRAP_SERVERS"
echo ""

# Check for existing API keys
echo "Checking existing API keys..."
API_KEYS=$(confluent api-key list --resource "$CLUSTER_ID")

if echo "$API_KEYS" | grep -q "API Key"; then
    echo "Existing API keys found:"
    echo "$API_KEYS"
    echo ""
    echo "Enter existing API Key ID to use (or press Enter to create new):"
    read -r API_KEY_ID

    if [ -n "$API_KEY_ID" ]; then
        API_KEY=$(echo "$API_KEYS" | grep "$API_KEY_ID" | awk '{print $1}')
        echo "Using existing API key: $API_KEY"
    fi
fi

# Create new API key if needed
if [ -z "$API_KEY" ]; then
    echo "Creating new API key..."
    API_KEY_OUTPUT=$(confluent api-key create --resource "$CLUSTER_ID" --description "DSQL CDC Connector")
    API_KEY=$(echo "$API_KEY_OUTPUT" | grep "API Key:" | awk '{print $3}')
    API_SECRET=$(echo "$API_KEY_OUTPUT" | grep "API Secret:" | awk '{print $3}')
    echo "✅ API Key created: $API_KEY"
    echo "⚠️  API Secret: $API_SECRET (save this securely!)"
    echo ""
fi

# Check Schema Registry
echo "Checking Schema Registry..."
if confluent schema-registry cluster describe &> /dev/null; then
    echo "✅ Schema Registry enabled"
    SR_DETAILS=$(confluent schema-registry cluster describe)
    SR_ENDPOINT=$(echo "$SR_DETAILS" | grep "Endpoint:" | awk '{print $2}')
    echo "Schema Registry endpoint: $SR_ENDPOINT"
    echo ""

    # Create SR API key
    echo "Creating Schema Registry API key..."
    SR_API_KEY_OUTPUT=$(confluent api-key create --resource sr --description "DSQL CDC Schema Registry")
    SR_API_KEY=$(echo "$SR_API_KEY_OUTPUT" | grep "API Key:" | awk '{print $3}')
    SR_API_SECRET=$(echo "$SR_API_KEY_OUTPUT" | grep "API Secret:" | awk '{print $3}')
    echo "✅ SR API Key: $SR_API_KEY"
    echo "⚠️  SR API Secret: $SR_API_SECRET (save this securely!)"
else
    echo "⚠️  Schema Registry not enabled. Using JSON converters instead."
    SR_ENDPOINT=""
    SR_API_KEY=""
    SR_API_SECRET=""
fi

echo ""
echo "=== CONFIGURATION SUMMARY ==="
echo "Cluster ID: $CLUSTER_ID"
echo "Bootstrap Servers: $BOOTSTRAP_SERVERS"
echo "API Key: $API_KEY"
echo "Schema Registry: ${SR_ENDPOINT:-Not configured}"
echo ""

# Update connector config
echo "Updating connector configuration..."
CONFIG_FILE="confluent-dsql-connector-updated.json"

if [ -n "$SR_ENDPOINT" ]; then
    # With Schema Registry
    sed \
      -e "s|REPLACE_WITH_CONFLUENT_BOOTSTRAP_SERVERS|$BOOTSTRAP_SERVERS|g" \
      -e "s|REPLACE_WITH_CONFLUENT_API_KEY|$API_KEY|g" \
      -e "s|REPLACE_WITH_CONFLUENT_API_SECRET|$API_SECRET|g" \
      -e "s|REPLACE_WITH_SCHEMA_REGISTRY_URL|$SR_ENDPOINT|g" \
      -e "s|REPLACE_WITH_SR_API_KEY|$SR_API_KEY|g" \
      -e "s|REPLACE_WITH_SR_API_SECRET|$SR_API_SECRET|g" \
      confluent-dsql-connector.json > "$CONFIG_FILE"
else
    # Without Schema Registry (JSON converters)
    cat > "$CONFIG_FILE" << EOF
{
  "name": "dsql-cdc-connector",
  "config": {
    "connector.class": "io.debezium.connector.dsql.DsqlConnector",
    "tasks.max": "1",
    "dsql.endpoint.primary": "vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com",
    "dsql.port": "5432",
    "dsql.region": "us-east-1",
    "dsql.iam.username": "lambda_dsql_user",
    "dsql.database.name": "car_entities",
    "dsql.tables": "event_headers",
    "dsql.poll.interval.ms": "1000",
    "dsql.batch.size": "1000",
    "topic.prefix": "dsql-cdc",

    "bootstrap.servers": "$BOOTSTRAP_SERVERS",
    "security.protocol": "SASL_SSL",
    "sasl.mechanism": "PLAIN",
    "sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$API_KEY\" password=\"$API_SECRET\";",
    "ssl.endpoint.identification.algorithm": "https",
    "client.dns.lookup": "use_all_dns_ips",
    "session.timeout.ms": "45000",

    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",

    "transforms": "route",
    "transforms.route.type": "io.confluent.connect.cloud.transforms.TopicRegexRouter",
    "transforms.route.regex": "dsql-cdc\\.event_headers",
    "transforms.route.replacement": "raw-event-headers"
  }
}
EOF
fi

echo "✅ Configuration updated: $CONFIG_FILE"
echo ""

echo "=== NEXT STEPS ==="
echo "1. 🚀 Deploy connector to Confluent Cloud:"
echo "   curl -X POST \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d @$CONFIG_FILE \\"
echo "     https://<your-connect-endpoint>/connectors"
echo ""
echo "2. 📝 Insert test events (on EC2 instance):"
echo "   export DSQL_ENDPOINT='$(cd /Users/rickzakharov/dev/github/api-performance-multi-lang/terraform && terraform output -raw aurora_dsql_endpoint)'"
echo "   export IAM_USER='lambda_dsql_user'"
echo "   TOKEN=\$(aws rds generate-db-auth-token --hostname \$DSQL_ENDPOINT --port 5432 --username \$IAM_USER --region us-east-1)"
echo "   PGPASSWORD=\"\$TOKEN\" psql -h \$DSQL_ENDPOINT -p 5432 -U \$IAM_USER -d car_entities -f insert-test-events.sql"
echo ""
echo "3. 👀 Monitor CDC events:"
echo "   confluent kafka topic consume dsql-cdc-event-headers --from-beginning"
echo ""
echo "4. 📊 Check connector status:"
echo "   curl https://<your-connect-endpoint>/connectors/dsql-cdc-connector/status"
echo ""

echo "=== CONFIGURATION FILES CREATED ==="
echo "✅ $CONFIG_FILE - Ready for deployment"
echo "✅ insert-test-events.sql - Test data script"
echo "✅ setup-confluent-cdc.sh - This setup script"
echo ""

echo "🎉 Setup complete! Ready to deploy and test CDC pipeline."
