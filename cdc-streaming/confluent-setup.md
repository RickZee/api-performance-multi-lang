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