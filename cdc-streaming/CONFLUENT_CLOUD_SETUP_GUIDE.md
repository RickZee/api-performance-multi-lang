# Complete Confluent Cloud Setup Guide

This guide provides a comprehensive, step-by-step walkthrough for setting up the CDC streaming pipeline in Confluent Cloud from scratch. It covers all steps from account creation to full pipeline deployment.

> **Quick Links:**
> - For Docker-based local development, see [README.md](README.md)
> - For advanced multi-region setup, see [Multi-Region Infrastructure Setup](#multi-region-infrastructure-setup) in this guide
> - For architecture details, see [ARCHITECTURE.md](ARCHITECTURE.md)

## Table of Contents

### Basic Setup (Required)
1. [Prerequisites](#prerequisites)
2. [Account Setup](#account-setup)
3. [Environment and Cluster Setup](#environment-and-cluster-setup)
4. [Topic Creation](#topic-creation)
5. [Schema Registry Configuration](#schema-registry-configuration)
6. [Flink Compute Pool Setup](#flink-compute-pool-setup)
7. [Connector Setup](#connector-setup)
8. [Flink SQL Configuration](#flink-sql-configuration)
9. [Deploy Flink SQL Statements](#deploy-flink-sql-statements)
10. [Testing and Verification](#testing-and-verification)
11. [Troubleshooting](#troubleshooting)

### Advanced Topics (Optional)
12. [Multi-Region Infrastructure Setup](#multi-region-infrastructure-setup)
13. [AWS PrivateLink Connectivity](#aws-privatelink-connectivity)
14. [Multi-Region Cluster Linking](#multi-region-cluster-linking)
15. [Multi-Region Flink Deployment](#multi-region-flink-deployment)
16. [Advanced CI/CD Integration](#advanced-cicd-integration)
17. [Enterprise Features and Best Practices](#enterprise-features-and-best-practices)

## Prerequisites

### Required Accounts and Access

1. **Confluent Cloud Account**
   - Sign up at https://confluent.cloud
   - Choose appropriate billing plan (Basic, Standard, or Enterprise)
   - For production: Enterprise plan recommended for advanced features

2. **AWS Account** (if using AWS)
   - Access to AWS Console
   - VPC in target region (us-east-1 recommended to start)
   - IAM permissions for PrivateLink (if using private networking)

3. **PostgreSQL Database**
   - Aurora PostgreSQL or self-managed PostgreSQL
   - Database with entity tables (car_entities, loan_entities, etc.)
   - Logical replication enabled
   - Network access from Confluent Cloud (or via PrivateLink)

### Required Tools

```bash
# Install Confluent CLI
brew install confluentinc/tap/cli
# Or for Linux:
curl -sL --http1.1 https://cnfl.io/cli | sh -s -- latest

# Install jq for JSON processing
brew install jq
# Or: apt-get install jq / yum install jq

# Install Terraform (optional, for IaC)
brew install terraform
```

### Verify Installations

```bash
# Check Confluent CLI
confluent version

# Check jq
jq --version

# Check Terraform (if installed)
terraform version
```

## Account Setup

### Step 1: Create Confluent Cloud Account

1. Go to https://confluent.cloud
2. Click "Sign Up" or "Start Free"
3. Enter your email and create password
4. Verify email address
5. Complete organization setup

### Step 2: Enable Stream Governance

Stream Governance includes Schema Registry and is required for this setup:

1. Navigate to: **Environments** → **Add Environment**
2. Select **Stream Governance** package:
   - **ESSENTIALS**: Basic schema management (recommended for start)
   - **ADVANCED**: Multi-region schema replication (for production)
3. Complete environment creation

**Via CLI:**

```bash
# Login to Confluent Cloud
confluent login

# Create environment with Stream Governance
confluent environment create prod \
  --stream-governance ESSENTIALS
```

### Step 3: Generate API Keys

You'll need API keys for:
- Confluent Cloud API (for Terraform/automation)
- Kafka Cluster API (for applications)
- Schema Registry API (for schema operations)
- Flink API (for Flink operations)

**Generate Cloud API Key (for Terraform/CLI):**

```bash
# Via Console:
# Navigate to: API Keys → Create Key → Cloud API Key
# Download and save securely

# Via CLI:
confluent api-key create --resource cloud \
  --description "Cloud API key for automation"
# Save the key and secret - you'll need them!
```

**Store API Keys Securely:**

```bash
# Option 1: Environment variables
export CONFLUENT_CLOUD_API_KEY="<your-key>"
export CONFLUENT_CLOUD_API_SECRET="<your-secret>"

# Option 2: Confluent CLI (stores in ~/.confluent/config.json)
confluent login --save

# Option 3: Secrets Manager (recommended for production)
# AWS Secrets Manager, HashiCorp Vault, etc.
```

## Environment and Cluster Setup

### Step 1: Create Environment (if not done)

```bash
# List existing environments
confluent environment list

# Create new environment
confluent environment create prod \
  --stream-governance ESSENTIALS

# Set as current environment
confluent environment use <env-id>
```

### Step 2: Create Kafka Cluster

**Choose Cluster Type:**

- **Basic**: For development/testing (limited features)
- **Standard**: For production (recommended)
- **Dedicated**: For high-throughput production (enterprise)

**Create Dedicated Cluster:**

```bash
# Create cluster
confluent kafka cluster create prod-kafka-east \
  --cloud aws \
  --region us-east-1 \
  --type dedicated \
  --cku 2

# Note the cluster ID from output (e.g., lkc-abc123)
# Set as current cluster
confluent kafka cluster use <cluster-id>
```

**Get Cluster Information:**

```bash
# Get bootstrap servers
confluent kafka cluster describe <cluster-id> \
  --output json | jq -r '.endpoint'

# Example output: pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
```

### Step 3: Generate Cluster API Keys

```bash
# Create API key for cluster access
confluent api-key create \
  --resource <cluster-id> \
  --description "Kafka cluster API key"

# Save the key and secret - needed for:
# - Flink SQL statements
# - Connector configuration
# - Consumer applications
```

**Store Cluster Credentials:**

```bash
# Export for use in scripts
export KAFKA_BOOTSTRAP_SERVERS="pkc-xxxxx.us-east-1.aws.confluent.cloud:9092"
export KAFKA_API_KEY="<api-key>"
export KAFKA_API_SECRET="<api-secret>"
```

## Topic Creation

### Step 1: Create Required Topics

```bash
# Set cluster context
confluent kafka cluster use <cluster-id>

# Create topics
confluent kafka topic create raw-business-events \
  --partitions 6 \
  --config retention.ms=604800000

confluent kafka topic create filtered-loan-events \
  --partitions 6

confluent kafka topic create filtered-service-events \
  --partitions 6

confluent kafka topic create filtered-car-events \
  --partitions 6

confluent kafka topic create filtered-high-value-loans \
  --partitions 6
```

### Step 2: Verify Topics

```bash
# List all topics
confluent kafka topic list

# Describe topic
confluent kafka topic describe raw-business-events

# Check topic configuration
confluent kafka topic describe raw-business-events \
  --output json | jq '.config'
```

### Step 3: Configure Topic Settings (Optional)

```bash
# Set retention policy
confluent kafka topic update raw-business-events \
  --config retention.ms=604800000  # 7 days

# Set compression
confluent kafka topic update raw-business-events \
  --config compression.type=snappy

# Set min.insync.replicas for durability
confluent kafka topic update raw-business-events \
  --config min.insync.replicas=2
```

## Schema Registry Configuration

### Step 1: Get Schema Registry Endpoint

Schema Registry is automatically enabled with Stream Governance:

```bash
# Get Schema Registry endpoint
confluent schema-registry cluster describe \
  --output json | jq -r '.endpoint'

# Example: https://psrc-xxxxx.us-east-1.aws.confluent.cloud
```

### Step 2: Generate Schema Registry API Keys

```bash
# Create API key for Schema Registry
confluent api-key create \
  --resource <schema-registry-cluster-id> \
  --description "Schema Registry API key"

# Save key and secret
export SCHEMA_REGISTRY_URL="https://psrc-xxxxx.us-east-1.aws.confluent.cloud"
export SCHEMA_REGISTRY_API_KEY="<api-key>"
export SCHEMA_REGISTRY_API_SECRET="<api-secret>"
```

### Step 3: Register Schemas

**Option A: Via REST API**

```bash
# Register raw event schema
curl -X POST \
  "${SCHEMA_REGISTRY_URL}/subjects/raw-business-events-value/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -u "${SCHEMA_REGISTRY_API_KEY}:${SCHEMA_REGISTRY_API_SECRET}" \
  -d @- << EOF
{
  "schema": "$(cat schemas/raw-event.avsc | jq -c . | jq -R .)"
}
EOF

# Register filtered event schema
curl -X POST \
  "${SCHEMA_REGISTRY_URL}/subjects/filtered-loan-events-value/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -u "${SCHEMA_REGISTRY_API_KEY}:${SCHEMA_REGISTRY_API_SECRET}" \
  -d @- << EOF
{
  "schema": "$(cat schemas/filtered-event.avsc | jq -c . | jq -R .)"
}
EOF
```

**Option B: Via Confluent CLI**

```bash
# Register schema
confluent schema-registry schema create \
  --subject raw-business-events-value \
  --schema schemas/raw-event.avsc \
  --type AVRO
```

### Step 4: Set Compatibility Mode

```bash
# Set backward compatibility (allows adding fields)
confluent schema-registry subject update-config \
  raw-business-events-value \
  --compatibility BACKWARD
```

## Flink Compute Pool Setup

### Step 1: Create Compute Pool

```bash
# Create compute pool
confluent flink compute-pool create prod-flink-east \
  --cloud aws \
  --region us-east-1 \
  --max-cfu 4

# Note the compute pool ID (e.g., cp-abc123)
# Set as current compute pool
confluent flink compute-pool use <compute-pool-id>
```

**CFU Sizing Guidelines:**
- **2-4 CFU**: Development/testing, up to 50K events/sec
- **4-8 CFU**: Production, 50K-200K events/sec
- **8-16 CFU**: High-throughput, 200K+ events/sec

### Step 2: Create Service Account for Flink

```bash
# Create service account
confluent iam service-account create flink-sa \
  --description "Service account for Flink compute pool"

# Note the service account ID (e.g., sa-abc123)
```

### Step 3: Assign FlinkDeveloper Role

```bash
# Get environment resource name
ENV_RESOURCE_NAME=$(confluent environment describe <env-id> --output json | jq -r '.resource_name')

# Assign role
confluent iam rbac role-binding create \
  --principal User:<service-account-id> \
  --role FlinkDeveloper \
  --resource-name $ENV_RESOURCE_NAME
```

### Step 4: Generate Flink API Key

```bash
# Create API key for Flink compute pool
confluent api-key create \
  --resource <compute-pool-id> \
  --service-account <service-account-id> \
  --description "Flink compute pool API key"

# Save key and secret
export FLINK_API_KEY="<api-key>"
export FLINK_API_SECRET="<api-secret>"
```

### Step 5: Get Flink REST Endpoint

```bash
# Get Flink REST endpoint
confluent flink compute-pool describe <compute-pool-id> \
  --output json | jq -r '.rest_endpoint'

# Example: https://flink.us-east-1.aws.confluent.cloud
```

## Connector Setup

### Step 1: Prepare Connector Configuration

Update `connectors/postgres-source-connector.json` for Confluent Cloud:

```json
{
  "name": "postgres-source-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "<aurora-endpoint>",
    "database.port": "5432",
    "database.user": "<postgres-user>",
    "database.password": "<postgres-password>",
    "database.dbname": "<database-name>",
    "database.server.name": "postgres-source",
    "topic.prefix": "raw-business-events",
    "table.include.list": "public.car_entities,public.loan_entities,public.service_record_entities",
    "plugin.name": "pgoutput",
    "tasks.max": "1",
    
    "key.converter": "io.confluent.connect.avro.AvroConverter",
    "key.converter.schema.registry.url": "https://psrc-xxxxx.us-east-1.aws.confluent.cloud",
    "key.converter.schema.registry.basic.auth.credentials.source": "USER_INFO",
    "key.converter.schema.registry.basic.auth.user.info": "<schema-registry-api-key>:<schema-registry-api-secret>",
    
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "https://psrc-xxxxx.us-east-1.aws.confluent.cloud",
    "value.converter.schema.registry.basic.auth.credentials.source": "USER_INFO",
    "value.converter.schema.registry.basic.auth.user.info": "<schema-registry-api-key>:<schema-registry-api-secret>",
    
    "kafka.bootstrap.servers": "pkc-xxxxx.us-east-1.aws.confluent.cloud:9092",
    "kafka.security.protocol": "SASL_SSL",
    "kafka.sasl.mechanism": "PLAIN",
    "kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"<kafka-api-key>\" password=\"<kafka-api-secret>\";"
  }
}
```

### Step 2: Deploy Connector

**Option A: Using Confluent Cloud Managed Connectors**

```bash
# Create connector
confluent connector create postgres-source \
  --kafka-cluster <cluster-id> \
  --config-file connectors/postgres-source-connector.json
```

**Option B: Using Self-Hosted Connect Cluster**

```bash
# Create connector cluster (if needed)
confluent connect cluster create connect-cluster-east \
  --cloud aws \
  --region us-east-1 \
  --kafka-cluster <cluster-id>

# Create connector
confluent connector create postgres-source \
  --connect-cluster <connect-cluster-id> \
  --config-file connectors/postgres-source-connector.json
```

### Step 3: Verify Connector Status

```bash
# Check connector status
confluent connector describe postgres-source-connector

# View connector logs
confluent connector logs postgres-source-connector

# Check connector health
confluent connector health-check postgres-source-connector
```

## Flink SQL Configuration

### Step 1: Update SQL for Confluent Cloud

The generated SQL from `generate-flink-sql.py` needs to be updated with Confluent Cloud endpoints.

**Create Confluent Cloud SQL Configuration:**

```bash
# Generate SQL from filters
python scripts/generate-flink-sql.py \
  --config flink-jobs/filters.yaml \
  --output flink-jobs/routing-confluent-cloud.sql \
  --kafka-bootstrap "${KAFKA_BOOTSTRAP_SERVERS}" \
  --schema-registry "${SCHEMA_REGISTRY_URL}"
```

**Manual Update Required:**

Update the generated SQL file to include Confluent Cloud authentication:

```sql
-- Source table with Confluent Cloud configuration
CREATE TABLE raw_business_events (
    `eventHeader` ROW<...>,
    `eventBody` ROW<...>,
    `sourceMetadata` ROW<...>,
    `proctime` AS PROCTIME(),
    `eventtime` AS TO_TIMESTAMP_LTZ(`eventHeader`.`createdDate`, 3),
    WATERMARK FOR `eventtime` AS `eventtime` - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'raw-business-events',
    'properties.bootstrap.servers' = 'pkc-xxxxx.us-east-1.aws.confluent.cloud:9092',
    'properties.security.protocol' = 'SASL_SSL',
    'properties.sasl.mechanism' = 'PLAIN',
    'properties.sasl.jaas.config' = 'org.apache.kafka.common.security.plain.PlainLoginModule required username="<kafka-api-key>" password="<kafka-api-secret>";',
    'properties.group.id' = 'flink-routing-job',
    'format' = 'avro',
    'avro.schema-registry.url' = 'https://psrc-xxxxx.us-east-1.aws.confluent.cloud',
    'avro.schema-registry.basic-auth.credentials-source' = 'USER_INFO',
    'avro.schema-registry.basic-auth.user-info' = '<schema-registry-api-key>:<schema-registry-api-secret>',
    'scan.startup.mode' = 'earliest-offset'
);

-- Sink tables with same configuration
CREATE TABLE filtered_loan_events (
    ...
) WITH (
    'connector' = 'kafka',
    'topic' = 'filtered-loan-events',
    'properties.bootstrap.servers' = 'pkc-xxxxx.us-east-1.aws.confluent.cloud:9092',
    'properties.security.protocol' = 'SASL_SSL',
    'properties.sasl.mechanism' = 'PLAIN',
    'properties.sasl.jaas.config' = 'org.apache.kafka.common.security.plain.PlainLoginModule required username="<kafka-api-key>" password="<kafka-api-secret>";',
    'format' = 'avro',
    'avro.schema-registry.url' = 'https://psrc-xxxxx.us-east-1.aws.confluent.cloud',
    'avro.schema-registry.basic-auth.credentials-source' = 'USER_INFO',
    'avro.schema-registry.basic-auth.user-info' = '<schema-registry-api-key>:<schema-registry-api-secret>',
    'sink.partitioner' = 'fixed'
);
```

**Use the Preparation Script (Recommended):**

A helper script is provided to automate SQL preparation:

```bash
# Set environment variables
export KAFKA_BOOTSTRAP_SERVERS="pkc-xxxxx.us-east-1.aws.confluent.cloud:9092"
export SCHEMA_REGISTRY_URL="https://psrc-xxxxx.us-east-1.aws.confluent.cloud"
export KAFKA_API_KEY="<your-kafka-api-key>"
export KAFKA_API_SECRET="<your-kafka-api-secret>"
export SCHEMA_REGISTRY_API_KEY="<your-schema-registry-api-key>"
export SCHEMA_REGISTRY_API_SECRET="<your-schema-registry-api-secret>"

# Run preparation script
./scripts/prepare-sql-for-confluent-cloud.sh
```

The script will:
1. Generate SQL from `filters.yaml`
2. Inject Confluent Cloud endpoints
3. Add authentication properties
4. Validate the generated SQL
5. Output: `flink-jobs/routing-confluent-cloud.sql`

**Manual Configuration (Alternative):**

If you prefer manual configuration, update the generated SQL file with Confluent Cloud authentication as shown in the examples above.

### Step 2: Validate SQL Syntax

```bash
# Validate SQL file
python scripts/validate-sql.py \
  --sql flink-jobs/routing-confluent-cloud.sql
```

## Deploy Flink SQL Statements

### Step 1: Deploy Statement

```bash
# Deploy SQL statement
confluent flink statement create \
  --compute-pool <compute-pool-id> \
  --statement-name event-routing-job \
  --statement-file flink-jobs/routing-confluent-cloud.sql
```

### Step 2: Verify Deployment

```bash
# List statements
confluent flink statement list --compute-pool <compute-pool-id>

# Describe statement
confluent flink statement describe <statement-id> \
  --compute-pool <compute-pool-id>

# Check statement status
confluent flink statement describe <statement-id> \
  --compute-pool <compute-pool-id> \
  --output json | jq '.status'
```

### Step 3: Monitor Statement

```bash
# View statement logs
confluent flink statement logs <statement-id> \
  --compute-pool <compute-pool-id>

# View statement metrics
confluent flink statement describe <statement-id> \
  --compute-pool <compute-pool-id> \
  --output json | jq '.metrics'
```

**Via Confluent Cloud Console:**
- Navigate to: **Flink** → **Statements**
- View statement status, metrics, and logs
- Monitor throughput, latency, and backpressure

## Testing and Verification

### Step 1: Verify Connector is Running

```bash
# Check connector status
confluent connector describe postgres-source-connector \
  --output json | jq '.status'

# Should show: {"state": "RUNNING", "tasks": [...]}
```

### Step 2: Verify Topics Have Messages

```bash
# Check raw topic
confluent kafka topic describe raw-business-events \
  --output json | jq '.partitions[].offset'

# Consume sample messages
confluent kafka topic consume raw-business-events \
  --max-messages 10 \
  --from-beginning
```

### Step 3: Verify Flink Statement is Processing

```bash
# Check statement metrics
confluent flink statement describe <statement-id> \
  --compute-pool <compute-pool-id> \
  --output json | jq '.metrics'

# Look for:
# - numRecordsInPerSecond > 0
# - numRecordsOutPerSecond > 0
# - status: RUNNING
```

### Step 4: Verify Filtered Topics

```bash
# Check filtered topics have messages
for topic in filtered-loan-events filtered-service-events filtered-car-events; do
  echo "Checking $topic:"
  confluent kafka topic describe "$topic" \
    --output json | jq '.partitions[].offset'
done

# Consume from filtered topics
confluent kafka topic consume filtered-loan-events \
  --max-messages 5
```

### Step 5: End-to-End Test

**Generate Test Data:**

```bash
# Use your producer API to create test events
# Events should appear in raw-business-events topic
# Then be filtered and appear in filtered topics
```

**Verify Complete Flow:**

```bash
# 1. Check raw topic has new messages
confluent kafka topic consume raw-business-events \
  --max-messages 1 \
  --offset latest

# 2. Wait a few seconds for Flink processing

# 3. Check filtered topics have new messages
confluent kafka topic consume filtered-loan-events \
  --max-messages 1 \
  --offset latest
```

## Troubleshooting

### Common Issues

#### Issue 1: Cannot Connect to Kafka

**Symptoms:**
- Flink statement fails to start
- Connector cannot connect
- Consumer applications timeout

**Solutions:**

```bash
# Verify bootstrap servers
confluent kafka cluster describe <cluster-id> \
  --output json | jq -r '.endpoint'

# Verify API keys are correct
confluent api-key list

# Test connectivity
kafka-console-producer \
  --bootstrap-server <bootstrap-servers> \
  --topic test-topic \
  --producer-property security.protocol=SASL_SSL \
  --producer-property sasl.mechanism=PLAIN \
  --producer-property sasl.jaas.config='org.apache.kafka.common.security.plain.PlainLoginModule required username="<key>" password="<secret>";'
```

#### Issue 2: Schema Registry Authentication Errors

**Symptoms:**
- Flink statement fails with schema registry errors
- Connector cannot register schemas

**Solutions:**

```bash
# Verify Schema Registry endpoint
confluent schema-registry cluster describe

# Verify API keys
confluent api-key list --resource <schema-registry-cluster-id>

# Test Schema Registry access
curl -u "<api-key>:<api-secret>" \
  "${SCHEMA_REGISTRY_URL}/subjects"
```

#### Issue 3: Flink Statement Not Processing

**Symptoms:**
- Statement status is RUNNING but no output
- numRecordsInPerSecond is 0

**Solutions:**

```bash
# Check statement logs for errors
confluent flink statement logs <statement-id> \
  --compute-pool <compute-pool-id>

# Verify topics exist
confluent kafka topic list

# Check statement configuration
confluent flink statement describe <statement-id> \
  --compute-pool <compute-pool-id> \
  --output json | jq '.statement'

# Verify bootstrap servers in SQL match cluster endpoint
```

#### Issue 4: Connector Not Capturing Changes

**Symptoms:**
- Connector is RUNNING but no messages in raw-business-events
- PostgreSQL changes not appearing in Kafka

**Solutions:**

```bash
# Check connector status
confluent connector describe postgres-source-connector

# View connector logs
confluent connector logs postgres-source-connector

# Verify PostgreSQL connectivity
# Test from connector cluster location

# Check replication slot
psql -h <postgres-host> -U <user> -d <database> \
  -c "SELECT * FROM pg_replication_slots WHERE slot_name = 'debezium_slot';"

# Verify tables are included
# Check table.include.list in connector config
```

#### Issue 5: High Consumer Lag

**Symptoms:**
- Consumers falling behind
- Lag increasing over time

**Solutions:**

```bash
# Check consumer group lag
confluent kafka consumer-group describe <consumer-group-name> \
  --output json | jq '.lag'

# Check Flink statement throughput
confluent flink statement describe <statement-id> \
  --compute-pool <compute-pool-id> \
  --output json | jq '.metrics.numRecordsOutPerSecond'

# Increase compute pool CFU if needed
confluent flink compute-pool update <compute-pool-id> \
  --max-cfu 8
```

### Getting Help

**Confluent Cloud Support:**
- Console: https://confluent.cloud → Support
- Documentation: https://docs.confluent.io/cloud/current/
- Community: https://forum.confluent.io/

**Logs and Diagnostics:**

```bash
# Export all relevant information for support
confluent environment describe <env-id> > diagnostics.txt
confluent kafka cluster describe <cluster-id> >> diagnostics.txt
confluent flink compute-pool describe <compute-pool-id> >> diagnostics.txt
confluent flink statement describe <statement-id> --compute-pool <compute-pool-id> >> diagnostics.txt
```

## Quick Reference

### Essential Commands

```bash
# Login
confluent login

# Set context
confluent environment use <env-id>
confluent kafka cluster use <cluster-id>
confluent flink compute-pool use <compute-pool-id>

# List resources
confluent environment list
confluent kafka cluster list
confluent flink compute-pool list
confluent kafka topic list
confluent connector list
confluent flink statement list --compute-pool <pool-id>

# Describe resources
confluent kafka cluster describe <cluster-id>
confluent kafka topic describe <topic-name>
confluent connector describe <connector-name>
confluent flink statement describe <statement-id> --compute-pool <pool-id>
```

### Key Endpoints to Save

After setup, save these values:

```bash
# Environment
export CONFLUENT_ENV_ID="env-xxxxx"

# Kafka Cluster
export KAFKA_CLUSTER_ID="lkc-xxxxx"
export KAFKA_BOOTSTRAP_SERVERS="pkc-xxxxx.us-east-1.aws.confluent.cloud:9092"

# Schema Registry
export SCHEMA_REGISTRY_URL="https://psrc-xxxxx.us-east-1.aws.confluent.cloud"

# Flink
export FLINK_COMPUTE_POOL_ID="cp-xxxxx"
export FLINK_REST_ENDPOINT="https://flink.us-east-1.aws.confluent.cloud"

# API Keys (store securely!)
export KAFKA_API_KEY="<key>"
export KAFKA_API_SECRET="<secret>"
export SCHEMA_REGISTRY_API_KEY="<key>"
export SCHEMA_REGISTRY_API_SECRET="<secret>"
export FLINK_API_KEY="<key>"
export FLINK_API_SECRET="<secret>"
```

## Next Steps

After completing basic setup:

1. **Configure Monitoring**: Set up alerts in Confluent Cloud Console
2. **Set Up Multi-Region** (Optional): See [Multi-Region Infrastructure Setup](#multi-region-infrastructure-setup) below
3. **Implement CI/CD** (Optional): See [Advanced CI/CD Integration](#advanced-cicd-integration) below
4. **Performance Tuning**: See [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md)
5. **Disaster Recovery**: See [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md)

## Related Documentation

- [README.md](README.md): Main documentation with Docker and Confluent Cloud options
- [CODE_GENERATION.md](CODE_GENERATION.md): Filter configuration and SQL generation
- [ARCHITECTURE.md](ARCHITECTURE.md): System architecture details
- [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md): Performance optimization
- [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md): Disaster recovery procedures

## Summary

This guide covers the complete setup process for Confluent Cloud:

1. ✅ Account creation and authentication
2. ✅ Environment and cluster setup
3. ✅ Topic creation
4. ✅ Schema Registry configuration
5. ✅ Flink compute pool setup
6. ✅ Connector deployment
7. ✅ Flink SQL configuration and deployment
8. ✅ Testing and verification
9. ✅ Troubleshooting common issues

After completing this guide, your CDC streaming pipeline will be fully operational in Confluent Cloud with:
- Real-time CDC from PostgreSQL
- Automatic event filtering via Flink SQL
- Consumer-specific topic routing
- Full monitoring and observability

---

## Advanced Topics

The following sections cover advanced configurations for multi-region deployments, private networking, and enterprise CI/CD integration. These are **optional** and can be implemented after completing the basic setup above.

## Multi-Region Infrastructure Setup

### Step 1: Create Secondary Region Cluster

After completing basic setup in us-east-1, create a second cluster in us-west-2:

```bash
# Create second Kafka cluster
confluent kafka cluster create prod-kafka-west \
  --cloud aws \
  --region us-west-2 \
  --type dedicated \
  --cku 2

# Create Flink compute pool in secondary region
confluent flink compute-pool create prod-flink-west \
  --cloud aws \
  --region us-west-2 \
  --max-cfu 4
```

**Terraform Multi-Region Module:**

```hcl
# terraform/confluent/modules/region/main.tf
variable "region" {
  description = "AWS region"
  type        = string
}

variable "env_id" {
  description = "Confluent environment ID"
  type        = string
}

resource "confluent_kafka_cluster" "cluster" {
  display_name = "prod-kafka-${replace(var.region, "-", "")}"
  availability = "MULTI_ZONE"
  cloud        = "AWS"
  region       = var.region
  dedicated {
    cku = 2
  }
  environment {
    id = var.env_id
  }
}

resource "confluent_flink_compute_pool" "compute_pool" {
  display_name = "prod-flink-${replace(var.region, "-", "")}"
  cloud        = "AWS"
  region       = var.region
  max_cfu      = 4
  environment {
    id = var.env_id
  }
}

output "kafka_cluster_id" {
  value = confluent_kafka_cluster.cluster.id
}

output "compute_pool_id" {
  value = confluent_flink_compute_pool.compute_pool.id
}
```

**Usage:**

```hcl
# terraform/confluent/main.tf
module "us_east_1" {
  source  = "./modules/region"
  region  = "us-east-1"
  env_id  = confluent_environment.prod.id
}

module "us_west_2" {
  source  = "./modules/region"
  region  = "us-west-2"
  env_id  = confluent_environment.prod.id
}
```

### Step 2: Create Topics in Secondary Region

Replicate topic structure in secondary region:

```bash
# Set cluster context
confluent kafka cluster use <west-cluster-id>

# Create topics (same as primary region)
confluent kafka topic create raw-business-events --partitions 6
confluent kafka topic create filtered-loan-events --partitions 6
confluent kafka topic create filtered-service-events --partitions 6
confluent kafka topic create filtered-car-events --partitions 6
confluent kafka topic create filtered-high-value-loans --partitions 6
```

**Terraform:**

```hcl
# terraform/confluent/modules/region/topics.tf
resource "confluent_kafka_topic" "topics" {
  for_each = toset([
    "raw-business-events",
    "filtered-loan-events",
    "filtered-service-events",
    "filtered-car-events",
    "filtered-high-value-loans"
  ])
  
  kafka_cluster {
    id = confluent_kafka_cluster.cluster.id
  }
  topic_name       = each.value
  partitions_count = 6
  rest_endpoint    = confluent_kafka_cluster.cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster_api_key.id
    secret = confluent_api_key.cluster_api_key.secret
  }
}
```

## AWS PrivateLink Connectivity

### Overview

AWS PrivateLink provides secure, private connectivity between your VPC and Confluent Cloud without exposing traffic to the public internet.

### Step 1: Create Confluent Network

**Via Console:**
1. Navigate to: **Network management** → **Add network**
2. Select **AWS** → **PrivateLink**
3. Specify /16 CIDR (non-overlapping, e.g., 10.1.0.0/16)
4. Select availability zones

**Via Terraform:**

```hcl
# terraform/confluent/network.tf
resource "confluent_network" "aws_privatelink" {
  display_name     = "aws-privatelink-network"
  cloud            = "AWS"
  region           = "us-east-1"
  connection_types = ["PRIVATELINK"]
  zones            = ["use1-az1", "use1-az2", "use1-az3"]
  cidr             = "10.1.0.0/16"
  environment {
    id = confluent_environment.prod.id
  }
}
```

### Step 2: Create PrivateLink Attachment

**Via Console:**
1. Navigate to: **Network management** → **Attachments** → **Create attachment**
2. Select your network and environment
3. Note the service name provided by Confluent

### Step 3: AWS Side Setup

**Create VPC Endpoint:**

```hcl
# terraform/aws/privatelink.tf
resource "aws_vpc_endpoint" "confluent" {
  vpc_id              = var.vpc_id
  service_name        = var.confluent_service_name  # From Confluent Console
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.confluent.id]
  
  private_dns_enabled = true
}

resource "aws_security_group" "confluent" {
  name        = "confluent-privatelink"
  description = "Security group for Confluent PrivateLink"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### Step 4: Accept Connection

**Via Console:**
1. Navigate to: **Network management** → **Attachments**
2. Find pending attachment from AWS
3. Click **Accept** to approve the connection

**Verification:**

```bash
# Test connectivity from EKS pod or EC2 instance
curl -k https://flink.us-east-1.aws.private.confluent.cloud

# Test Kafka connectivity
kafka-console-producer \
  --bootstrap-server pkc-xxxxx.us-east-1.aws.private.confluent.cloud:9092 \
  --topic test-topic \
  --producer-property security.protocol=SASL_SSL \
  --producer-property sasl.mechanism=PLAIN \
  --producer-property sasl.jaas.config='org.apache.kafka.common.security.plain.PlainLoginModule required username="<key>" password="<secret>";'
```

## Multi-Region Cluster Linking

### Overview

Cluster Linking enables automatic replication of topics between regions for disaster recovery and active-active deployments.

### Step 1: Create Cluster Link

**Via Console:**
1. Navigate to: **Replication** → **Add link**
2. Configure exactly-once replication
3. Link topics: `raw-business-events`, filtered topics

**Via Terraform:**

```hcl
# terraform/confluent/cluster-linking.tf
resource "confluent_kafka_cluster_link" "east_to_west" {
  link_name = "east-to-west-link"
  
  kafka_cluster {
    id = module.us_east_1.kafka_cluster_id
  }
  
  destination_kafka_cluster {
    id = module.us_west_2.kafka_cluster_id
  }
  
  environment {
    id = confluent_environment.prod.id
  }
  
  config = {
    "replication.factor" = "3"
    "consumer.offset.sync.enable" = "true"
  }
}

# Create mirrored topics
resource "confluent_kafka_topic_mirror" "raw_events" {
  link_name = confluent_kafka_cluster_link.east_to_west.link_name
  kafka_cluster {
    id = module.us_east_1.kafka_cluster_id
  }
  mirror_topic_name = "raw-business-events"
  source_topic_name = "raw-business-events"
}
```

### Step 2: Verify Replication

```bash
# Check message counts in both regions
confluent kafka topic describe raw-business-events \
  --cluster <east-cluster-id> \
  --output json | jq '.partitions[].offset'

confluent kafka topic describe raw-business-events \
  --cluster <west-cluster-id> \
  --output json | jq '.partitions[].offset'

# Check replication lag
confluent kafka link describe east-to-west-link \
  --cluster <east-cluster-id> \
  --output json | jq '.lag'
```

## Multi-Region Flink Deployment

Deploy the same Flink SQL statements to each region's compute pool:

```bash
# Deploy to us-east-1
confluent flink statement create \
  --compute-pool <east-compute-pool-id> \
  --statement-name event-routing-job-east \
  --statement-file flink-jobs/routing-confluent-cloud.sql

# Deploy to us-west-2
confluent flink statement create \
  --compute-pool <west-compute-pool-id> \
  --statement-name event-routing-job-west \
  --statement-file flink-jobs/routing-confluent-cloud.sql
```

## Advanced CI/CD Integration

### Complete Jenkins Pipeline

```groovy
// Jenkinsfile
pipeline {
    agent any
    environment {
        CONFLUENT_API_KEY = credentials('confluent-api-key')
        CONFLUENT_API_SECRET = credentials('confluent-api-secret')
    }
    stages {
        stage('Lint & Validate') {
            parallel {
                stage('Lint SQL') {
                    steps {
                        sh 'sqlfluff lint cdc-streaming/flink-jobs/*.sql'
                    }
                }
                stage('Validate Terraform') {
                    steps {
                        dir('terraform/confluent') {
                            sh 'terraform init && terraform validate'
                        }
                    }
                }
            }
        }
        stage('Deploy Infrastructure') {
            steps {
                dir('terraform/confluent') {
                    sh 'terraform apply -auto-approve'
                }
            }
        }
        stage('Deploy Flink Jobs') {
            steps {
                sh '''
                    python scripts/deploy-flink-statement.py \
                        --compute-pool ${COMPUTE_POOL_ID} \
                        --sql-file cdc-streaming/flink-jobs/routing-generated.sql
                '''
            }
        }
    }
}
```

### GitHub Actions Multi-Region Workflow

```yaml
# .github/workflows/confluent-multi-region-deploy.yml
name: Deploy Confluent Multi-Region
on:
  push:
    branches: [main]
    paths: ['terraform/confluent/**', 'cdc-streaming/**']

jobs:
  deploy:
    strategy:
      matrix:
        region: [us-east-1, us-west-2]
    steps:
      - uses: actions/checkout@v3
      - name: Deploy Infrastructure
        working-directory: terraform/confluent
        run: |
          terraform init
          terraform apply -target=module.${replace(matrix.region, "-", "_")} -auto-approve
```

## Enterprise Features and Best Practices

### Security Considerations

- **API Key Management**: Store all API keys in HashiCorp Vault or AWS Secrets Manager
- **Service Accounts**: Use service accounts with least privilege
- **RBAC**: Implement role-based access control for all resources
- **Network Security**: Use PrivateLink for all production traffic

### Disaster Recovery

- **RTO/RPO Targets**: Define recovery time objectives and recovery point objectives
- **Backup Strategy**: Regular backups of Terraform state and configurations
- **Failover Procedures**: Document and test failover procedures

### Performance Optimization

- **CFU Sizing**: Right-size Flink compute pools based on throughput requirements
- **Partitioning**: Optimize topic partitioning for parallel processing
- **Compression**: Enable compression (snappy, gzip) for topics

### Multi-Region Deployment Strategies

1. **Parallel Deployment**: Deploy to all regions simultaneously (fastest)
2. **Sequential Deployment**: Deploy to primary region first, then replicate (safer)
3. **Blue-Green**: Deploy to new region, test, then switch traffic (zero downtime)
4. **Canary**: Deploy to one region, monitor, then expand (risk mitigation)

### Monitoring and Alerting

**Key Metrics to Monitor:**
- Replication lag between regions
- Flink statement throughput and latency
- Consumer group lag
- Cluster health and availability

**Recommended Alerts:**
- Replication lag > 5 minutes
- Flink statement failures
- Consumer lag > 10,000 messages
- Cluster unavailability

