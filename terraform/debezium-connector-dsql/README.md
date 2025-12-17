# Debezium DSQL Connector Testing Setup

> **Note**: This folder is **NOT managed by Terraform**. It contains manual testing scripts and configuration for the Debezium DSQL connector. These scripts are run manually on EC2 instances for connector testing and validation.

This folder contains a turnkey setup for testing the custom Debezium DSQL connector:

**Aurora DSQL (VPC-only)** → **Self-managed Kafka Connect on EC2** → **Confluent Cloud topic**

This avoids Confluent Cloud “custom connector upload” while still validating:
- IAM auth to DSQL
- your custom connector logic
- delivery into Confluent Cloud topics

## Prereqs

- An EC2 instance **inside the same VPC** as DSQL (you already have one via Terraform).
- Ability for that EC2 instance to reach Confluent Cloud:
  - **Either** Confluent Cloud supports IPv6 from your VPC (EC2 has IPv6)
  - **Or** you have an IPv4 egress path (NAT) / Confluent PrivateLink

## Required environment variables (on EC2)

Set these before running:

- **Confluent Cloud**:
  - `CC_BOOTSTRAP_SERVERS` (example: `pkc-xxxxx.us-east-1.aws.confluent.cloud:9092`)
  - `CC_KAFKA_API_KEY`
  - `CC_KAFKA_API_SECRET`

- **DSQL**:
  - `DSQL_ENDPOINT_PRIMARY` (VPC endpoint DNS)
  - `DSQL_IAM_USERNAME` (example: `lambda_dsql_user`)
  - `DSQL_DATABASE_NAME` (example: `car_entities`)
  - `DSQL_TABLE` (example: `event_headers`)

Optional:
- `CONNECTOR_NAME` (default: `dsql-cdc-source-event-headers`)
- `TOPIC_PREFIX` (default: `dsql-cdc`)
- `ROUTED_TOPIC` (default: `raw-event-headers`)

## One-command E2E run

On the EC2 instance (via SSM session):

```bash
cd /tmp/api-performance-multi-lang/terraform/debezium-connector-dsql
./run-e2e.sh
```

## What `run-e2e.sh` does

1. Preflight checks (DNS + TCP reachability to Confluent bootstrap)
2. Builds the custom connector fat JAR
3. Starts Kafka Connect (Docker) pointed at Confluent Cloud
4. Creates required internal Kafka Connect topics + the routed output topic
5. Deploys the connector to the local Connect REST API
6. Inserts test events into DSQL (requires `psql` + IAM token)
7. Consumes messages from Confluent Cloud topic to validate end-to-end flow
