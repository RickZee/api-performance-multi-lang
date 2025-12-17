# Bastion Host Setup Complete - Final Step Required

## ✅ Completed Steps

1. **Infrastructure Migration**
   - ✅ Terminated old test runner instance (`i-058cb2a0dc3fdcf3b`)
   - ✅ Removed test runner from Terraform
   - ✅ Updated bastion host with S3 and Confluent Cloud access
   - ✅ Bastion host instance: `i-0adcbf0f85849149e`

2. **Connector Build & Deployment**
   - ✅ Fixed Java 11 compatibility in test file
   - ✅ Built connector JAR (31.5 MB)
   - ✅ Uploaded JAR to S3: `s3://producer-api-lambda-deployments-978300727880/debezium-connector-dsql/`

3. **Kafka Connect Setup on Bastion Host**
   - ✅ Installed Docker, docker-compose, Java 11, jq
   - ✅ Downloaded connector JAR from S3
   - ✅ Created Docker Compose configuration
   - ✅ Created `connect.env` with Confluent Cloud credentials
   - ✅ Started Kafka Connect container
   - ✅ Connector plugin loaded successfully
   - ✅ Connector deployed and running

4. **Connector Status**
   - ✅ Connector State: **RUNNING**
   - ✅ Task State: **RUNNING**
   - ✅ Plugin: `io.debezium.connector.dsql.DsqlConnector` loaded

## ⚠️ Final Step Required: IAM Role Mapping

The connector is running but cannot connect to DSQL due to missing IAM role mapping. The bastion host's IAM role needs to be mapped to `dsql_iam_user` in DSQL.

### Required Action

Connect to DSQL as an admin user (from a machine with admin access) and run:

```sql
AWS IAM GRANT dsql_iam_user TO 'arn:aws:iam::978300727880:role/producer-api-bastion-role';
```

### How to Connect

You need to connect from a machine that already has admin access to DSQL. Options:

1. **From your local machine** (if you have DSQL admin access configured):
   ```bash
   # Generate IAM token for postgres user (if your local IAM role/user is mapped)
   TOKEN=$(aws rds generate-db-auth-token \
     --hostname vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws \
     --port 5432 \
     --region us-east-1 \
     --username postgres)
   
   export PGPASSWORD="$TOKEN"
   psql "postgresql://postgres@vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws:5432/postgres?sslmode=require"
   ```

2. **Via AWS Console/CLI** (if DSQL supports it)

3. **From the original setup machine** (if you have one with admin access)

### After Granting Access

Once the IAM role mapping is granted:

1. The connector will automatically retry (it polls every second)
2. Check connector logs:
   ```bash
   # On bastion host
   docker logs dsql-kafka-connect | grep -iE "connection|pool|hikari" | tail -20
   ```
3. Verify connection success - you should see:
   - `HikariCP connection pool created`
   - `Connected to DSQL`
   - No more "access denied" errors

## Testing End-to-End

After the IAM mapping is complete, test the full pipeline:

1. **Insert a test event into DSQL:**
   ```bash
   # On bastion host
   DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
   IAM_USER="dsql_iam_user"
   
   TOKEN=$(aws rds generate-db-auth-token \
     --hostname "$DSQL_HOST" \
     --port 5432 \
     --region us-east-1 \
     --username "$IAM_USER")
   
   export PGPASSWORD="$TOKEN"
   psql "postgresql://${IAM_USER}@${DSQL_HOST}:5432/postgres?sslmode=require" <<EOF
   INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data)
   VALUES (
     'test-' || extract(epoch from now())::text,
     'TestEvent',
     'TestEvent',
     NOW(),
     NOW(),
     '{"test": true, "timestamp": "' || NOW() || '"}'::jsonb
   );
   EOF
   ```

2. **Verify event in Confluent Cloud:**
   - Topic: `raw-event-headers`
   - Check via Confluent Cloud Console or CLI

## Current Configuration

- **Bastion Host**: `i-0adcbf0f85849149e`
- **DSQL Host**: `vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws`
- **IAM User**: `dsql_iam_user`
- **Bastion IAM Role**: `arn:aws:iam::978300727880:role/producer-api-bastion-role`
- **Connector Name**: `dsql-cdc-source-event-headers`
- **Output Topic**: `raw-event-headers`
- **Kafka Connect**: Running on port 8083

## Quick Commands

### Connect to Bastion Host
```bash
cd terraform
terraform output -raw bastion_host_ssm_command | bash
```

### Check Connector Status
```bash
# On bastion host
curl -s http://localhost:8083/connectors/dsql-cdc-source-event-headers/status | jq '.'
```

### View Connector Logs
```bash
# On bastion host
docker logs dsql-kafka-connect | tail -50
```

### Restart Connector
```bash
# On bastion host
curl -X POST http://localhost:8083/connectors/dsql-cdc-source-event-headers/restart
```
