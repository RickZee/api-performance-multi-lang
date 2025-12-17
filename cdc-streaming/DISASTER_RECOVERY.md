# Disaster Recovery Guide

## Overview

This document provides comprehensive disaster recovery procedures for the CDC streaming architecture in our use case environment. It covers backup strategies, recovery procedures, failover mechanisms, and testing methodologies to ensure business continuity and data integrity.

## Confluent Cloud vs. Self-Managed

### What Confluent Cloud Handles Automatically

When using **Confluent Cloud** (managed service), the following disaster recovery aspects are handled automatically:

#### Kafka Infrastructure

- **Automatic Broker Failover**: Brokers automatically failover within the same region (multi-zone deployment)
- **Automatic Replication**: 3x replication is configured and managed automatically
- **Automatic Scaling**: Brokers scale up/down based on load
- **Infrastructure Backups**: Confluent handles infrastructure-level backups
- **Health Monitoring**: Automatic health checks and alerting for broker failures
- **Zero-Downtime Updates**: Rolling updates without service interruption

#### Schema Registry

- **High Availability**: Schema Registry is automatically replicated across zones
- **Automatic Failover**: Failover handled automatically within region
- **Schema Backups**: Schema versions are automatically backed up
- **Multi-Region Replication**: Available with Stream Governance Advanced package

#### Cluster Linking (Multi-Region)

- **Automatic Replication**: Cluster Linking automatically replicates topics between regions
- **Lag Monitoring**: Built-in lag monitoring and alerting
- **Exactly-Once Semantics**: Automatic exactly-once configuration
- **Connection Management**: Automatic connection health monitoring

#### Monitoring and Alerting

- **Built-in Metrics**: Comprehensive metrics dashboard in Confluent Cloud Console
- **Automatic Alerts**: Pre-configured alerts for critical issues
- **Health Dashboards**: Real-time health monitoring

### What You Still Need to Manage

Even with Confluent Cloud, you are responsible for:

#### Application-Level Recovery

- **Flink Jobs**: Job configuration, checkpoint management, savepoint creation
- **Connectors**: Connector configuration, offset management, error handling
- **Consumer Applications**: Application code, consumer group management, offset commits
- **Custom Monitoring**: Application-specific metrics and alerting

#### Data Backup and Recovery

- **Flink State**: Savepoint creation and management
- **Connector Offsets**: Backup and restore of connector offsets
- **Application State**: Any application-level state outside of Kafka
- **Long-Term Backups**: Snapshot backups for compliance (beyond replication)

#### Multi-Region Failover

- **DNS/Load Balancer Updates**: Routing traffic to secondary region
- **Client Configuration**: Updating bootstrap servers in applications
- **Flink Job Deployment**: Deploying jobs to secondary region compute pools
- **Connector Deployment**: Registering connectors in secondary region
- **Failover Automation**: Custom scripts for automated failover

#### Testing and Validation

- **Disaster Recovery Drills**: Regular testing of failover procedures
- **Data Integrity Verification**: Post-recovery data validation
- **Performance Testing**: Ensuring secondary region can handle load

### Recommendations

**For Confluent Cloud Users**:
1. Focus on application-level disaster recovery (Flink, connectors, consumers)
2. Leverage Confluent Cloud's built-in monitoring and alerting
3. Use Cluster Linking for multi-region replication (configure once, managed automatically)
4. Implement custom failover automation for application components
5. Regular testing of failover procedures (even though infrastructure is managed)

**For Self-Managed Users**:
1. Follow all procedures in this document
2. Implement comprehensive backup strategies
3. Set up monitoring and alerting (Prometheus, Grafana)
4. Automate failover procedures
5. Regular disaster recovery drills

---

## Recovery Objectives

### Recovery Time Objective (RTO)

**Target**: < 1 hour for full system recovery

**Breakdown**:
- **Detection Time**: < 5 minutes (automated monitoring)
- **Decision Time**: < 10 minutes (incident response)
- **Recovery Execution**: < 30 minutes (automated failover)
- **Verification**: < 15 minutes (data integrity checks)

### Recovery Point Objective (RPO)

**Target**: < 5 minutes of data loss

**Achieved Through**:
- Flink checkpoint interval: 30-60 seconds
- Kafka replication: 3x replication factor
- Real-time replication: Cluster Linking with < 1 second lag

### Service Level Agreements (SLAs)

| Component | RTO | RPO | Availability Target |
|-----------|-----|-----|---------------------|
| Kafka Cluster | 15 min | 0 min | 99.9% |
| Flink Jobs | 30 min | 30 sec | 99.5% |
| Connectors | 15 min | 0 min | 99.9% |
| Consumers | 10 min | 0 min | 99.9% |
| Overall System | 60 min | 5 min | 99.5% |

---

## Backup Strategies

### Kafka Backup

**Strategy**: Multi-level backup approach

#### 1. Replication-Based Backup (Automatic with Confluent Cloud)

**Primary Method**: Kafka partition replication

```yaml
# Topic configuration
replication.factor: 3
min.insync.replicas: 2
```

**Benefits**:
- Automatic backup via replication
- No additional storage overhead
- Fast recovery (no restore needed)

#### 2. Snapshot Backups (Manual/Compliance)

**Purpose**: Long-term retention and compliance

**Backup Frequency**:
- **Incremental**: Every 6 hours
- **Full**: Daily at 2 AM UTC
- **Retention**: 30 days for incremental, 1 year for full

**Backup Script Example**:
```bash
#!/bin/bash
# scripts/backup-kafka-topics.sh

TOPICS=(
  "raw-event-headers"
  "filtered-loan-events"
  "filtered-service-events"
  "filtered-car-events"
)

BACKUP_DIR="/backup/kafka/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

for topic in "${TOPICS[@]}"; do
  echo "Backing up topic: $topic"
  
  # Export topic data (using Confluent Cloud CLI or kafka tools)
  confluent kafka topic consume "$topic" \
    --from-beginning \
    --max-messages 1000000 \
    > "$BACKUP_DIR/${topic}.json" 2>&1
done

# Compress and upload to S3
tar -czf "$BACKUP_DIR.tar.gz" "$BACKUP_DIR"
aws s3 cp "$BACKUP_DIR.tar.gz" \
  "s3://backup-bucket/kafka/$(date +%Y/%m/%d)/"
```

### Flink Backup

**Strategy**: Savepoint-based backup

#### 1. Periodic Savepoints

**Frequency**: Every 6 hours

**Purpose**: Enable job recovery to specific point in time

**Configuration**:
```yaml
# flink-conf.yaml
state.savepoints.dir: file:///opt/flink/savepoints
execution.savepoint.interval: 21600000  # 6 hours in milliseconds
```

**Automated Savepoint Script**:
```bash
#!/bin/bash
# scripts/create-flink-savepoint.sh

JOB_ID=$1
SAVEPOINT_DIR="/backup/flink/savepoints/$(date +%Y%m%d_%H%M%S)"
FLINK_REST_URL="http://flink-jobmanager:8081"

# Trigger savepoint (Confluent Cloud Flink)
confluent flink statement savepoint create \
  --compute-pool cp-east-123 \
  --statement-id $JOB_ID \
  --savepoint-dir "$SAVEPOINT_DIR"

# Or for self-managed Flink
SAVEPOINT_PATH=$(curl -X POST \
  "$FLINK_REST_URL/jobs/$JOB_ID/savepoints" \
  -H "Content-Type: application/json" \
  -d '{"target-directory":"'"$SAVEPOINT_DIR"'"}' \
  | jq -r '.request-id')

echo "Savepoint created: $SAVEPOINT_PATH"

# Copy to S3 for long-term storage
aws s3 sync "$SAVEPOINT_DIR" \
  "s3://backup-bucket/flink/savepoints/$(date +%Y/%m/%d)/"
```

### Connector Backup

**Strategy**: Configuration and offset backup

#### 1. Connector Configuration Backup

```bash
#!/bin/bash
# scripts/backup-connectors.sh

CONNECT_REST_URL="http://kafka-connect:8083"
BACKUP_DIR="/backup/connectors/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Get all connectors
connectors=$(curl -s "$CONNECT_REST_URL/connectors" | jq -r '.[]')

for connector in $connectors; do
  echo "Backing up connector: $connector"
  
  # Export configuration
  curl -s "$CONNECT_REST_URL/connectors/$connector/config" \
    > "$BACKUP_DIR/${connector}.json"
  
  # Export status
  curl -s "$CONNECT_REST_URL/connectors/$connector/status" \
    > "$BACKUP_DIR/${connector}_status.json"
done

# Backup offset storage topic
confluent kafka topic consume docker-connect-offsets \
  --from-beginning \
  --max-messages 10000 \
  > "$BACKUP_DIR/offsets.json"

# Compress and upload
tar -czf "$BACKUP_DIR.tar.gz" "$BACKUP_DIR"
aws s3 cp "$BACKUP_DIR.tar.gz" \
  "s3://backup-bucket/connectors/$(date +%Y/%m/%d)/"
```

---

## Multi-Region Architecture

### Active-Active Setup

**Primary Region**: us-east-1
**Secondary Region**: us-west-2

### Cluster Linking Configuration

**Purpose**: Automatic topic replication between regions

**Setup** (Confluent Cloud):
```bash
# Create cluster link from east to west
confluent kafka cluster-link create east-to-west-link \
  --source-cluster prod-kafka-east \
  --destination-cluster prod-kafka-west \
  --config-file cluster-link-config.properties
```

**Configuration File** (`cluster-link-config.properties`):
```properties
# Enable exactly-once semantics
transactional.id.prefix=cluster-link-
enable.idempotence=true

# Replication settings
replication.factor=3
min.insync.replicas=2

# Lag monitoring
consumer.fetch.min.bytes=1024
consumer.fetch.max.wait.ms=500
```

**Replication Lag Monitoring**:
```bash
# Check replication lag (Confluent Cloud)
confluent kafka cluster-link describe east-to-west-link \
  --cluster prod-kafka-west \
  | jq '.lag'
```

### Flink Multi-Region Deployment

**Strategy**: Deploy identical SQL statements to compute pools in both regions

**Compute Pool Setup**:
```bash
# Create compute pool in primary region
confluent flink compute-pool create prod-flink-east \
  --cloud aws \
  --region us-east-1 \
  --max-cfu 4

# Create compute pool in secondary region
confluent flink compute-pool create prod-flink-west \
  --cloud aws \
  --region us-west-2 \
  --max-cfu 4
```

**Deployment Script**:
```bash
#!/bin/bash
# scripts/deploy-flink-multi-region.sh

SQL_FILE="flink-jobs/routing-generated.sql"
PRIMARY_COMPUTE_POOL="cp-east-123"
SECONDARY_COMPUTE_POOL="cp-west-456"

# Deploy to east region
echo "Deploying to us-east-1..."
confluent flink statement create \
  --compute-pool $PRIMARY_COMPUTE_POOL \
  --statement-name event-routing-job-east \
  --statement-file "$SQL_FILE"

# Deploy to west region
echo "Deploying to us-west-2..."
confluent flink statement create \
  --compute-pool $SECONDARY_COMPUTE_POOL \
  --statement-name event-routing-job-west \
  --statement-file "$SQL_FILE"

# Verify deployments
echo "Verifying deployments..."
confluent flink statement list --compute-pool $PRIMARY_COMPUTE_POOL
confluent flink statement list --compute-pool $SECONDARY_COMPUTE_POOL
```

**Region-Specific Configuration**:
- Each region's SQL statement connects to its local Kafka cluster
- Bootstrap servers are region-specific
- Schema Registry URLs are region-specific
- Statements process events from local Kafka topics
- Filtered events are written to local filtered topics

---

## Component-Specific Recovery

### Kafka Broker Recovery

#### Single Broker Failure

**Scenario**: One broker in 3-broker cluster fails

**Recovery Steps**:
1. **Detect Failure**: Monitoring alerts on broker health
2. **Verify Replication**: Check that all partitions have 2+ replicas
3. **No Action Required**: System continues with remaining brokers (automatic with Confluent Cloud)
4. **Replace Broker**: Confluent Cloud automatically replaces failed brokers
5. **Verify**: Check partition replication status

**Verification**:
```bash
# Check partition replication (Confluent Cloud)
confluent kafka topic describe raw-event-headers \
  --cluster prod-kafka-east
```

#### Complete Cluster Failure

**Scenario**: All brokers in primary region fail

**Recovery Steps**:
1. **Failover to Secondary Region**: Route traffic to us-west-2
2. **Verify Data**: Check that all topics exist in secondary region
3. **Update Client Configs**: Point all clients to secondary region
4. **Monitor Lag**: Ensure replication lag is minimal
5. **Restore Primary**: When primary recovers, Confluent Cloud automatically restores
6. **Re-establish Replication**: Recreate cluster links if needed

**Failover Script**:
```bash
#!/bin/bash
# scripts/failover-kafka.sh

PRIMARY_REGION="us-east-1"
SECONDARY_REGION="us-west-2"

echo "Failing over from $PRIMARY_REGION to $SECONDARY_REGION"

# Update DNS/load balancer to point to secondary region
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123456789 \
  --change-batch file://route53-failover.json

# Verify secondary region is operational
confluent kafka cluster describe prod-kafka-west

# Check topic replication
for topic in raw-business-events filtered-loan-events; do
  echo "Checking topic: $topic"
  confluent kafka topic describe "$topic" \
    --cluster prod-kafka-west
done

echo "Failover complete"
```

### Flink Job Recovery

#### Confluent Cloud Flink Statement Recovery

**Scenario**: Flink SQL statement fails or compute pool becomes unavailable

**Automatic Recovery** (Confluent Cloud):
- **Auto-Restart**: Confluent Cloud automatically restarts failed statements
- **Checkpoint Recovery**: Statements automatically restore from last checkpoint
- **State Preservation**: State is preserved across restarts
- **Monitoring**: Built-in monitoring alerts on statement failures

**Recovery Steps**:
1. **Check Statement Status**:
   ```bash
   confluent flink statement describe ss-456789 \
     --compute-pool cp-east-123
   ```

2. **Review Statement Logs**:
   ```bash
   # View statement logs in Confluent Cloud Console
   # Or via CLI
   confluent flink statement logs ss-456789 \
     --compute-pool cp-east-123
   ```

3. **Verify Auto-Recovery**: Confluent Cloud automatically restores from checkpoint
4. **Monitor Processing**: Verify events are being processed
5. **Check Lag**: Ensure consumer lag is decreasing

**Manual Recovery from Savepoint** (Confluent Cloud):
```bash
# List available savepoints
confluent flink statement savepoint list \
  --compute-pool cp-east-123 \
  --statement-id ss-456789

# Create savepoint before recovery
confluent flink statement savepoint create \
  --compute-pool cp-east-123 \
  --statement-id ss-456789 \
  --savepoint-dir s3://backup-bucket/flink/savepoints/

# Restore statement from savepoint
confluent flink statement update \
  --compute-pool cp-east-123 \
  --statement-id ss-456789 \
  --statement-file routing-generated.sql \
  --savepoint-path s3://backup-bucket/flink/savepoints/savepoint-123
```

#### Compute Pool Failure Recovery

**Scenario**: Compute pool becomes unavailable or fails

**Recovery Steps**:
1. **Check Compute Pool Status**:
   ```bash
   confluent flink compute-pool describe cp-east-123
   ```

2. **Verify High Availability**: Confluent Cloud automatically provides HA for compute pools
3. **Failover to Secondary Region**: If primary compute pool fails:
   ```bash
   # Deploy statements to secondary region compute pool
   confluent flink statement create \
     --compute-pool cp-west-456 \
     --statement-name event-routing-job-west \
     --statement-file routing-generated.sql
   ```

4. **Update Bootstrap Servers**: Update SQL statements to point to secondary region Kafka cluster
5. **Monitor Replication**: Ensure data is replicated to secondary region

**Compute Pool Auto-Scaling**:
- Confluent Cloud automatically scales compute pools based on workload
- No manual intervention required for scaling
- CFU usage is monitored and adjusted automatically

#### Self-Managed Flink Recovery

**Scenario**: Self-managed Flink cluster fails

**Recovery Steps**:
1. **Checkpoint Recovery**: Flink automatically restores from last checkpoint
2. **Verify State**: Check that state is restored correctly
3. **Monitor Processing**: Verify events are being processed
4. **Check Lag**: Ensure consumer lag is decreasing

**Manual Recovery from Savepoint** (Self-Managed):
```bash
# List available savepoints
flink savepoint list

# Restore job from savepoint
flink run \
  --fromSavepoint /path/to/savepoint \
  --class com.example.EventRoutingJob \
  /path/to/job.jar
```

**Via REST API** (Self-Managed):
```bash
# Trigger savepoint before recovery
SAVEPOINT_PATH=$(curl -X POST \
  "http://flink-jobmanager:8081/jobs/$JOB_ID/savepoints" \
  -H "Content-Type: application/json" \
  -d '{"target-directory":"/opt/flink/savepoints"}' \
  | jq -r '.request-id')

# Restore from savepoint
curl -X POST \
  "http://flink-jobmanager:8081/jobs/$JOB_ID/savepoints/$SAVEPOINT_PATH" \
  -H "Content-Type: application/json"
```

### Connector Recovery

#### Connector Failure Recovery

**Scenario**: Postgres source connector fails

**Recovery Steps**:
1. **Check Status**: 
   ```bash
   curl http://kafka-connect:8083/connectors/postgres-source-connector/status
   ```
2. **Review Logs**: Check connector logs for errors
3. **Restart Connector**:
   ```bash
   curl -X POST \
     http://kafka-connect:8083/connectors/postgres-source-connector/restart
   ```
4. **Verify Offset**: Check that connector resumes from last offset
5. **Monitor Lag**: Ensure connector catches up

---

## Failover Procedures

### Automated Failover

**Trigger Conditions**:
- Primary region unavailable for > 2 minutes
- Kafka cluster health < 50%
- Flink job failures > 3 in 5 minutes
- Consumer lag > 10,000 messages

**Failover Automation**:
```bash
#!/bin/bash
# scripts/automated-failover.sh

PRIMARY_REGION="us-east-1"
SECONDARY_REGION="us-west-2"
FAILOVER_THRESHOLD=120  # seconds

# Check primary region health
check_primary_health() {
  confluent kafka cluster describe prod-kafka-east > /dev/null 2>&1
}

# Monitor and failover
while true; do
  if ! check_primary_health; then
    FAILURE_TIME=$(date +%s)
    
    # Wait for threshold
    while [ $(($(date +%s) - $FAILURE_TIME)) -lt $FAILOVER_THRESHOLD ]; do
      sleep 10
      if check_primary_health; then
        echo "Primary region recovered"
        exit 0
      fi
    done
    
    # Execute failover
    echo "Executing failover to $SECONDARY_REGION"
    ./scripts/failover-kafka.sh
    ./scripts/failover-flink.sh
    ./scripts/failover-connectors.sh
    
    # Send alert
    send_alert "Automated failover executed to $SECONDARY_REGION"
    
    break
  fi
  
  sleep 30
done
```

### Manual Failover Procedure

**Step-by-Step**:

1. **Verify Secondary Region Health**
   ```bash
   # Check Kafka
   confluent kafka cluster describe prod-kafka-west
   
   # Check Flink
   confluent flink compute-pool describe cp-west-456
   
   # Check Schema Registry
   confluent schema-registry cluster describe
   ```

2. **Update DNS/Load Balancer**
   ```bash
   # Update Route53 records
   aws route53 change-resource-record-sets \
     --hosted-zone-id Z123456789 \
     --change-batch file://failover-route53.json
   ```

3. **Update Client Configurations**
   ```bash
   # Update bootstrap servers in all clients
   # Producer APIs
   # Consumer applications
   # Flink jobs
   ```

4. **Verify Data Availability**
   ```bash
   # Check topics exist
   confluent kafka topic list --cluster prod-kafka-west
   
   # Check message counts
   for topic in raw-business-events filtered-loan-events; do
     confluent kafka topic describe "$topic" \
       --cluster prod-kafka-west
   done
   ```

5. **Monitor Replication Lag**
   ```bash
   # Check cluster link lag
   confluent kafka cluster-link describe east-to-west-link \
     --cluster prod-kafka-west
   ```

6. **Restart Components**
   ```bash
   # Restart Flink jobs in secondary region
   ./scripts/deploy-flink-multi-region.sh --region us-west-2
   
   # Restart connectors
   curl -X POST http://kafka-connect-west:8083/connectors/postgres-source-connector/restart
   ```

---

## Data Integrity Verification

### Post-Recovery Verification

**Checks to Perform**:

1. **Message Count Verification**
   ```bash
   # Compare message counts between regions
   PRIMARY_COUNT=$(confluent kafka topic describe raw-business-events \
     --cluster prod-kafka-east \
     | jq '.partitions[].offset')
   
   SECONDARY_COUNT=$(confluent kafka topic describe raw-business-events \
     --cluster prod-kafka-west \
     | jq '.partitions[].offset')
   
   echo "Primary: $PRIMARY_COUNT, Secondary: $SECONDARY_COUNT"
   ```

2. **Schema Verification**
   ```bash
   # Compare schemas between regions
   confluent schema-registry subject list \
     --environment env-east > /tmp/schemas-east.txt
   
   confluent schema-registry subject list \
     --environment env-west > /tmp/schemas-west.txt
   
   diff /tmp/schemas-east.txt /tmp/schemas-west.txt
   ```

3. **Consumer Offset Verification**
   ```bash
   # Check consumer group offsets
   confluent kafka consumer-group describe loan-consumer-group \
     --cluster prod-kafka-east
   ```

---

## Recovery Testing

### Test Scenarios

#### 1. Single Component Failure

**Test**: Kill one Kafka broker (or simulate in Confluent Cloud)

**Expected**: System continues with remaining brokers

**Verification**:
- All topics remain accessible
- No data loss
- Replication continues

#### 2. Complete Region Failure

**Test**: Simulate complete us-east-1 failure

**Expected**: Automatic failover to us-west-2

**Verification**:
- Failover completes in < 15 minutes
- All services operational in secondary region
- Data available and consistent

#### 3. Flink Job Failure

**Test**: Kill Flink JobManager or stop job

**Expected**: Job restarts from last checkpoint

**Verification**:
- Job recovers within 5 minutes
- No duplicate events
- State restored correctly

### Testing Schedule

**Frequency**:
- **Weekly**: Single component failure tests
- **Monthly**: Multi-component failure tests
- **Quarterly**: Complete region failure drill
- **Annually**: Full disaster recovery exercise

---

## Runbooks

### Runbook: Kafka Cluster Failure

**Symptoms**:
- Cannot connect to Kafka brokers
- Consumer lag increasing
- Producer errors

**Steps**:
1. Verify broker status: `confluent kafka cluster describe <cluster-id>`
2. Check Confluent Cloud Console for alerts
3. If single broker: Confluent Cloud automatically replaces
4. If multiple brokers: Failover to secondary region
5. Verify recovery: Check topic accessibility and replication

### Runbook: Flink Job Failure

**Symptoms**:
- Flink statement status shows FAILED
- No events being processed
- Consumer lag increasing

**Steps** (Confluent Cloud):
1. **Check Statement Status**:
   ```bash
   confluent flink statement describe ss-456789 \
     --compute-pool cp-east-123
   ```

2. **Review Statement Logs**:
   - Access logs via Confluent Cloud Console
   - Or via CLI: `confluent flink statement logs ss-456789 --compute-pool cp-east-123`

3. **Check Compute Pool Status**:
   ```bash
   confluent flink compute-pool describe cp-east-123
   ```

4. **Verify Auto-Recovery**: Confluent Cloud automatically restarts failed statements
5. **Manual Restart** (if needed):
   ```bash
   confluent flink statement update \
     --compute-pool cp-east-123 \
     --statement-id ss-456789 \
     --statement-file routing-generated.sql
   ```

6. **Monitor Processing**: Verify events are being processed
7. **Check Consumer Lag**: Ensure lag decreases
8. **Verify Checkpoints**: Check that checkpoints are being created successfully

**Steps** (Self-Managed):
1. Check job status: `curl http://flink-jobmanager:8081/jobs`
2. Review job logs: `docker logs cdc-flink-jobmanager`
3. Check checkpoint status: `curl http://flink-jobmanager:8081/jobs/$JOB_ID/checkpoints`
4. Restart job from last checkpoint
5. Monitor processing: Verify events are being processed
6. Check consumer lag: Ensure lag decreases

### Runbook: Connector Failure

**Symptoms**:
- Connector status shows FAILED
- No new events in raw-business-events topic
- Connector logs show errors

**Steps**:
1. Check connector status: `curl http://kafka-connect:8083/connectors/postgres-source-connector/status`
2. Review connector logs
3. Check PostgreSQL connectivity
4. Verify replication slot: `SELECT * FROM pg_replication_slots WHERE slot_name = 'debezium_slot'`
5. Restart connector: `curl -X POST http://kafka-connect:8083/connectors/postgres-source-connector/restart`
6. Monitor offset: Verify connector resumes from last position

---

## Conclusion

This disaster recovery guide provides comprehensive procedures for maintaining business continuity in the CDC streaming architecture. Regular testing, monitoring, and documentation updates ensure the system can recover quickly from any failure scenario while maintaining data integrity and meeting RTO/RPO objectives.

**Key Takeaways**:
- **Automation**: Automate failover procedures where possible
- **Testing**: Regular disaster recovery drills are essential
- **Monitoring**: Proactive monitoring enables quick detection and response
- **Documentation**: Keep runbooks updated and accessible
- **Practice**: Regular practice ensures team readiness
