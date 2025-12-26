# Complete AWS MSK + Managed Flink Setup Guide

This guide provides a comprehensive, step-by-step walkthrough for setting up the CDC streaming pipeline using AWS managed services (Amazon MSK Serverless + Managed Service for Apache Flink) as an alternative to Confluent Cloud.

> **Quick Links:**
>
> - For Docker-based local development, see [README.md](README.md)
> - For Confluent Cloud setup, see [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md)
> - For architecture details, see [ARCHITECTURE.md](ARCHITECTURE.md)

## Table of Contents

### Basic Setup (Required)

1. [Prerequisites](#prerequisites)
2. [Terraform Infrastructure Setup](#terraform-infrastructure-setup)
3. [MSK Serverless Cluster](#msk-serverless-cluster)
4. [MSK Connect with Debezium](#msk-connect-with-debezium)
5. [Managed Service for Apache Flink](#managed-service-for-apache-flink)
6. [Glue Schema Registry (Optional)](#glue-schema-registry-optional)
7. [Deploy Flink Application](#deploy-flink-application)
8. [Deploy MSK Consumers](#deploy-msk-consumers)
9. [Testing and Verification](#testing-and-verification)

## Prerequisites

### Required Accounts and Access

1. **AWS Account**
   - Access to AWS Console
   - IAM permissions for MSK, MSK Connect, Kinesis Analytics, Glue, S3, VPC
   - VPC in target region (us-east-1 recommended)

2. **PostgreSQL Database**
   - Aurora PostgreSQL or self-managed PostgreSQL
   - Database with entity tables (car_entities, loan_entities, etc.)
   - Logical replication enabled
   - Network access from MSK Connect workers

### Required Tools

```bash
# Install Terraform
brew install terraform
# Or: apt-get install terraform / yum install terraform

# Install AWS CLI
brew install awscli
# Or: pip install awscli

# Install Java 11 (REQUIRED - AWS Managed Flink 1.18 uses Java 11)
brew install openjdk@11
# Or: apt-get install openjdk-11-jdk
# Note: Java 17 will cause UnsupportedClassVersionError

# Install Gradle (for building Flink application)
brew install gradle
# Or: Use Gradle wrapper included in project
```

### Verify Installations

```bash
# Check Terraform
terraform version

# Check AWS CLI
aws --version

# Check Java
java -version

# Check Gradle
cd cdc-streaming/flink-msk && ./gradlew --version
```

## Terraform Infrastructure Setup

### Step 1: Configure Terraform Variables

Edit `terraform/terraform.tfvars`:

```hcl
# Enable MSK infrastructure
enable_msk = true

# MSK cluster name (optional, defaults to project_name-msk-cluster)
msk_cluster_name = "cdc-streaming-msk"

# Enable Glue Schema Registry (optional)
enable_glue_schema_registry = false

# Flink application JAR key in S3
flink_app_jar_key = "flink-app.jar"

# Ensure VPC is enabled (required for MSK)
enable_vpc = true

# Ensure Aurora is enabled (required for CDC source)
enable_aurora = true
```

### Step 2: Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply
```

Or use the deployment script:

```bash
cd cdc-streaming
./scripts/deploy-msk-infrastructure.sh
```

### Step 3: Get MSK Bootstrap Servers

After deployment, get the bootstrap servers:

```bash
cd terraform
terraform output msk_bootstrap_brokers
```

Save this value - you'll need it for Flink and consumers.

## MSK Serverless Cluster

The MSK Serverless cluster is automatically created by Terraform with:

- **IAM Authentication**: Enabled by default
- **VPC Configuration**: Deployed in private subnets
- **Security Groups**: Configured for Kafka ports (9092, 9094, 9098)

**Key Outputs:**

```bash
terraform output msk_cluster_arn
terraform output msk_cluster_name
terraform output msk_bootstrap_brokers
```

**Connection Details:**

- **Bootstrap Servers**: Use `msk_bootstrap_brokers` output (IAM auth endpoint, port 9098)
- **Security Protocol**: SASL_SSL
- **SASL Mechanism**: AWS_MSK_IAM
- **Authentication**: Uses IAM roles/users with MSK access policy

## MSK Connect with Debezium

### Prerequisites: Create MSK Topic

**Important**: Before starting the connector, create the `raw-event-headers` topic in MSK Serverless. MSK Serverless does not reliably auto-create topics when connectors write to them, so manual creation is required.

**Why this is needed:**

- MSK Serverless does not reliably auto-create topics when connectors write to them
- The connector will show `UNKNOWN_TOPIC_OR_PARTITION` errors until the topic exists
- Creating the topic manually ensures reliable operation

**Quick Start (Using Script):**

```bash
# From project root, use the provided script
./scripts/create-msk-topic-aws-cli.sh raw-event-headers 3
```

This script automatically:

- Gets MSK cluster information from Terraform
- Uses `kafka-topics.sh` with IAM authentication
- Creates the topic with the specified partitions
- Verifies the topic was created

**Alternative Methods:**

See [Step 3: Create MSK Topic](#step-3-create-msk-topic) below for:

- AWS Console method (easiest, no tools required)
- Manual `kafka-topics.sh` command (for advanced users)

### Step 1: Upload Debezium Plugin to S3

MSK Connect requires the Debezium PostgreSQL connector plugin to be uploaded to S3:

```bash
# Download Debezium PostgreSQL connector
curl -L -o debezium-connector-postgres.zip \
  https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.4.0.Final/debezium-connector-postgres-2.4.0.Final-plugin.tar.gz

# Get S3 bucket name from Terraform
S3_BUCKET=$(cd terraform && terraform output -raw msk_connect_s3_bucket_name)

# Upload to S3
aws s3 cp debezium-connector-postgres.zip \
  s3://$S3_BUCKET/debezium-connector-postgres.zip \
  --region us-east-1
```

### Step 2: Verify Connector Status

The connector is automatically created by Terraform. Check status:

```bash
# Get connector ARN
CONNECTOR_ARN=$(cd terraform && terraform output -raw msk_connect_connector_arn)

# Check connector status
aws kafkaconnect describe-connector \
  --connector-arn $CONNECTOR_ARN \
  --region us-east-1
```

**Expected Status**: `RUNNING`

### Step 3: Create MSK Topic

**Important**: The `raw-event-headers` topic must be created before the connector can write to it. MSK Serverless does not support automatic topic creation via the connector.

**Option 1: Create via AWS Console (Recommended)**

1. Navigate to AWS Console → MSK → Clusters
2. Select your cluster: `producer-api-msk-cluster`
3. Click on the "Topics" tab
4. Click "Create topic"
5. Enter:
   - **Topic name**: `raw-event-headers`
   - **Partitions**: `3`
   - Click "Create topic"

**Option 2: Wait for Auto-Creation (May Not Work)**

MSK Serverless topics are typically auto-created when first written to, but this may not work reliably. It's recommended to create the topic manually.

**Option 3: Use AWS CLI with Kafka Tools (Recommended for Automation)**

This method uses `kafka-topics.sh` with IAM authentication. It requires:

- AWS CLI configured with credentials
- Apache Kafka tools installed (`kafka-topics.sh`)
- IAM permissions for MSK access
- **Network access to MSK cluster** (must be run from within VPC or via VPN/bastion)

**Important Network Requirement:**
MSK Serverless clusters are only accessible from within the VPC. To use this method:

- Run from an EC2 instance in the same VPC as the MSK cluster
- Use AWS Systems Manager Session Manager to connect to an EC2 instance
- Use a VPN connection to the VPC
- Or use the AWS Console method (no network restrictions)

**Step 1: Install Kafka Tools**

```bash
# macOS
brew install kafka

# Ubuntu/Debian
sudo apt-get install kafka

# Or download from: https://kafka.apache.org/downloads
# Extract and add bin/ directory to PATH
```

**Step 2: Get Bootstrap Servers from Terraform**

```bash
cd terraform
BOOTSTRAP_SERVERS=$(terraform output -raw msk_bootstrap_brokers)
echo "Bootstrap servers: $BOOTSTRAP_SERVERS"
```

**Step 3: Create Topic Using Script**

Use the provided script (recommended):

```bash
# From project root
./scripts/create-msk-topic-aws-cli.sh raw-event-headers 3

# Or specify custom parameters
./scripts/create-msk-topic-aws-cli.sh <topic-name> <partitions> [terraform-dir]
```

**Step 4: Create Topic Manually (Alternative)**

If you prefer to create the topic manually using `kafka-topics.sh`:

```bash
# Get bootstrap servers
cd terraform
BOOTSTRAP_SERVERS=$(terraform output -raw msk_bootstrap_brokers)

# Create topic with IAM authentication
kafka-topics.sh \
  --create \
  --bootstrap-server "$BOOTSTRAP_SERVERS" \
  --topic raw-event-headers \
  --partitions 3 \
  --command-config <(cat <<EOF
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
EOF
)

# Verify topic creation
kafka-topics.sh \
  --list \
  --bootstrap-server "$BOOTSTRAP_SERVERS" \
  --command-config <(cat <<EOF
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
EOF
)
```

**Note**: The IAM authentication uses your AWS CLI credentials automatically. Ensure your AWS credentials are configured (`aws configure` or environment variables).

**Verify Topic Creation:**

```bash
# Check via AWS Console → MSK → Topics
# The topic should appear in the list after creation

# Verify connector can write (check logs - should no longer show UNKNOWN_TOPIC errors)
aws logs tail /aws/mskconnect/producer-api --since 5m | grep -i "unknown_topic"
# Should return no results if topic exists
```

**Quick Console Link:**

- Direct link to MSK Console: `https://console.aws.amazon.com/msk/home?region=us-east-1#/clusters`
- Select your cluster → Topics tab → Create topic

## Managed Service for Apache Flink

### Step 1: Build Flink Application

**Important**: The Flink application must be compiled with **Java 11** (not Java 17), as AWS Managed Flink 1.18 uses Java 11 runtime.

```bash
cd cdc-streaming/flink-msk

# Verify Java version (should be 11)
java -version

# If using Java 17, switch to Java 11:
# On macOS: brew install openjdk@11
# Then: export JAVA_HOME=$(/usr/libexec/java_home -v 11)

# Build the application JAR
./gradlew clean fatJar

# The JAR will be in: build/libs/flink-msk-event-routing-1.0.0-all.jar
```

**Note**: The `build.gradle` file is configured to use Java 11 (`sourceCompatibility = '11'`, `targetCompatibility = '11'`). The application includes a properties file (`application.properties`) with bootstrap servers as a fallback configuration.

### Step 2: Upload JAR to S3

```bash
# Use the deployment script
cd cdc-streaming
./scripts/deploy-msk-flink-app.sh
```

Or manually:

```bash
# Get S3 bucket name
S3_BUCKET=$(cd terraform && terraform output -raw flink_s3_bucket_name)

# Upload JAR
aws s3 cp cdc-streaming/flink-msk/build/libs/flink-msk-event-routing-1.0.0-all.jar \
  s3://$S3_BUCKET/flink-app.jar \
  --region us-east-1

# Verify upload
aws s3 ls s3://$S3_BUCKET/flink-app.jar
```

### Step 3: Update Flink Application with JAR

The Flink application is automatically created by Terraform. After uploading a new JAR, update the application:

```bash
# Get application name and current version
APP_NAME=$(cd terraform && terraform output -raw flink_application_name)
VERSION=$(aws kinesisanalyticsv2 describe-application --application-name $APP_NAME --query 'ApplicationDetail.ApplicationVersionId' --output text)

# Get S3 bucket and key
S3_BUCKET=$(cd terraform && terraform output -raw flink_s3_bucket_name)
JAR_KEY=$(cd terraform && terraform output -raw flink_app_jar_key)

# Wait for application to be READY (cannot update while STARTING or RUNNING)
echo "Waiting for application to be READY..."
while [ "$(aws kinesisanalyticsv2 describe-application --application-name $APP_NAME --query 'ApplicationDetail.ApplicationStatus' --output text)" != "READY" ]; do
  sleep 5
done

# Update application code
aws kinesisanalyticsv2 update-application \
  --application-name $APP_NAME \
  --current-application-version-id $VERSION \
  --application-configuration-update '{
    "ApplicationCodeConfigurationUpdate": {
      "CodeContentUpdate": {
        "S3ContentLocationUpdate": {
          "FileKeyUpdate": "'$JAR_KEY'"
        }
      }
    }
  }' \
  --region us-east-1
```

**Note**: The application must be in `READY` or `STOPPED` state to update. If it's `STARTING` or `RUNNING`, wait for it to finish or stop it first.

### Step 4: Configure Bootstrap Servers

The Flink application reads bootstrap servers from multiple sources (in priority order):

1. System property: `bootstrap.servers`
2. Environment variable: `BOOTSTRAP_SERVERS`
3. Command line argument
4. Properties file: `/application.properties` (included in JAR)
5. TableEnvironment configuration (from property groups)

**The application includes a properties file with bootstrap servers**, so no additional configuration is required. However, you can also set property groups for Flink SQL connectors:

```bash
# Update application with environment properties (optional - properties file is fallback)
BOOTSTRAP_SERVERS=$(cd terraform && terraform output -raw msk_bootstrap_brokers)
VERSION=$(aws kinesisanalyticsv2 describe-application --application-name $APP_NAME --query 'ApplicationDetail.ApplicationVersionId' --output text)

aws kinesisanalyticsv2 update-application \
  --application-name $APP_NAME \
  --current-application-version-id $VERSION \
  --application-configuration-update '{
    "EnvironmentPropertyUpdates": {
      "PropertyGroups": [
        {
          "PropertyGroupId": "kafka.source",
          "PropertyMap": {
            "bootstrap.servers": "'$BOOTSTRAP_SERVERS'",
            "security.protocol": "SASL_SSL",
            "sasl.mechanism": "AWS_MSK_IAM"
          }
        },
        {
          "PropertyGroupId": "kafka.sink",
          "PropertyMap": {
            "bootstrap.servers": "'$BOOTSTRAP_SERVERS'",
            "security.protocol": "SASL_SSL",
            "sasl.mechanism": "AWS_MSK_IAM"
          }
        }
      ]
    }
  }' \
  --region us-east-1
```

**Note**: The properties file (`cdc-streaming/flink-msk/src/main/resources/application.properties`) contains the bootstrap servers and is included in the JAR, so the application will work without additional configuration.

### Step 5: Start Flink Application

```bash
# Start the application
aws kinesisanalyticsv2 start-application \
  --application-name $APP_NAME \
  --run-configuration '{
    "ApplicationRestoreConfiguration": {
      "ApplicationRestoreType": "SKIP_RESTORE_FROM_SNAPSHOT"
    }
  }' \
  --region us-east-1

# Wait for application to start (can take 2-5 minutes)
echo "Waiting for application to start..."
while [ "$(aws kinesisanalyticsv2 describe-application --application-name $APP_NAME --query 'ApplicationDetail.ApplicationStatus' --output text)" = "STARTING" ]; do
  sleep 10
  echo "Status: $(aws kinesisanalyticsv2 describe-application --application-name $APP_NAME --query 'ApplicationDetail.ApplicationStatus' --output text)"
done

# Check final status
aws kinesisanalyticsv2 describe-application --application-name $APP_NAME --query 'ApplicationDetail.ApplicationStatus'
```

**Expected Status**: `RUNNING` (if successful) or `READY` (if there were errors - check logs)

### Step 6: Monitor Flink Application

```bash
# Check application status
aws kinesisanalyticsv2 describe-application \
  --application-name $APP_NAME \
  --region us-east-1

# View CloudWatch logs
LOG_GROUP=$(cd terraform && terraform output -raw flink_log_group_name)
aws logs tail $LOG_GROUP --follow --region us-east-1
```

## Glue Schema Registry (Optional)

If enabled, the Glue Schema Registry is automatically created by Terraform:

```bash
# Get registry ARN
REGISTRY_ARN=$(cd terraform && terraform output -raw glue_schema_registry_arn)

# List schemas
aws glue get-schemas \
  --registry-id Id=$REGISTRY_ARN \
  --region us-east-1
```

## Deploy Flink Application

The Flink application reads SQL statements from `business-events-routing-msk.sql` and executes them to:

1. Create source table: `raw-event-headers`
2. Create sink tables: `filtered-*-events-msk`
3. Deploy INSERT statements for filtering and routing

**Topics Created Automatically:**

- `filtered-loan-created-events-msk`
- `filtered-loan-payment-submitted-events-msk`
- `filtered-car-created-events-msk`
- `filtered-service-events-msk`

## Deploy MSK Consumers

### Step 1: Set Environment Variables

```bash
# Get bootstrap servers from Terraform
export KAFKA_BOOTSTRAP_SERVERS=$(cd terraform && terraform output -raw msk_bootstrap_brokers)
export AWS_REGION=us-east-1

# Set AWS credentials (for local testing)
# For production, use IAM roles
export AWS_ACCESS_KEY_ID="<your-access-key>"
export AWS_SECRET_ACCESS_KEY="<your-secret-key>"
```

### Step 2: Start Consumers

```bash
cd cdc-streaming

# Start all 4 consumers
docker-compose -f docker-compose.msk.yml up -d

# View logs
docker-compose -f docker-compose.msk.yml logs -f loan-consumer
docker-compose -f docker-compose.msk.yml logs -f loan-payment-consumer
docker-compose -f docker-compose.msk.yml logs -f car-consumer
docker-compose -f docker-compose.msk.yml logs -f service-consumer
```

## Testing and Verification

### Step 1: Verify Infrastructure Components

```bash
# 1. Check MSK Cluster
MSK_CLUSTER_ARN=$(cd terraform && terraform output -raw msk_cluster_arn)
aws kafka describe-cluster --cluster-arn $MSK_CLUSTER_ARN --query 'ClusterInfo.State'

# 2. Check MSK Connect Connector
CONNECTOR_ARN=$(cd terraform && terraform output -raw msk_connect_connector_arn)
aws kafkaconnect describe-connector \
  --connector-arn $CONNECTOR_ARN \
  --query 'connectorState' \
  --output text

# 3. Check Flink Application
APP_NAME=$(cd terraform && terraform output -raw flink_application_name)
aws kinesisanalyticsv2 describe-application \
  --application-name $APP_NAME \
  --query 'ApplicationDetail.ApplicationStatus' \
  --output text

# 4. Check Aurora PostgreSQL
aws rds describe-db-clusters \
  --db-cluster-identifier producer-api-aurora-cluster \
  --query 'DBClusters[0].Status' \
  --output text
```

**Expected Statuses:**

- MSK Cluster: `ACTIVE`
- MSK Connect Connector: `RUNNING`
- Flink Application: `RUNNING` (or `READY` if not started)
- Aurora PostgreSQL: `available`

### Step 2: Verify MSK Connect Connector

```bash
# Check connector status
CONNECTOR_ARN=$(cd terraform && terraform output -raw msk_connect_connector_arn)
aws kafkaconnect describe-connector \
  --connector-arn $CONNECTOR_ARN \
  --query '{Name: connectorName, State: connectorState}' \
  --output json

# Check connector logs for errors
aws logs tail /aws/mskconnect/producer-api --since 10m | grep -iE "(error|exception|unknown_topic)" | tail -20
```

**Expected**: `State: RUNNING`, no `UNKNOWN_TOPIC_OR_PARTITION` errors (after topic is created)

### Step 3: Verify Topics Have Messages

**Create the `raw-event-headers` topic first** (see MSK Connect section, Step 3):

```bash
# Verify topic exists via AWS Console
# MSK → Clusters → producer-api-msk-cluster → Topics
# Should see: raw-event-headers (3 partitions)

# Check connector can write (no more UNKNOWN_TOPIC errors in logs)
aws logs tail /aws/mskconnect/producer-api --since 5m | grep -i "unknown_topic"
# Should return no results if topic exists
```

**Note**: MSK Serverless doesn't support direct topic listing via AWS CLI. Use the AWS Console to verify topics and message counts.

### Step 4: Verify Flink Application

```bash
# Check application status
APP_NAME=$(cd terraform && terraform output -raw flink_application_name)
aws kinesisanalyticsv2 describe-application \
  --application-name $APP_NAME \
  --query 'ApplicationDetail.{Name: ApplicationName, Status: ApplicationStatus, Version: ApplicationVersionId}' \
  --output json

# Check application logs
aws logs tail /aws/kinesisanalytics/producer-api-flink-app --since 5m | grep -iE "(bootstrap|starting|executing sql|successfully|error)" | tail -20
```

**Expected**:

- Status: `RUNNING` (if successful) or `READY` (if errors occurred)
- Logs should show: "Found bootstrap servers from properties file" and "Successfully executed SQL statement"

### Step 5: Verify Consumers

```bash
# Check consumer logs
docker-compose -f docker-compose.msk.yml logs loan-consumer | tail -20
```

**Expected**: Consumers should be receiving and processing events.

## Key Differences from Confluent Cloud

| Aspect | Confluent Cloud | AWS MSK + Flink |
|--------|-----------------|-----------------|
| **Kafka** | Confluent Cloud | MSK Serverless |
| **Flink** | Confluent Cloud Flink (SQL statements) | Managed Service for Apache Flink (JAR) |
| **Schema Registry** | Confluent Schema Registry | AWS Glue Schema Registry |
| **CDC Connector** | Managed PostgresCdcSourceV2 | MSK Connect + Debezium |
| **Authentication** | API Keys (SASL_SSL/PLAIN) | IAM (SASL_SSL/AWS_MSK_IAM) |
| **Topic Suffix** | `-flink` | `-msk` |
| **Flink SQL Connector** | `'connector' = 'confluent'` | `'connector' = 'kafka'` |
| **Deployment** | SQL via CLI/Console | JAR upload to S3 |

## Troubleshooting

### MSK Connect Connector Not Running

```bash
# Check connector status
CONNECTOR_ARN=$(cd terraform && terraform output -raw msk_connect_connector_arn)
aws kafkaconnect describe-connector --connector-arn $CONNECTOR_ARN --query 'connectorState'

# Check connector logs
aws logs tail /aws/mskconnect/producer-api --follow --region us-east-1
```

**Common Issues:**

- **Connection failed**: Ensure Aurora PostgreSQL is running and accessible from MSK Connect workers
- **UNKNOWN_TOPIC_OR_PARTITION**: Create the `raw-event-headers` topic manually (see Step 3 above)
- **Invalid connector configuration**: Check that `topic.prefix` is set in connector configuration

### Flink Application Not Processing

**Check Application Status:**

```bash
APP_NAME=$(cd terraform && terraform output -raw flink_application_name)
aws kinesisanalyticsv2 describe-application --application-name $APP_NAME
```

**Check Application Logs:**

```bash
aws logs tail /aws/kinesisanalytics/producer-api-flink-app --follow --region us-east-1
```

**Common Issues:**

1. **Java Version Mismatch**
   - **Error**: `UnsupportedClassVersionError: class file version 61.0` (Java 17) vs `55.0` (Java 11)
   - **Fix**: Rebuild JAR with Java 11: `cd cdc-streaming/flink-msk && ./gradlew clean fatJar`

2. **Bootstrap Servers Not Found**
   - **Error**: `BOOTSTRAP_SERVERS environment variable is required`
   - **Fix**: The application should read from `application.properties` file. Verify the file exists in the JAR:

     ```bash
     jar -tf build/libs/flink-msk-event-routing-1.0.0-all.jar | grep application.properties
     ```

3. **SQL Parse Error**
   - **Error**: `Non-query expression encountered in illegal context`
   - **Fix**: Ensure SQL file doesn't have semicolons inside string literals (e.g., in JAAS config). The SQL file should use `'software.amazon.msk.auth.iam.IAMLoginModule required'` (no semicolon at end)

4. **Application Not Starting**
   - **Error**: Application stuck in `STARTING` state
   - **Fix**: Check CloudWatch logs for specific errors. Common causes:
     - Missing bootstrap servers
     - SQL syntax errors
     - Missing dependencies in JAR

**Update Application Code:**

```bash
# Get current version
VERSION=$(aws kinesisanalyticsv2 describe-application --application-name $APP_NAME --query 'ApplicationDetail.ApplicationVersionId' --output text)

# Update with new JAR (wait for application to be READY first)
aws kinesisanalyticsv2 update-application \
  --application-name $APP_NAME \
  --current-application-version-id $VERSION \
  --application-configuration-update '{
    "ApplicationCodeConfigurationUpdate": {
      "CodeContentUpdate": {
        "S3ContentLocationUpdate": {
          "FileKeyUpdate": "flink-app.jar"
        }
      }
    }
  }'
```

### Consumers Not Receiving Events

1. Verify bootstrap servers: `echo $KAFKA_BOOTSTRAP_SERVERS`
2. Verify AWS credentials: `aws sts get-caller-identity`
3. Check consumer logs: `docker-compose -f docker-compose.msk.yml logs`
4. Verify IAM permissions for MSK access
5. Verify topics exist and have messages (check via AWS Console)

## Next Steps

After completing setup:

1. **Monitor**: Set up CloudWatch alarms for MSK, Flink, and consumers
2. **Scale**: Adjust Flink parallelism and MSK Connect workers as needed
3. **Optimize**: Tune Flink checkpointing and MSK Connect batch settings
4. **Document**: Document your specific configuration and procedures

## Related Documentation

- [README.md](README.md): Main documentation with all deployment options
- [ARCHITECTURE.md](ARCHITECTURE.md): System architecture details
- [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md): Confluent Cloud alternative
