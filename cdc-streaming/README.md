# CDC Streaming Architecture

A configurable streaming architecture that enables event-based consumers to subscribe to filtered subsets of events. This implementation uses Confluent Platform (Kafka, Schema Registry, Control Center, Connect), Confluent Postgres Source Connector for CDC, and Flink SQL for stream processing.

## Overview

This CDC streaming system captures changes from PostgreSQL database tables and streams them through Kafka, where Flink SQL jobs filter and route events to consumer-specific topics. The architecture is designed for:

- **Configurability at CI/CD Level**: Filtering and routing rules are defined as code (YAML/JSON files and Flink SQL scripts) stored in version control
- **Scalability and Resilience**: Built for horizontal scaling with Kafka partitioning and Flink parallelism
- **Integration with Existing Stack**: Events ingress via existing Ingestion APIs and PostgreSQL database
- **Security and Observability**: Schema Registry for schema enforcement, monitoring via Control Center
- **Cost Efficiency**: Stateful processing with Flink and efficient filtering/routing

## Architecture

### Data Flow

```
[PostgreSQL Entity Tables] 
  → [Confluent Postgres Source Connector (Debezium)] 
  → [Kafka: raw-business-events topic]
  → [Flink SQL Jobs (filtering/routing)]
  → [Consumer-specific Kafka topics]
  → [Example Consumers]
```

### Components

1. **Confluent Platform**:
   - Zookeeper: Coordination service for Kafka
   - Kafka Broker: Message streaming platform
   - Schema Registry: Schema management for Avro
   - Kafka Connect: Connector framework for CDC
   - Control Center: Monitoring and management UI (optional)

2. **Flink Cluster**:
   - JobManager: Coordinates Flink jobs
   - TaskManager: Executes Flink tasks
   - Flink SQL: Declarative stream processing

3. **Postgres Source Connector**:
   - Debezium-based connector
   - Captures INSERT/UPDATE/DELETE from entity tables
   - Publishes to `raw-business-events` topic

4. **Example Consumers**:
   - Loan Consumer: Consumes filtered loan events
   - Service Consumer: Consumes filtered service events

## Prerequisites

- Docker and Docker Compose
- PostgreSQL 15+ (can use existing `postgres-large` service)
- jq (for JSON processing in scripts)
- curl (for API calls)
- Access to existing producer APIs for generating test events

## Quick Start

### 1. Start Infrastructure Services

#### Option A: Docker Compose (Local Development)

Start the Confluent Platform stack and Flink cluster:

```bash
cd cdc-streaming
docker-compose up -d
```

This will start:
- Zookeeper (port 2181)
- Kafka (port 9092)
- Schema Registry (port 8081)
- Kafka Connect (port 8083)
- Flink JobManager (port 8081)
- Flink TaskManager
- Example consumers (loan-consumer, service-consumer)

Optional: Start Control Center for monitoring:

```bash
docker-compose --profile monitoring up -d control-center
```

Access Control Center at: http://localhost:9021

#### Option B: Confluent Cloud (Production)

Set up Confluent Cloud infrastructure:

```bash
# Login to Confluent Cloud
confluent login

# Create environment
confluent environment create prod --stream-governance

# Create Kafka cluster
confluent kafka cluster create prod-kafka-east \
  --cloud aws \
  --region us-east-1 \
  --type dedicated \
  --cku 2

# Create Flink compute pool
confluent flink compute-pool create prod-flink-east \
  --cloud aws \
  --region us-east-1 \
  --max-cfu 4

# Generate API keys for cluster access
confluent api-key create --resource <cluster-id> --description "Cluster API key"
```

**What's Included:**
- Managed Kafka cluster (auto-scaling, multi-zone)
- Schema Registry (auto-enabled with Stream Governance)
- Flink compute pools (managed Flink infrastructure)
- Built-in monitoring and alerting
- High availability and automatic failover

**CI/CD Alternatives:**

**Option B1: Terraform (Infrastructure as Code)**

```hcl
# terraform/confluent/environment.tf
provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

resource "confluent_environment" "prod" {
  display_name = "prod"
  stream_governance {
    package = "ESSENTIALS"
  }
}

resource "confluent_kafka_cluster" "dedicated" {
  display_name = "prod-kafka-east"
  availability = "MULTI_ZONE"
  cloud        = "AWS"
  region       = "us-east-1"
  dedicated {
    cku = 2
  }
  environment {
    id = confluent_environment.prod.id
  }
}

resource "confluent_flink_compute_pool" "prod_flink_east" {
  display_name = "prod-flink-east"
  cloud        = "AWS"
  region       = "us-east-1"
  max_cfu      = 4
  environment {
    id = confluent_environment.prod.id
  }
}
```

**Option B2: REST API**

```python
# scripts/setup-confluent-cloud.py
import requests
import base64

def create_environment(name, api_key, api_secret):
    url = "https://api.confluent.cloud/org/v2/environments"
    auth = base64.b64encode(f'{api_key}:{api_secret}'.encode()).decode()
    headers = {
        "Authorization": f"Basic {auth}",
        "Content-Type": "application/json"
    }
    payload = {
        "display_name": name,
        "stream_governance": {"package": "ESSENTIALS"}
    }
    response = requests.post(url, json=payload, headers=headers)
    return response.json()
```

**Option B3: GitHub Actions**

```yaml
# .github/workflows/setup-confluent-cloud.yml
name: Setup Confluent Cloud Infrastructure
on:
  workflow_dispatch:

jobs:
  setup:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Confluent CLI
        run: brew install confluentinc/tap/cli
      - name: Create Environment
        env:
          CONFLUENT_CLOUD_API_KEY: ${{ secrets.CONFLUENT_API_KEY }}
          CONFLUENT_CLOUD_API_SECRET: ${{ secrets.CONFLUENT_API_SECRET }}
        run: |
          confluent login --api-key $CONFLUENT_CLOUD_API_KEY --api-secret $CONFLUENT_CLOUD_API_SECRET
          confluent environment create prod --stream-governance
          confluent kafka cluster create prod-kafka-east --cloud aws --region us-east-1 --type dedicated --cku 2
```

For detailed Confluent Cloud setup, see [confluent-setup.md](confluent-setup.md).

### 2. Create Kafka Topics

#### Option A: Docker Compose (Local Development)

Create the necessary Kafka topics:

```bash
./scripts/create-topics.sh
```

This creates:
- `raw-business-events` (3 partitions)
- `filtered-loan-events` (3 partitions)
- `filtered-service-events` (3 partitions)
- `filtered-car-events` (3 partitions)
- `filtered-high-value-loans` (3 partitions)

#### Option B: Confluent Cloud (Production)

Create topics in Confluent Cloud:

```bash
# Set cluster context
confluent kafka cluster use <cluster-id>

# Create topics via CLI
confluent kafka topic create raw-business-events --partitions 6
confluent kafka topic create filtered-loan-events --partitions 6
confluent kafka topic create filtered-service-events --partitions 6
confluent kafka topic create filtered-car-events --partitions 6
confluent kafka topic create filtered-high-value-loans --partitions 6

# Or create all topics in batch
for topic in raw-business-events filtered-loan-events filtered-service-events filtered-car-events filtered-high-value-loans; do
  confluent kafka topic create "$topic" --partitions 6
done
```

**CI/CD Alternatives:**

**Option B1: Terraform**

```hcl
# terraform/confluent/kafka-topics.tf
resource "confluent_kafka_topic" "raw_events" {
  kafka_cluster {
    id = confluent_kafka_cluster.dedicated.id
  }
  topic_name       = "raw-business-events"
  partitions_count = 6
  rest_endpoint    = confluent_kafka_cluster.dedicated.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster_api_key.id
    secret = confluent_api_key.cluster_api_key.secret
  }
}

resource "confluent_kafka_topic" "filtered_loan_events" {
  kafka_cluster {
    id = confluent_kafka_cluster.dedicated.id
  }
  topic_name       = "filtered-loan-events"
  partitions_count = 6
  rest_endpoint    = confluent_kafka_cluster.dedicated.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster_api_key.id
    secret = confluent_api_key.cluster_api_key.secret
  }
}

# Repeat for other topics...
```

**Option B2: REST API**

```python
# scripts/create-topics-confluent-cloud.py
import requests
import base64

def create_topic(cluster_id, topic_name, partitions, api_key, api_secret):
    url = f"https://api.confluent.cloud/kafka/v3/clusters/{cluster_id}/topics"
    auth = base64.b64encode(f'{api_key}:{api_secret}'.encode()).decode()
    headers = {
        "Authorization": f"Basic {auth}",
        "Content-Type": "application/json"
    }
    payload = {
        "topic_name": topic_name,
        "partitions_count": partitions
    }
    response = requests.post(url, json=payload, headers=headers)
    return response.json()

# Create all topics
topics = [
    ("raw-business-events", 6),
    ("filtered-loan-events", 6),
    ("filtered-service-events", 6),
    ("filtered-car-events", 6),
    ("filtered-high-value-loans", 6)
]

for topic_name, partitions in topics:
    create_topic(cluster_id, topic_name, partitions, api_key, api_secret)
```

**Option B3: GitHub Actions**

```yaml
# .github/workflows/create-topics.yml
name: Create Kafka Topics
on:
  workflow_dispatch:

jobs:
  create-topics:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Confluent CLI
        run: brew install confluentinc/tap/cli
      - name: Create Topics
        env:
          CONFLUENT_CLOUD_API_KEY: ${{ secrets.CONFLUENT_API_KEY }}
          CONFLUENT_CLOUD_API_SECRET: ${{ secrets.CONFLUENT_API_SECRET }}
        run: |
          confluent login --api-key $CONFLUENT_CLOUD_API_KEY --api-secret $CONFLUENT_CLOUD_API_SECRET
          confluent kafka cluster use ${{ secrets.CLUSTER_ID }}
          for topic in raw-business-events filtered-loan-events filtered-service-events filtered-car-events; do
            confluent kafka topic create "$topic" --partitions 6
          done
```

### 3. Set Up Postgres Connector

#### Option A: Docker Compose (Local Development)

Register the Postgres Source Connector:

```bash
./scripts/setup-connector.sh
```

This will:
- Register the connector with Kafka Connect
- Configure it to capture changes from entity tables
- Start streaming changes to `raw-business-events` topic

#### Option B: Confluent Cloud (Production)

Deploy Postgres Source Connector to Confluent Cloud:

```bash
# Create connector cluster (if not using managed connectors)
# Note: Confluent Cloud supports managed connectors or self-hosted Connect clusters

# Option 1: Using Confluent Cloud managed connectors (if available)
confluent connector create postgres-source \
  --kafka-cluster <cluster-id> \
  --config-file connectors/postgres-source-connector.json

# Option 2: Using self-hosted Connect cluster
# First, create connector cluster or use existing one
confluent connect cluster create connect-cluster-east \
  --cloud aws \
  --region us-east-1 \
  --kafka-cluster <cluster-id>

# Then create connector
confluent connector create postgres-source \
  --connect-cluster <connect-cluster-id> \
  --config-file connectors/postgres-source-connector.json
```

**Connector Configuration for Confluent Cloud:**

Update `connectors/postgres-source-connector.json` with Confluent Cloud settings:

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
    "key.converter.schema.registry.url": "https://<schema-registry-endpoint>",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "https://<schema-registry-endpoint>",
    "value.converter.schema.registry.basic.auth.credentials.source": "USER_INFO",
    "value.converter.schema.registry.basic.auth.user.info": "<api-key>:<api-secret>"
  }
}
```

**CI/CD Alternatives:**

**Option B1: Terraform**

```hcl
# terraform/confluent/connectors.tf
resource "confluent_connector" "postgres_source" {
  environment {
    id = confluent_environment.prod.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.dedicated.id
  }
  
  config_sensitive = {
    "database.password" = var.postgres_password
    "value.converter.schema.registry.basic.auth.user.info" = "${var.schema_registry_api_key}:${var.schema_registry_api_secret}"
  }
  
  config_nonsensitive = {
    "connector.class"          = "io.debezium.connector.postgresql.PostgresConnector"
    "database.hostname"        = var.aurora_endpoint
    "database.port"            = "5432"
    "database.user"            = var.postgres_user
    "database.dbname"          = var.database_name
    "database.server.name"     = "postgres-source"
    "topic.prefix"             = "raw-business-events"
    "table.include.list"       = "public.car_entities,public.loan_entities"
    "plugin.name"              = "pgoutput"
    "tasks.max"                = "1"
    "key.converter"            = "io.confluent.connect.avro.AvroConverter"
    "key.converter.schema.registry.url" = var.schema_registry_url
    "value.converter"          = "io.confluent.connect.avro.AvroConverter"
    "value.converter.schema.registry.url" = var.schema_registry_url
  }
}
```

**Option B2: REST API**

```python
# scripts/deploy-connector-confluent-cloud.py
import requests
import base64
import json

def deploy_connector(env_id, cluster_id, config_file, api_key, api_secret):
    with open(config_file, 'r') as f:
        connector_config = json.load(f)
    
    url = f"https://api.confluent.cloud/connect/v1/environments/{env_id}/clusters/{cluster_id}/connectors"
    auth = base64.b64encode(f'{api_key}:{api_secret}'.encode()).decode()
    headers = {
        "Authorization": f"Basic {auth}",
        "Content-Type": "application/json"
    }
    response = requests.post(url, json=connector_config, headers=headers)
    return response.json()

# Deploy connector
deploy_connector(
    env_id="env-123456",
    cluster_id="lkc-abc123",
    config_file="connectors/postgres-source-connector.json",
    api_key=os.getenv("CONFLUENT_API_KEY"),
    api_secret=os.getenv("CONFLUENT_API_SECRET")
)
```

**Option B3: GitHub Actions**

```yaml
# .github/workflows/deploy-connector.yml
name: Deploy Postgres Connector
on:
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Confluent CLI
        run: brew install confluentinc/tap/cli
      - name: Deploy Connector
        env:
          CONFLUENT_CLOUD_API_KEY: ${{ secrets.CONFLUENT_API_KEY }}
          CONFLUENT_CLOUD_API_SECRET: ${{ secrets.CONFLUENT_API_SECRET }}
        run: |
          confluent login --api-key $CONFLUENT_CLOUD_API_KEY --api-secret $CONFLUENT_CLOUD_API_SECRET
          confluent connector create postgres-source \
            --kafka-cluster ${{ secrets.CLUSTER_ID }} \
            --config-file connectors/postgres-source-connector.json
```

### 4. Deploy Flink SQL Jobs

#### Option A: Confluent Cloud Flink (Recommended for Production)

Deploy Flink SQL statements to Confluent Cloud compute pools:

```bash
# Create compute pool
confluent flink compute-pool create prod-flink-east \
  --cloud aws \
  --region us-east-1 \
  --max-cfu 4

# Deploy SQL statement
confluent flink statement create \
  --compute-pool cp-east-123 \
  --statement-name event-routing-job \
  --statement-file flink-jobs/routing-generated.sql

# Monitor statement
confluent flink statement describe ss-456789 \
  --compute-pool cp-east-123
```

For detailed Confluent Cloud setup, see [confluent-setup.md](confluent-setup.md).

#### Option B: Self-Managed Flink (Docker Compose)

Deploy the Flink SQL routing job to self-managed Flink cluster:

```bash
# Copy SQL file to Flink job directory (already mounted in docker-compose)
# Submit the job via Flink REST API or SQL Client

# Using Flink SQL Client (from Flink container)
docker exec -it cdc-flink-jobmanager ./bin/sql-client.sh embedded -f /opt/flink/jobs/routing.sql

# Or using Flink REST API
curl -X POST http://localhost:8081/v1/jobs \
  -H "Content-Type: application/json" \
  -d @- << EOF
{
  "jobName": "event-routing-job",
  "parallelism": 2
}
EOF
```

**Note**: For production deployments, Confluent Cloud Flink is recommended for managed infrastructure, auto-scaling, and high availability.

#### CI/CD Alternatives for Flink SQL Deployment

**Option A1: Terraform (Infrastructure as Code)**

```hcl
# terraform/confluent/flink-statements.tf
resource "confluent_flink_statement" "event_routing" {
  compute_pool_id = confluent_flink_compute_pool.prod_flink_east.id
  statement_name  = "event-routing-job"
  statement       = file("${path.module}/../cdc-streaming/flink-jobs/routing-generated.sql")
  
  properties = {
    "sql.current-catalog" = "default_catalog"
    "sql.current-database" = "default_database"
  }
  
  rest_endpoint = confluent_flink_compute_pool.prod_flink_east.rest_endpoint
  credentials {
    key    = confluent_api_key.flink_api_key.id
    secret = confluent_api_key.flink_api_key.secret
  }
}
```

**Option A2: REST API (Python/Go Script)**

```python
# scripts/deploy-flink-statement.py
import requests
import base64
import sys

def deploy_flink_statement(compute_pool_id, statement_name, sql_file, api_key, api_secret):
    with open(sql_file, 'r') as f:
        sql_content = f.read()
    
    url = f"https://api.confluent.cloud/flink/v1beta1/compute-pools/{compute_pool_id}/statements"
    auth = base64.b64encode(f'{api_key}:{api_secret}'.encode()).decode()
    headers = {
        "Authorization": f"Basic {auth}",
        "Content-Type": "application/json"
    }
    payload = {
        "statement_name": statement_name,
        "statement": sql_content
    }
    response = requests.post(url, json=payload, headers=headers)
    return response.json()

if __name__ == '__main__':
    deploy_flink_statement(
        compute_pool_id=sys.argv[1],
        statement_name=sys.argv[2],
        sql_file=sys.argv[3],
        api_key=sys.argv[4],
        api_secret=sys.argv[5]
    )
```

**Option A3: GitHub Actions Workflow**

```yaml
# .github/workflows/deploy-flink-job.yml
name: Deploy Flink SQL Job
on:
  push:
    branches: [main]
    paths:
      - 'cdc-streaming/flink-jobs/routing-generated.sql'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v3
      - name: Setup Confluent CLI
        run: brew install confluentinc/tap/cli
      - name: Login to Confluent
        env:
          CONFLUENT_CLOUD_API_KEY: ${{ secrets.CONFLUENT_API_KEY }}
          CONFLUENT_CLOUD_API_SECRET: ${{ secrets.CONFLUENT_API_SECRET }}
        run: confluent login --api-key $CONFLUENT_CLOUD_API_KEY --api-secret $CONFLUENT_CLOUD_API_SECRET
      - name: Deploy Flink Statement
        run: |
          confluent flink statement create \
            --compute-pool ${{ secrets.COMPUTE_POOL_ID }} \
            --statement-name event-routing-job \
            --statement-file cdc-streaming/flink-jobs/routing-generated.sql
      - name: Verify Deployment
        run: |
          confluent flink statement list --compute-pool ${{ secrets.COMPUTE_POOL_ID }}
```

**Option A4: Jenkins Pipeline**

```groovy
// Jenkinsfile
pipeline {
    agent any
    environment {
        CONFLUENT_API_KEY = credentials('confluent-api-key')
        CONFLUENT_API_SECRET = credentials('confluent-api-secret')
        COMPUTE_POOL_ID = 'cp-east-123'
    }
    stages {
        stage('Deploy Flink SQL') {
            steps {
                sh '''
                    confluent login --api-key ${CONFLUENT_API_KEY} --api-secret ${CONFLUENT_API_SECRET}
                    confluent flink statement create \
                        --compute-pool ${COMPUTE_POOL_ID} \
                        --statement-name event-routing-job \
                        --statement-file cdc-streaming/flink-jobs/routing-generated.sql
                '''
            }
        }
        stage('Verify Deployment') {
            steps {
                sh '''
                    confluent flink statement list --compute-pool ${COMPUTE_POOL_ID}
                '''
            }
        }
    }
}
```

**Option B1: Docker Compose in CI/CD**

```yaml
# .github/workflows/deploy-flink-docker.yml
name: Deploy Flink SQL to Docker
on:
  push:
    branches: [main]
    paths:
      - 'cdc-streaming/flink-jobs/routing-generated.sql'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Start Flink Cluster
        run: |
          cd cdc-streaming
          docker-compose up -d flink-jobmanager flink-taskmanager
      - name: Wait for Flink
        run: |
          timeout 60 bash -c 'until curl -f http://localhost:8081/overview; do sleep 2; done'
      - name: Deploy SQL Job
        run: |
          docker exec cdc-flink-jobmanager \
            ./bin/sql-client.sh embedded \
            -f /opt/flink/jobs/routing-generated.sql
      - name: Verify Job
        run: |
          curl http://localhost:8081/jobs | jq
```

**Option B2: Kubernetes Deployment**

```yaml
# k8s/flink-job-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: flink-routing-sql
data:
  routing.sql: |
    # SQL content from routing-generated.sql
---
apiVersion: batch/v1
kind: Job
metadata:
  name: deploy-flink-sql
spec:
  template:
    spec:
      containers:
      - name: flink-sql-client
        image: flink:1.18
        command: ["/bin/sh", "-c"]
        args:
          - |
            ./bin/sql-client.sh embedded \
              -f /opt/flink/jobs/routing.sql
        volumeMounts:
        - name: sql-config
          mountPath: /opt/flink/jobs
      volumes:
      - name: sql-config
        configMap:
          name: flink-routing-sql
      restartPolicy: Never
```

**Option B3: Helm Chart Deployment**

```yaml
# k8s/helm/flink-sql/values.yaml
flink:
  jobManager:
    serviceType: ClusterIP
  taskManager:
    replicas: 2
  sqlJobs:
    - name: event-routing-job
      sqlFile: routing-generated.sql
      parallelism: 2
```

**Option B4: Terraform for Self-Managed Flink**

```hcl
# terraform/flink/self-managed.tf
resource "kubernetes_config_map" "flink_sql" {
  metadata {
    name      = "flink-routing-sql"
    namespace = "flink"
  }
  data = {
    "routing.sql" = file("${path.module}/../cdc-streaming/flink-jobs/routing-generated.sql")
  }
}

resource "kubernetes_job" "deploy_flink_sql" {
  metadata {
    name      = "deploy-flink-sql"
    namespace = "flink"
  }
  spec {
    template {
      spec {
        container {
          name  = "sql-client"
          image = "flink:1.18"
          command = ["/bin/sh", "-c"]
          args = [
            "./bin/sql-client.sh embedded -f /opt/flink/jobs/routing.sql"
          ]
          volume_mount {
            name       = "sql-config"
            mount_path = "/opt/flink/jobs"
          }
        }
        volume {
          name = "sql-config"
          config_map {
            name = kubernetes_config_map.flink_sql.metadata[0].name
          }
        }
        restart_policy = "Never"
      }
    }
  }
}
```

### 5. Verify Pipeline

#### Option A: Docker Compose (Local Development)

Test the end-to-end pipeline:

```bash
./scripts/test-pipeline.sh
```

#### Option B: Confluent Cloud (Production)

Verify the pipeline in Confluent Cloud:

```bash
# Check connector status
confluent connector describe postgres-source-connector

# Check topics have messages
confluent kafka topic describe raw-business-events --output json | jq '.partitions[].offset'

# Check Flink statement is running
confluent flink statement list --compute-pool <compute-pool-id>

# Check filtered topics have messages
confluent kafka topic describe filtered-loan-events --output json | jq '.partitions[].offset'

# Check consumer groups
confluent kafka consumer-group describe <consumer-group-name>

# Consume sample messages
confluent kafka topic consume raw-business-events --max-messages 10
confluent kafka topic consume filtered-loan-events --max-messages 10
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment
- Check connector status and metrics
- Verify topics have messages and throughput
- Monitor Flink statement execution and metrics
- Check consumer group lag and offsets

## Configuration

### Filter Configuration

Edit `flink-jobs/filters.yaml` to modify filtering rules. See `flink-jobs/filters-examples.yaml` for comprehensive examples.

**Code Generation**: Flink SQL queries can be automatically generated from YAML filter configurations. See [CODE_GENERATION.md](CODE_GENERATION.md) for details.

To generate SQL from filters:
```bash
# Validate filters
python scripts/validate-filters.py

# Generate SQL
python scripts/generate-flink-sql.py \
  --config flink-jobs/filters.yaml \
  --output flink-jobs/routing-generated.sql

# Validate generated SQL
python scripts/validate-sql.py --sql flink-jobs/routing-generated.sql
```

Basic example:

```yaml
filters:
  - id: loan-events-filter
    name: "Loan Events Filter"
    consumerId: loan-consumer
    outputTopic: filtered-loan-events
    conditions:
      - field: eventHeader.eventName
        operator: in
        values: ["LoanCreated", "LoanPaymentSubmitted"]
    enabled: true
```

**Available Operators:**
- `equals`: Exact match
- `in`: Match any value in list
- `greaterThan`: Numeric comparison
- `lessThan`: Numeric comparison
- `greaterThanOrEqual`: Numeric comparison
- `lessThanOrEqual`: Numeric comparison
- `between`: Range check
- `matches`: Regex pattern matching
- `notIn`: Exclude values in list

**Example Filter Types:**
- **Event Name Filter**: Filter by specific event types
- **Value-Based Filter**: Filter by numeric thresholds (e.g., loan amount > 100000)
- **Status-Based Filter**: Filter by entity status (e.g., active loans only)
- **Time-Based Filter**: Filter by timestamp (e.g., last 24 hours)
- **Multi-Condition Filter**: Combine multiple conditions with AND logic
- **Pattern Matching**: Filter using regex patterns

See `flink-jobs/filters-examples.yaml` for 20+ example configurations.

### Flink SQL Jobs

**Option 1: Generated SQL (Recommended)**
- SQL is automatically generated from `filters.yaml`
- See [CODE_GENERATION.md](CODE_GENERATION.md) for code generation guide
- Generated file: `flink-jobs/routing-generated.sql`

**Option 2: Manual SQL**
- Edit `flink-jobs/routing.sql` manually for custom queries
- See `flink-jobs/routing-examples.sql` for comprehensive examples

Basic example:

```sql
-- Route Loan-related events
INSERT INTO filtered_loan_events
SELECT 
    eventHeader,
    eventBody,
    sourceMetadata,
    ROW('loan-events-filter', 'loan-consumer', UNIX_TIMESTAMP() * 1000) AS filterMetadata
FROM raw_business_events
WHERE eventHeader.eventName = 'LoanCreated' OR eventHeader.eventName = 'LoanPaymentSubmitted';
```

**Example Query Types:**
- **Basic Filtering**: Filter by event name, entity type, or field values
- **Value-Based Filtering**: Numeric comparisons (>, <, >=, <=, BETWEEN)
- **Status Filtering**: Filter by entity status or state
- **Time-Based Filtering**: Filter by timestamp or time windows
- **Pattern Matching**: Use LIKE or REGEXP for pattern matching
- **Windowed Aggregations**: Tumbling or sliding window aggregations
- **Multi-Topic Routing**: Route to different topics based on conditions
- **Joins**: Join with reference data tables
- **Error Handling**: Route invalid events to dead letter queue

See `flink-jobs/routing-examples.sql` for 19+ example SQL queries including:
- Basic and advanced filtering
- Windowed aggregations
- Multi-topic routing
- Join operations
- Error handling patterns

### Postgres Connector

Edit `connectors/postgres-source-connector.json` to modify connector configuration:

```json
{
  "name": "postgres-source-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "postgres-large",
    "table.include.list": "public.car_entities,public.loan_entities,..."
  }
}
```

## Monitoring

### Kafka Topics

#### Option A: Docker Compose (Local Development)

Monitor topic messages:

```bash
# Raw events
docker exec -it cdc-kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic raw-business-events \
  --from-beginning

# Filtered loan events
docker exec -it cdc-kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic filtered-loan-events \
  --from-beginning
```

#### Option B: Confluent Cloud (Production)

Monitor topics via Confluent Cloud:

```bash
# Consume messages via CLI
confluent kafka topic consume raw-business-events --from-beginning
confluent kafka topic consume filtered-loan-events --from-beginning

# View topic details and metrics
confluent kafka topic describe raw-business-events
confluent kafka topic describe filtered-loan-events

# View topic metrics (message count, throughput, etc.)
confluent kafka topic describe raw-business-events --output json | jq '.metrics'
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment → Topics
- View real-time metrics: throughput, latency, message count
- Monitor consumer lag per topic
- View partition-level details

**Via REST API:**

```python
# scripts/monitor-topics-confluent-cloud.py
import requests
import base64

def get_topic_metrics(cluster_id, topic_name, api_key, api_secret):
    url = f"https://api.confluent.cloud/kafka/v3/clusters/{cluster_id}/topics/{topic_name}"
    auth = base64.b64encode(f'{api_key}:{api_secret}'.encode()).decode()
    headers = {"Authorization": f"Basic {auth}"}
    response = requests.get(url, headers=headers)
    return response.json()
```

### Consumer Logs

#### Option A: Docker Compose (Local Development)

View consumer application logs:

```bash
# Loan consumer
docker logs -f cdc-loan-consumer

# Service consumer
docker logs -f cdc-service-consumer
```

#### Option B: Confluent Cloud (Production)

Monitor consumer groups and lag:

```bash
# View consumer groups
confluent kafka consumer-group list

# Describe consumer group (shows lag, offsets)
confluent kafka consumer-group describe loan-consumer-group

# View consumer lag details
confluent kafka consumer-group describe loan-consumer-group --output json | jq '.lag'

# Monitor consumer group metrics
confluent kafka consumer-group describe loan-consumer-group --output json | jq '.metrics'
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment → Consumers
- View consumer group lag, offsets, and throughput
- Monitor consumer group health
- Set up alerts for lag thresholds

**Application Logs:**
- Access application logs via your logging infrastructure (CloudWatch, Datadog, etc.)
- Consumer applications should log to standard output/structured logging
- Use log aggregation tools for centralized monitoring

### Flink Dashboard

#### Option A: Docker Compose (Local Development)

Access Flink Web UI at: http://localhost:8081

- View running jobs
- Monitor job metrics
- Check checkpoint status
- View task manager details

#### Option B: Confluent Cloud (Production)

Monitor Flink statements via Confluent Cloud:

```bash
# List all Flink statements
confluent flink statement list --compute-pool <compute-pool-id>

# Describe statement (shows status, metrics, logs)
confluent flink statement describe <statement-id> --compute-pool <compute-pool-id>

# View statement metrics
confluent flink statement describe <statement-id> \
  --compute-pool <compute-pool-id> \
  --output json | jq '.metrics'

# View statement logs
confluent flink statement logs <statement-id> --compute-pool <compute-pool-id>

# Monitor compute pool
confluent flink compute-pool describe <compute-pool-id>
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment → Flink
- View statement status, metrics, and logs
- Monitor compute pool CFU utilization
- View throughput, latency, and backpressure metrics
- Access statement execution logs

**Key Metrics to Monitor:**
- `numRecordsInPerSecond`: Input records per second
- `numRecordsOutPerSecond`: Output records per second
- `latency`: End-to-end latency
- `backpressured-time-per-second`: Backpressure time
- `checkpoint-duration`: Checkpoint duration
- `cfu-usage`: Current CFU utilization

### Control Center / Confluent Cloud Console

#### Option A: Docker Compose (Local Development)

Access Control Center at: http://localhost:9021 (if enabled)

- Monitor Kafka cluster health
- View topic metrics
- Monitor connectors
- View consumer lag

#### Option B: Confluent Cloud Console (Production)

Access Confluent Cloud Console at: https://confluent.cloud

**Dashboard Features:**
- **Overview**: System health, throughput, and key metrics
- **Topics**: Topic-level metrics, partitions, and configuration
- **Consumers**: Consumer group lag, offsets, and throughput
- **Connectors**: Connector status, metrics, and logs
- **Flink**: Statement status, metrics, and compute pool utilization
- **Schema Registry**: Schema versions, compatibility, and evolution
- **Alerts**: Configure alerts for lag, throughput, errors

**Built-in Monitoring:**
- Real-time metrics dashboards
- Historical metrics and trends
- Custom alert rules
- Performance insights and recommendations
- Cost optimization suggestions

## Testing

### Generate Test Events

#### Using the Test Data Generation Script (Recommended)

Use the provided script to generate test data using k6 and the Java REST API:

```bash
cd cdc-streaming/scripts

# Basic usage (10 virtual users for 30 seconds)
./generate-test-data.sh

# Custom configuration
VUS=20 DURATION=60s PAYLOAD_SIZE=4k ./generate-test-data.sh

# With request rate limit
VUS=50 DURATION=120s RATE=10 PAYLOAD_SIZE=8k ./generate-test-data.sh
```

Configuration options:
- `VUS`: Number of virtual users (default: 10)
- `DURATION`: Test duration (default: 30s)
- `RATE`: Request rate per second (optional)
- `PAYLOAD_SIZE`: Payload size - 400b, 4k, 8k, 32k, 64k (default: 4k)
- `API_HOST`: API hostname (default: producer-api-java-rest)
- `API_PORT`: API port (default: 8081)

The script will:
1. Generate events using k6 load testing tool
2. Send events to the Java REST API
3. Events are stored in PostgreSQL
4. CDC connector captures changes and streams to Kafka
5. Flink filters and routes events to consumer topics

#### Manual Event Generation

You can also manually generate test events using curl:

```bash
# Example: Using Java REST API
curl -X POST http://localhost:9081/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "eventHeader": {
      "eventName": "LoanCreated",
      "eventType": "LoanCreated"
    },
    "eventBody": {
      "entities": [{
        "entityType": "Loan",
        "entityId": "loan-123",
        "updatedAttributes": {
          "loanAmount": 50000,
          "balance": 50000,
          "status": "active"
        }
      }]
    }
  }'
```

### Verify Event Flow

1. **Check Raw Events**: Verify events appear in `raw-business-events` topic
2. **Check Filtered Events**: Verify filtered events appear in consumer-specific topics
3. **Check Consumer Logs**: Verify consumers receive and process events

### Validate Data in Kafka and Flink

#### Validate Kafka Topics

Use the validation script to check Kafka topics:

```bash
cd cdc-streaming/scripts

# Validate raw events topic
./validate-kafka.sh raw-business-events

# Validate filtered loan events
./validate-kafka.sh filtered-loan-events

# Validate with custom limit
LIMIT=20 ./validate-kafka.sh filtered-service-events
```

The script will:
- Check if the topic exists
- Show topic information (partitions, replication)
- Display message count
- Show sample messages
- Validate message structure (JSON format)

#### Validate Flink Jobs

Use the validation script to check Flink job status:

```bash
cd cdc-streaming/scripts

# Validate all Flink jobs
./validate-flink.sh

# Validate specific job by name
./validate-flink.sh event-routing-job
```

The script will:
- Check Flink cluster status
- List all jobs
- Show job details (status, metrics, operators)
- Display processing metrics (records in/out, throughput)
- Check for errors or failures

#### Manual Validation

You can also manually validate using Kafka and Flink tools:

```bash
# Check Kafka topic messages
docker exec -it cdc-kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic raw-business-events \
  --from-beginning \
  --max-messages 10

# Check Flink job status via REST API
curl http://localhost:8081/jobs | jq

# Check Flink job metrics
curl http://localhost:8081/jobs/<job-id>/metrics | jq
```

## Troubleshooting

### Connector Not Starting

#### Option A: Docker Compose (Local Development)

Check connector status:

```bash
curl http://localhost:8083/connectors/postgres-source-connector/status | jq
```

Common issues:
- PostgreSQL not accessible: Check network connectivity
- Replication slot already exists: Drop and recreate slot
- Missing tables: Ensure tables exist in PostgreSQL

#### Option B: Confluent Cloud (Production)

Check connector status:

```bash
# Via CLI
confluent connector describe postgres-source-connector

# View connector status and metrics
confluent connector describe postgres-source-connector --output json | jq '.status'

# View connector logs
confluent connector logs postgres-source-connector

# Check connector health
confluent connector health-check postgres-source-connector
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment → Connectors
- View connector status, metrics, and logs
- Check connector task status and errors
- View connector configuration

**Common Issues:**
- **PostgreSQL not accessible**: Verify network connectivity, security groups, and VPC endpoints
- **Replication slot already exists**: Drop and recreate slot: `SELECT pg_drop_replication_slot('debezium_slot');`
- **Missing tables**: Ensure tables exist in PostgreSQL and are included in `table.include.list`
- **Schema Registry authentication**: Verify API keys for Schema Registry access
- **Connector cluster unavailable**: Check connector cluster status and health

**Troubleshooting Steps:**
1. Check connector status: `confluent connector describe <connector-name>`
2. Review connector logs: `confluent connector logs <connector-name>`
3. Verify PostgreSQL connectivity from connector cluster
4. Check Schema Registry connectivity and authentication
5. Verify topic exists: `confluent kafka topic describe <topic-name>`
6. Restart connector: `confluent connector update <connector-name> --config-file <config-file>`

### Flink Job Failing

#### Option A: Docker Compose (Local Development)

Check Flink job logs:

```bash
docker logs cdc-flink-jobmanager
docker logs cdc-flink-taskmanager
```

Common issues:
- Schema mismatch: Verify Avro schemas in Schema Registry
- Topic not found: Ensure topics are created
- Serialization errors: Check schema compatibility

#### Option B: Confluent Cloud (Production)

Check Flink statement status and logs:

```bash
# Check statement status
confluent flink statement describe <statement-id> --compute-pool <compute-pool-id>

# View statement logs
confluent flink statement logs <statement-id> --compute-pool <compute-pool-id>

# Check compute pool status
confluent flink compute-pool describe <compute-pool-id>

# View statement metrics (includes error rates)
confluent flink statement describe <statement-id> \
  --compute-pool <compute-pool-id> \
  --output json | jq '.metrics'

# List all statements in compute pool
confluent flink statement list --compute-pool <compute-pool-id>
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment → Flink
- View statement status, metrics, and execution logs
- Check for backpressure, checkpoint failures, or errors
- Monitor CFU utilization and auto-scaling events

**Common Issues:**
- **Schema mismatch**: Verify Avro schemas in Schema Registry match SQL table definitions
- **Topic not found**: Ensure topics exist: `confluent kafka topic list`
- **Serialization errors**: Check schema compatibility and Schema Registry authentication
- **Checkpoint failures**: Check checkpoint configuration and storage access
- **Backpressure**: Increase CFU limit or optimize SQL queries
- **Statement not starting**: Check SQL syntax, bootstrap servers, and API key permissions

**Troubleshooting Steps:**
1. Check statement status: `confluent flink statement describe <statement-id> --compute-pool <pool-id>`
2. Review statement logs: `confluent flink statement logs <statement-id> --compute-pool <pool-id>`
3. Verify topics exist: `confluent kafka topic list`
4. Check Schema Registry: `confluent schema-registry subject list`
5. Verify compute pool health: `confluent flink compute-pool describe <pool-id>`
6. Check CFU utilization: Monitor if max CFU limit is reached
7. Update statement: `confluent flink statement update <statement-id> --compute-pool <pool-id> --statement-file <sql-file>`

### Consumers Not Receiving Events

#### Option A: Docker Compose (Local Development)

Check consumer configuration:

```bash
docker logs cdc-loan-consumer
docker logs cdc-service-consumer
```

Common issues:
- Wrong topic name: Verify topic names match
- Consumer group offset: Reset consumer group if needed
- Network issues: Verify Kafka connectivity

#### Option B: Confluent Cloud (Production)

Check consumer group status and lag:

```bash
# View consumer groups
confluent kafka consumer-group list

# Describe consumer group (shows lag, offsets, members)
confluent kafka consumer-group describe <consumer-group-name>

# Check consumer lag
confluent kafka consumer-group describe <consumer-group-name> --output json | jq '.lag'

# View consumer group metrics
confluent kafka consumer-group describe <consumer-group-name> --output json | jq '.metrics'

# Check topic message count
confluent kafka topic describe <topic-name> --output json | jq '.partitions[].offset'
```

**Via Confluent Cloud Console:**
- Navigate to: https://confluent.cloud → Your Environment → Consumers
- View consumer group lag, offsets, and member status
- Check if consumers are actively consuming
- Monitor consumer group health and throughput

**Common Issues:**
- **Wrong topic name**: Verify topic names match: `confluent kafka topic list`
- **Consumer group offset**: Check offsets: `confluent kafka consumer-group describe <group-name>`
- **Network issues**: Verify bootstrap servers and network connectivity
- **No messages in topic**: Check if Flink jobs are writing to topics
- **Consumer not running**: Verify consumer application is running and connected
- **Authentication issues**: Verify API keys and credentials

**Troubleshooting Steps:**
1. Check consumer group status: `confluent kafka consumer-group describe <group-name>`
2. Verify topic exists and has messages: `confluent kafka topic describe <topic-name>`
3. Check consumer lag: If lag is high, consumers may be slow or stopped
4. Verify bootstrap servers in consumer configuration
5. Check API keys and authentication
6. Review consumer application logs (via your logging infrastructure)
7. Reset consumer group if needed: `confluent kafka consumer-group delete <group-name>` (then restart consumers)

## File Structure

```
cdc-streaming/
├── docker-compose.yml              # Docker Compose configuration
├── README.md                       # This file
├── .env.example                    # Environment variables template
├── connectors/
│   └── postgres-source-connector.json  # Postgres connector config
├── flink-jobs/
│   ├── filters.yaml               # Filter configuration
│   ├── filters-examples.yaml       # Example filter configurations
│   ├── routing.sql                # Flink SQL routing job
│   └── routing-examples.sql       # Example Flink SQL queries
├── schemas/
│   ├── raw-event.avsc             # Avro schema for raw events
│   └── filtered-event.avsc        # Avro schema for filtered events
├── consumers/
│   ├── loan-consumer/             # Loan event consumer
│   │   ├── Dockerfile
│   │   ├── consumer.py
│   │   └── requirements.txt
│   └── service-consumer/           # Service event consumer
│       ├── Dockerfile
│       ├── consumer.py
│       └── requirements.txt
├── config/
│   ├── kafka-connect.properties   # Kafka Connect worker config
│   └── flink-conf.yaml            # Flink configuration
└── scripts/
    ├── setup-connector.sh          # Connector setup script
    ├── create-topics.sh            # Topic creation script
    ├── test-pipeline.sh            # Pipeline test script
    ├── generate-test-data.sh       # Generate test data using k6 and Java REST API
    ├── validate-kafka.sh           # Validate data in Kafka topics
    └── validate-flink.sh           # Validate Flink job status and metrics
```

## Integration with Existing Stack

This CDC streaming system integrates with:

- **PostgreSQL Database**: Uses existing `postgres-large` service or connects to existing PostgreSQL instance
- **Producer APIs**: Events generated by existing producer APIs (Go, Rust, Java) are captured via CDC
- **Event Schema**: Aligns with existing event structure from `data/event-templates.json`
- **Entity Types**: Supports existing entity types: Car, Loan, LoanPayment, ServiceRecord

## Production Considerations

For production deployment:

1. **Multi-Region**: Use Confluent Cluster Linking for multi-region replication
2. **Security**: Enable SASL/SSL for Kafka, use IAM roles for AWS
3. **Monitoring**: Integrate with ELK stack for centralized logging
4. **CI/CD**: Deploy Flink jobs via Jenkins pipelines with Terraform or REST API
5. **Schema Evolution**: Use Schema Registry compatibility modes for schema evolution
6. **Backup**: Configure Flink savepoints for job state backup
7. **Scaling**: Adjust Flink parallelism and Kafka partitions based on load

## References

- [Confluent Platform Documentation](https://docs.confluent.io/)
- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Apache Flink SQL](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)

## License

See main project LICENSE file.

