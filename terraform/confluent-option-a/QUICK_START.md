# Quick Start: Test DSQL Connector with Confluent Cloud (Option A)

This guide runs **Kafka Connect on EC2** (in your VPC) and streams CDC events to **Confluent Cloud**.

## Prerequisites Checklist

- [ ] EC2 test runner instance deployed (`terraform apply`)
- [ ] Repo-root `.env` file with Confluent credentials
- [ ] Connector JAR built (`debezium-connector-dsql/build/libs/debezium-connector-dsql-1.0.0.jar`)
- [ ] Docker installed on EC2 (will be installed automatically if missing)

## Step-by-Step Execution

### 1. Connect to EC2 Instance

```bash
cd terraform
terraform output -raw dsql_test_runner_ssm_command | bash
```

### 2. On EC2: Clone and Setup

```bash
# Clone repository
cd /tmp
git clone https://github.com/rickzakharov/api-performance-multi-lang.git
cd api-performance-multi-lang

# Ensure .env exists (copy from your local machine or create manually)
# The .env should contain:
# KAFKA_BOOTSTRAP_SERVERS=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
# KAFKA_API_KEY=your-key
# KAFKA_API_SECRET=your-secret

# Generate connect.env from Terraform + .env
./terraform/confluent-option-a/setup-connect-env.sh
```

### 3. Run End-to-End Test

```bash
cd terraform/confluent-option-a
./run-e2e.sh
```

This script will:
1. ✅ Install Docker if needed
2. ✅ Build connector JAR if missing
3. ✅ Start Kafka Connect container
4. ✅ Create Confluent Cloud topics
5. ✅ Deploy DSQL connector
6. ✅ Insert test events into DSQL
7. ✅ Consume and display events from Confluent topic

### 4. Verify Results

The script will show:
- Connector status (should be RUNNING)
- Test events inserted into DSQL
- CDC events consumed from Confluent topic `raw-event-headers`

## Expected Output

You should see Debezium-formatted CDC events like:

```json
{
  "schema": {...},
  "payload": {
    "before": null,
    "after": {
      "id": "test-1",
      "event_name": "user.event",
      "event_type": "CREATE",
      ...
    },
    "source": {
      "connector": "dsql",
      "name": "dsql-cdc",
      ...
    },
    "op": "c",
    "ts_ms": 1734086400000
  }
}
```

## Troubleshooting

### Connector Won't Start

1. **Check logs**:
   ```bash
   docker logs kafka-connect-dsql
   ```

2. **Verify DSQL connectivity**:
   ```bash
   # On EC2
   export DSQL_ENDPOINT=$(cd /tmp/api-performance-multi-lang/terraform && terraform output -raw aurora_dsql_endpoint)
   export IAM_USER="lambda_dsql_user"
   TOKEN=$(aws rds generate-db-auth-token --hostname $DSQL_ENDPOINT --port 5432 --username $IAM_USER --region us-east-1)
   PGPASSWORD="$TOKEN" psql -h $DSQL_ENDPOINT -p 5432 -U $IAM_USER -d car_entities -c "SELECT 1;"
   ```

3. **Check Confluent connectivity**:
   ```bash
   # Test from EC2
   curl -v telnet://$(echo $KAFKA_BOOTSTRAP_SERVERS | cut -d: -f1):9092
   ```

### No Events in Confluent Topic

1. **Verify connector is RUNNING**:
   ```bash
   curl http://localhost:8083/connectors/dsql-cdc-connector/status | jq
   ```

2. **Check DSQL table has data**:
   ```sql
   SELECT COUNT(*) FROM event_headers WHERE saved_date > NOW() - INTERVAL '5 minutes';
   ```

3. **Check connector logs for errors**:
   ```bash
   docker logs kafka-connect-dsql | tail -50
   ```

### Network Issues

If EC2 can't reach Confluent Cloud:
- **IPv6**: Your VPC has IPv6 enabled, but Confluent may require IPv4
- **Solution**: Enable NAT Gateway in Terraform (`enable_nat_gateway = true`)
- **Or**: Use Confluent Cloud PrivateLink (see `terraform/modules/confluent-privatelink/`)

## Manual Steps (Alternative)

If the automated script fails, you can run steps manually:

```bash
# 1. Start Kafka Connect
cd /tmp/api-performance-multi-lang/terraform/confluent-option-a
docker-compose -f docker-compose.connect.yml up -d

# 2. Wait for Connect to be ready
sleep 30
curl http://localhost:8083/

# 3. Deploy connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connector.json

# 4. Check status
curl http://localhost:8083/connectors/dsql-cdc-connector/status | jq

# 5. Insert test data
# (Use insert-test-events.sql from terraform/)

# 6. Consume from Confluent
confluent kafka topic consume raw-event-headers --from-beginning
```

## Next Steps After Success

1. **Monitor connector health** regularly
2. **Set up alerts** for connector failures
3. **Configure downstream consumers** for CDC events
4. **Test failover scenarios** (multi-region DSQL)
5. **Performance tuning** based on load

## Files Reference

- **`setup-connect-env.sh`**: Generates `connect.env` from Terraform + `.env`
- **`run-e2e.sh`**: Complete end-to-end test automation
- **`docker-compose.connect.yml`**: Kafka Connect container config
- **`connector.json.tmpl`**: DSQL connector configuration template
- **`connect.env.example`**: Example environment file (copy to `connect.env`)

