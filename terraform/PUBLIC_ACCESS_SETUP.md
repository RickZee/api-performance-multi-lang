# Public Internet Access Setup for RDS/Aurora with Confluent Cloud

This guide covers **Option 1: Public Internet Access** for connecting RDS/Aurora to Confluent Cloud using the **Postgres CDC Source V2 (Debezium)** connector.

**Connector Type**: This guide uses **Postgres CDC Source V2 (Debezium)**, which is Confluent Cloud's fully managed PostgreSQL CDC connector that uses Debezium under the hood for change data capture.

## When to Use Public Internet Access

- **Testing/Development**: Quick setup for development and testing
- **Public RDS**: When RDS instance is already publicly accessible
- **Temporary Setup**: Before implementing PrivateLink (Option 2)
- **Non-Production**: Environments where security requirements are less strict

**For Production**: Prefer AWS PrivateLink (Option 2) over public access for better security.

## Requirements

1. **RDS Instance**: Must have "Publicly accessible" enabled in AWS Console
2. **Security Group**: Must allow inbound TCP/5432 from Confluent Cloud IP ranges
3. **SSL/TLS**: Required for secure connections (use `sslmode=require`)

## Setup Steps

### Step 1: Enable Public Access in AWS RDS Console

1. Navigate to AWS RDS Console → Databases
2. Select your Aurora cluster
3. Click **Modify**
4. Under **Connectivity**, enable **Publicly accessible**
5. Click **Continue** → **Modify cluster**

**Note**: This change requires a maintenance window and may cause brief downtime.

### Step 2: Get Confluent Cloud Egress IP Ranges

Confluent Cloud uses specific egress IP ranges that must be allowed in your security group.

#### Method 1: Using Helper Script (Recommended)

```bash
cd terraform
./scripts/get-confluent-cloud-ips.sh us-east-1
```

This script will:
- Try to fetch IPs via Confluent CLI
- Provide manual lookup instructions
- Show example configuration format

#### Method 2: Using Confluent CLI

```bash
# Install Confluent CLI (if not installed)
brew install confluentinc/tap/cli
# Or: curl -sL --http1.1 https://cnfl.io/cli | sh -s -- latest

# Login to Confluent Cloud
confluent login

# List egress IPs for your region
confluent network egress-ip list --region us-east-1
```

#### Method 3: Check Documentation

1. Visit: https://docs.confluent.io/cloud/current/networking/ip-ranges.html
2. Find egress IP ranges for your region
3. Copy CIDR blocks

#### Method 4: Contact Confluent Support

1. Log in to https://confluent.cloud
2. Navigate to **Support** → **Create a ticket**
3. Request egress IP ranges for your region

### Step 3: Update Terraform Configuration

Edit `terraform/terraform.tfvars`:

```hcl
# Enable Aurora with public access
enable_aurora = true
aurora_publicly_accessible = true

# Restrict access to Confluent Cloud IP ranges (RECOMMENDED)
confluent_cloud_cidrs = [
  "13.57.0.0/16",  # Replace with actual Confluent Cloud egress IPs
  "52.0.0.0/16"    # Replace with actual Confluent Cloud egress IPs
]

# Aurora configuration
aurora_instance_class = "db.t3.medium"
database_name = "car_entities"
database_user = "postgres"
database_password = "your-secure-password"
```

**Important**: Replace example IPs with actual Confluent Cloud egress IP ranges from Step 2.

### Step 4: Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform (if first time)
terraform init

# Review changes
terraform plan

# Apply changes
terraform apply
```

### Step 5: Verify Security Group Configuration

1. Navigate to AWS Console → EC2 → Security Groups
2. Find security group: `{project-name}-aurora-sg`
3. Verify inbound rules:
   - **Type**: PostgreSQL (TCP/5432)
   - **Source**: Confluent Cloud CIDR blocks (if configured)
   - **Description**: "PostgreSQL access from Confluent Cloud (restricted)"

### Step 6: Update Connector Configuration

In your Confluent Cloud connector configuration, use the **Postgres CDC Source V2 (Debezium)** connector with the public endpoint:

#### Option A: Via Confluent Cloud Console

1. Navigate to: **Connectors** → **Add connector**
2. Select: **Postgres CDC Source V2 (Debezium)**
3. Configure with your Aurora public endpoint:
   - **Database hostname**: `your-aurora-endpoint.cluster-xxxxx.us-east-1.rds.amazonaws.com`
   - **Database port**: `5432`
   - **Database user**: `postgres`
   - **Database password**: `your-password`
   - **Database name**: `car_entities`
   - **Table include list**: `public.car_entities`
   - **Plugin name**: `pgoutput`
   - **Replication slot name**: `confluent_cdc_slot`
   - **Snapshot mode**: `initial`

#### Option B: Via Confluent CLI

```json
{
  "name": "postgres-cdc-source-confluent-cloud",
  "config": {
    "connector.class": "PostgresCdcSource",
    "name": "postgres-cdc-source-confluent-cloud",
    "kafka.auth.mode": "SASL_SSL",
    "kafka.api.key": "${KAFKA_API_KEY}",
    "kafka.api.secret": "${KAFKA_API_SECRET}",
    "output.data.format": "AVRO",
    "database.hostname": "your-aurora-endpoint.cluster-xxxxx.us-east-1.rds.amazonaws.com",
    "database.port": "5432",
    "database.user": "postgres",
    "database.password": "your-password",
    "database.dbname": "car_entities",
    "database.server.name": "postgres-cdc",
    "table.include.list": "public.car_entities",
    "plugin.name": "pgoutput",
    "slot.name": "confluent_cdc_slot",
    "snapshot.mode": "initial",
    "output.data.key.format": "AVRO",
    "output.data.value.format": "AVRO",
    "schema.registry.auth.mode": "BASIC",
    "schema.registry.api.key": "${SCHEMA_REGISTRY_API_KEY}",
    "schema.registry.api.secret": "${SCHEMA_REGISTRY_API_SECRET}",
    "schema.registry.url": "${SCHEMA_REGISTRY_URL}",
    "topic.prefix": "postgres-cdc",
    "tasks.max": "1"
  }
}
```

Deploy using:
```bash
confluent connect create \
  --plugin PostgresCdcSource \
  --config-file connector-config.json \
  --kafka-cluster <cluster-id>
```

**Important**: 
- Use the **Postgres CDC Source V2 (Debezium)** connector (Confluent Cloud managed)
- Use the **public endpoint** (not the private endpoint)
- Ensure SSL/TLS is enabled in connector configuration if supported

### Step 7: Test Connectivity

#### From Confluent Cloud

Test connectivity using Postgres CDC Source V2 (Debezium) connector:
1. Deploy connector via Confluent Cloud Console (select "Postgres CDC Source V2 (Debezium)") or CLI
2. Check connector status - should be `RUNNING`
3. Verify data is flowing to Kafka topics
4. Confirm connector is using Debezium: Check connector logs for Debezium-related messages

#### From Local Machine (Optional)

```bash
# Test PostgreSQL connection
PGPASSWORD="your-password" psql \
  -h your-aurora-endpoint.cluster-xxxxx.us-east-1.rds.amazonaws.com \
  -U postgres \
  -d car_entities \
  -c "SELECT version();"
```

**Note**: This test may fail if your local IP is not in the security group. That's expected - only Confluent Cloud IPs should have access.

## Security Considerations

### 1. IP Restriction

**Recommended**: Restrict security group to Confluent Cloud IP ranges only:

```hcl
confluent_cloud_cidrs = [
  "13.57.0.0/16",  # Confluent Cloud egress IPs
  "52.0.0.0/16"
]
```

**Not Recommended**: Allowing all IPs:

```hcl
confluent_cloud_cidrs = []  # Empty
aurora_allowed_cidr_blocks = ["0.0.0.0/0"]  # Allows all IPs
```

### 2. SSL/TLS Requirement

Always use SSL/TLS for database connections:
- Use `sslmode=require` in connection strings
- Configure connector to use SSL if supported
- Verify SSL certificates are valid

### 3. Strong Passwords

- Use strong, unique passwords for database users
- Rotate passwords regularly
- Store passwords in AWS Secrets Manager (not in code)

### 4. Regular IP Range Updates

Confluent Cloud IP ranges may change:
- Monitor Confluent Cloud documentation for updates
- Update `confluent_cloud_cidrs` in Terraform when IPs change
- Set up alerts for security group changes

### 5. Network Monitoring

- Enable CloudWatch logs for Aurora
- Monitor security group rules
- Set up alerts for unusual connection patterns

## Troubleshooting

### Issue: Connector Cannot Connect to Database

**Symptoms**:
- Connector status: `FAILED`
- Error: "Connection refused" or "Timeout"

**Solutions**:

1. **Verify Public Access**:
   ```bash
   # Check if Aurora is publicly accessible
   aws rds describe-db-clusters \
     --db-cluster-identifier your-cluster-name \
     --query 'DBClusters[0].PubliclyAccessible'
   ```
   Should return `true`

2. **Check Security Group Rules**:
   - Verify inbound rule allows TCP/5432 from Confluent Cloud IPs
   - Check that Confluent Cloud CIDRs are correct and up-to-date

3. **Verify Endpoint**:
   - Use public endpoint (not private endpoint)
   - Endpoint should be accessible from internet

4. **Test Connectivity**:
   ```bash
   # Test from a machine with Confluent Cloud IP (if possible)
   telnet your-aurora-endpoint.cluster-xxxxx.us-east-1.rds.amazonaws.com 5432
   ```

### Issue: Security Group Allows All IPs

**Symptoms**:
- Security group shows `0.0.0.0/0` as source
- You want to restrict to Confluent Cloud IPs only

**Solution**:

1. Get Confluent Cloud IP ranges (see Step 2)
2. Update `terraform.tfvars`:
   ```hcl
   confluent_cloud_cidrs = [
     "13.57.0.0/16",  # Actual Confluent Cloud IPs
     "52.0.0.0/16"
   ]
   ```
3. Apply changes:
   ```bash
   terraform plan
   terraform apply
   ```

### Issue: IP Ranges Changed

**Symptoms**:
- Connector was working but stopped
- Confluent Cloud updated their egress IP ranges

**Solution**:

1. Get updated IP ranges (see Step 2)
2. Update `confluent_cloud_cidrs` in `terraform.tfvars`
3. Apply changes:
   ```bash
   terraform apply
   ```

### Issue: Terraform Validation Errors

**Symptoms**:
- `terraform plan` fails with CIDR validation error

**Solution**:

1. Verify CIDR format: `X.X.X.X/XX` (e.g., `13.57.0.0/16`)
2. Check for typos in IP addresses
3. Use helper script to validate:
   ```bash
   ./scripts/get-confluent-cloud-ips.sh us-east-1 13.57.0.0/16 52.0.0.0/16
   ```

## Testing Connectivity

### Test 1: Verify Security Group Rules

```bash
# Get security group ID
SG_ID=$(terraform output -raw aurora_security_group_id)

# Check inbound rules
aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --query 'SecurityGroups[0].IpPermissions'
```

### Test 2: Verify Public Endpoint

```bash
# Get Aurora endpoint
ENDPOINT=$(terraform output -raw aurora_endpoint)

# Check if endpoint is publicly accessible
aws rds describe-db-clusters \
  --db-cluster-identifier your-cluster-name \
  --query 'DBClusters[0].PubliclyAccessible'
```

### Test 3: Test Connector Deployment

```bash
# Deploy connector using Postgres CDC Source V2 (Debezium)
cd cdc-streaming/scripts
./deploy-confluent-postgres-cdc-connector.sh

# Check connector status
confluent connector describe postgres-cdc-source-confluent-cloud

# Verify connector is using Postgres CDC Source V2 (Debezium)
confluent connector describe postgres-cdc-source-confluent-cloud \
  --output json | jq '.connector_class'
# Should show: "PostgresCdcSource" (which is the Postgres CDC Source V2 - Debezium connector)

# Check connector logs for Debezium confirmation
confluent connector logs postgres-cdc-source-confluent-cloud | grep -i debezium
```

## Next Steps

After setting up public internet access:

1. **Monitor**: Set up CloudWatch alarms for connection failures
2. **Document**: Document your IP ranges and update process
3. **Plan Migration**: Consider migrating to PrivateLink for production
4. **Review Security**: Regularly review security group rules

## Alternative: AWS PrivateLink (Recommended for Production)

For production environments, consider using **AWS PrivateLink** instead:

- **Better Security**: No public internet exposure
- **Lower Latency**: Direct VPC connection
- **More Reliable**: No dependency on public IP ranges

See: `cdc-streaming/CONFLUENT_CLOUD_SETUP_GUIDE.md` for PrivateLink setup.

## References

- [Confluent Cloud IP Ranges Documentation](https://docs.confluent.io/cloud/current/networking/ip-ranges.html)
- [AWS RDS Public Access](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.WorkingWithRDSInstanceinaVPC.html#USER_VPC.PubliclyAccessible)
- [Confluent Cloud Networking Guide](https://docs.confluent.io/cloud/current/networking/index.html)
- [Terraform AWS RDS Module](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster)

## Support

For issues or questions:

1. Check troubleshooting section above
2. Review Terraform outputs: `terraform output connection_instructions`
3. Check Confluent Cloud connector logs
4. Contact Confluent support for IP range updates
