# Execute DSQL Connector Test via SSM (Network Workaround)

Since the EC2 instance may not have direct internet access to GitHub, here's how to execute the test manually via SSM Session Manager.

## Prerequisites

1. **Connect to EC2 via SSM**:
   ```bash
   cd terraform
   terraform output -raw dsql_test_runner_ssm_command | bash
   ```

2. **On EC2, install prerequisites**:
   ```bash
   sudo dnf install -y git docker java-17-amazon-corretto-headless postgresql15 jq gettext
   sudo systemctl enable --now docker
   ```

## Option 1: Manual File Transfer

### Step 1: From Your Local Machine

Create a tarball of necessary files:
```bash
cd /Users/rickzakharov/dev/github/api-performance-multi-lang
tar -czf /tmp/dsql-test.tar.gz \
  terraform/confluent-option-a/ \
  debezium-connector-dsql/ \
  --exclude='**/build' \
  --exclude='**/.gradle'
```

### Step 2: Transfer to EC2

**Via SCP (if you have SSH access)**:
```bash
scp -i your-key.pem /tmp/dsql-test.tar.gz ec2-user@<ec2-ip>:/tmp/
```

**Via SSM (base64 encode)**:
```bash
# On local machine
base64 /tmp/dsql-test.tar.gz > /tmp/dsql-test.b64

# Copy content and paste into EC2 session:
# On EC2:
cat > /tmp/dsql-test.b64 << 'EOF'
<paste base64 content here>
EOF
base64 -d /tmp/dsql-test.b64 > /tmp/dsql-test.tar.gz
tar -xzf /tmp/dsql-test.tar.gz -C /tmp/
```

### Step 3: On EC2, Run Setup

```bash
cd /tmp
tar -xzf dsql-test.tar.gz

# Get DSQL endpoint from Terraform (if Terraform is accessible)
# Or set manually:
export DSQL_ENDPOINT_PRIMARY="vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com"
export DSQL_IAM_USERNAME="lambda_dsql_user"
export DSQL_DATABASE_NAME="car_entities"

# Create connect.env manually or use setup script
cd terraform/confluent-option-a
cat > connect.env << EOF
CC_BOOTSTRAP_SERVERS=<your-confluent-bootstrap>
CC_KAFKA_API_KEY=<your-key>
CC_KAFKA_API_SECRET=<your-secret>
DSQL_ENDPOINT_PRIMARY=$DSQL_ENDPOINT_PRIMARY
DSQL_IAM_USERNAME=$DSQL_IAM_USERNAME
DSQL_DATABASE_NAME=$DSQL_DATABASE_NAME
DSQL_TABLE=event_headers
TOPIC_PREFIX=dsql-cdc
ROUTED_TOPIC=raw-event-headers
CONNECTOR_NAME=dsql-cdc-source-event-headers
EOF

# Build connector
cd /tmp/debezium-connector-dsql
./gradlew clean jar --no-daemon

# Run E2E test
cd /tmp/terraform/confluent-option-a
./run-e2e.sh
```

## Option 2: Direct SSM Session (Recommended)

1. **Connect interactively**:
   ```bash
   cd terraform
   terraform output -raw dsql_test_runner_ssm_command | bash
   ```

2. **On EC2, follow the manual steps above** but you can copy-paste commands directly.

## Option 3: Use S3 as Intermediate Storage

If you have S3 access:

```bash
# From local machine
aws s3 cp /tmp/dsql-test.tar.gz s3://your-bucket/dsql-test.tar.gz

# On EC2 (via SSM)
aws s3 cp s3://your-bucket/dsql-test.tar.gz /tmp/dsql-test.tar.gz
tar -xzf /tmp/dsql-test.tar.gz -C /tmp/
```

## Troubleshooting Network Issues

If EC2 can't reach external services:

1. **Check IPv6 connectivity**:
   ```bash
   ping6 -c 3 2001:4860:4860::8888  # Google DNS
   ```

2. **Check if NAT Gateway is needed**:
   - Your VPC has IPv6 enabled but may need IPv4 NAT for some services
   - Enable in Terraform: `enable_nat_gateway = true`

3. **Use VPC endpoints**:
   - For S3: Already configured via VPC endpoints
   - For GitHub: Not available, use manual transfer

## Quick Test Without Full Setup

If you just want to test DSQL connectivity:

```bash
# On EC2
export DSQL_ENDPOINT="vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com"
export IAM_USER="lambda_dsql_user"
TOKEN=$(aws rds generate-db-auth-token --hostname $DSQL_ENDPOINT --port 5432 --username $IAM_USER --region us-east-1)
PGPASSWORD="$TOKEN" psql -h $DSQL_ENDPOINT -p 5432 -U $IAM_USER -d car_entities -c "SELECT COUNT(*) FROM event_headers;"
```

