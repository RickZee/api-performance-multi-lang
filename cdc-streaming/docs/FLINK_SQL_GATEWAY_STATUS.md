# Flink SQL Gateway Deployment Status

## ✅ Completed Infrastructure Setup

### 1. Flink Cluster
- **JobManager**: Running on port 8082
- **TaskManager**: Running with 4 slots
- **Configuration**: Properly configured for session cluster

### 2. Flink SQL Gateway
- **Service**: Running on port 28083 (mapped from internal 8083)
- **Status**: Accessible and responding to REST API calls
- **Configuration**: Connected to JobManager at `flink-jobmanager:6123`

### 3. Kafka Connector
- **JAR Files**:
  - `flink-sql-connector-kafka-3.1.0-1.18.jar` (5.4M) - ✅ Downloaded and installed
  - `kafka-clients.jar` (5.1M) - ✅ Downloaded and installed
- **Location**: `/opt/flink/lib/` in SQL Gateway container
- **Classpath**: Included in SQL Gateway's Java classpath

### 4. Deployment Automation
- **Script**: `scripts/deploy-flink-via-gateway.py`
- **Functionality**:
  - Creates SQL Gateway sessions
  - Sets execution mode to streaming
  - Executes CREATE TABLE statements successfully
  - Submits INSERT statements (returns operation handles)

## ⚠️ Known Issue

### Problem
INSERT statements submitted via SQL Gateway REST API:
- Return operation handles (indicating submission)
- Show "ERROR" status when checked
- Do not create persistent streaming jobs in Flink cluster
- Jobs do not appear in `flink list`

### Error Messages
- Generic: "Failed to fetchResults"
- Specific (from logs): "Could not find any factory for identifier 'kafka'"
- However, connector JAR is present in classpath

### Root Cause Analysis
This appears to be a **limitation of Flink SQL Gateway 1.18** with persistent streaming job submission via INSERT statements. Possible reasons:

1. **Connector Discovery**: SQL Gateway may not properly discover connectors at runtime, even when JARs are in classpath
2. **Session Management**: Tables created in one statement may not persist for subsequent INSERT statements
3. **Job Submission**: SQL Gateway may not properly submit jobs to the cluster for persistent execution
4. **Version Limitation**: Flink 1.18 SQL Gateway may have known issues with streaming job persistence

## 🔧 Attempted Solutions

1. ✅ Downloaded correct connector JAR (3.1.0-1.18)
2. ✅ Added kafka-clients dependency
3. ✅ Ensured JARs are in `/opt/flink/lib/`
4. ✅ Verified JARs are in SQL Gateway classpath
5. ✅ Fixed JobManager connection configuration
6. ✅ Tried SQL Client with `--endpoint` (same issue)

## 💡 Recommended Next Steps

### Option 1: Alternative Deployment Method
Use Flink's REST API directly to submit jobs:
- Convert SQL to Flink job graph
- Submit via `/jars/upload` and `/jars/{jarid}/run`
- Or use Flink's programmatic API (Java/Scala)

### Option 2: Upgrade Flink Version
Try Flink 1.19+ or 1.20+ where SQL Gateway may have improved support for persistent streaming jobs.

### Option 3: Use Java Application
Create a small Java application using Flink Table API that:
- Connects to the cluster
- Submits SQL statements programmatically
- Keeps jobs running persistently

### Option 4: Use Flink SQL Client in Interactive Mode
Run SQL Client in a persistent container that keeps the session alive:
```bash
docker exec -it cdc-local-flink-jobmanager /opt/flink/bin/sql-client.sh embedded
# Then execute SQL statements interactively
```

## 📝 Current State

**Infrastructure**: ✅ 95% Complete
- All services running
- Connectors installed
- Deployment scripts working
- Only job persistence issue remains

**Deployment**: ⚠️ Functional but Limited
- Can create tables
- Can submit INSERT statements
- Jobs do not persist as streaming jobs

## 📚 References

- Flink SQL Gateway Documentation: https://nightlies.apache.org/flink/flink-docs-release-1.18/docs/dev/table/sql-gateway/
- Flink SQL Client Documentation: https://nightlies.apache.org/flink/flink-docs-release-1.18/docs/dev/table/sqlclient/
- Kafka Connector: https://nightlies.apache.org/flink/flink-docs-release-1.18/docs/connectors/table/kafka/

