# Quick Start Guide - DSQL Connector Deployment

This guide provides a quick path to deploy the DSQL Debezium connector on your bastion host.

## Prerequisites Checklist

Before starting, ensure you have:
- [ ] DSQL cluster endpoint and database name
- [ ] IAM database username with `rds-db:connect` permission
- [ ] AWS credentials configured (IAM role on bastion or credentials file)
- [ ] Kafka bootstrap servers (for Kafka Connect deployment)
- [ ] List of tables to monitor for CDC

## Step 1: Verify Bastion Setup

Run the verification script to check if everything is ready:

```bash
cd debezium-connector-dsql
./scripts/verify-bastion-setup.sh
```

This will check:
- ✅ Docker installation and status
- ✅ Java installation
- ✅ Directory structure
- ✅ Connector JAR presence
- ✅ Configuration files
- ✅ Kafka Connect container status
- ✅ AWS credentials

## Step 2: Configure DSQL Connection

Connect to bastion and create `.env.dsql`:

```bash
# Connect to bastion
aws ssm start-session --target i-0adcbf0f85849149e --region us-east-1

# On bastion
cd ~/debezium-connector-dsql
cat > .env.dsql <<'EOF'
export DSQL_ENDPOINT_PRIMARY="your-dsql-endpoint.cluster-xyz.us-east-1.rds.amazonaws.com"
export DSQL_DATABASE_NAME="your-database-name"
export DSQL_REGION="us-east-1"
export DSQL_IAM_USERNAME="your-iam-username"
export DSQL_TABLES="table1,table2"
export DSQL_PORT="5432"
export DSQL_TOPIC_PREFIX="dsql-cdc"
EOF

chmod 600 .env.dsql
source .env.dsql
```

## Step 3: Deploy Kafka Connect (If Not Already Deployed)

**Option A: Automated Deployment**

```bash
# From local machine
cd debezium-connector-dsql
export KAFKA_BOOTSTRAP_SERVERS="your-kafka-brokers:9092"
./scripts/deploy-kafka-connect-bastion.sh "$KAFKA_BOOTSTRAP_SERVERS"
```

**Option B: Manual Deployment**

```bash
# On bastion
cd ~/debezium-connector-dsql
mkdir -p connector
cp lib/debezium-connector-dsql.jar connector/

docker pull debezium/connect:latest

docker run -d \
  --name kafka-connect-dsql \
  --restart unless-stopped \
  -p 8083:8083 \
  -v ~/debezium-connector-dsql/connector:/kafka/connect/debezium-connector-dsql \
  -e CONNECT_BOOTSTRAP_SERVERS="your-kafka-brokers:9092" \
  -e CONNECT_REST_PORT=8083 \
  -e CONNECT_REST_ADVERTISED_HOST_NAME=localhost \
  -e CONNECT_GROUP_ID=dsql-connect-cluster \
  -e CONNECT_CONFIG_STORAGE_TOPIC=dsql-connect-config \
  -e CONNECT_OFFSET_STORAGE_TOPIC=dsql-connect-offsets \
  -e CONNECT_STATUS_STORAGE_TOPIC=dsql-connect-status \
  -e CONNECT_KEY_CONVERTER=org.apache.kafka.connect.json.JsonConverter \
  -e CONNECT_VALUE_CONVERTER=org.apache.kafka.connect.json.JsonConverter \
  -e CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE=false \
  -e CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE=false \
  -e CONNECT_PLUGIN_PATH=/kafka/connect \
  debezium/connect:latest
```

Wait for Kafka Connect to start (about 30 seconds), then verify:

```bash
curl http://localhost:8083/connector-plugins | grep -i dsql
```

## Step 4: Create Connector Configuration

On bastion, create the connector config file:

```bash
cd ~/debezium-connector-dsql
source .env.dsql

cat > config/dsql-connector.json <<EOF
{
  "name": "dsql-cdc-source",
  "config": {
    "connector.class": "io.debezium.connector.dsql.DsqlConnector",
    "tasks.max": "1",
    "dsql.endpoint.primary": "$DSQL_ENDPOINT_PRIMARY",
    "dsql.port": "$DSQL_PORT",
    "dsql.region": "$DSQL_REGION",
    "dsql.iam.username": "$DSQL_IAM_USERNAME",
    "dsql.database.name": "$DSQL_DATABASE_NAME",
    "dsql.tables": "$DSQL_TABLES",
    "dsql.poll.interval.ms": "1000",
    "dsql.batch.size": "1000",
    "dsql.pool.max.size": "10",
    "dsql.pool.min.idle": "1",
    "dsql.pool.connection.timeout.ms": "30000",
    "topic.prefix": "$DSQL_TOPIC_PREFIX",
    "output.data.format": "JSON"
  }
}
EOF
```

## Step 5: Create the Connector

```bash
# On bastion
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @config/dsql-connector.json
```

## Step 6: Verify Connector Status

```bash
# Check connector status
curl http://localhost:8083/connectors/dsql-cdc-source/status | jq

# Check connector tasks
curl http://localhost:8083/connectors/dsql-cdc-source/tasks | jq

# View logs
docker logs -f kafka-connect-dsql
```

Expected status: `"state": "RUNNING"`

## Step 7: Verify CDC Events

Check Kafka topics for CDC events:

```bash
# List topics (if you have kafka-console-consumer available)
# Or use your Kafka client to consume from topics:
# - dsql-cdc.public.table1
# - dsql-cdc.public.table2
# etc.
```

## Troubleshooting

### Connector in FAILED State

```bash
# Get detailed error
curl http://localhost:8083/connectors/dsql-cdc-source/status | jq '.tasks[0].trace'

# Common issues:
# - DSQL endpoint not accessible (check security groups)
# - IAM authentication failed (check credentials and permissions)
# - Tables don't exist or missing primary keys
```

### Connection Errors

```bash
# Test connection manually
source ~/debezium-connector-dsql/.env.dsql
# Use DsqlConnectionTester if test classes are available
```

### Kafka Connect Not Starting

```bash
# Check logs
docker logs kafka-connect-dsql

# Check if port is in use
netstat -tuln | grep 8083

# Restart container
docker restart kafka-connect-dsql
```

## Next Steps

After successful deployment:

1. **Monitor Performance**: Track connector metrics and latency
2. **Set Up Alerts**: Configure monitoring for connector failures
3. **Test Failover**: If multi-region, test failover scenarios
4. **Scale**: Adjust `tasks.max` if needed for multiple tables
5. **Production Hardening**: Enable TLS, configure secrets management

## Quick Reference

### Bastion Connection
```bash
aws ssm start-session --target i-0adcbf0f85849149e --region us-east-1
```

### Key Commands

```bash
# Check connector status
curl http://localhost:8083/connectors/dsql-cdc-source/status

# Restart connector
curl -X POST http://localhost:8083/connectors/dsql-cdc-source/restart

# Delete connector
curl -X DELETE http://localhost:8083/connectors/dsql-cdc-source

# View logs
docker logs -f kafka-connect-dsql
```

## Documentation

- **KAFKA-CONNECT-DEPLOYMENT.md** - Detailed deployment guide
- **BASTION-TESTING-GUIDE.md** - Testing guide
- **DEPLOYMENT-STATUS.md** - Current deployment status
- **test-on-ec2-md** - Original instructions

## Support

For issues or questions:
1. Check logs: `docker logs kafka-connect-dsql`
2. Verify setup: `./scripts/verify-bastion-setup.sh`
3. Review documentation in `debezium-connector-dsql/` directory
