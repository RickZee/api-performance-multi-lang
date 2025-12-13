# DSQL Test Runner EC2 Instance

This document describes how to use the EC2 test runner instance for testing the DSQL Debezium connector from inside the VPC.

## Overview

The test runner is an EC2 instance deployed in a **private subnet** with:
- **SSM Session Manager access only** (no inbound ports)
- IAM permissions for DSQL database authentication
- Pre-installed tools: Java 17, PostgreSQL client, Git, AWS CLI

## Prerequisites

1. **Enable the test runner** in `terraform.tfvars`:
   ```hcl
   enable_dsql_test_runner_ec2 = true
   dsql_test_runner_instance_type = "t3.small"
   ```

2. **Deploy with Terraform**:
   ```bash
   cd terraform
   terraform apply
   ```

3. **Verify instance is ready** (wait 2-3 minutes for SSM agent to register):
   ```bash
   aws ssm describe-instance-information \
     --filters "Key=InstanceIds,Values=$(terraform output -raw dsql_test_runner_instance_id)" \
     --region us-east-1
   ```

## Connecting to the Test Runner

### Via SSM Session Manager

```bash
# Get instance ID
INSTANCE_ID=$(terraform output -raw dsql_test_runner_instance_id)

# Connect via SSM
aws ssm start-session --target $INSTANCE_ID --region us-east-1
```

Or use the convenience command from Terraform output:
```bash
terraform output -raw dsql_test_runner_ssm_command | bash
```

## Testing DSQL Connectivity

Once connected to the instance, test DSQL connectivity:

### 1. Get DSQL Endpoint

You can use either the VPC endpoint DNS or the DSQL host format:

```bash
# Option 1: VPC Endpoint DNS (recommended)
DSQL_ENDPOINT=$(cd terraform && terraform output -raw aurora_dsql_endpoint)
echo $DSQL_ENDPOINT
# Example: vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com

# Option 2: DSQL Host format (alternative)
DSQL_HOST=$(cd terraform && terraform output -raw aurora_dsql_host)
echo $DSQL_HOST
# Example: vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws
```

Both endpoints resolve to the same DSQL cluster. Use the VPC endpoint DNS (`aurora_dsql_endpoint`) for most cases.

### 2. Generate IAM Auth Token

On the EC2 instance:
```bash
# Get endpoint (you'll need to pass this from your local machine or hardcode it)
DSQL_ENDPOINT="vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com"
IAM_USER="lambda_dsql_user"
REGION="us-east-1"

# Generate token
TOKEN=$(aws rds generate-db-auth-token \
  --hostname $DSQL_ENDPOINT \
  --port 5432 \
  --username $IAM_USER \
  --region $REGION)

echo $TOKEN
```

### 3. Test Connection with psql

```bash
# Connect to DSQL
PGPASSWORD=$TOKEN psql \
  -h $DSQL_ENDPOINT \
  -p 5432 \
  -U $IAM_USER \
  -d car_entities \
  -c "SELECT version();"
```

## Running DSQL Connector Tests

### 1. Clone Repository on Test Runner

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

Create `test-config.properties`:
```properties
dsql.endpoint.primary=vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com
dsql.port=5432
dsql.region=us-east-1
dsql.iam.username=lambda_dsql_user
dsql.database.name=car_entities
dsql.tables=event_headers
dsql.poll.interval.ms=1000
dsql.batch.size=1000
topic.prefix=dsql-cdc
```

### 4. Run Integration Tests

Follow the test procedures in `debezium-connector-dsql/REAL_DSQL_TESTING.md`.

## Troubleshooting

### SSM Connection Fails

1. **Wait for SSM agent registration**: It can take 2-3 minutes after instance launch
2. **Check IAM role**: Verify the instance has `AmazonSSMManagedInstanceCore` policy
3. **Check VPC endpoints**: Ensure SSM endpoints are created and accessible

### DSQL Connection Fails

1. **Verify IAM permissions**: Check that the IAM role has `rds-db:connect` permission
2. **Check security groups**: Ensure EC2 SG allows outbound to port 5432
3. **Verify endpoint DNS**: The VPC endpoint DNS should resolve from within the VPC
4. **Check IAM database user**: Ensure `lambda_dsql_user` exists in the DSQL cluster

### Instance Not Appearing in SSM

```bash
# Check instance status
aws ec2 describe-instances \
  --instance-ids $(terraform output -raw dsql_test_runner_instance_id) \
  --region us-east-1 \
  --query 'Reservations[0].Instances[0].[State.Name,IamInstanceProfile.Arn]'
```

## Cost Considerations

- **Instance**: `t3.small` costs ~$0.0208/hour (~$15/month if running 24/7)
- **VPC Endpoints**: SSM endpoints cost ~$0.01/hour each (~$7/month for 3 endpoints)
- **Recommendation**: Stop the instance when not in use to save costs

### Stop Instance

```bash
INSTANCE_ID=$(terraform output -raw dsql_test_runner_instance_id)
aws ec2 stop-instances --instance-ids $INSTANCE_ID --region us-east-1
```

### Start Instance

```bash
INSTANCE_ID=$(terraform output -raw dsql_test_runner_instance_id)
aws ec2 start-instances --instance-ids $INSTANCE_ID --region us-east-1
# Wait 1-2 minutes for instance to be ready
```

## Cleanup

To remove the test runner:

1. **Update terraform.tfvars**:
   ```hcl
   enable_dsql_test_runner_ec2 = false
   ```

2. **Apply Terraform**:
   ```bash
   terraform apply
   ```

This will destroy the EC2 instance and SSM endpoints (if no other resources need them).

