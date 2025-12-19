# Testing with Real DSQL

This guide explains how to test the DSQL Debezium connector against a real Amazon Aurora DSQL cluster.

## Prerequisites

1. **Amazon Aurora DSQL Cluster**
   - DSQL cluster must be running and accessible
   - IAM authentication must be enabled
   - Network access configured (security groups, VPC, etc.)

2. **AWS Credentials**
   - AWS credentials configured via one of:
     - Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
     - `~/.aws/credentials` file
     - IAM role (if running on EC2/ECS/EKS)
   - IAM user/role must have `rds-db:connect` permission

3. **IAM Database User**
   - IAM database user created in DSQL
   - User granted access to the database
   - Resource ARN format: `arn:aws:rds-db:REGION:ACCOUNT_ID:dbuser:CLUSTER_RESOURCE_ID/USERNAME`

4. **Java 11+** and **Gradle** (for running tests)

## Configuration Setup

### Step 1: Create Environment File

Copy the example environment file:

```bash
cd debezium-connector-dsql
cp .env.dsql.example .env.dsql
```

### Step 2: Edit Configuration

Edit `.env.dsql` and fill in your DSQL cluster details:

```bash
# Required
export DSQL_ENDPOINT_PRIMARY="dsql-primary.cluster-xyz.us-east-1.rds.amazonaws.com"
export DSQL_DATABASE_NAME="mortgage_db"
export DSQL_REGION="us-east-1"
export DSQL_IAM_USERNAME="admin"
export DSQL_TABLES="event_headers,business_events"

# Optional
export DSQL_ENDPOINT_SECONDARY="dsql-secondary.cluster-xyz.us-west-2.rds.amazonaws.com"
export DSQL_PORT="5432"
export DSQL_TOPIC_PREFIX="dsql-cdc"
```

### Step 3: Configure AWS Credentials

Choose one of these methods:

#### Option 1: Environment Variables (in .env.dsql)

```bash
export AWS_ACCESS_KEY_ID="YOUR_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="YOUR_SECRET_KEY"
```

#### Option 2: AWS Credentials File (Recommended)

Create `~/.aws/credentials`:

```ini
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
```

Or use a specific profile:

```bash
export AWS_PROFILE="your-profile-name"
```

#### Option 3: IAM Role

If running on EC2/ECS/EKS, the connector will automatically use the IAM role.

### Step 4: Source the Environment File

```bash
source .env.dsql
```

Or use the test script which sources it automatically:

```bash
./scripts/test-real-dsql.sh
```

## Running Tests

### Connection Validation

Before running full tests, validate your connection:

```bash
./scripts/validate-dsql-connection.sh
```

This script will:
- Check environment variables
- Test IAM token generation
- Test database connection
- Validate table schemas

### Running Integration Tests

#### Method 1: Using the Test Script (Recommended)

```bash
./scripts/test-real-dsql.sh
```

This script:
- Sources `.env.dsql` automatically
- Validates environment variables
- Checks AWS credentials
- Runs connection validation
- Executes all tests tagged with `real-dsql`

#### Method 2: Using Gradle Directly

```bash
source .env.dsql
./gradlew testRealDsql
```

#### Method 3: Running Specific Tests

```bash
source .env.dsql
./gradlew testRealDsql --tests "RealDsqlConnectorIT.testConnectionToRealDsql"
```

### Test Tags

All real DSQL tests are tagged with `real-dsql`. This allows you to:

- Run only real DSQL tests: `./gradlew testRealDsql`
- Exclude real DSQL tests: `./gradlew test --exclude-tag real-dsql`
- Run all tests: `./gradlew test` (real DSQL tests will be skipped if env vars not set)

## Test Coverage

The real DSQL integration tests include:

1. **Connection Tests**
   - `testConnectionToRealDsql()` - Basic database connection
   - `testIamAuthentication()` - IAM token generation and authentication

2. **Schema Tests**
   - `testSchemaDiscovery()` - Schema building from real database
   - Validates primary keys, required columns (saved_date), etc.

3. **CDC Tests**
   - `testBasicPolling()` - Polling for changes
   - `testOffsetPersistence()` - Offset storage and recovery

4. **Configuration Tests**
   - `testMultiTableConfiguration()` - Multiple table support
   - `testConnectorStartup()` - Connector initialization

## Troubleshooting

### Issue: "Missing required environment variables"

**Solution**: Ensure you've created `.env.dsql` and sourced it, or set environment variables manually.

```bash
# Check if variables are set
echo $DSQL_ENDPOINT_PRIMARY
echo $DSQL_DATABASE_NAME

# Source the file
source .env.dsql
```

### Issue: "AWS credentials not available"

**Solution**: Configure AWS credentials using one of the methods above.

```bash
# Check credentials
aws sts get-caller-identity

# Or verify environment variables
echo $AWS_ACCESS_KEY_ID
```

### Issue: "IAM token generation failed"

**Possible causes**:
- IAM user doesn't have `rds-db:connect` permission
- Wrong cluster resource ID in IAM policy
- IAM user not created in DSQL

**Solution**: Verify IAM permissions and database user setup.

### Issue: "Connection timeout"

**Possible causes**:
- Security group doesn't allow connections from your IP
- VPC configuration issues
- Wrong endpoint hostname

**Solution**: 
- Check security group rules
- Verify endpoint hostname
- Test connection from same network/VPC

### Issue: "Table does not exist" or "Missing required column"

**Solution**: Ensure tables exist and have:
- Primary key
- `saved_date` column (TIMESTAMP WITH TIME ZONE)
- Optional: `updated_date` and `deleted_date` columns

### Issue: Tests are skipped

**Solution**: Tests are skipped if:
- Required environment variables are not set
- AWS credentials are not available

Check that you've sourced `.env.dsql` and configured AWS credentials.

## Security Best Practices

1. **Never commit `.env.dsql`**
   - The file is gitignored
   - Contains sensitive connection information
   - Review `.gitignore` to ensure it's excluded

2. **Use IAM Roles When Possible**
   - Prefer IAM roles over access keys
   - Use least privilege principle
   - Rotate credentials regularly

3. **Isolate Test Data**
   - Tests create tables with `test_cdc_` prefix
   - Test data is cleaned up after tests
   - Use separate test database if possible

4. **IAM Permissions**
   - Grant only `rds-db:connect` permission
   - Use resource ARNs to limit access
   - Review IAM policies regularly

## IAM Policy Example

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "rds-db:connect",
      "Resource": "arn:aws:rds-db:us-east-1:123456789012:dbuser:cluster-ABC123XYZ/admin"
    }
  ]
}
```

Replace:
- `us-east-1` with your region
- `123456789012` with your AWS account ID
- `cluster-ABC123XYZ` with your cluster resource ID
- `admin` with your IAM database username

## Test Execution Strategy

1. **Unit Tests**: Run without DSQL (no changes needed)
   ```bash
   ./gradlew test --exclude-tag real-dsql
   ```

2. **Testcontainers Tests**: Run with Docker (when available)
   ```bash
   ./gradlew test --exclude-tag real-dsql
   ```

3. **Real DSQL Tests**: Run selectively when DSQL is configured
   ```bash
   ./scripts/test-real-dsql.sh
   ```

## Continuous Integration

For CI/CD pipelines:

1. Set environment variables in CI configuration
2. Configure AWS credentials via CI secrets
3. Run tests: `./gradlew testRealDsql`
4. Tests will be skipped gracefully if variables are not set

Example GitHub Actions:

```yaml
- name: Run Real DSQL Tests
  env:
    DSQL_ENDPOINT_PRIMARY: ${{ secrets.DSQL_ENDPOINT_PRIMARY }}
    DSQL_DATABASE_NAME: ${{ secrets.DSQL_DATABASE_NAME }}
    DSQL_REGION: ${{ secrets.DSQL_REGION }}
    DSQL_IAM_USERNAME: ${{ secrets.DSQL_IAM_USERNAME }}
    DSQL_TABLES: ${{ secrets.DSQL_TABLES }}
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  run: ./gradlew testRealDsql
```

## Additional Resources

- [AWS Aurora DSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html)
- [IAM Database Authentication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)
- [Debezium Connector Documentation](../README.md)
