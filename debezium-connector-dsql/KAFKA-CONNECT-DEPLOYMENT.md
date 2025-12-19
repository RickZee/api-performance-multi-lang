# Kafka Connect Deployment on Bastion

This guide explains how to deploy Kafka Connect with the DSQL connector on the bastion host.

## Prerequisites

✅ **Completed:**
- Docker installed and running on bastion
- Java 11 installed
- Connector JAR uploaded to bastion (`~/debezium-connector-dsql/lib/debezium-connector-dsql.jar`)

## Deployment Steps

### Step 1: Deploy Kafka Connect Container

**Option A: Automated Deployment (from local machine)**

```bash
cd debezium-connector-dsql

# Set Kafka bootstrap servers
export KAFKA_BOOTSTRAP_SERVERS="your-kafka-brokers:9092"

# Deploy
./scripts/deploy-kafka-connect-bastion.sh "$KAFKA_BOOTSTRAP_SERVERS"
```

**Option B: Manual Deployment (on bastion)**

```bash
# Connect to bastion
aws ssm start-session --target i-0adcbf0f85849149e --region us-east-1

# On bastion
cd ~/debezium-connector-dsql
mkdir -p connector
cp lib/debezium-connector-dsql.jar connector/

# Pull Debezium Connect image
docker pull debezium/connect:latest

# Run Kafka Connect container
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

### Step 2: Verify Kafka Connect is Running

```bash
# Check container status
docker ps | grep kafka-connect

# Check logs
docker logs kafka-connect-dsql

# Check health
curl http://localhost:8083/connector-plugins
```

### Step 3: Upload Connector Configuration

**Option A: Automated (from local machine)**

```bash
./scripts/create-connector-bastion.sh
```

**Option B: Manual (on bastion)**

```bash
# Create config directory
mkdir -p ~/debezium-connector-dsql/config

# Create connector config file
cat > ~/debezium-connector-dsql/config/dsql-connector.json <<'EOF'
{
  "name": "dsql-cdc-source",
  "config": {
    "connector.class": "io.debezium.connector.dsql.DsqlConnector",
    "tasks.max": "1",
    "dsql.endpoint.primary": "your-dsql-endpoint.cluster-xyz.us-east-1.rds.amazonaws.com",
    "dsql.port": "5432",
    "dsql.region": "us-east-1",
    "dsql.iam.username": "your-iam-username",
    "dsql.database.name": "your-database-name",
    "dsql.tables": "table1,table2",
    "dsql.poll.interval.ms": "1000",
    "dsql.batch.size": "1000",
    "dsql.pool.max.size": "10",
    "dsql.pool.min.idle": "1",
    "dsql.pool.connection.timeout.ms": "30000",
    "topic.prefix": "dsql-cdc",
    "output.data.format": "JSON"
  }
}
EOF
```

### Step 4: Create the Connector

```bash
# On bastion
cd ~/debezium-connector-dsql

# Create connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @config/dsql-connector.json
```

### Step 5: Verify Connector Status

```bash
# List all connectors
curl http://localhost:8083/connectors

# Check connector status
curl http://localhost:8083/connectors/dsql-cdc-source/status

# Check connector configuration
curl http://localhost:8083/connectors/dsql-cdc-source/config
```

## Configuration Reference

### Required Configuration Properties

| Property | Description | Example |
|----------|-------------|---------|
| `connector.class` | Connector class name | `io.debezium.connector.dsql.DsqlConnector` |
| `dsql.endpoint.primary` | Primary DSQL endpoint | `dsql-primary.cluster-xyz.us-east-1.rds.amazonaws.com` |
| `dsql.database.name` | Database name | `mortgage_db` |
| `dsql.region` | AWS region | `us-east-1` |
| `dsql.iam.username` | IAM database username | `admin` |
| `dsql.tables` | Comma-separated tables | `event_headers,business_events` |

### Optional Configuration Properties

| Property | Default | Description |
|----------|---------|-------------|
| `dsql.endpoint.secondary` | None | Secondary endpoint for failover |
| `dsql.port` | `5432` | Database port |
| `dsql.poll.interval.ms` | `1000` | Polling interval (ms) |
| `dsql.batch.size` | `1000` | Max records per poll |
| `dsql.pool.max.size` | `10` | Max connection pool size |
| `dsql.pool.min.idle` | `1` | Min idle connections |
| `dsql.pool.connection.timeout.ms` | `30000` | Connection timeout (ms) |
| `topic.prefix` | `dsql-cdc` | Kafka topic prefix |
| `tasks.max` | `1` | Number of connector tasks |

## Troubleshooting

### Container Not Starting

```bash
# Check logs
docker logs kafka-connect-dsql

# Check if port is already in use
netstat -tuln | grep 8083

# Restart container
docker restart kafka-connect-dsql
```

### Connector Not Found

```bash
# Verify connector JAR is in the right place
ls -lh ~/debezium-connector-dsql/connector/

# Check if connector is loaded
curl http://localhost:8083/connector-plugins | grep -i dsql

# Restart Kafka Connect to reload plugins
docker restart kafka-connect-dsql
```

### Connection Errors

```bash
# Check connector status for errors
curl http://localhost:8083/connectors/dsql-cdc-source/status

# Check logs
docker logs kafka-connect-dsql | grep -i error

# Verify DSQL endpoint is accessible from bastion
# (Check security groups, VPC routing, etc.)
```

### Connector in FAILED State

```bash
# Get detailed error
curl http://localhost:8083/connectors/dsql-cdc-source/status | jq

# Restart connector
curl -X POST http://localhost:8083/connectors/dsql-cdc-source/restart

# Delete and recreate if needed
curl -X DELETE http://localhost:8083/connectors/dsql-cdc-source
# Then recreate with corrected config
```

## Monitoring

### Check Connector Metrics

```bash
# Connector status
curl http://localhost:8083/connectors/dsql-cdc-source/status

# Connector tasks
curl http://localhost:8083/connectors/dsql-cdc-source/tasks

# Kafka Connect cluster info
curl http://localhost:8083
```

### View Logs

```bash
# Follow logs
docker logs -f kafka-connect-dsql

# Last 100 lines
docker logs --tail 100 kafka-connect-dsql
```

## Next Steps

After successful deployment:

1. **Verify CDC Events**: Check Kafka topics for CDC events
2. **Monitor Performance**: Track connector metrics and latency
3. **Test Failover**: Test multi-region failover if configured
4. **Production Hardening**: Configure monitoring, alerting, and backup

## Security Considerations

- **Network**: Ensure security groups allow outbound to Kafka brokers
- **IAM**: Verify IAM user has `rds-db:connect` permission
- **Secrets**: Consider using AWS Secrets Manager or Vault for credentials
- **TLS**: Enable TLS for Kafka connections in production
- **Firewall**: Restrict access to Kafka Connect REST API (port 8083)

## References

- [Debezium Documentation](https://debezium.io/documentation/)
- [Kafka Connect REST API](https://kafka.apache.org/documentation/#connect_rest)
- `test-on-ec2-md` - Original deployment instructions
- `BASTION-TESTING-GUIDE.md` - Testing guide
