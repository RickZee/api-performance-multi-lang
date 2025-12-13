# DSQL Test Runner Quick Start

Quick reference for using the EC2 test runner to test DSQL connectivity and the Debezium connector.

## Prerequisites

- Terraform infrastructure deployed with `enable_dsql_test_runner_ec2 = true`
- AWS CLI configured with appropriate credentials
- SSM Session Manager access (via IAM permissions)

## Get Connection Information

```bash
cd terraform

# Get instance ID
INSTANCE_ID=$(terraform output -raw dsql_test_runner_instance_id)
echo "Instance ID: $INSTANCE_ID"

# Get DSQL endpoints
DSQL_ENDPOINT=$(terraform output -raw aurora_dsql_endpoint)
DSQL_HOST=$(terraform output -raw aurora_dsql_host)
echo "DSQL Endpoint: $DSQL_ENDPOINT"
echo "DSQL Host: $DSQL_HOST"

# Get SSM connection command
terraform output -raw dsql_test_runner_ssm_command
```

## Connect to Test Runner

```bash
# Option 1: Use Terraform output command
terraform output -raw dsql_test_runner_ssm_command | bash

# Option 2: Manual connection
aws ssm start-session \
  --target $(terraform output -raw dsql_test_runner_instance_id) \
  --region us-east-1
```

**Note**: Wait 2-3 minutes after instance creation for SSM agent to register. Check status:
```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$(terraform output -raw dsql_test_runner_instance_id)" \
  --region us-east-1 \
  --query 'InstanceInformationList[0].PingStatus'
```

## Run Connectivity Test

Once connected to the instance, run the test script:

```bash
# On the EC2 instance (via SSM)
cd /tmp

# Copy test script (or create it manually)
cat > test-dsql.sh << 'SCRIPT'
# ... (script content from scripts/test-dsql-connectivity.sh)
SCRIPT

chmod +x test-dsql.sh
./test-dsql.sh
```

Or run commands manually:

```bash
# Set variables
export DSQL_ENDPOINT="vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com"
export IAM_USER="lambda_dsql_user"
export REGION="us-east-1"
export DB_NAME="car_entities"

# Generate token
TOKEN=$(aws rds generate-db-auth-token \
  --hostname $DSQL_ENDPOINT \
  --port 5432 \
  --username $IAM_USER \
  --region $REGION)

# Test connection
PGPASSWORD="$TOKEN" psql \
  -h $DSQL_ENDPOINT \
  -p 5432 \
  -U $IAM_USER \
  -d $DB_NAME \
  -c "SELECT version();"
```

## Test Debezium Connector

### 1. Clone Repository

```bash
cd /tmp
git clone <your-repo-url>
cd api-performance-multi-lang/debezium-connector-dsql
```

### 2. Build Connector

```bash
./gradlew build
```

### 3. Create Test Configuration

```bash
cat > test-connector-config.json << EOF
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
```

### 4. Run Integration Tests

Follow the test procedures in `debezium-connector-dsql/REAL_DSQL_TESTING.md`.

## Troubleshooting

### SSM Connection Fails

1. **Wait for SSM agent**: Can take 2-3 minutes after instance launch
2. **Check instance status**:
   ```bash
   aws ec2 describe-instance-status --instance-ids $INSTANCE_ID
   ```
3. **Verify IAM role**: Instance must have `AmazonSSMManagedInstanceCore` policy

### DSQL Connection Fails

1. **Check IAM permissions**: Verify `rds-db:connect` permission for the IAM user
2. **Verify endpoint**: Ensure you're using the correct VPC endpoint DNS
3. **Check security groups**: EC2 SG must allow outbound to port 5432
4. **Test DNS resolution**: 
   ```bash
   nslookup $DSQL_ENDPOINT
   ping -c 1 $DSQL_ENDPOINT
   ```

### Token Generation Fails

1. **Check AWS credentials**: `aws sts get-caller-identity`
2. **Verify IAM user exists**: Connect to DSQL and check:
   ```sql
   SELECT usename FROM pg_user WHERE usename = 'lambda_dsql_user';
   ```
3. **Check region**: Ensure region matches DSQL cluster region

## Next Steps

1. ✅ Infrastructure deployed
2. ✅ Test runner instance running
3. ⏭️ Connect via SSM and test DSQL connectivity
4. ⏭️ Run Debezium connector tests
5. ⏭️ Verify CDC functionality

For detailed testing procedures, see:
- `debezium-connector-dsql/REAL_DSQL_TESTING.md` - Comprehensive test suite
- `DSQL_TEST_RUNNER.md` - Full documentation

