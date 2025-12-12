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

# Create raw-business-events topic (only topic that needs manual creation)
confluent kafka topic create raw-business-events \
  --partitions 6 \
  --config retention.ms=604800000

# Note: Filtered topics (filtered-loan-events, filtered-service-events, etc.) 
# are automatically created by Flink when it writes to them for the first time.
# No manual creation is required for filtered topics.
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
# Get Schema Registry endpoint (requires environment context)
confluent schema-registry cluster describe \
  --environment <env-id> \
  --output json | jq -r '.endpoint_url'

# Or if environment is already set as current:
# confluent schema-registry cluster describe --output json | jq -r '.endpoint_url'

# Example: https://psrc-xxxxx.us-east-1.aws.confluent.cloud
```

### Step 2: Generate Schema Registry API Keys

```bash
# Get Schema Registry cluster ID
SR_CLUSTER_ID=$(confluent schema-registry cluster describe --output json | jq -r '.cluster')
echo "Schema Registry Cluster ID: $SR_CLUSTER_ID"

# Create API key for Schema Registry
confluent api-key create \
  --resource $SR_CLUSTER_ID \
  --description "Schema Registry API key"

# Save key and secret (replace with actual values from the command output)
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
confluent schema-registry subject update raw-business-events-value --compatibility backward
confluent schema-registry subject update filtered-loan-events-value --compatibility backward
confluent schema-registry subject update filtered-service-events-value --compatibility backward
```

## Flink Compute Pool Setup

### Step 1: Create Compute Pool

```bash
# Create compute pool (valid --max-cfu values: 5, 10, 20, 30, 40, 50)
confluent flink compute-pool create prod-flink-east \
  --cloud aws \
  --region us-east-1 \
  --max-cfu 5

# Note the compute pool ID (e.g., cp-abc123)
# Set as current compute pool
confluent flink compute-pool use <compute-pool-id>
```

**CFU Sizing Guidelines:**
- **5 CFU**: Development/testing, low-throughput workloads
- **10 CFU**: Production, moderate workloads (up to 100K events/sec)
- **20 CFU**: Production, high workloads (100K-500K events/sec)
- **30-50 CFU**: Enterprise, very high-throughput (500K+ events/sec)

### Step 2: Create Service Account for Flink

```bash
# Create service account
confluent iam service-account create flink-sa \
  --description "Service account for Flink compute pool"

# Note the service account ID (e.g., sa-abc123)
```

### Step 3: Assign FlinkDeveloper Role

```bash
# Assign FlinkDeveloper role to service account
confluent iam rbac role-binding create \
  --principal User:<service-account-id> \
  --role FlinkDeveloper \
  --environment <env-id>
```

### Step 4: Generate Flink API Key

```bash
# Create API key for Flink (uses region-based resource, not compute-pool-id)
confluent api-key create \
  --resource flink \
  --cloud aws \
  --region us-east-1 \
  --service-account <service-account-id> \
  --description "Flink compute pool API key"

# Save key and secret
export FLINK_API_KEY="<api-key>"
export FLINK_API_SECRET="<api-secret>"
```

### Step 5: Get Flink REST Endpoint

```bash
# Flink REST endpoint follows pattern: https://flink.{region}.{cloud}.confluent.cloud
# For AWS us-east-1:
export FLINK_REST_ENDPOINT="https://flink.us-east-1.aws.confluent.cloud"

# For other regions, use pattern: https://flink.<region>.<cloud>.confluent.cloud
```

## Connector Setup

### Overview

This section covers setting up CDC (Change Data Capture) from PostgreSQL to Confluent Cloud using Debezium.

**Two Options:**
- **Option A**: Confluent Cloud Managed Connectors (fully managed, easier)
- **Option B**: Self-Hosted Kafka Connect (more control, local bridge)

### Option A: Confluent Cloud Managed Connectors

Use Confluent Cloud's managed PostgreSQL CDC connector (`postgres-cdc-source` type):

**Recommended: Use the deployment script:**

```bash
# Set required environment variables
export KAFKA_API_KEY="<your-kafka-api-key>"
export KAFKA_API_SECRET="<your-kafka-api-secret>"
export DB_HOSTNAME="<postgres-hostname>"
export DB_USERNAME="postgres"
export DB_PASSWORD="<password>"
export DB_NAME="car_entities"
export SCHEMA_REGISTRY_API_KEY="<your-sr-api-key>"
export SCHEMA_REGISTRY_API_SECRET="<your-sr-api-secret>"
export SCHEMA_REGISTRY_URL="https://psrc-xxxxx.us-east-1.aws.confluent.cloud"
export TABLE_INCLUDE_LIST="public.car_entities"  # Optional, defaults to car_entities

# Deploy connector
cd cdc-streaming/scripts
./deploy-confluent-postgres-cdc-connector.sh
```

**Or manually via CLI:**

```bash
# Create managed connector via CLI
confluent connector create postgres-cdc-source \
  --cluster lkc-xxxxx \
  --type postgres-cdc-source \
  --config-file connectors/postgres-cdc-source-confluent-cloud.json
```

**Available connector configurations:**
- `connectors/postgres-cdc-source-confluent-cloud.json` - For `car_entities` table
- `connectors/postgres-cdc-source-simple-events-confluent-cloud.json` - For `simple_events` table

**Note:** Confluent's `postgres-cdc-source` connector is the recommended managed connector for PostgreSQL CDC. It provides better integration with Confluent Cloud features and is fully managed by Confluent.

### Option B: Self-Hosted Kafka Connect (Local to Cloud Bridge)

This option is useful when testing locally or when your database isn't accessible from Confluent Cloud.

#### Step 1: Enable PostgreSQL Logical Replication

```bash
# Update postgresql.conf
wal_level = logical
max_replication_slots = 4
max_wal_senders = 4

# Restart PostgreSQL
docker restart <postgres-container>

# Verify settings
psql -c "SHOW wal_level;"
```

#### Step 2: Install Debezium Connector

If Confluent Hub fails, download manually from Maven Central:

```bash
docker exec <kafka-connect-container> bash -c "
curl -L -o /tmp/debezium.tar.gz \
  https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.4.0.Final/debezium-connector-postgres-2.4.0.Final-plugin.tar.gz &&
mkdir -p /usr/share/confluent-hub-components/debezium-connector-postgresql &&
tar -xzf /tmp/debezium.tar.gz -C /usr/share/confluent-hub-components/debezium-connector-postgresql --strip-components=1 &&
rm /tmp/debezium.tar.gz
"

# Restart Kafka Connect to load plugin
docker restart <kafka-connect-container>
```

#### Step 3: Create CDC Topics

Topics must exist before connector writes to them:

```bash
# Create CDC topics with proper naming
confluent kafka topic create cdc-raw.public.car_entities --partitions 3
confluent kafka topic create cdc-raw.public.loan_entities --partitions 3
```

#### Step 4: Deploy Connector

Create connector configuration (JSON format is simpler for testing):

```json
{
  "name": "postgres-cdc-confluent-cloud",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "1",
    "database.hostname": "<postgres-hostname>",
    "database.port": "5432",
    "database.user": "postgres",
    "database.password": "<password>",
    "database.dbname": "<database-name>",
    "database.server.name": "postgres-cdc",
    "topic.prefix": "cdc-raw",
    "table.include.list": "public.car_entities,public.loan_entities",
    "plugin.name": "pgoutput",
    "slot.name": "cdc_confluent_slot",
    "publication.name": "cdc_confluent_publication",
    "publication.autocreate.mode": "filtered",
    
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    
    "producer.bootstrap.servers": "<kafka-bootstrap-servers>",
    "producer.security.protocol": "SASL_SSL",
    "producer.sasl.mechanism": "PLAIN",
    "producer.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"<kafka-api-key>\" password=\"<kafka-api-secret>\";",
    
    "snapshot.mode": "never",
    "tombstones.on.delete": "true",
    "include.schema.changes": "false",
    
    "transforms": "unwrap",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "false",
    "transforms.unwrap.add.fields": "op,table,ts_ms",
    
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
```

Deploy via REST API:

```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/postgres-cdc-confluent-cloud.json
```

#### Step 5: Verify Connector

```bash
# Check status
curl http://localhost:8083/connectors/<connector-name>/status | jq

# Verify data flow
docker exec <kafka-connect-container> kafka-console-consumer \
  --bootstrap-server <confluent-cloud-bootstrap> \
  --consumer.config /tmp/kafka.properties \
  --topic cdc-raw.public.car_entities \
  --from-beginning \
  --max-messages 5
```

**Expected output:**
```json
{
  "id": "car-123",
  "entity_type": "Car",
  "data": "{\"make\": \"Honda\", \"model\": \"Accord\"}",
  "__op": "c",
  "__table": "car_entities",
  "__ts_ms": 1732900000000
}
```

## Flink SQL Configuration

### Important: Confluent Cloud Flink Dialect Differences

Confluent Cloud Flink uses a **different SQL dialect** than Apache Flink:

| Feature | Apache Flink | Confluent Cloud |
|---------|--------------|-----------------|
| Connector | `'kafka'` | `'confluent'` |
| Topic specification | `'topic' = 'name'` | Table name = topic name |
| Processing time | `PROCTIME()` | Not supported |
| Formats | `'json'`, `'avro'` | Requires Schema Registry or specific configuration |

**Recommendation**: Use the **Confluent Cloud Web Console SQL Workspace** for initial development. It provides:
- Real-time syntax validation
- Interactive query testing
- Better error messages
- Built-in documentation

### Step 1: Access Flink SQL Workspace

**Via Web Console (Recommended):**

1. Navigate to https://confluent.cloud
2. Select your environment
3. Click **Flink** → **Open SQL Workspace**
4. Select compute pool: `prod-flink-east`

**Via CLI:**

```bash
# Set context
confluent environment use <env-id>
confluent flink compute-pool use <compute-pool-id>

# Deploy statement
confluent flink statement create <statement-name> \
  --sql "<your-sql>" \
  --database <kafka-cluster-id>
```

### Step 2: Create Source Table

In Confluent Cloud Flink, use the Web Console to create tables:

```sql
-- Example: Create source table for existing topic
CREATE TABLE my_source_table (
    id STRING,
    name STRING,
    timestamp BIGINT
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry',
    'scan.startup.mode' = 'earliest-offset'
);
```

**Note**: Table name automatically maps to topic name. For topics with dots (e.g., `cdc-raw.public.car_entities`), reference them directly:

```sql
SELECT * FROM `cdc-raw.public.car_entities` LIMIT 10;
```

### Step 3: Test Queries Interactively

Before deploying INSERT statements, test SELECT queries:

```sql
-- Test: Read from your topic
SELECT * FROM your_table_name LIMIT 10;

-- Test: Filter data
SELECT * FROM your_table_name 
WHERE field_name = 'value'
LIMIT 10;
```

### Step 4: Create Sink Table and INSERT Statement

Once source table works, create sink and INSERT:

**Important: Sink Tables Require `key` Column**

When using the Confluent connector in Confluent Cloud Flink, sink tables automatically include a `key BYTES` column. You must include this column in your sink table definition and provide it in your INSERT statement.

```sql
-- Create sink table (note: includes key BYTES column)
CREATE TABLE my_sink_table (
    `key` BYTES,           -- Required: Kafka message key
    id STRING,
    processed_field STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry'
);

-- Deploy INSERT statement (must include key)
INSERT INTO my_sink_table
SELECT 
    CAST(id AS BYTES) AS `key`,  -- Derive key from id or other field
    id, 
    UPPER(name) as processed_field
FROM my_source_table;
```

**Why the `key` Column is Required:**
- Confluent Cloud Flink's sink tables automatically include a `key BYTES` column for Kafka message keys
- Kafka messages have both key and value - the connector requires both
- Using `id` as the key ensures:
  - Same `id` values go to the same partition (partitioning)
  - Events with the same `id` are ordered within a partition
  - Useful for downstream consumers that process by `id`

### Common Pitfalls

1. **Reserved Keywords**: `model`, `timestamp`, `date`, `time` are reserved - use backticks or rename
2. **JSON Parsing**: Use `JSON_VALUE(field, '$.path')` to extract from JSON strings
3. **Schema Registry**: JSON format requires Schema Registry integration or use `'raw'` format
4. **Multiple Statements**: CLI doesn't support multiple CREATE/INSERT statements well - use Web Console
5. **Missing `key` Column in Sink Tables**: Sink tables must include `key BYTES` as the first column, and INSERT statements must provide it (e.g., `CAST(id AS BYTES) AS key`)
6. **Missing `INSERT INTO` Clause**: INSERT statements must start with `INSERT INTO <table>` - SELECT-only statements will be automatically stopped after 5 minutes

### Working with CDC Data

For Debezium CDC data (JSON format):

```sql
-- CDC data structure from Debezium
CREATE TABLE cdc_source (
    id STRING,
    entity_type STRING,
    data STRING,           -- JSON string with nested data
    __op STRING,           -- Operation: 'c'=create, 'u'=update, 'd'=delete
    __table STRING,        -- Source table name
    __ts_ms BIGINT         -- Timestamp
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry',
    'scan.startup.mode' = 'earliest-offset'
);

-- Extract fields from JSON data
SELECT 
    id,
    JSON_VALUE(data, '$.make') as make,
    JSON_VALUE(data, '$.model') as car_model,
    __op as operation
FROM cdc_source
WHERE __op IN ('c', 'u');
```

## Deploy Flink SQL Statements

### Recommended: Use Web Console for Initial Deployment

Due to Confluent Cloud Flink dialect differences, the **Web Console is strongly recommended** for first-time deployments.

**Steps:**

1. Go to https://confluent.cloud
2. Navigate: **Environment** → **Flink** → **Open SQL Workspace**
3. Select compute pool: `prod-flink-east`
4. Write SQL interactively with real-time validation
5. Run queries to test before deploying INSERT statements

### Option 1: Web Console Deployment (Recommended)

**Test connectivity first:**
```sql
-- Verify you can read from topics
SELECT * FROM `your-topic-name` LIMIT 10;
```

**Deploy processing:**
```sql
-- Create source table (table name = topic name)
CREATE TABLE source_table (...);

-- Create sink table
CREATE TABLE sink_table (...);

-- Deploy INSERT statement
INSERT INTO sink_table
SELECT ... FROM source_table;
```

### Option 2: CLI Deployment (For Automation)

```bash
# Set context
confluent environment use <env-id>
confluent flink compute-pool use <compute-pool-id>

# Deploy single statement
confluent flink statement create <statement-name> \
  --sql "CREATE TABLE my_table (id STRING) WITH ('connector' = 'confluent');" \
  --database <kafka-cluster-id> \
  --wait
```

**Important CLI Limitations:**
- Cannot deploy multiple statements together easily
- Error messages are less detailed than Web Console
- No interactive syntax validation
- Best for simple queries or automation after development

### Step 2: Verify Deployment

**Via Web Console:**
- View statement in **Flink** → **Statements**
- Check status: Should be `RUNNING`
- Monitor throughput and metrics in real-time

**Via CLI:**

```bash
# List all statements
confluent flink statement list

# Get statement details
confluent flink statement describe <statement-name>

# Check if processing records
confluent flink statement describe <statement-name> --output json | jq '.status'
```

### Step 3: Monitor Statement

**Key Metrics to Watch:**

```bash
# View statement details
confluent flink statement describe <statement-name> --output json | jq '{
  status: .status,
  phase: .phase,
  created: .created_at
}'

# Check if data is flowing
# Consume from output topic to verify
```

**Via Confluent Cloud Console:**
- Navigate to: **Flink** → **Statements** → Click your statement
- View: Status, Job Graph, Metrics
- Monitor: Records In/Out, Throughput, Backpressure
- Check: Logs for errors or warnings

## Testing and Verification

### Step 1: Verify Connector is Running

**For Self-Hosted Kafka Connect:**

```bash
# Check connector status
curl http://localhost:8083/connectors/<connector-name>/status | jq

# Expected output:
# {
#   "connector": {"state": "RUNNING"},
#   "tasks": [{"state": "RUNNING"}]
# }

# Check connector logs
docker logs <kafka-connect-container> 2>&1 | grep "records sent"
```

**For Confluent Cloud Managed Connector:**

```bash
confluent connector describe <connector-name> \
  --output json | jq '.status'
```

### Step 2: Verify Messages in Topics

**Check topic exists and has messages:**

```bash
# List topics
confluent kafka topic list

# Describe topic (shows partition count, replication factor)
confluent kafka topic describe <topic-name>
```

**Consume messages to verify data flow:**

For topics with plain text/JSON (without Schema Registry):
```bash
# Using kafka-console-consumer inside Kafka Connect container
docker exec <kafka-connect-container> kafka-console-consumer \
  --bootstrap-server <bootstrap-servers> \
  --consumer.config /tmp/kafka.properties \
  --topic <topic-name> \
  --from-beginning \
  --max-messages 5
```

For topics with Avro (requires Schema Registry):
```bash
# Confluent Cloud CLI automatically handles Avro
confluent kafka topic consume <topic-name> \
  --value-format avro \
  --schema-registry-endpoint <url> \
  --schema-registry-api-key <key> \
  --schema-registry-api-secret <secret> \
  --from-beginning
```

### Step 3: End-to-End Data Flow Test

**Insert test data into PostgreSQL:**

```bash
# Insert test record
docker exec <postgres-container> psql -U postgres -d <database> -c "
INSERT INTO car_entities (id, entity_type, created_at, updated_at, data)
VALUES ('test-$(date +%s)', 'Car', NOW(), NOW(), 
'{\"make\": \"Toyota\", \"model\": \"Camry\", \"year\": 2024}'::jsonb);
"
```

**Verify CDC captured the change:**

```bash
# Wait a few seconds, then consume from CDC topic
docker exec <kafka-connect-container> kafka-console-consumer \
  --bootstrap-server <bootstrap-servers> \
  --consumer.config /tmp/kafka.properties \
  --topic cdc-raw.public.car_entities \
  --from-beginning \
  --max-messages 1
```

**Expected output:**
```json
{
  "id": "test-1234567890",
  "entity_type": "Car",
  "data": "{\"make\": \"Toyota\", \"model\": \"Camry\", \"year\": 2024}",
  "__op": "c",
  "__table": "car_entities",
  "__ts_ms": 1732900000000
}
```

### Step 4: Verify Flink Processing (If Deployed)

**Check Flink statement status:**

```bash
# Via CLI
confluent flink statement list

# Via Web Console
# Navigate: Flink → Statements → Check status
```

**Verify output topic has processed data:**

```bash
# Consume from Flink output topic
docker exec <kafka-connect-container> kafka-console-consumer \
  --bootstrap-server <bootstrap-servers> \
  --consumer.config /tmp/kafka.properties \
  --topic <flink-output-topic> \
  --from-beginning
```

### Step 5: Troubleshoot Issues

**Connector not sending data:**

```bash
# Check connector logs for errors
docker logs <kafka-connect-container> 2>&1 | grep -i "error\|exception"

# Verify PostgreSQL replication slot exists
docker exec <postgres-container> psql -U postgres -d <database> -c "
SELECT * FROM pg_replication_slots;
"

# Restart connector if needed
curl -X POST http://localhost:8083/connectors/<connector-name>/restart
```

**Topics not receiving messages:**

```bash
# Verify topics exist
confluent kafka topic list | grep <topic-name>

# Check Kafka API credentials are correct
# Review connector configuration
curl http://localhost:8083/connectors/<connector-name> | jq '.config'
```

**Flink statement not processing:**

```bash
# Check statement status and errors via Web Console
# Flink → Statements → Click statement → View Logs

# Common issues:
# - Table/topic name mismatch
# - Authentication errors
# - Invalid SQL syntax for Confluent Cloud dialect
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

#### Issue 4: Database Schema Missing or Corrupted

**Symptoms:**
- API returns: `"relation \"business_events\" does not exist"`
- Events cannot be inserted into database
- Lambda functions fail with database errors

**Solutions:**

```bash
# 1. Verify database connection details
# Check .env.aurora file for current password
cat .env.aurora | grep DB_PASSWORD

# 2. Apply schema using Docker (if psql not available locally)
export DATABASE_PASSWORD="<password-from-env-aurora>"
AURORA_ENDPOINT="<aurora-endpoint>"
docker run --rm -i -e PGPASSWORD="$DATABASE_PASSWORD" postgres:15-alpine \
  psql -h "$AURORA_ENDPOINT" -U postgres -d car_entities -f - < data/schema.sql

# 3. Or use Python script
python3 scripts/init-aurora-schema.py

# 4. Verify tables were created
docker run --rm -i -e PGPASSWORD="$DATABASE_PASSWORD" postgres:15-alpine \
  psql -h "$AURORA_ENDPOINT" -U postgres -d car_entities -c "\dt"

# Expected output should show:
# - business_events
# - car_entities
# - loan_entities
# - loan_payment_entities
# - service_record_entities
```

#### Issue 5: Flink Source Table Schema Registry Mismatch

**Symptoms:**
- Flink statement fails with: `"Schema Registry subject 'raw-business-events-value' doesn't match the existing one"`
- Cannot recreate source table after cleanup
- Source table status is FAILED
- Existing RUNNING statements may still work but stop processing new events

**Solutions:**

```bash
# Option 1: Delete and recreate Schema Registry subject (if safe to do)
# Note: This will delete existing schemas for the topic
confluent schema-registry subject delete raw-business-events-value --force

# Then recreate the source table
SOURCE_SQL="CREATE TABLE \`raw-business-events\` ( \`id\` STRING, \`event_name\` STRING, \`event_type\` STRING, \`created_date\` STRING, \`saved_date\` STRING, \`event_data\` STRING, \`__op\` STRING, \`__table\` STRING, \`__ts_ms\` BIGINT ) WITH ( 'connector' = 'confluent', 'value.format' = 'json-registry', 'scan.startup.mode' = 'earliest-offset' );"
confluent flink statement create "source-raw-business-events" \
  --compute-pool <compute-pool-id> \
  --database <kafka-cluster-id> \
  --sql "$SOURCE_SQL"

# Option 2: Use existing RUNNING statements (if they exist)
# Check for existing RUNNING statements that may still work
confluent flink statement list --compute-pool <compute-pool-id> | grep RUNNING

# Option 3: Contact Confluent Support to resolve schema compatibility
```

#### Issue 6: Checking Flink Statement Logs and Status

**Symptoms:**
- Need to verify Flink statements are processing events correctly
- Want to check for errors or exceptions
- Need to monitor statement health

**How to Check:**

```bash
# 1. List all statements and their status
confluent flink statement list --compute-pool <compute-pool-id>

# 2. Get detailed information about a statement
confluent flink statement describe <statement-name>

# 3. Check for exceptions
confluent flink statement exception list <statement-name>

# 4. Get comprehensive status summary (using Python)
python3 << 'PYEOF'
import json
import subprocess

result = subprocess.run(
    ['confluent', 'flink', 'statement', 'list', '--compute-pool', '<compute-pool-id>', '--output', 'json'],
    capture_output=True,
    text=True
)

if result.returncode == 0:
    data = json.loads(result.stdout)
    
    # Source table status
    source_tables = [s for s in data if 'source-raw-business-events' in s.get('name', '')]
    print("Source Tables:")
    for s in source_tables:
        print(f"  {s['name']}: {s.get('status')} - {s.get('status_detail', 'N/A')[:100]}")
    
    # Running INSERT statements
    running = [s for s in data if s.get('status') == 'RUNNING' and 'insert' in s.get('name', '').lower()]
    print(f"\nRUNNING INSERT Statements: {len(running)}")
    for s in running:
        offsets = s.get('latest_offsets', {})
        timestamp = s.get('latest_offsets_timestamp', 'N/A')
        print(f"  {s['name']}:")
        print(f"    Latest Offsets: {offsets}")
        print(f"    Last Updated: {timestamp}")
    
    # Failed statements
    failed = [s for s in data if s.get('status') == 'FAILED' and 'insert' in s.get('name', '').lower()]
    if failed:
        print(f"\nFAILED Statements: {len(failed)}")
        for s in failed:
            print(f"  {s['name']}: {s.get('status_detail', 'Unknown')[:150]}")
PYEOF
```

**Key Metrics to Monitor:**
- **Status**: Should be `RUNNING` for active statements
- **Latest Offsets**: Shows which partition/offset Flink has processed
- **Latest Offsets Timestamp**: Indicates when Flink last processed events
- **Exceptions**: Should be empty for healthy statements

**Note**: If `Latest Offsets Timestamp` is old (hours/days), it may indicate:
- No new events in the source topic
- Source table is FAILED and can't read new events
- Statement is stuck or needs restart

#### Issue 7: Flink Filter Not Matching Events - Data Structure Mismatch

**Symptoms:**
- Flink statement is RUNNING but no events in filtered topic
- Statement shows offsets but filtered topic is empty
- Filter condition uses `__op` or `__table` but events don't match

**Root Cause:**
The Flink statement expects CDC metadata fields (`__op`, `__table`, `__ts_ms`) that are added by the CDC connector transforms. If the connector doesn't add these fields, the Flink filter will not match any events.

**Example Flink Statement:**
```sql
INSERT INTO `filtered-service-events`
SELECT `id`, `event_name`, `event_type`, `created_date`, `saved_date`, `event_data`, `__op`, `__table`
FROM `raw-business-events`
WHERE `event_name` = 'CarServiceDone' AND `__op` = 'c';
```

**Expected Data Structure in raw-business-events:**
```json
{
  "id": "uuid",
  "event_name": "CarServiceDone",
  "event_type": "CarServiceDone",
  "created_date": "2025-12-11T21:26:10Z",
  "saved_date": "2025-12-11T21:26:10Z",
  "event_data": "{...}",
  "__op": "c",           // ← REQUIRED by Flink filter
  "__table": "business_events",
  "__ts_ms": 1733941570000
}
```

**Database Table Structure:**
- Columns: `id`, `event_name`, `event_type`, `created_date`, `saved_date`, `event_data`
- Note: `__op`, `__table`, `__ts_ms` are NOT in database - added by CDC connector

**Solutions:**

```bash
# 1. Verify connector configuration includes ExtractNewRecordState transform
confluent connect describe <connector-name> --output json | \
  jq '.config | {transforms, unwrap_type: ."transforms.unwrap.type", add_fields: ."transforms.unwrap.add.fields"}'

# Expected output should show:
# {
#   "transforms": "unwrap,route",
#   "unwrap_type": "io.debezium.transforms.ExtractNewRecordState",
#   "add_fields": "op,table,ts_ms"
# }

# 2. If connector doesn't have unwrap transform, update it:
# Use postgres-cdc-source-business-events-confluent-cloud-fixed.json config
# which includes:
# - transforms: "unwrap,route"
# - transforms.unwrap.type: "io.debezium.transforms.ExtractNewRecordState"
# - transforms.unwrap.add.fields: "op,table,ts_ms"
# - transforms.unwrap.add.fields.prefix: "__"

# 3. Verify actual data structure in topic
# Check a sample message to confirm __op field exists
# (Note: Requires API key setup to consume)

# 4. Alternative: Modify Flink filter to not require __op
# Remove AND `__op` = 'c' condition if connector doesn't add it
# But this is NOT recommended - you'll get all operations (insert, update, delete)
```

**Comparison Table:**

| Component | Has `__op` Field? | Flink Filter Works? |
|-----------|-------------------|---------------------|
| Database Table | ❌ No | N/A |
| Basic Connector (route only) | ❌ No | ❌ Filter fails |
| Fixed Connector (unwrap + route) | ✅ Yes | ✅ Filter works |
| Flink Statement Expects | ✅ Yes | ✅ If data has it |

#### Issue 8: Flink Statements Not Processing New Events

**Symptoms:**
- Flink statements show status `RUNNING`
- `Latest Offsets Timestamp` is old (hours/days ago)
- No new events being processed despite new events in source topic
- Source table may be FAILED

**Diagnosis:**

```bash
# Check source table status
confluent flink statement list --compute-pool <compute-pool-id> | grep source-raw-business-events

# Check statement offsets and timestamps
confluent flink statement describe <statement-name> | grep -E "(Latest Offsets|Timestamp)"

# Compare current time with last processed timestamp
date -u
# If timestamp is hours/days old, statement may be stuck
```

**Solutions:**

```bash
# 1. If source table is FAILED, fix it first (see Issue 5)

# 2. Restart the statement
confluent flink statement stop <statement-name>
confluent flink statement resume <statement-name>

# 3. Check if source topic has new events
confluent kafka topic describe raw-business-events

# 4. Verify CDC connector is sending events
confluent connector describe <connector-name> --output json | jq '.status'
```

#### Issue 10: Flink Statement Automatically Stopped - Missing INSERT INTO Clause

**Symptoms:**
- Flink statement status is `STOPPED` instead of `RUNNING`
- Status detail shows: "This statement was automatically stopped since no client has consumed the results for 5 minutes or more."
- Some INSERT statements are RUNNING while others are STOPPED
- Statement was deployed as a SELECT query without `INSERT INTO` clause

**Root Cause:**
When deploying Flink INSERT statements via CLI, if the SQL extraction process misses the `INSERT INTO` clause, the statement is deployed as just a SELECT query. SELECT statements without INSERT don't write to any sink, so Confluent Cloud automatically stops them after 5 minutes of no consumption.

**Example of Incorrect Statement:**
```sql
-- ❌ WRONG: Missing INSERT INTO clause
SELECT CAST(`id` AS BYTES) AS `key`, `id`, `event_name`, `event_type`, ...
FROM `raw-business-events`
WHERE `event_type` = 'LoanCreated' AND `__op` = 'c';
```

**Example of Correct Statement:**
```sql
-- ✅ CORRECT: Includes INSERT INTO clause
INSERT INTO `filtered-loan-created-events`
SELECT CAST(`id` AS BYTES) AS `key`, `id`, `event_name`, `event_type`, ...
FROM `raw-business-events`
WHERE `event_type` = 'LoanCreated' AND `__op` = 'c';
```

**Diagnosis:**
```bash
# Check statement details to see the actual SQL
confluent flink statement describe <statement-name> --output json | jq '.statement'

# Look for statements that start with SELECT instead of INSERT INTO
confluent flink statement list --compute-pool <compute-pool-id> --output json | \
  jq -r '.[] | select(.status == "STOPPED" and (.statement | startswith("SELECT"))) | "\(.name) - \(.status_detail)"'
```

**Solutions:**
```bash
# 1. Delete the incorrectly deployed statement
confluent flink statement delete <statement-name> --force

# 2. Extract the correct SQL from the source file (ensuring INSERT INTO is included)
cd /path/to/project
FLINK_SQL_FILE="cdc-streaming/flink-jobs/business-events-routing-confluent-cloud.sql"

# Extract INSERT statement with proper awk pattern that includes INSERT INTO
INSERT_SQL=$(awk '/INSERT INTO.*filtered-loan-created-events/,/;/{if(/INSERT/ || /SELECT/ || /FROM/ || /WHERE/ || /^[^-\/]/) print}' "$FLINK_SQL_FILE" | \
  grep -v "^--" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

# Verify the SQL starts with INSERT INTO
echo "$INSERT_SQL" | grep -q "^INSERT INTO" && echo "✓ SQL is correct" || echo "✗ SQL is missing INSERT INTO"

# 3. Redeploy with correct SQL
confluent flink statement create <statement-name> \
  --compute-pool <compute-pool-id> \
  --database <kafka-cluster-id> \
  --sql "$INSERT_SQL" \
  --wait

# 4. Verify statement is now RUNNING
confluent flink statement describe <statement-name> | grep -E "(Status|Statement)"
```

**Prevention:**
- Always verify extracted SQL includes `INSERT INTO` before deploying
- Use Web Console for initial deployment to catch syntax issues early
- When using CLI, validate SQL extraction with: `echo "$SQL" | grep "^INSERT INTO"`
- Consider using deployment scripts that validate SQL before deployment

**Key Takeaway:**
All Flink INSERT statements must include the `INSERT INTO <sink-table>` clause. SELECT-only statements will be automatically stopped by Confluent Cloud as they don't produce any consumable output.

#### Issue 9: Cleaning Up Flink Statements

**Symptoms:**
- Too many COMPLETED or FAILED statements cluttering the compute pool
- Need to clean up old statements before redeploying

**Solutions:**

```bash
# Use the cleanup script
cd cdc-streaming
bash scripts/cleanup-flink-statements.sh

# Or manually delete COMPLETED/FAILED statements
confluent flink statement list --compute-pool <compute-pool-id> --output json | \
  python3 -c "import sys, json; data = json.load(sys.stdin); \
  to_delete = [s['name'] for s in data if s.get('status') in ['COMPLETED', 'FAILED']]; \
  [print(name) for name in to_delete]" | \
  while read name; do
    confluent flink statement delete "$name" --force
  done

# After cleanup, redeploy using deployment script
bash scripts/deploy-business-events-flink.sh
```

#### Issue 7: Connector Not Capturing Changes

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

## Practical Notes and Lessons Learned

Based on real-world implementation experience, here are key insights:

### Debezium Connector Installation

**Issue**: `confluent-hub install` may fail to find the Debezium connector.

**Solution**: Download manually from Maven Central:
```bash
curl -L -o /tmp/debezium.tar.gz \
  https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.4.0.Final/debezium-connector-postgres-2.4.0.Final-plugin.tar.gz
tar -xzf /tmp/debezium.tar.gz -C /usr/share/confluent-hub-components/
```

### Schema Compatibility Challenges

**Issue**: Debezium's raw table structure doesn't match custom Avro schemas expecting structured events.

**Pragmatic Solution**: Use JSON format for initial CDC capture, transform later with Flink:
```json
"key.converter": "org.apache.kafka.connect.json.JsonConverter",
"key.converter.schemas.enable": "false",
"value.converter": "org.apache.kafka.connect.json.JsonConverter",
"value.converter.schemas.enable": "false"
```

**Best Practice**: Create dedicated CDC topics (e.g., `cdc-raw.public.table_name`) separate from application-level topics.

### Topic Naming for Flink

**Issue**: Topics with dots (e.g., `cdc-raw.public.car_entities`) require backticks in Flink SQL.

**Workaround**:
```sql
SELECT * FROM `cdc-raw.public.car_entities`;
```

**Best Practice**: For new deployments, use underscores: `cdc_raw_public_car_entities`.

### Confluent Cloud Flink vs Apache Flink

**Critical Differences**:

| Feature | Apache Flink | Confluent Cloud |
|---------|--------------|-----------------|
| Connector | `'kafka'` | `'confluent'` |
| Topic config | `'topic' = 'name'` | Table name IS topic name |
| PROCTIME() | Supported | Not supported |
| JSON format | Simple | Needs Schema Registry or special config |

**Impact**: SQL written for Apache Flink often won't work in Confluent Cloud without significant changes.

**Recommendation**: Always develop Flink SQL in the Web Console first. CLI deployment is best for automation after development.

### Removing Database Migration Code from Lambda Functions

**Important**: Lambda functions should NOT contain database migration code. Database schema should be managed separately.

**Before (Incorrect):**
```python
# In lambda_handler.py
async def _run_migrations(pool):
    # Migration code here
    await conn.execute("CREATE TABLE IF NOT EXISTS...")

async def _initialize_service():
    pool = await get_connection_pool(_config.database_url)
    await _run_migrations(pool)  # ❌ Don't do this
    # ...
```

**After (Correct):**
```python
# In lambda_handler.py
async def _initialize_service():
    pool = await get_connection_pool(_config.database_url)
    # ✅ No migration code - schema managed separately
    # ...
```

**Apply Schema Separately:**
```bash
# Use dedicated script to apply schema
export DATABASE_PASSWORD="<password-from-env-aurora>"
AURORA_ENDPOINT="<aurora-endpoint>"
docker run --rm -i -e PGPASSWORD="$DATABASE_PASSWORD" postgres:15-alpine \
  psql -h "$AURORA_ENDPOINT" -U postgres -d car_entities -f - < data/schema.sql

# Or use Python script
python3 scripts/init-aurora-schema.py
```

**Benefits:**
- Clear separation of concerns
- Schema changes don't require Lambda redeployment
- Easier to version control schema changes
- Can apply schema updates independently

### Verifying Data Flow

**Don't rely solely on connector status showing "RUNNING"**. Always verify actual data:

```bash
# Create kafka.properties inside Kafka Connect container
docker exec <kafka-connect-container> bash -c "cat > /tmp/kafka.properties << 'EOF'
bootstrap.servers=<bootstrap-servers>
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"<key>\" password=\"<secret>\";
EOF"

# Then consume to verify
docker exec <kafka-connect-container> kafka-console-consumer \
  --bootstrap-server <bootstrap-servers> \
  --consumer.config /tmp/kafka.properties \
  --topic <topic-name> \
  --from-beginning \
  --max-messages 5
```

### PostgreSQL Replication Setup

**Critical**: Logical replication must be enabled BEFORE creating connectors:

```sql
-- Check current setting
SHOW wal_level;

-- If not 'logical', update postgresql.conf:
-- wal_level = logical
-- max_replication_slots = 4
-- max_wal_senders = 4

-- Then restart PostgreSQL
```

**Verify replication slot is created**:
```sql
SELECT * FROM pg_replication_slots;
```

### Working CDC Pipeline Components

**What's Proven to Work**:
1. PostgreSQL (Docker) → Debezium → Kafka Connect → Confluent Cloud Topics
2. JSON format for CDC data (simpler than Avro for initial capture)
3. ExtractNewRecordState transform to flatten Debezium envelope
4. Direct consumption from topics to verify data flow

**What Requires More Setup**:
1. Avro format requires schema compatibility between Debezium and custom schemas
2. Flink SQL deployment via CLI (Web Console is much easier)
3. Complex Flink transformations with nested JSON parsing

### Recommended Development Flow

1. **Start with Docker locally**: PostgreSQL + Kafka Connect bridging to Confluent Cloud
2. **Use JSON for CDC**: Simpler than Avro, easy to debug
3. **Verify each step**: PostgreSQL → Topics → Consumers (don't skip validation)
4. **Develop Flink SQL in Web Console**: Interactive, better errors, syntax validation
5. **Automate with CLI later**: After SQL is proven to work

### Common Gotchas

1. **Reserved Keywords in Flink**: `model`, `timestamp`, `date`, `time` - use backticks or rename columns
2. **Topic Must Exist First**: Only `raw-business-events` topic must exist before deploying connectors. Filtered topics are automatically created by Flink.
3. **Credentials in Multiple Places**: Kafka Connect, Flink SQL, Consumer configs all need auth
4. **CLI Token Expiration**: `confluent login` tokens expire; re-authenticate if commands fail
5. **Multiple Statements**: Confluent Cloud Flink CLI doesn't handle multiple CREATE/INSERT well - use Web Console

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

1. Account creation and authentication
2. Environment and cluster setup
3. Topic creation
4. Schema Registry configuration
5. Flink compute pool setup
6. Connector deployment
7. Flink SQL configuration and deployment
8. Testing and verification
9. Troubleshooting common issues

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

# Create raw-business-events topic (only topic that needs manual creation)
confluent kafka topic create raw-business-events --partitions 6

# Note: Filtered topics are automatically created by Flink when it writes to them.
# No manual creation is required for filtered topics in secondary region.
```

**Terraform:**

```hcl
# terraform/confluent/modules/region/topics.tf
# Note: Only raw-business-events needs to be created manually.
# Filtered topics are automatically created by Flink when it writes to them.
resource "confluent_kafka_topic" "raw_business_events" {
  kafka_cluster {
    id = confluent_kafka_cluster.cluster.id
  }
  topic_name       = "raw-business-events"
  partitions_count = 6
  rest_endpoint    = confluent_kafka_cluster.cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster_api_key.id
    secret = confluent_api_key.cluster_api_key.secret
  }
  
  config = {
    "retention.ms" = "604800000"  # 7 days
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
