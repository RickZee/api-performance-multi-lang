# Complete AWS MSK + Managed Flink Setup Guide

This guide provides a comprehensive, step-by-step walkthrough for setting up the CDC streaming pipeline using AWS managed services (Amazon MSK Serverless + Managed Service for Apache Flink) as an alternative to Confluent Cloud.

> **Quick Links:**
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

# Install Java (for building Flink application)
brew install openjdk@17
# Or: apt-get install openjdk-17-jdk

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

### Step 3: Verify Topics Created

The connector automatically creates the `raw-event-headers` topic:

```bash
# List topics (requires AWS CLI with MSK access)
aws kafka list-clusters --region us-east-1
```

## Managed Service for Apache Flink

### Step 1: Build Flink Application

```bash
cd cdc-streaming/flink-msk

# Build the application JAR
./gradlew clean fatJar

# The JAR will be in: build/libs/flink-msk-event-routing-1.0.0-all.jar
```

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
```

### Step 3: Configure Flink Application

The Flink application is automatically created by Terraform. Update it with the JAR location:

```bash
# Get application name
APP_NAME=$(cd terraform && terraform output -raw flink_application_name)

# Get S3 bucket and key
S3_BUCKET=$(cd terraform && terraform output -raw flink_s3_bucket_name)
JAR_KEY=$(cd terraform && terraform output -raw flink_app_jar_key)

# Get bootstrap servers
BOOTSTRAP_SERVERS=$(cd terraform && terraform output -raw msk_bootstrap_brokers)

# Update application code
aws kinesisanalyticsv2 update-application \
  --application-name $APP_NAME \
  --application-code-configuration '{
    "CodeContent": {
      "S3ContentLocation": {
        "BucketARN": "arn:aws:s3:::'$S3_BUCKET'",
        "FileKey": "'$JAR_KEY'"
      }
    },
    "CodeContentType": "ZIPFILE"
  }' \
  --region us-east-1
```

### Step 4: Set Environment Variables

The Flink application needs the bootstrap servers as an environment variable:

```bash
# Update application with environment properties
aws kinesisanalyticsv2 update-application \
  --application-name $APP_NAME \
  --application-configuration '{
    "EnvironmentProperties": {
      "PropertyGroups": [
        {
          "PropertyGroupId": "kafka.source",
          "PropertyMap": {
            "bootstrap.servers": "'$BOOTSTRAP_SERVERS'"
          }
        },
        {
          "PropertyGroupId": "kafka.sink",
          "PropertyMap": {
            "bootstrap.servers": "'$BOOTSTRAP_SERVERS'"
          }
        }
      ]
    }
  }' \
  --region us-east-1
```

### Step 5: Start Flink Application

```bash
# Start the application
aws kinesisanalyticsv2 start-application \
  --application-name $APP_NAME \
  --run-configuration '{
    "ApplicationRestoreConfiguration": {
      "ApplicationRestoreType": "RESTORE_FROM_LATEST_SNAPSHOT"
    }
  }' \
  --region us-east-1
```

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
docker-compose -f docker-compose.msk.yml logs -f loan-consumer-msk
docker-compose -f docker-compose.msk.yml logs -f loan-payment-consumer-msk
docker-compose -f docker-compose.msk.yml logs -f car-consumer-msk
docker-compose -f docker-compose.msk.yml logs -f service-consumer-msk
```

## Testing and Verification

### Step 1: Verify MSK Connect Connector

```bash
# Check connector status
CONNECTOR_ARN=$(cd terraform && terraform output -raw msk_connect_connector_arn)
aws kafkaconnect describe-connector \
  --connector-arn $CONNECTOR_ARN \
  --region us-east-1 | jq '.connectorState'
```

**Expected**: `RUNNING`

### Step 2: Verify Topics Have Messages

```bash
# Check topic exists and has messages
# Note: Requires Kafka client tools or AWS SDK
# Use AWS Console → MSK → Topics to verify
```

### Step 3: Verify Flink Application

```bash
# Check application status
APP_NAME=$(cd terraform && terraform output -raw flink_application_name)
aws kinesisanalyticsv2 describe-application \
  --application-name $APP_NAME \
  --region us-east-1 | jq '.ApplicationStatus'
```

**Expected**: `RUNNING`

### Step 4: Verify Consumers

```bash
# Check consumer logs
docker-compose -f docker-compose.msk.yml logs loan-consumer-msk | tail -20
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
# Check connector logs
LOG_GROUP=$(cd terraform && terraform output -raw msk_connect_log_group_name)
aws logs tail $LOG_GROUP --follow --region us-east-1
```

### Flink Application Not Processing

1. Check application logs in CloudWatch
2. Verify bootstrap servers are correct
3. Verify IAM permissions for MSK access
4. Check application status: `aws kinesisanalyticsv2 describe-application`

### Consumers Not Receiving Events

1. Verify bootstrap servers: `echo $KAFKA_BOOTSTRAP_SERVERS`
2. Verify AWS credentials: `aws sts get-caller-identity`
3. Check consumer logs: `docker-compose -f docker-compose.msk.yml logs`
4. Verify IAM permissions for MSK access

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
