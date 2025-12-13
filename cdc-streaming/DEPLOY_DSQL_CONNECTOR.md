# Deploy Custom DSQL Debezium Connector to Confluent Cloud

This guide walks through deploying the custom DSQL Debezium connector to Confluent Cloud.

## Prerequisites

1. **Confluent Cloud Account** with Kafka cluster
2. **Confluent CLI** installed and authenticated
3. **DSQL Cluster** deployed via Terraform
4. **Connector JAR** built (`debezium-connector-dsql/build/libs/debezium-connector-dsql-1.0.0.jar`)

## Quick Start

### Step 1: Get DSQL Configuration

```bash
cd terraform

# Get DSQL endpoint and cluster resource ID
export DSQL_ENDPOINT_PRIMARY=$(terraform output -raw aurora_dsql_endpoint)
export DSQL_CLUSTER_RESOURCE_ID=$(terraform output -raw aurora_dsql_cluster_resource_id)
export DSQL_IAM_USERNAME="lambda_dsql_user"
export DSQL_DATABASE_NAME="car_entities"
export DSQL_REGION="us-east-1"
export DSQL_PORT="5432"
export DSQL_TABLES="event_headers"
```

### Step 2: Get Confluent Cloud Credentials

```bash
# Login to Confluent Cloud
confluent login

# Get cluster ID
export KAFKA_CLUSTER_ID=$(confluent kafka cluster list --output json | jq -r '.[0].id')

# Create API key for Kafka
confluent api-key create --resource "$KAFKA_CLUSTER_ID" --description "DSQL CDC Connector"
# Save the key and secret

export KAFKA_API_KEY="<your-api-key>"
export KAFKA_API_SECRET="<your-api-secret>"
```

### Step 3: Deploy Connector

```bash
cd ../cdc-streaming

# Run deployment script
./scripts/deploy-dsql-connector.sh
```

The script will:
- ✅ Check prerequisites
- ✅ Create required topics
- ✅ Deploy connector configuration
- ✅ Verify connector status

## Manual Deployment (Alternative)

If the automated script doesn't work, deploy manually:

### 1. Upload Connector JAR to Confluent Cloud

1. Visit Confluent Cloud Console
2. Navigate to **Connectors** → **Add connector**
3. Select **Custom connector**
4. Upload: `debezium-connector-dsql/build/libs/debezium-connector-dsql-1.0.0.jar`

### 2. Configure Connector

Use the configuration from `cdc-streaming/connectors/dsql-cdc-source-event-headers-confluent-cloud.json`:

```json
{
  "name": "dsql-cdc-source-event-headers",
  "config": {
    "connector.class": "io.debezium.connector.dsql.DsqlConnector",
    "kafka.auth.mode": "SASL_SSL",
    "kafka.api.key": "<your-kafka-api-key>",
    "kafka.api.secret": "<your-kafka-api-secret>",
    "dsql.endpoint.primary": "vpce-xxx.dsql-fnh4.us-east-1.vpce.amazonaws.com",
    "dsql.port": "5432",
    "dsql.region": "us-east-1",
    "dsql.iam.username": "lambda_dsql_user",
    "dsql.database.name": "car_entities",
    "dsql.cluster.resource.id": "vftmkydwxvxys6asbsc6ih2the",
    "dsql.tables": "event_headers",
    "dsql.poll.interval.ms": "1000",
    "dsql.batch.size": "1000",
    "topic.prefix": "dsql-cdc",
    "tasks.max": "1"
  }
}
```

### 3. Create Topics

```bash
confluent kafka topic create dsql-cdc.event_headers --partitions 3 --retention-ms -1
confluent kafka topic create raw-event-headers --partitions 3 --retention-ms -1
```

## Testing

### Step 1: Insert Test Events

On the EC2 test runner instance:

```bash
# Connect to EC2
cd terraform
terraform output -raw dsql_test_runner_ssm_command | bash

# On EC2 instance:
export DSQL_ENDPOINT=$(cd /tmp/api-performance-multi-lang/terraform && terraform output -raw aurora_dsql_endpoint)
export IAM_USER="lambda_dsql_user"

# Generate token
TOKEN=$(aws rds generate-db-auth-token \
  --hostname $DSQL_ENDPOINT \
  --port 5432 \
  --username $IAM_USER \
  --region us-east-1)

# Insert test events
PGPASSWORD="$TOKEN" psql \
  -h $DSQL_ENDPOINT \
  -p 5432 \
  -U $IAM_USER \
  -d car_entities \
  -f /tmp/api-performance-multi-lang/terraform/insert-test-events.sql
```

### Step 2: Monitor CDC Events

```bash
# Monitor the topic
confluent kafka topic consume raw-event-headers --from-beginning

# Or with JSON formatting
confluent kafka topic consume raw-event-headers --from-beginning --value-format json
```

### Expected Output

You should see Debezium-formatted CDC events:

```json
{
  "schema": {...},
  "payload": {
    "before": null,
    "after": {
      "id": "confluent-test-1",
      "event_name": "user.event",
      "event_type": "CREATE",
      "created_date": "2024-12-13T...",
      "saved_date": "2024-12-13T...",
      "header_data": {"test_id": 1, "source": "confluent_test"}
    },
    "source": {
      "version": "1.0.0",
      "connector": "dsql",
      "name": "dsql-cdc",
      "ts_ms": 1734086400000,
      "snapshot": "false",
      "db": "car_entities",
      "table": "event_headers"
    },
    "op": "c",
    "ts_ms": 1734086400000
  }
}
```

## Troubleshooting

### Connector Won't Start

1. **Check connector status**:
   ```bash
   confluent connect list
   confluent connect describe <connector-id>
   ```

2. **View logs**:
   ```bash
   confluent connect logs <connector-id>
   ```

3. **Common issues**:
   - Missing connector JAR upload
   - Incorrect IAM permissions
   - DSQL endpoint not accessible from Confluent Cloud
   - Missing topics

### No Events Appearing

1. **Verify connector is RUNNING**:
   ```bash
   confluent connect describe <connector-id> | jq '.status.connector.state'
   ```

2. **Check DSQL table has data**:
   ```sql
   SELECT COUNT(*) FROM event_headers WHERE saved_date > NOW() - INTERVAL '5 minutes';
   ```

3. **Verify IAM permissions**:
   - EC2 instance role has `rds-db:connect` permission
   - IAM database user exists in DSQL

4. **Check networking**:
   - Confluent Cloud may need VPC peering to access DSQL
   - Or use Confluent Cloud PrivateLink (if available)

### Connection Errors

1. **Test DSQL connectivity**:
   ```bash
   # On EC2 instance
   TOKEN=$(aws rds generate-db-auth-token --hostname $DSQL_ENDPOINT --port 5432 --username $IAM_USER --region us-east-1)
   PGPASSWORD="$TOKEN" psql -h $DSQL_ENDPOINT -p 5432 -U $IAM_USER -d car_entities -c "SELECT 1;"
   ```

2. **Check security groups**:
   - Ensure Confluent Cloud IPs can reach DSQL (if public)
   - Or configure VPC peering/PrivateLink

## Useful Commands

```bash
# List all connectors
confluent connect list

# Check connector status
confluent connect describe <connector-id>

# View connector logs
confluent connect logs <connector-id>

# Restart connector
confluent connect pause <connector-id>
confluent connect resume <connector-id>

# Delete connector
confluent connect delete <connector-id> --force

# Monitor topics
confluent kafka topic consume raw-event-headers --from-beginning
confluent kafka topic describe raw-event-headers

# Check topic messages
confluent kafka topic consume raw-event-headers --from-beginning --max-messages 10
```

## Next Steps

After successful deployment:

1. **Monitor connector health** regularly
2. **Set up alerts** for connector failures
3. **Configure downstream consumers** for the CDC events
4. **Test failover scenarios** (multi-region DSQL)
5. **Performance tuning** based on load

## Configuration Reference

See `cdc-streaming/connectors/dsql-cdc-source-event-headers-confluent-cloud.json` for full configuration options.

Key settings:
- `dsql.poll.interval.ms`: How often to poll for changes (default: 1000ms)
- `dsql.batch.size`: Maximum records per poll (default: 1000)
- `topic.prefix`: Prefix for generated topics (default: dsql-cdc)
- `transforms.route.replacement`: Final topic name (default: raw-event-headers)
