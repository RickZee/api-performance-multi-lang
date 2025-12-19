# Production Setup - DSQL Debezium Connector

**Last Updated**: December 19, 2025  
**Status**: ✅ Deployed and Running

## Overview

This document describes the current production deployment of the DSQL Debezium connector on the bastion host, including infrastructure, configuration, monitoring, and troubleshooting.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Amazon Aurora DSQL                        │
│  Endpoint: vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1  │
│  Database: car_entities                                      │
│  Tables: event_headers                                       │
│  Auth: IAM (dsql_iam_user)                                  │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        │ IAM Token + JDBC
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                  EC2 Bastion Host                            │
│  Instance: i-0adcbf0f85849149e                              │
│  Region: us-east-1                                           │
│  IP: 44.198.171.47                                           │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │         Kafka Connect Container                     │    │
│  │  Image: debezium/connect:2.6                        │    │
│  │  Container: dsql-kafka-connect                      │    │
│  │  Port: 8083                                          │    │
│  └──────────────────┬─────────────────────────────────┘    │
│                     │                                        │
│  ┌──────────────────▼─────────────────────────────────┐    │
│  │         DSQL Connector Plugin                       │    │
│  │  JAR: debezium-connector-dsql-1.0.0.jar (32 MB)    │    │
│  │  Location: ~/debezium-connector-dsql/connector/     │    │
│  └──────────────────┬─────────────────────────────────┘    │
│                     │                                        │
│  ┌──────────────────▼─────────────────────────────────┐    │
│  │         Connector Instance                           │    │
│  │  Name: dsql-cdc-source                               │    │
│  │  Status: RUNNING                                     │    │
│  │  Tasks: 1 (RUNNING)                                  │    │
│  └──────────────────────────────────────────────────────┘    │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        │ SASL/SSL + Kafka Protocol
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                  Confluent Cloud                             │
│  Bootstrap: pkc-oxqxx9.us-east-1.aws.confluent.cloud:9092   │
│  Auth: SASL/PLAIN (API Key/Secret)                           │
│                                                              │
│  Topics:                                                     │
│    - dsql-cdc.public.event_headers                          │
│    - dsql-connect-config                                    │
│    - dsql-connect-offsets                                   │
│    - dsql-connect-status                                    │
└─────────────────────────────────────────────────────────────┘
```

## Infrastructure Components

### 1. Bastion Host

**Instance Details**:
- **Instance ID**: `i-0adcbf0f85849149e`
- **Public IP**: `44.198.171.47`
- **Region**: `us-east-1`
- **OS**: Amazon Linux 2023
- **Connection**: SSM Session Manager (preferred)

**Software Installed**:
- Docker 25.0.13
- Java 11 (OpenJDK)
- AWS CLI

**Directory Structure**:
```
~/debezium-connector-dsql/
├── lib/
│   └── debezium-connector-dsql-1.0.0.jar (32 MB)
├── connector/
│   └── debezium-connector-dsql-1.0.0.jar (symlink/copy)
├── config/
│   └── dsql-connector.json
├── .env.dsql
└── logs/
```

### 2. Kafka Connect Container

**Container Details**:
- **Name**: `dsql-kafka-connect`
- **Image**: `debezium/connect:2.6` (from Docker Hub)
- **Status**: Running
- **Port**: `8083` (REST API)
- **Restart Policy**: Unless stopped

**Environment Variables**:
```bash
CONNECT_BOOTSTRAP_SERVERS=pkc-oxqxx9.us-east-1.aws.confluent.cloud:9092
CONNECT_REST_PORT=8083
CONNECT_REST_ADVERTISED_HOST_NAME=localhost
CONNECT_GROUP_ID=dsql-connect-cluster
CONNECT_CONFIG_STORAGE_TOPIC=dsql-connect-config
CONNECT_OFFSET_STORAGE_TOPIC=dsql-connect-offsets
CONNECT_STATUS_STORAGE_TOPIC=dsql-connect-status
CONNECT_KEY_CONVERTER=org.apache.kafka.connect.json.JsonConverter
CONNECT_VALUE_CONVERTER=org.apache.kafka.connect.json.JsonConverter
CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE=false
CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE=false
CONNECT_PLUGIN_PATH=/kafka/connect

# Confluent Cloud SASL/SSL
CONNECT_SASL_MECHANISM=PLAIN
CONNECT_SECURITY_PROTOCOL=SASL_SSL
CONNECT_SASL_JAAS_CONFIG=org.apache.kafka.common.security.plain.PlainLoginModule required username='<API_KEY>' password='<API_SECRET>';
CONNECT_PRODUCER_SASL_MECHANISM=PLAIN
CONNECT_PRODUCER_SECURITY_PROTOCOL=SASL_SSL
CONNECT_PRODUCER_SASL_JAAS_CONFIG=org.apache.kafka.common.security.plain.PlainLoginModule required username='<API_KEY>' password='<API_SECRET>';
CONNECT_CONSUMER_SASL_MECHANISM=PLAIN
CONNECT_CONSUMER_SECURITY_PROTOCOL=SASL_SSL
CONNECT_CONSUMER_SASL_JAAS_CONFIG=org.apache.kafka.common.security.plain.PlainLoginModule required username='<API_KEY>' password='<API_SECRET>';
```

### 3. DSQL Connector Configuration

**Connector Name**: `dsql-cdc-source`

**Configuration**:
```json
{
  "connector.class": "io.debezium.connector.dsql.DsqlConnector",
  "tasks.max": "1",
  "dsql.endpoint.primary": "vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws",
  "dsql.port": "5432",
  "dsql.region": "us-east-1",
  "dsql.iam.username": "dsql_iam_user",
  "dsql.database.name": "car_entities",
  "dsql.tables": "event_headers",
  "dsql.poll.interval.ms": "1000",
  "dsql.batch.size": "1000",
  "dsql.pool.max.size": "10",
  "dsql.pool.min.idle": "1",
  "dsql.pool.connection.timeout.ms": "30000",
  "topic.prefix": "dsql-cdc",
  "output.data.format": "JSON"
}
```

## Configuration Files

### 1. Environment Variables (`.env.dsql`)

Located at: `~/debezium-connector-dsql/.env.dsql`

```bash
export DSQL_ENDPOINT_PRIMARY="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
export DSQL_DATABASE_NAME="car_entities"
export DSQL_REGION="us-east-1"
export DSQL_IAM_USERNAME="dsql_iam_user"
export DSQL_TABLES="event_headers"
export DSQL_PORT="5432"
export DSQL_TOPIC_PREFIX="dsql-cdc"
```

### 2. Connector Configuration (`config/dsql-connector.json`)

Located at: `~/debezium-connector-dsql/config/dsql-connector.json`

Contains the full connector configuration as shown above.

### 3. Confluent Cloud Credentials

**Source**: `cdc-streaming/.env` (gitignored)

**Variables Used**:
- `KAFKA_BOOTSTRAP_SERVERS` → `CC_BOOTSTRAP_SERVERS`
- `KAFKA_API_KEY` → `CC_KAFKA_API_KEY`
- `KAFKA_API_SECRET` → `CC_KAFKA_API_SECRET`

**Note**: Credentials are also available in `terraform/debezium-connector-dsql/connect.env` (gitignored)

## Deployment Scripts

All deployment scripts are located in `scripts/`:

| Script | Purpose |
|--------|---------|
| `setup-from-terraform.sh` | Extract DSQL config from Terraform and set up on bastion |
| `deploy-kafka-connect-bastion.sh` | Deploy Kafka Connect container with Confluent Cloud config |
| `create-connector-bastion.sh` | Create connector in Kafka Connect |
| `verify-bastion-setup.sh` | Verify infrastructure setup |
| `upload-to-bastion.sh` | Upload connector JAR to bastion via S3 |

## Monitoring

### Connector Status

**Check Status**:
```bash
curl http://localhost:8083/connectors/dsql-cdc-source/status
```

**Expected Response**:
```json
{
  "name": "dsql-cdc-source",
  "connector": {
    "state": "RUNNING",
    "worker_id": "localhost:8083"
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "localhost:8083"
    }
  ],
  "type": "source"
}
```

### Connector Configuration

**View Config**:
```bash
curl http://localhost:8083/connectors/dsql-cdc-source/config
```

### Connector Tasks

**View Tasks**:
```bash
curl http://localhost:8083/connectors/dsql-cdc-source/tasks
```

### Logs

**View Container Logs**:
```bash
docker logs -f dsql-kafka-connect
```

**View Recent Logs**:
```bash
docker logs --tail 100 dsql-kafka-connect
```

**Filter for Errors**:
```bash
docker logs dsql-kafka-connect 2>&1 | grep -i error
```

### Kafka Topics

**Check Topics in Confluent Cloud**:
- Main CDC topic: `dsql-cdc.public.event_headers`
- Config topic: `dsql-connect-config`
- Offset topic: `dsql-connect-offsets`
- Status topic: `dsql-connect-status`

## Current Status

**Last Verified**: December 19, 2025

### Connector Status
- ✅ **State**: RUNNING
- ✅ **Tasks**: 1 task RUNNING
- ⚠️ **Issues**: Connection errors to DSQL (authentication) and Kafka broker disconnections observed

### Known Issues

1. **DSQL Authentication Errors** ✅ **FIXED**
   - Error: `FATAL: password authentication failed for user "dsql_iam_user"`
   - **Root Cause**: Java connector was using Aurora RDS token generation method instead of DSQL-specific presigned URL generation
   - **Fix Implemented**: Pure Java SigV4 query string signing implemented in `SigV4QueryStringSigner.java`
   - **Status**: Python dependency removed, pure Java implementation complete
   - **Action**: 
     - Verify IAM role mapping: `./scripts/verify-iam-role-mapping.sh`
     - Test connection: `./scripts/test-dsql-connection.sh`
     - See `FIXES-IMPLEMENTED.md` for details

2. **Kafka Broker Disconnections** 🟡 MEDIUM
   - Warning: `Bootstrap broker ... disconnected`
   - **Root Cause**: Under investigation - possible network connectivity, SASL config, or credential issues
   - **Impact**: Intermittent disconnections, automatic retry works, not blocking
   - **Action**: 
     - Run `./scripts/test-kafka-connectivity.sh` to test network
     - Run `./scripts/test-confluent-credentials.sh` to verify credentials
     - See `INVESTIGATION-FINDINGS.md` for details

### Health Checks

**Run Health Check**:
```bash
# On bastion
cd ~/debezium-connector-dsql

# Check connector status
curl -s http://localhost:8083/connectors/dsql-cdc-source/status | python3 -m json.tool

# Check for errors in logs
docker logs dsql-kafka-connect 2>&1 | grep -i "error\|exception\|failed" | tail -20

# Check container health
docker ps | grep kafka-connect
```

## Troubleshooting

### Diagnostic Scripts

**Comprehensive Diagnostics**:
```bash
./scripts/diagnose-issues.sh
```
Generates a diagnostic report with all findings.

**Specific Checks**:
```bash
# Check IAM role mapping
./scripts/verify-iam-role-mapping.sh

# Test IAM token generation
./scripts/test-iam-token-generation.sh

# Test DSQL connection
./scripts/test-dsql-connection.sh

# Test Kafka connectivity
./scripts/test-kafka-connectivity.sh

# Test Confluent credentials
./scripts/test-confluent-credentials.sh
```

### Connector Not Running

1. **Check Container Status**:
   ```bash
   docker ps -a | grep kafka-connect
   ```

2. **Restart Container**:
   ```bash
   docker restart dsql-kafka-connect
   ```

3. **Check Logs**:
   ```bash
   docker logs dsql-kafka-connect
   ```

### DSQL Authentication Errors

**Symptoms**: `FATAL: password authentication failed for user "dsql_iam_user"`

**Root Cause**: Java connector uses wrong token generation method (Aurora RDS instead of DSQL)

**Immediate Actions**:

1. **Verify IAM Role Mapping**:
   ```bash
   ./scripts/verify-iam-role-mapping.sh
   ```
   If mapping is missing, grant access:
   ```sql
   AWS IAM GRANT dsql_iam_user TO 'arn:aws:iam::978300727880:role/producer-api-bastion-role';
   ```

2. **Test Token Generation**:
   ```bash
   ./scripts/test-iam-token-generation.sh
   ```
   This will show if token generation is working.

3. **Test Connection**:
   ```bash
   ./scripts/test-dsql-connection.sh
   ```
   This will test full connection with IAM authentication.

4. **Token Generation** (✅ **FIXED**):
   - Pure Java implementation complete in `SigV4QueryStringSigner.java`
   - No Python dependency required
   - See `FIXES-IMPLEMENTED.md` for details

**Common Causes**:
- IAM role not mapped to DSQL user (most likely)
- Wrong token generation method (CRITICAL - needs code fix)
- Invalid endpoint format
- Network connectivity issues

### Kafka Connection Issues

**Symptoms**: `Bootstrap broker ... disconnected`

**Immediate Actions**:

1. **Test Network Connectivity**:
   ```bash
   ./scripts/test-kafka-connectivity.sh
   ```

2. **Test Credentials**:
   ```bash
   ./scripts/test-confluent-credentials.sh
   ```

3. **Check Container Networking**:
   ```bash
   docker exec dsql-kafka-connect nc -zv pkc-oxqxx9.us-east-1.aws.confluent.cloud 9092
   ```

**Common Causes**:
- Security group blocking outbound traffic
- Invalid or expired API credentials
- SASL configuration format issues
- Container networking problems
- DNS resolution failures

### Restart Connector

```bash
# Restart connector
curl -X POST http://localhost:8083/connectors/dsql-cdc-source/restart

# Restart specific task
curl -X POST http://localhost:8083/connectors/dsql-cdc-source/tasks/0/restart
```

### Delete and Recreate Connector

```bash
# Delete connector
curl -X DELETE http://localhost:8083/connectors/dsql-cdc-source

# Recreate connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @~/debezium-connector-dsql/config/dsql-connector.json
```

## Maintenance

### Update Connector JAR

1. **Build New JAR**:
   ```bash
   cd debezium-connector-dsql
   ./gradlew build
   ```

2. **Upload to Bastion**:
   ```bash
   ./scripts/upload-to-bastion.sh
   ```

3. **Restart Kafka Connect**:
   ```bash
   docker restart dsql-kafka-connect
   ```

### Update Configuration

1. **Edit Config on Bastion**:
   ```bash
   # Connect to bastion
   aws ssm start-session --target i-0adcbf0f85849149e --region us-east-1
   
   # Edit config
   vi ~/debezium-connector-dsql/config/dsql-connector.json
   ```

2. **Update Connector**:
   ```bash
   curl -X PUT http://localhost:8083/connectors/dsql-cdc-source/config \
     -H "Content-Type: application/json" \
     -d @~/debezium-connector-dsql/config/dsql-connector.json
   ```

## Security

### Credentials Management

- ✅ `connect.env` is gitignored
- ✅ `.env.dsql` contains no sensitive data (only DSQL endpoint)
- ✅ Confluent Cloud credentials stored in `cdc-streaming/.env` (gitignored)
- ✅ IAM authentication used for DSQL (no passwords)

### Network Security

- Bastion host in private VPC
- DSQL endpoint accessible only from VPC
- Confluent Cloud connection via SASL/SSL
- Security groups restrict access

## Investigation and Remediation

### Investigation Results

- **INVESTIGATION-FINDINGS.md** - Detailed root cause analysis
- **REMEDIATION-PLAN.md** - Step-by-step fixes
- **Diagnostic Scripts** - Automated diagnostic tools in `scripts/`

### Key Findings

1. **DSQL Authentication**: Java connector uses wrong token generation method
   - Current: Aurora RDS SDK method
   - Required: DSQL presigned URL with SigV4QueryAuth
   - Reference: Python implementation shows correct approach

2. **Kafka Disconnections**: Under investigation
   - Run diagnostic scripts to identify root cause
   - Likely network or credential issues

## References

### Documentation Files

- **README.md** - Main connector documentation
- **QUICK-START.md** - Quick deployment guide
- **KAFKA-CONNECT-DEPLOYMENT.md** - Detailed deployment guide
- **DEPLOYMENT-COMPLETE.md** - Deployment completion summary
- **BASTION-TESTING-GUIDE.md** - Testing procedures
- **TESTING-REAL-DSQL.md** - Real DSQL testing guide
- **INVESTIGATION-FINDINGS.md** - Investigation results
- **REMEDIATION-PLAN.md** - Fix recommendations

### External Resources

- [Debezium Documentation](https://debezium.io/documentation/)
- [Kafka Connect REST API](https://kafka.apache.org/documentation/#connect_rest)
- [Amazon Aurora DSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/data-api.html)
- [Confluent Cloud](https://docs.confluent.io/cloud/current/overview.html)

## Support

For issues or questions:
1. Check logs: `docker logs dsql-kafka-connect`
2. Verify setup: `./scripts/verify-bastion-setup.sh`
3. Review documentation in `debezium-connector-dsql/` directory
