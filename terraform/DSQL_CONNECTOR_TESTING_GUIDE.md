# Debezium DSQL Connector Testing Guide

## Prerequisites

1. **EC2 Test Runner**: Deployed and accessible via SSM
2. **Tools Installed**: Java 17, PostgreSQL client, Git, Docker
3. **DSQL Database**: Aurora DSQL cluster with `event_headers` table
4. **Repository**: Cloned on EC2 instance

## Quick Test Commands

### 1. Connect to EC2 Instance

```bash
cd terraform
terraform output -raw dsql_test_runner_ssm_command | bash
```

### 2. Run Basic Tests

On the EC2 instance:
```bash
cd /tmp/api-performance-multi-lang/debezium-connector-dsql
./gradlew build test
```

### 3. Test DSQL Connectivity

```bash
export DSQL_ENDPOINT="vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com"
export IAM_USER="lambda_dsql_user"

TOKEN=$(aws rds generate-db-auth-token --hostname $DSQL_ENDPOINT --port 5432 --username $IAM_USER --region us-east-1)
PGPASSWORD="$TOKEN" psql -h $DSQL_ENDPOINT -p 5432 -U $IAM_USER -d car_entities -c "SELECT * FROM event_headers LIMIT 5;"
```

### 4. Full Integration Test

```bash
# Run comprehensive test
bash /tmp/api-performance-multi-lang/terraform/scripts/test-debezium-connector.sh
```

## Manual Testing Steps

### Step 1: Verify Environment

```bash
# Check tools
java -version
psql --version
git --version
docker --version

# Check AWS credentials
aws sts get-caller-identity

# Check DSQL access
aws rds generate-db-auth-token --hostname $DSQL_ENDPOINT --port 5432 --username $IAM_USER --region us-east-1
```

### Step 2: Build and Test Connector

```bash
cd /tmp/api-performance-multi-lang/debezium-connector-dsql

# Clean build
./gradlew clean build --no-daemon

# Run unit tests
./gradlew test --no-daemon

# Check build output
ls -la build/libs/
```

### Step 3: Set Up Test Environment

```bash
cd /tmp

# Run the deployment script
bash api-performance-multi-lang/terraform/scripts/deploy-connector-test.sh
```

This sets up:
- Zookeeper
- Kafka broker
- Kafka Connect with Debezium connector
- PostgreSQL test database

### Step 4: Deploy Connector

```bash
# Check connector plugins
curl -X GET http://localhost:8083/connector-plugins | jq '.[] | select(.class | contains("Dsql"))'

# Deploy connector
curl -X POST -H "Content-Type: application/json" \
  -d @dsql-connector-test.json \
  http://localhost:8083/connectors

# Check status
curl -X GET http://localhost:8083/connectors/dsql-cdc-connector/status
```

### Step 5: Test CDC Functionality

```bash
# Insert test data into DSQL
PGPASSWORD="$TOKEN" psql -h $DSQL_ENDPOINT -p 5432 -U $IAM_USER -d car_entities << 'EOF'
INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data)
VALUES
    ('cdc-test-1', 'user.created', 'CREATE', NOW(), NOW(), '{"user_id": "456", "email": "cdc@example.com"}'),
    ('cdc-test-2', 'user.updated', 'UPDATE', NOW(), NOW(), '{"user_id": "456", "changes": ["email"]}');
EOF

# Monitor Kafka topic
docker exec $(docker-compose -f docker-compose.test.yml ps -q kafka) \
  kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic dsql-test.event_headers \
  --from-beginning \
  --max-messages 10
```

### Step 6: Verify CDC Events

Expected output in Kafka topic should contain:
```json
{
  "schema": {...},
  "payload": {
    "before": null,
    "after": {
      "id": "cdc-test-1",
      "event_name": "user.created",
      "event_type": "CREATE",
      "created_date": "2024-12-13T...",
      "saved_date": "2024-12-13T...",
      "header_data": {"user_id": "456", "email": "cdc@example.com"}
    },
    "source": {
      "version": "1.0.0",
      "connector": "dsql",
      "name": "dsql-test",
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

1. **Check logs**:
   ```bash
   curl -X GET http://localhost:8083/connectors/dsql-cdc-connector/status
   docker-compose -f docker-compose.test.yml logs kafka-connect
   ```

2. **Verify configuration**:
   - Check DSQL endpoint is accessible
   - Verify IAM permissions
   - Ensure `event_headers` table exists

### No CDC Events

1. **Check connector status**:
   ```bash
   curl -X GET http://localhost:8083/connectors/dsql-cdc-connector/tasks/0/status
   ```

2. **Verify data insertion**:
   ```sql
   SELECT COUNT(*) FROM event_headers WHERE saved_date > NOW() - INTERVAL '5 minutes';
   ```

3. **Check Kafka topics**:
   ```bash
   docker exec $(docker-compose -f docker-compose.test.yml ps -q kafka) \
     kafka-topics --bootstrap-server localhost:9092 --list
   ```

### Connection Issues

1. **Test DSQL directly**:
   ```bash
   PGPASSWORD="$TOKEN" psql -h $DSQL_ENDPOINT -p 5432 -U $IAM_USER -d car_entities -c "SELECT 1;"
   ```

2. **Check VPC connectivity**:
   - Ensure EC2 is in correct VPC/subnet
   - Verify security groups allow outbound to port 5432

## Performance Testing

### High Volume Test

```bash
# Generate test data
PGPASSWORD="$TOKEN" psql -h $DSQL_ENDPOINT -p 5432 -U $IAM_USER -d car_entities << 'EOF'
DO $$
BEGIN
  FOR i IN 1..1000 LOOP
    INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data)
    VALUES (
      'perf-' || i,
      'perf.event',
      'CREATE',
      NOW(),
      NOW(),
      jsonb_build_object('index', i, 'timestamp', extract(epoch from now()))
    );
  END LOOP;
END $$;
EOF
```

### Monitor Performance

```bash
# Check connector metrics
curl -X GET http://localhost:8083/connectors/dsql-cdc-connector | jq '.tasks[0]'

# Monitor Kafka lag
docker exec $(docker-compose -f docker-compose.test.yml ps -q kafka) \
  kafka-consumer-groups --bootstrap-server localhost:9092 \
  --group dsql-connect-group \
  --describe
```

## Cleanup

```bash
# Stop test environment
docker-compose -f docker-compose.test.yml down -v

# Remove test files
rm -f docker-compose.test.yml init-test-db.sql dsql-connector-test.json test-config.json
```

## Success Criteria

✅ **Connector builds without errors**
✅ **Unit tests pass**
✅ **DSQL connection works**
✅ **Connector deploys to Kafka Connect**
✅ **CDC events appear in Kafka topics**
✅ **Event format matches Debezium standard**
✅ **Handles INSERT/UPDATE/DELETE operations**
✅ **Maintains offset tracking**
✅ **Recovers from failures**

## Next Steps

After successful testing:
1. **Deploy to production Kafka Connect**
2. **Configure monitoring and alerting**
3. **Set up schema registry**
4. **Test with real application data**
5. **Performance tuning and optimization**
