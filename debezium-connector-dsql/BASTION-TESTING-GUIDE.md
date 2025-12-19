# Testing DSQL Connector on Bastion Host

This guide explains how to run real DSQL connector tests on the bastion host.

## Prerequisites

✅ **Docker is installed** (completed via `install-docker-via-ssm.sh`)

## Bastion Information

- **Instance ID**: `i-0adcbf0f85849149e`
- **Public IP**: `44.198.171.47`
- **Region**: `us-east-1`
- **SSM Command**: `aws ssm start-session --target i-0adcbf0f85849149e --region us-east-1`

## Setup Steps

### 1. Connect to Bastion

```bash
aws ssm start-session --target i-0adcbf0f85849149e --region us-east-1
```

### 2. Install Java 11 (if not already installed)

```bash
sudo dnf install -y java-11-amazon-corretto
java -version
```

### 3. Create Project Directory

```bash
mkdir -p ~/debezium-connector-dsql/{lib,config,scripts}
cd ~/debezium-connector-dsql
```

### 4. Upload Connector JAR

**Option A: Via S3 (if bucket is configured)**
```bash
# From local machine
./scripts/upload-to-bastion.sh
```

**Option B: Manual upload via SCP**
```bash
# From local machine (if SSH key available)
scp -i ~/.ssh/key.pem build/libs/debezium-connector-dsql-1.0.0.jar \
    ec2-user@44.198.171.47:~/debezium-connector-dsql/lib/
```

**Option C: Build on bastion**
```bash
# On bastion
sudo dnf install -y git gradle
git clone <repo-url>
cd debezium-connector-dsql
./gradlew build
cp build/libs/debezium-connector-dsql-1.0.0.jar ~/debezium-connector-dsql/lib/
```

### 5. Set Up Environment Variables

Create `.env.dsql` file on bastion:

```bash
# On bastion
cd ~/debezium-connector-dsql
cat > .env.dsql <<'EOF'
export DSQL_ENDPOINT_PRIMARY="your-dsql-endpoint"
export DSQL_DATABASE_NAME="your-database"
export DSQL_REGION="us-east-1"
export DSQL_IAM_USERNAME="your-iam-user"
export DSQL_TABLES="table1,table2"
export DSQL_PORT="5432"
export DSQL_TOPIC_PREFIX="dsql-cdc"

# AWS credentials (or use IAM role)
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
EOF

chmod 600 .env.dsql
```

### 6. Upload Test Classes (if needed)

The test classes need to be on the bastion. Options:

**Option A: Build full test JAR**
```bash
# On local machine
./gradlew testJar  # If task exists, or
./gradlew jar testClasses
# Then upload test classes
```

**Option B: Clone repo on bastion and build**
```bash
# On bastion
git clone <repo-url>
cd debezium-connector-dsql
./gradlew build testClasses
```

## Running Tests

### Option 1: Using Gradle (if repo is cloned on bastion)

```bash
cd ~/debezium-connector-dsql
source .env.dsql
./gradlew testRealDsql
```

### Option 2: Using Java directly

```bash
cd ~/debezium-connector-dsql
source .env.dsql

# Set classpath (adjust paths as needed)
export CLASSPATH="lib/*:build/classes/java/test:build/classes/java/main"

# Run connection test
java io.debezium.connector.dsql.testutil.DsqlConnectionTester

# Run integration tests
java org.junit.platform.console.ConsoleLauncher \
    --class-path . \
    --select-tag real-dsql \
    --details verbose
```

### Option 3: Using the automated script

```bash
# From local machine
./scripts/run-tests-on-bastion.sh
```

## Verification Steps

1. **Test Docker** (already done):
   ```bash
   docker version
   docker run --rm hello-world
   ```

2. **Test Java**:
   ```bash
   java -version
   ```

3. **Test AWS credentials**:
   ```bash
   aws sts get-caller-identity
   ```

4. **Test DSQL connection**:
   ```bash
   source .env.dsql
   java -cp lib/* io.debezium.connector.dsql.testutil.DsqlConnectionTester
   ```

## Next Steps After Testing

1. **Deploy Kafka Connect container** (if needed):
   ```bash
   docker pull confluentinc/cp-kafka-connect:latest
   # Configure and run Kafka Connect with connector
   ```

2. **Run full integration tests**:
   - Test CDC pipeline end-to-end
   - Validate records in Kafka topics
   - Monitor connector metrics

3. **Production deployment**:
   - Deploy connector to production Kafka Connect cluster
   - Configure monitoring and alerting
   - Set up multi-region replication

## Troubleshooting

### Java not found
```bash
sudo dnf install -y java-11-amazon-corretto
export JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto
```

### Class not found errors
- Ensure all dependencies are in classpath
- Use fat JAR that includes all dependencies
- Or set up proper classpath with all JARs

### Connection errors
- Verify `.env.dsql` is sourced
- Check AWS credentials: `aws sts get-caller-identity`
- Test IAM token generation manually
- Verify security group allows outbound to DSQL

### Docker permission errors
```bash
# Reconnect to apply group changes
newgrp docker
# Or log out and back in
```

## Files on Bastion

After setup, bastion should have:
```
~/debezium-connector-dsql/
├── lib/
│   └── debezium-connector-dsql-1.0.0.jar
├── config/
│   └── (connector configs if needed)
├── scripts/
│   └── (helper scripts)
└── .env.dsql (environment variables)
```
