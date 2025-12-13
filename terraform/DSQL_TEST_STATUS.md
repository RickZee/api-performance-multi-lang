# DSQL Test Runner Status

## ✅ Infrastructure Deployed

- **EC2 Test Runner Instance**: `i-058cb2a0dc3fdcf3b` (running)
- **Private IP**: `10.0.11.48`
- **SSM Agent**: Online and ready
- **SSM VPC Endpoints**: All 3 endpoints created (ssm, ssmmessages, ec2messages)
- **DSQL Endpoints**:
  - VPC Endpoint DNS: `vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com`
  - DSQL Host: `vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws`

## ✅ Verified Working

1. **SSM Connectivity**: ✓ Instance is accessible via SSM Session Manager
2. **IAM Token Generation**: ✓ Successfully generates DSQL authentication tokens
   - Token length: 1815 characters
   - Token generation works correctly

## ⏳ In Progress

**Tool Installation**: PostgreSQL client, Java, and Git are being installed on the instance. This can take 5-10 minutes.

## 🔧 Manual Steps Required

Since automated tool installation via SSM commands is taking longer than expected, you can complete the setup manually:

### Option 1: Connect via SSM and Install Tools

```bash
# Connect to the instance
aws ssm start-session --target i-058cb2a0dc3fdcf3b --region us-east-1

# Once connected, install tools
sudo dnf install -y java-17-amazon-corretto-headless postgresql15 git

# Verify installation
java -version
psql --version
git --version
```

### Option 2: Run Test Script Manually

Once tools are installed, run the connectivity test:

```bash
# On the EC2 instance (via SSM)
cd /tmp

# Set environment variables
export DSQL_ENDPOINT="vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com"
export IAM_USER="lambda_dsql_user"
export AWS_REGION="us-east-1"
export DB_NAME="car_entities"

# Generate token
TOKEN=$(aws rds generate-db-auth-token \
  --hostname $DSQL_ENDPOINT \
  --port 5432 \
  --username $IAM_USER \
  --region $AWS_REGION)

# Test connection
PGPASSWORD="$TOKEN" psql \
  -h $DSQL_ENDPOINT \
  -p 5432 \
  -U $IAM_USER \
  -d $DB_NAME \
  -c "SELECT version();"
```

## 📋 Next Steps

1. **Wait for tool installation to complete** (or install manually via SSM)
2. **Test DSQL connectivity** using the script above
3. **Clone the repository** on the EC2 instance:
   ```bash
   cd /tmp
   git clone <your-repo-url>
   cd api-performance-multi-lang/debezium-connector-dsql
   ```
4. **Build and test the Debezium connector**:
   ```bash
   ./gradlew build
   # Follow test procedures in REAL_DSQL_TESTING.md
   ```

## 📝 Connection Information

**SSM Connection Command**:
```bash
aws ssm start-session --target i-058cb2a0dc3fdcf3b --region us-east-1
```

**Or use Terraform output**:
```bash
cd terraform
terraform output -raw dsql_test_runner_ssm_command | bash
```

## 🎯 Test Results Summary

| Component | Status | Notes |
|-----------|--------|-------|
| Infrastructure | ✅ Complete | All resources deployed |
| SSM Connectivity | ✅ Working | Instance accessible |
| IAM Token Generation | ✅ Working | Tokens generated successfully |
| Tool Installation | ⏳ In Progress | PostgreSQL, Java, Git installing |
| DSQL Connection | ⏸️ Pending | Waiting for psql client |
| Debezium Connector | ⏸️ Pending | Requires tools + repo clone |

## 📚 Documentation

- **Full Guide**: `DSQL_TEST_RUNNER.md`
- **Quick Start**: `DSQL_TEST_RUNNER_QUICKSTART.md`
- **Test Script**: `scripts/test-dsql-connectivity.sh`
- **Connector Tests**: `../debezium-connector-dsql/REAL_DSQL_TESTING.md`

