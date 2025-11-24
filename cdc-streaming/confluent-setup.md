# Execute Pipeline with Confluent Cloud Kafka and Flink

## Overview

This plan provides step-by-step instructions to execute the CDC streaming pipeline using:

- **Confluent Cloud**: Managed Kafka clusters, Schema Registry, and Flink compute pools
- **AWS Infrastructure**: VPC connectivity via PrivateLink/VPC Peering for secure access
- **PostgreSQL**: Source database for CDC (Aurora Postgres)
- **CI/CD Integration**: Jenkins pipelines with Terraform for infrastructure as code
- **Multi-Region**: Active-active setup across us-east-1 and us-west-2

## Prerequisites Check

1. Confluent Cloud account with enterprise billing enabled
2. AWS account with VPCs in target regions (us-east-1, us-west-2)
3. Confluent CLI installed (`brew install confluentinc/tap/cli` or equivalent)
4. Terraform installed with Confluent provider (~v1.5+)
5. Jenkins access for CI/CD automation
6. HashiCorp Vault for API key management
7. Access to Aurora Postgres database

## Execution Steps

### Step 1: Confluent Cloud Account and Environment Setup

**1.1 Sign In/Create Account:**

- Access https://confluent.cloud
- Log in or create organization
- Enable multi-factor auth for compliance

**1.2 Create Environment:**

```bash
# Via Console: Add environment with "Stream Governance" package
# Via CLI:
confluent login
confluent environment create <env-name> --stream-governance
```

**1.3 API/CLI Setup:**

```bash
# Install Confluent CLI
brew install confluentinc/tap/cli

# Login and store credentials in Vault for Jenkins
confluent login
# Store API keys in HashiCorp Vault
```

**1.4 Terraform Integration:**

- Configure Confluent Terraform provider in Jenkins
- Use API keys from Vault for IaC deployments

**1.5 CI/CD Alternatives:**

**Option A: Terraform (Infrastructure as Code)**

```hcl
# terraform/confluent/environment.tf
provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

resource "confluent_environment" "prod" {
  display_name = var.environment_name
  stream_governance {
    package = "ESSENTIALS" # or "ADVANCED"
  }
}
```

**Option B: REST API (Python/Go Script)**

```python
# scripts/setup-environment.py
import requests
import base64
import os

def create_environment(name, api_key, api_secret):
    url = "https://api.confluent.cloud/org/v2/environments"
    headers = {
        "Authorization": f"Basic {base64.b64encode(f'{api_key}:{api_secret}'.encode()).decode()}"
    }
    payload = {
        "display_name": name,
        "stream_governance": {"package": "ESSENTIALS"}
    }
    response = requests.post(url, json=payload, headers=headers)
    return response.json()
```

**Option C: GitHub Actions Workflow**

```yaml
# .github/workflows/confluent-setup.yml
name: Setup Confluent Environment
on:
  workflow_dispatch:
    inputs:
      environment_name:
        required: true

jobs:
  setup:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Confluent CLI
        run: |
          brew install confluentinc/tap/cli
      - name: Login to Confluent
        env:
          CONFLUENT_CLOUD_EMAIL: ${{ secrets.CONFLUENT_CLOUD_EMAIL }}
          CONFLUENT_CLOUD_PASSWORD: ${{ secrets.CONFLUENT_CLOUD_PASSWORD }}
        run: confluent login --save
      - name: Create Environment
        run: |
          confluent environment create ${{ inputs.environment_name }} --stream-governance
      - name: Store API Keys in Vault
        run: |
          # Store keys using Vault CLI or API
```

**Option D: Jenkins Pipeline**

```groovy
// Jenkinsfile
pipeline {
    agent any
    environment {
        CONFLUENT_API_KEY = credentials('confluent-api-key')
        CONFLUENT_API_SECRET = credentials('confluent-api-secret')
    }
    stages {
        stage('Setup Environment') {
            steps {
                sh '''
                    confluent login --api-key ${CONFLUENT_API_KEY} --api-secret ${CONFLUENT_API_SECRET}
                    confluent environment create ${ENV_NAME} --stream-governance
                '''
            }
        }
    }
}
```

**Verification:**

```bash
# Check environment
confluent environment list

# Verify CLI access
confluent current
```

### Step 2: Create Kafka Clusters in Confluent Cloud

**2.1 Create Dedicated Cluster (us-east-1):**

```bash
# Via Console: "Add cluster" > "Dedicated" > AWS > us-east-1 > Multi-zone
# Via CLI:
confluent kafka cluster create prod-kafka-east \
  --cloud aws \
  --region us-east-1 \
  --type dedicated \
  --cku 2
```

**2.2 Configure Schema Registry:**

- Auto-enabled with Stream Governance
- Set compatibility mode (e.g., BACKWARD) via Console

**2.3 Create Topics:**

```bash
# Via Console: "Topics" > "Create topic"
# Via CLI:
confluent kafka topic create raw_business_events --partitions 6
confluent kafka topic create filtered_loan_events --partitions 6
confluent kafka topic create filtered_service_events --partitions 6
confluent kafka topic create filtered_car_events --partitions 6
```

**2.4 Generate API Keys:**

```bash
# Via Console: "API access" > "Create API key"
# Download and store in Vault
# For Ingestion API: Use in Spring Kafka Producer config
```

**2.5 CI/CD Alternatives:**

**Option A: Terraform**

```hcl
# terraform/confluent/kafka-cluster.tf
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

resource "confluent_kafka_topic" "raw_events" {
  kafka_cluster {
    id = confluent_kafka_cluster.dedicated.id
  }
  topic_name       = "raw_business_events"
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
  topic_name       = "filtered_loan_events"
  partitions_count = 6
  rest_endpoint    = confluent_kafka_cluster.dedicated.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster_api_key.id
    secret = confluent_api_key.cluster_api_key.secret
  }
}

resource "confluent_kafka_topic" "filtered_service_events" {
  kafka_cluster {
    id = confluent_kafka_cluster.dedicated.id
  }
  topic_name       = "filtered_service_events"
  partitions_count = 6
  rest_endpoint    = confluent_kafka_cluster.dedicated.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster_api_key.id
    secret = confluent_api_key.cluster_api_key.secret
  }
}

resource "confluent_kafka_topic" "filtered_car_events" {
  kafka_cluster {
    id = confluent_kafka_cluster.dedicated.id
  }
  topic_name       = "filtered_car_events"
  partitions_count = 6
  rest_endpoint    = confluent_kafka_cluster.dedicated.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster_api_key.id
    secret = confluent_api_key.cluster_api_key.secret
  }
}
```

**Option B: REST API Script**

```python
# scripts/create-kafka-cluster.py
import requests
import base64

def create_kafka_cluster(env_id, name, region, cku, api_key, api_secret):
    url = "https://api.confluent.cloud/cmk/v2/clusters"
    auth = base64.b64encode(f'{api_key}:{api_secret}'.encode()).decode()
    headers = {
        "Authorization": f"Basic {auth}",
        "Content-Type": "application/json"
    }
    payload = {
        "spec": {
            "display_name": name,
            "availability": "MULTI_ZONE",
            "cloud": "AWS",
            "region": region,
            "config": {
                "kind": "Basic",
                "dedicated": {"cku": cku}
            },
            "environment": {"id": env_id}
        }
    }
    response = requests.post(url, json=payload, headers=headers)
    return response.json()

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
```

**Option C: GitOps with ArgoCD/Flux**

```yaml
# k8s/confluent/kafka-cluster.yaml
apiVersion: confluent.cloud/v1
kind: KafkaCluster
metadata:
  name: prod-kafka-east
spec:
  displayName: prod-kafka-east
  availability: MULTI_ZONE
  cloud: AWS
  region: us-east-1
  dedicated:
    cku: 2
```

**Verification:**

```bash
# List clusters
confluent kafka cluster list

# List topics
confluent kafka topic list
```

### Step 3: Set Up AWS PrivateLink Connectivity

**3.1 Create Confluent Network:**

- Console: "Network management" > "Add network" > AWS > PrivateLink
- Specify /16 CIDR (non-overlapping, e.g., 10.1.0.0/16)

**3.2 Create PrivateLink Attachment:**

- Console: For environment, create attachment
- Get service name from Confluent

**3.3 AWS Side Setup:**

- VPC Console > "Endpoints" > Create interface endpoint
- Use Confluent service name
- Select VPC/subnets

**3.4 Accept Connection:**

- Confluent Console: Approve the attachment connection

**3.5 DNS Setup:**

- Use private DNS (flink.<region>.aws.private.confluent.cloud)
- Configure Route 53 resolver for forwarding

**3.6 Multi-Region:**

- Repeat per region (us-east-1, us-west-2)
- Use Transit Gateway for cross-region routing

**3.7 CI/CD Alternatives:**

**Option A: Terraform (AWS + Confluent)**

```hcl
# terraform/aws/privatelink.tf
resource "aws_vpc_endpoint" "confluent" {
  vpc_id              = var.vpc_id
  service_name        = var.confluent_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.confluent.id]
}

# Confluent side - requires Confluent Terraform provider
resource "confluent_network" "aws_privatelink" {
  display_name     = "aws-privatelink-network"
  cloud            = "AWS"
  region           = "us-east-1"
  connection_types = ["PRIVATELINK"]
  zones            = ["use1-az1", "use1-az2", "use1-az3"]
  environment {
    id = confluent_environment.prod.id
  }
}
```

**Option B: AWS CDK/CloudFormation**

```python
# cdk/confluent_privatelink.py
from aws_cdk import Stack, aws_ec2

class ConfluentPrivateLinkStack(Stack):
    def __init__(self, scope, id, **kwargs):
        super().__init__(scope, id, **kwargs)
        
        vpc_endpoint = aws_ec2.VpcEndpoint(
            self, "ConfluentEndpoint",
            vpc=vpc,
            service=aws_ec2.VpcEndpointService(
                service_name=confluent_service_name
            ),
            subnets=subnets
        )
```

**Verification:**

```bash
# Test connectivity from EKS pod
curl -k https://flink.us-east-1.aws.private.confluent.cloud
```

### Step 4: Create Flink Compute Pools

**4.1 Enable Flink in Environment:**

- Console: Environment > "Flink" tab > Enable (requires Dedicated cluster)

**4.2 Create Compute Pool (us-east-1):**

```bash
# Via Console: "Compute pools" > "Create pool"
# Via CLI:
confluent flink compute-pool create prod-flink-east \
  --cloud aws \
  --region us-east-1 \
  --max-cfu 4
```

**4.3 Create Service Account:**

```bash
# Via Console: "Principals" > "Add account"
# Assign "FlinkDeveloper" role
# Generate API key for service account
```

**4.4 Multi-Region:**

- Create separate compute pools per region
- Deploy statements per pool for local processing

**4.5 CI/CD Alternatives:**

**Option A: Terraform**

```hcl
# terraform/confluent/flink-compute-pool.tf
resource "confluent_flink_compute_pool" "prod_flink_east" {
  display_name = "prod-flink-east"
  cloud        = "AWS"
  region       = "us-east-1"
  max_cfu      = 4
  environment {
    id = confluent_environment.prod.id
  }
}

resource "confluent_service_account" "flink_service_account" {
  display_name = "flink-service-account"
  description   = "Service account for Flink compute pool"
}

resource "confluent_role_binding" "flink_developer" {
  principal   = "User:${confluent_service_account.flink_service_account.id}"
  role_name   = "FlinkDeveloper"
  crn_pattern = confluent_environment.prod.resource_name
}

resource "confluent_api_key" "flink_api_key" {
  owner {
    id          = confluent_service_account.flink_service_account.id
    api_version = "iam/v2"
    kind        = "ServiceAccount"
  }
  managed_resource {
    id          = confluent_flink_compute_pool.prod_flink_east.id
    api_version = "flink/v1beta1"
    kind        = "ComputePool"
    environment {
      id = confluent_environment.prod.id
    }
  }
}
```

**Option B: REST API**

```python
# scripts/create-flink-pool.py
import requests
import base64

def create_flink_compute_pool(env_id, name, region, max_cfu, api_key, api_secret):
    url = "https://api.confluent.cloud/flink/v1beta1/compute-pools"
    auth = base64.b64encode(f'{api_key}:{api_secret}'.encode()).decode()
    headers = {
        "Authorization": f"Basic {auth}",
        "Content-Type": "application/json"
    }
    payload = {
        "display_name": name,
        "cloud": "AWS",
        "region": region,
        "max_cfu": max_cfu,
        "environment": {"id": env_id}
    }
    response = requests.post(url, json=payload, headers=headers)
    return response.json()
```

**Verification:**

```bash
# List compute pools
confluent flink compute-pool list
```

### Step 5: Deploy Flink SQL Statements

**5.1 Prepare SQL Files:**

- Use existing SQL from `flink-jobs/routing-working.sql`
- Adapt for Confluent Cloud (update bootstrap servers, topic names)

**5.2 Deploy via Console:**

- Console: "Flink" > "Statements" > "Create statement"
- Upload SQL file or paste SQL

**5.3 Deploy via Terraform:**

```hcl
resource "confluent_flink_statement" "event_routing" {
  compute_pool_id = confluent_flink_compute_pool.prod_flink_east.id
  statement_name  = "event-routing-job"
  statement      = file("${path.module}/flink-jobs/routing-working.sql")
}
```

**5.4 Multi-Region Deployment:**

- Deploy same SQL to each region's compute pool
- Use savepoints for zero-downtime updates

**5.5 CI/CD Alternatives:**

**Option A: Terraform (Enhanced)**

```hcl
# terraform/confluent/flink-statements.tf
resource "confluent_flink_statement" "event_routing" {
  compute_pool_id = confluent_flink_compute_pool.prod_flink_east.id
  statement_name  = "event-routing-job"
  statement       = file("${path.module}/../cdc-streaming/flink-jobs/routing.sql")
  
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

**Option B: REST API with Validation**

```python
# scripts/deploy-flink-statement.py
import requests
import base64
import json

def validate_sql(sql_file):
    # Add SQL syntax validation using sqlfluff or custom validator
    pass

def deploy_flink_statement(compute_pool_id, statement_name, sql_file, api_key, api_secret):
    # Validate SQL syntax
    validate_sql(sql_file)
    
    # Read SQL file
    with open(sql_file, 'r') as f:
        sql_content = f.read()
    
    # Deploy via REST API
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
    
    # Wait for deployment and verify
    statement_id = response.json()["id"]
    wait_for_statement_ready(statement_id, api_key, api_secret)
    return statement_id
```

**Option C: GitHub Actions with SQL Linting**

```yaml
# .github/workflows/deploy-flink-job.yml
name: Deploy Flink SQL Job
on:
  push:
    paths:
      - 'cdc-streaming/flink-jobs/**'

jobs:
  lint-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Lint SQL
        run: |
          pip install sqlfluff
          sqlfluff lint cdc-streaming/flink-jobs/*.sql
      - name: Deploy to Confluent
        env:
          CONFLUENT_API_KEY: ${{ secrets.CONFLUENT_API_KEY }}
          CONFLUENT_API_SECRET: ${{ secrets.CONFLUENT_API_SECRET }}
        run: |
          python scripts/deploy-flink-statement.py \
            --compute-pool ${{ env.COMPUTE_POOL_ID }} \
            --sql-file cdc-streaming/flink-jobs/routing.sql
```

**Verification:**

```bash
# List statements
confluent flink statement list --compute-pool <pool-id>

# Check statement status
confluent flink statement describe <statement-id>
```

### Step 6: Configure PostgreSQL CDC Connector

**6.1 Set Up Kafka Connect (if using managed):**

- Create connector cluster in Confluent Cloud
- Or use existing Qlik Replicate for Aurora Postgres CDC

**6.2 Configure Connector:**

- Update connector config with Confluent Cloud bootstrap servers
- Use API keys from Vault
- Point to Aurora Postgres endpoint

**6.3 Deploy via Terraform:**

```hcl
resource "confluent_connector" "postgres_source" {
  environment = confluent_environment.prod.id
  kafka_cluster = confluent_kafka_cluster.prod_kafka_east.id
  config = {
    "connector.class" = "io.debezium.connector.postgresql.PostgresConnector"
    "database.hostname" = var.aurora_endpoint
    "topic.prefix" = "raw_business_events"
    # ... other config
  }
}
```

**6.4 CI/CD Alternatives:**

**Option A: Terraform (Complete)**

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
  }
  
  config_nonsensitive = {
    "connector.class"          = "io.debezium.connector.postgresql.PostgresConnector"
    "database.hostname"        = var.aurora_endpoint
    "database.port"            = "5432"
    "database.user"            = var.postgres_user
    "database.dbname"          = var.database_name
    "database.server.name"     = "postgres-source"
    "topic.prefix"             = "raw_business_events"
    "table.include.list"       = "public.car_entities,public.loan_entities"
    "plugin.name"              = "pgoutput"
    "tasks.max"                = "1"
  }
}
```

**Option B: REST API with Config Management**

```python
# scripts/deploy-connector.py
import requests
import base64
import json

def deploy_postgres_connector(env_id, cluster_id, config_file, api_key, api_secret):
    with open(config_file, 'r') as f:
        connector_config = json.load(f)
    
    url = f"https://api.confluent.cloud/connect/v1/environments/{env_id}/clusters/{cluster_id}/connectors"
    auth = base64.b64encode(f'{api_key}:{api_secret}'.encode()).decode()
    headers = {
        "Authorization": f"Basic {auth}",
        "Content-Type": "application/json"
    }
    response = requests.post(url, json=connector_config, headers=headers)
    
    # Monitor connector status
    connector_id = response.json()["id"]
    monitor_connector_health(connector_id, env_id, cluster_id, api_key, api_secret)
    return connector_id
```

**Verification:**

```bash
# Check connector status
confluent connector list
confluent connector describe <connector-id>
```

### Step 7: Update Ingestion API Configuration

**7.1 Update Spring Boot Kafka Producer:**

- Update `bootstrap.servers` to Confluent Cloud endpoint
- Use API keys from Vault
- Update topic names if changed

**7.2 Test Connection:**

```bash
# From EKS pod, test Kafka connectivity
kafka-console-producer --bootstrap-server <confluent-endpoint> \
  --topic raw_business_events \
  --producer-property security.protocol=SASL_SSL \
  --producer-property sasl.mechanism=PLAIN
```

**7.3 Deploy via Jenkins:**

- Update application config in Jenkins pipeline
- Deploy to EKS via Helm/Kubernetes

**7.4 CI/CD Alternatives:**

**Option A: Helm Chart with ConfigMap**

```yaml
# k8s/helm/producer-api/values.yaml
kafka:
  bootstrapServers: ${CONFLUENT_BOOTSTRAP_SERVERS}
  security:
    protocol: SASL_SSL
    sasl:
      mechanism: PLAIN
      username: ${CONFLUENT_API_KEY}
      password: ${CONFLUENT_API_SECRET}
  topics:
    rawEvents: raw_business_events
```

**Option B: Terraform for EKS Config**

```hcl
# terraform/k8s/configmap.tf
resource "kubernetes_config_map" "kafka_config" {
  metadata {
    name      = "kafka-config"
    namespace = "default"
  }
  data = {
    "bootstrap.servers" = confluent_kafka_cluster.dedicated.bootstrap_endpoint
    "security.protocol" = "SASL_SSL"
    "sasl.mechanism"    = "PLAIN"
  }
}

resource "kubernetes_secret" "kafka_credentials" {
  metadata {
    name      = "kafka-credentials"
    namespace = "default"
  }
  data = {
    "api-key"    = base64encode(confluent_api_key.cluster_api_key.id)
    "api-secret" = base64encode(confluent_api_key.cluster_api_key.secret)
  }
}
```

**Verification:**

```bash
# Check producer metrics in Confluent Console
# Verify messages in raw_business_events topic
```

### Step 8: Set Up Multi-Region Cluster Linking

**8.1 Create Second Cluster (us-west-2):**

```bash
confluent kafka cluster create prod-kafka-west \
  --cloud aws \
  --region us-west-2 \
  --type dedicated \
  --cku 2
```

**8.2 Enable Cluster Linking:**

- Console: "Replication" > "Add link"
- Configure exactly-once replication
- Link topics: `raw_business_events`, filtered topics

**8.3 Verify Replication:**

```bash
# Check message counts in both regions
confluent kafka topic describe raw_business_events --cluster <cluster-id>
```

**8.4 CI/CD Alternatives:**

**Option A: Terraform Multi-Region Module**

```hcl
# terraform/confluent/modules/region/main.tf
module "us_east_1" {
  source = "./region"
  region = "us-east-1"
  env_id = confluent_environment.prod.id
}

module "us_west_2" {
  source = "./region"
  region = "us-west-2"
  env_id = confluent_environment.prod.id
}

# Cluster linking
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
}
```

**Option B: GitOps Multi-Region**

```yaml
# k8s/argocd/applications/multi-region.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: confluent-multi-region
spec:
  sources:
    - repoURL: https://github.com/org/repo
      path: terraform/confluent
      helm:
        valueFiles:
          - values-us-east-1.yaml
    - repoURL: https://github.com/org/repo
      path: terraform/confluent
      helm:
        valueFiles:
          - values-us-west-2.yaml
```

**Verification:**

- Messages should replicate automatically
- Check lag metrics in Confluent Console

### Step 9: Generate Test Data and Verify Pipeline

**9.1 Generate Test Events:**

- Use existing Producer API
- Or use Confluent kafka-console-producer

**9.2 Verify Data Flow:**

```bash
# Check raw topic
confluent kafka topic consume raw_business_events --from-beginning

# Check filtered topics
confluent kafka topic consume filtered_loan_events --from-beginning
```

**9.3 Monitor via Confluent Console:**

- View metrics, throughput, lag
- Check Flink statement execution
- Monitor connector status

**9.4 Multi-Region Testing:**

- Inject events in us-east-1
- Verify replication to us-west-2
- Test failover scenarios

**9.5 CI/CD Alternatives:**

**Option A: Automated Testing Pipeline**

```yaml
# .github/workflows/test-pipeline.yml
name: Test CDC Pipeline
on:
  schedule:
    - cron: '0 0 * * *' # Daily
  workflow_dispatch:

jobs:
  test-pipeline:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Generate Test Data
        run: |
          python scripts/generate-test-data.py \
            --count 1000 \
            --api-endpoint ${{ env.API_ENDPOINT }}
      
      - name: Wait for Events
        run: sleep 30
      
      - name: Verify Raw Topic
        run: |
          python scripts/verify-topic.py \
            --topic raw_business_events \
            --expected-count 1000
      
      - name: Verify Filtered Topics
        run: |
          python scripts/verify-filtered-topics.py \
            --topics filtered_loan_events,filtered_service_events
      
      - name: Generate Test Report
        run: |
          python scripts/generate-test-report.py > test-report.html
      
      - name: Upload Test Report
        uses: actions/upload-artifact@v3
        with:
          name: test-report
          path: test-report.html
```

**Option B: Terraform Test Module**

```hcl
# terraform/tests/pipeline-test.tf
module "pipeline_test" {
  source = "./modules/pipeline-test"
  
  kafka_endpoint = confluent_kafka_cluster.dedicated.bootstrap_endpoint
  topics = [
    "raw_business_events",
    "filtered_loan_events",
    "filtered_service_events"
  ]
  
  test_data_count = 1000
}
```

**Verification:**

- Messages flow: Producer → Raw Topic → Flink → Filtered Topics → Consumers
- Multi-region replication working
- All metrics visible in Confluent Console

### Step 10: CI/CD Integration with Jenkins

**10.1 Jenkins Pipeline:**

- Lint SQL files
- Unit test (Flink MiniCluster)
- Deploy Terraform (Confluent resources)
- E2E test (inject events, assert filtered topics)

**10.2 Terraform State:**

- Store in S3 backend
- Use DynamoDB for locking

**10.3 Multi-Region Deployment:**

- Parallel Jenkins stages for each region
- Chaos testing: simulate region failure

**10.4 CI/CD Alternatives:**

**Option A: Complete Jenkins Pipeline**

```groovy
// Jenkinsfile
pipeline {
    agent any
    environment {
        CONFLUENT_API_KEY = credentials('confluent-api-key')
        CONFLUENT_API_SECRET = credentials('confluent-api-secret')
        AWS_CREDENTIALS = credentials('aws-credentials')
        VAULT_ADDR = 'https://vault.example.com'
    }
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
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
                            sh 'terraform init'
                            sh 'terraform validate'
                            sh 'terraform fmt -check'
                        }
                    }
                }
            }
        }
        stage('Terraform Plan') {
            steps {
                dir('terraform/confluent') {
                    sh 'terraform plan -out=tfplan'
                    archiveArtifacts 'tfplan'
                }
            }
        }
        stage('Deploy Infrastructure') {
            when {
                anyOf {
                    branch 'main'
                    branch 'production'
                }
            }
            steps {
                dir('terraform/confluent') {
                    sh 'terraform apply tfplan'
                }
            }
        }
        stage('Deploy Flink Jobs') {
            steps {
                script {
                    def computePools = sh(
                        script: 'confluent flink compute-pool list -o json',
                        returnStdout: true
                    )
                    def pools = readJSON text: computePools
                    pools.each { pool ->
                        sh """
                            python scripts/deploy-flink-statement.py \
                                --compute-pool ${pool.id} \
                                --sql-file cdc-streaming/flink-jobs/routing.sql
                        """
                    }
                }
            }
        }
        stage('E2E Test') {
            steps {
                sh 'python scripts/generate-test-data.py --count 100'
                sleep(time: 30, unit: 'SECONDS')
                sh 'python scripts/verify-pipeline.py'
            }
        }
        stage('Rollback on Failure') {
            when {
                expression { currentBuild.result == 'FAILURE' }
            }
            steps {
                dir('terraform/confluent') {
                    sh 'terraform destroy -auto-approve'
                }
            }
        }
    }
    post {
        always {
            publishHTML([
                reportDir: 'test-results',
                reportFiles: 'test-report.html',
                reportName: 'Pipeline Test Report'
            ])
        }
    }
}
```

**Option B: GitHub Actions Complete Workflow**

```yaml
# .github/workflows/confluent-deploy.yml
name: Deploy Confluent Infrastructure
on:
  push:
    branches: [main]
    paths:
      - 'terraform/confluent/**'
      - 'cdc-streaming/**'
  pull_request:
    branches: [main]

env:
  TF_VERSION: '1.5.0'
  CONFLUENT_CLI_VERSION: '3.0.0'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: ${{ env.TF_VERSION }}
      - name: Terraform Init
        working-directory: terraform/confluent
        run: terraform init
      - name: Terraform Validate
        working-directory: terraform/confluent
        run: terraform validate
      - name: Terraform Format Check
        working-directory: terraform/confluent
        run: terraform fmt -check

  deploy:
    needs: validate
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    strategy:
      matrix:
        region: [us-east-1, us-west-2]
    steps:
      - uses: actions/checkout@v3
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: ${{ env.TF_VERSION }}
          terraform_cloud_organization: ${{ secrets.TF_ORG }}
          terraform_cloud_token: ${{ secrets.TF_TOKEN }}
      - name: Setup Confluent CLI
        run: |
          brew install confluentinc/tap/cli
      - name: Deploy Infrastructure
        working-directory: terraform/confluent
        env:
          CONFLUENT_CLOUD_API_KEY: ${{ secrets.CONFLUENT_API_KEY }}
          CONFLUENT_CLOUD_API_SECRET: ${{ secrets.CONFLUENT_API_SECRET }}
          AWS_REGION: ${{ matrix.region }}
        run: |
          terraform init
          terraform plan -var="region=${{ matrix.region }}"
          terraform apply -auto-approve
      - name: Deploy Flink Jobs
        env:
          CONFLUENT_CLOUD_API_KEY: ${{ secrets.CONFLUENT_API_KEY }}
          CONFLUENT_CLOUD_API_SECRET: ${{ secrets.CONFLUENT_API_SECRET }}
        run: |
          python scripts/deploy-flink-statements.py --region ${{ matrix.region }}

  test:
    needs: deploy
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run E2E Tests
        run: |
          python scripts/generate-test-data.py
          python scripts/verify-pipeline.py
      - name: Upload Test Results
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: test-results/
```

**Option C: GitLab CI/CD**

```yaml
# .gitlab-ci.yml
stages:
  - validate
  - deploy
  - test

variables:
  TF_ROOT: terraform/confluent
  TF_VERSION: "1.5.0"

validate:
  stage: validate
  image: hashicorp/terraform:$TF_VERSION
  script:
    - cd $TF_ROOT
    - terraform init -backend=false
    - terraform validate
    - terraform fmt -check

deploy:
  stage: deploy
  image: hashicorp/terraform:$TF_VERSION
  only:
    - main
  script:
    - cd $TF_ROOT
    - terraform init
    - terraform plan
    - terraform apply -auto-approve
  environment:
    name: production
    action: start

test:
  stage: test
  image: python:3.11
  script:
    - pip install -r requirements.txt
    - python scripts/generate-test-data.py
    - python scripts/verify-pipeline.py
  artifacts:
    reports:
      junit: test-results/junit.xml
```

**Verification:**

- Pipeline runs successfully
- Zero-downtime deployments
- Rollback procedures tested

## Troubleshooting

**Connectivity Issues:**

- Verify PrivateLink endpoints are active
- Check Route 53 DNS resolution
- Test from EKS pod: `curl -k <confluent-endpoint>`

**Flink Statement Failures:**

- Check statement logs in Confluent Console
- Verify topic names and bootstrap servers
- Check compute pool status

**Multi-Region Replication:**

- Verify Cluster Linking is active
- Check replication lag metrics
- Test failover procedures

**API Key Issues:**

- Verify keys in Vault
- Check RBAC permissions
- Regenerate if expired

## Expected Results

After completing all steps:

- ✅ Confluent Cloud clusters running in both regions
- ✅ PrivateLink connectivity established
- ✅ Flink compute pools processing events
- ✅ Topics created and receiving data
- ✅ Multi-region replication active
- ✅ CI/CD pipeline deploying via Jenkins
- ✅ End-to-end data flow operational

## Quick Reference

**Key Commands:**

```bash
# Confluent CLI
confluent login
confluent environment list
confluent kafka cluster list
confluent flink compute-pool list
confluent flink statement list --compute-pool <pool-id>

# Terraform
terraform init
terraform plan
terraform apply

# Jenkins
# Run pipeline via Jenkins UI or CLI
```

**Key URLs:**

- Confluent Cloud Console: https://confluent.cloud
- Flink UI: Access via Confluent Console
- Monitoring: Confluent Console metrics dashboard

## CI/CD Recommendations

### Recommended CI/CD Architecture

**Option 1: Terraform + GitHub Actions (Recommended for GitOps)**

- **Pros**: Version controlled, easy rollback, multi-region support
- **Cons**: Requires Terraform expertise
- **Best for**: Teams with IaC experience, GitOps workflows

**Option 2: Confluent CLI + Jenkins (Current Mention)**

- **Pros**: Simple, direct CLI access
- **Cons**: Less declarative, harder to version control
- **Best for**: Teams already using Jenkins, quick setup

**Option 3: REST API + Custom Scripts + Any CI/CD**

- **Pros**: Maximum flexibility, language agnostic
- **Cons**: More code to maintain, error handling complexity
- **Best for**: Custom requirements, multi-cloud scenarios

**Option 4: Hybrid Approach (Recommended)**

- Use Terraform for infrastructure (clusters, topics, compute pools)
- Use REST API/CLI for dynamic operations (Flink statement updates)
- Use CI/CD platform for orchestration and testing
- Store secrets in Vault/AWS Secrets Manager

### Implementation Priority

1. **High Priority**: Steps 2, 4, 5 (Kafka clusters, Flink pools, SQL statements) - Core infrastructure
2. **Medium Priority**: Steps 1, 6, 7 (Environment, connectors, API config) - Setup and integration
3. **Low Priority**: Steps 3, 8, 9, 10 (Networking, multi-region, testing) - Advanced features

### Security Considerations

- Store all API keys in secrets management (Vault, AWS Secrets Manager, GitHub Secrets)
- Use service accounts with least privilege
- Enable audit logging for all infrastructure changes
- Implement approval gates for production deployments
- Use separate credentials per environment

### Multi-Region Deployment Strategy

1. **Parallel Deployment**: Deploy to all regions simultaneously using matrix strategy
2. **Sequential Deployment**: Deploy to primary region first, then replicate
3. **Blue-Green**: Deploy to new region, test, then switch traffic
4. **Canary**: Deploy to one region, monitor, then expand

### Next Steps

1. Create Terraform modules for each Confluent resource type
2. Set up CI/CD pipeline with chosen platform
3. Implement secret management integration
4. Create test automation scripts
5. Document rollback procedures
6. Set up monitoring and alerting
