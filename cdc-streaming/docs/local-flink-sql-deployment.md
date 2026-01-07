To resolve the issue with deploying your Flink SQL INSERT statements as persistent streaming jobs, the core problem is the use of the SQL Client in embedded mode (`sql-client.sh embedded -f file.sql`). This mode spins up a temporary local mini-cluster that executes the statements but terminates when the client session exits, preventing continuous processing. For persistent streaming jobs (like your CDC-based filtering and routing), you need to submit the SQL to a running Flink session cluster, where jobs execute independently and remain active until canceled.

Your existing Docker Compose setup (with separate JobManager and TaskManager services) is already configured as a session cluster, which is ideal for this. However, the deployment script isn't connecting to it properly. The recommended fix is to add and use the Flink SQL Gateway, which provides a REST API for submitting SQL to the cluster. This is available in Flink 1.18 and ensures jobs run persistently. It's lightweight, integrates seamlessly with your setup, and supports automation via scripts (e.g., curl or the SQL Client with `--endpoint`).

### Step 1: Update Docker Compose for SQL Gateway
Add a new service to your `docker-compose.yml` file for the SQL Gateway. This runs alongside your JobManager and TaskManager, exposing a REST endpoint for job submission. Ensure the Kafka connector JARs are in `/opt/flink/lib/` on all services (JobManager, TaskManager, and SQL Gateway) for consistency—your volume mounts already handle this.

```yaml
services:
  # Existing JobManager service (ensure it has the updated configs you mentioned)
  cdc-local-flink-jobmanager:
    image: flink:1.18.0-scala_2.12
    # ... (your existing config, ports, volumes, etc.)
    environment:
      - FLINK_PROPERTIES=jobmanager.rpc.address: cdc-local-flink-jobmanager
        taskmanager.numberOfTaskSlots: 4
        parallelism.default: 1
        state.backend: filesystem
        state.checkpoints.dir: file:///opt/flink/checkpoints

  # Existing TaskManager service
  cdc-local-flink-taskmanager:
    image: flink:1.18.0-scala_2.12
    # ... (your existing config, depends_on: cdc-local-flink-jobmanager, etc.)

  # New: SQL Gateway service
  cdc-local-flink-sql-gateway:
    image: flink:1.18.0-scala_2.12
    command: bin/sql-gateway.sh start -Dsql-gateway.endpoint.rest.address=0.0.0.0 -Dsql-gateway.endpoint.rest.port=8083
    ports:
      - "8083:8083"  # Expose REST API (access from host at localhost:8083)
    depends_on:
      - cdc-local-flink-jobmanager
    environment:
      - FLINK_PROPERTIES=jobmanager.rpc.address: cdc-local-flink-jobmanager
    volumes:
      - ./flink-jobs:/opt/flink/jobs
      - ./flink-connectors:/opt/flink/lib  # Ensure connectors are available here
```

- **Key Changes**:
  - Command starts the SQL Gateway with REST binding to all interfaces (for Docker accessibility).
  - Environment points to the JobManager for cluster coordination.
  - Volumes match your existing mounts for SQL files and connectors.
- Restart your cluster: `docker-compose up -d`.
- Verify: Access `http://localhost:8083/v1/info` (should return Flink version info). Check Flink Web UI at `http://localhost:8082` (your mapped port) for cluster status.

### Step 2: Update Deployment Script
Replace your current script's background/nohup approach with submissions via the SQL Gateway. This ensures jobs are submitted to the running cluster and persist.

Two options for the script: (a) Use `curl` for pure REST (fully non-interactive, ideal for CI/CD), or (b) Use SQL Client with `--endpoint` (simpler if you prefer executing the full SQL file at once). I'll provide both—start with (b) for ease, as it handles your multi-statement SQL file directly.

#### Option (a): Using curl (REST API) for Granular Submission
This submits statements sequentially. Parse your `business-events-routing-local-docker.sql` to separate DDL (CREATE TABLE) from DML (INSERT). Submit CREATEs first (they're synchronous), then each INSERT (starts a persistent job).

Example updated `deploy-flink-local.sh` snippet (replace lines 77-159):

```bash
#!/bin/bash

GATEWAY_URL="http://localhost:8083/v1"  # Host-accessible URL
SQL_FILE="business-events-routing-local-docker.sql"

# Step 1: Create a session
SESSION_RESPONSE=$(curl -s -X POST "$GATEWAY_URL/sessions")
SESSION_HANDLE=$(echo "$SESSION_RESPONSE" | jq -r '.sessionHandle')  # Requires jq installed

# Step 2: Extract and submit all CREATE TABLE statements (as one batch)
CREATE_STATEMENTS=$(grep -E '^CREATE TABLE' "$SQL_FILE" | tr '\n' ' ')  # Combine into single statement if needed
curl -s -X POST "$GATEWAY_URL/sessions/$SESSION_HANDLE/statements" -d "{\"statement\": \"$CREATE_STATEMENTS\"}"
# Wait briefly and check status if needed (fetch operationHandle and poll /operations/{handle}/status)

# Step 3: Extract and submit each INSERT statement individually
INSERT_STATEMENTS=$(grep -E '^INSERT INTO' "$SQL_FILE")
echo "$INSERT_STATEMENTS" | while read -r INSERT; do
  RESPONSE=$(curl -s -X POST "$GATEWAY_URL/sessions/$SESSION_HANDLE/statements" -d "{\"statement\": \"$INSERT\"}")
  OPERATION_HANDLE=$(echo "$RESPONSE" | jq -r '.operationHandle')
  echo "Submitted job for: $INSERT (Operation: $OPERATION_HANDLE)"
  # Optionally poll status: curl "$GATEWAY_URL/sessions/$SESSION_HANDLE/operations/$OPERATION_HANDLE/status"
done

# Close session if no longer needed
curl -s -X DELETE "$GATEWAY_URL/sessions/$SESSION_HANDLE"
```

- **Why This Works**: Each INSERT submits a detached streaming job to the cluster. Jobs appear in `flink list` and process events continuously from `raw-event-headers`.
- **Tips**: Install `jq` for JSON parsing. For error handling, add status polling loops. If your SQL has dependencies, submit in order.

#### Option (b): Using SQL Client with --endpoint (File-Based Submission)
Run the SQL Client from within Docker, connected to the Gateway. This executes your entire SQL file non-interactively, submitting jobs persistently.

Updated script snippet:

```bash
#!/bin/bash

# Run from host: Use docker-compose to exec into JobManager (or add a temporary SQL Client service)
docker-compose exec cdc-local-flink-jobmanager bin/sql-client.sh --endpoint http://cdc-local-flink-sql-gateway:8083 -f /opt/flink/jobs/business-events-routing-local-docker.sql

# Alternatively, add a one-off SQL Client service in docker-compose.yml and run `docker-compose run sql-client`
# sql-client service example:
#   cdc-local-flink-sql-client:
#     image: flink:1.18.0-scala_2.12
#     command: bin/sql-client.sh --endpoint http://cdc-local-flink-sql-gateway:8083 -f /opt/flink/jobs/business-events-routing-local-docker.sql
#     depends_on:
#       - cdc-local-flink-sql-gateway
#     volumes:
#       - ./flink-jobs:/opt/flink/jobs
```

- **Why This Works**: `--endpoint` connects to the Gateway, submitting to the remote cluster. The client executes the file and exits, but jobs persist. Your 4 INSERTs will each launch a RUNNING job visible in `flink list` or the Web UI.
- **Verification**: After running, check `docker-compose exec cdc-local-flink-jobmanager bin/flink list`—expect 4 running jobs. Produce events to `raw-event-headers` and confirm continuous filtering to sink topics.

### Additional Recommendations
- **Monitoring & Scaling**: Use the Flink Web UI (`localhost:8082`) to monitor jobs, cancel if needed (`flink cancel <job-id>`), and adjust parallelism/slots based on load. With 4 slots, your 4 jobs (one per INSERT) should fit; scale TaskManagers if needed (`docker-compose scale cdc-local-flink-taskmanager=2`).
- **Error Handling**: If jobs fail (e.g., due to Kafka config), check logs via `docker-compose logs` or Web UI. Ensure `bootstrap.servers: redpanda:9092` is resolvable within containers.
- **Testing**: Start with a single INSERT in a test SQL file to validate persistence. Confirm consumers receive continuous events (not just one).
- **Alternatives if Needed**:
  - If SQL Gateway overhead is a concern (minimal, but), package your SQL as a Java/Scala app using Flink's Table API and submit as a JAR via `flink run`.
  - For production evolution: Consider Kubernetes (EKS-aligned) with Flink's application mode for better scalability.

This aligns with your AWS EKS/Aurora/Confluent Kafka infrastructure—treat this local setup as a prototype for cloud migration, where you'd use Flink's Kubernetes operator for session clusters and job submission. If issues persist (e.g., connector loading), share error logs for further debugging.

## Remaining Issues

To address the remaining limitation with Flink SQL Gateway in version 1.18—where INSERT statements submitted via the REST API or SQL Client (with `--endpoint`) are tied to session mode and do not persist as long-running streaming jobs after the session closes—we need a deployment approach that supports detached, persistent execution in your session cluster. Based on the architecture (EKS-hosted microservices, Aurora Postgres with CDC via Qlik Replicate to Confluent Kafka, and downstream data lake processing with EMR on EKS, Iceberg tables, Dremio, and Snowflake federation), this local Docker Compose setup is a prototype for active-active regional failover. Ensuring persistent streaming aligns with production reliability, avoiding session-bound jobs that could fail on restarts or scaling.

Upgrading to Flink 1.19 (released March 2024) or later (e.g., 1.20 LTS from August 2024) is worth considering for potential improvements in SQL submission stability, but the core issue stems from SQL Gateway's experimental nature and lack of native application mode support in these versions (per ongoing FLIP-316 discussions). If upgrading the Docker image to `flink:1.19.1-scala_2.12` resolves it via testing, great—it's a low-risk change here. However, for robustness, I recommend wrapping your SQL in a simple Java application using the Table API. This packages the job as a JAR, submits it via `flink run -d` (detached mode), and ensures it runs persistently on the cluster until explicitly canceled, independent of any client session. This mirrors how we'd deploy streaming jobs in EKS for fault-tolerant, scalable processing, with monitoring via ELK/APM and secrets from HashiCorp Vault.

### Step 1: Create the Java Application
Create a new Maven project (or plain Java) for the job. The app will:
- Use `TableEnvironment` in streaming mode.
- Execute your CREATE TABLE statements (source and sinks).
- Use a `StatementSet` to bundle the 4 INSERT statements into a single job (efficient for parallel execution on your 4 task slots; avoids multiple separate jobs).
- Block indefinitely for continuous processing from `raw-event-headers` to the filtered sink topics.

File: `src/main/java/com/example/BusinessEventsRoutingJob.java`
```java
import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.StatementSet;
import org.apache.flink.table.api.TableEnvironment;

public class BusinessEventsRoutingJob {
    public static void main(String[] args) {
        // Set up streaming environment
        EnvironmentSettings settings = EnvironmentSettings.newInstance()
                .inStreamingMode()
                .build();
        TableEnvironment tEnv = TableEnvironment.create(settings);

        // Execute CREATE TABLE for source (adapt from your SQL file)
        tEnv.executeSql(
                "CREATE TABLE raw_event_headers (" +
                "    -- Your schema here, e.g., event_id STRING, event_type STRING, __op STRING, etc. " +
                ") WITH (" +
                "    'connector' = 'kafka'," +
                "    'topic' = 'raw-event-headers'," +
                "    'properties.bootstrap.servers' = 'redpanda:9092'," +
                "    'format' = 'debezium-json'," +
                "    'scan.startup.mode' = 'earliest-offset' " +  // Or 'latest-offset' as needed
                ")"
        );

        // Execute CREATE TABLE for sinks (adapt similarly)
        tEnv.executeSql(
                "CREATE TABLE filtered_car_created_events_flink (" +
                "    -- Sink schema " +
                ") WITH (" +
                "    'connector' = 'kafka'," +
                "    'topic' = 'filtered-car-created-events'," +  // Adapt topic name
                "    'properties.bootstrap.servers' = 'redpanda:9092'," +
                "    'format' = 'json' " +  // Or debezium-json if needed
                ")"
        );
        // Repeat for other 3 sinks: filtered_loan_created_events_flink, etc.

        // Bundle INSERTs into one job via StatementSet
        StatementSet stmtSet = tEnv.createStatementSet();

        stmtSet.addInsertSql(
                "INSERT INTO filtered_car_created_events_flink " +
                "SELECT * FROM raw_event_headers " +
                "WHERE event_type = 'car_created' AND __op = 'c'"  // Adapt filters/transforms
        );

        stmtSet.addInsertSql(
                "INSERT INTO filtered_loan_created_events_flink " +
                "SELECT * FROM raw_event_headers " +
                "WHERE event_type = 'loan_created' AND __op = 'c'"
        );

        // Add the other 2 INSERTs similarly

        // Execute as a single persistent streaming job
        stmtSet.execute();  // Blocks for streaming; job runs continuously
    }
}
```

- **Adaptations**: Copy schema, WITH options, and SELECT logic from `business-events-routing-local-docker.sql`. Ensure Kafka connector properties match (e.g., no 'confluent' if using plain Kafka).
- **Dependencies**: In `pom.xml` (for Maven):
  ```xml
  <dependencies>
      <dependency>
          <groupId>org.apache.flink</groupId>
          <artifactId>flink-table-api-java</artifactId>
          <version>1.18.0</version>
          <scope>provided</scope>  <!-- Cluster provides Flink runtime -->
      </dependency>
      <dependency>
          <groupId>org.apache.flink</groupId>
          <artifactId>flink-table-planner_2.12</artifactId>  <!-- For SQL planning -->
          <version>1.18.0</version>
          <scope>provided</scope>
      </dependency>
  </dependencies>
  ```
  Build: `mvn clean package` → Produces `target/business-events-routing-job-1.0.jar` (thin JAR, since connectors are in `/opt/flink/lib/`).

### Step 2: Update Docker Compose and Volumes
Mount the JAR:
```yaml
services:
  cdc-local-flink-jobmanager:
    volumes:
      - ./flink-jobs:/opt/flink/jobs  # Already have; place JAR here
      # ... other configs
```

Copy the JAR to `./flink-jobs/business-events-routing-job.jar` on host.

### Step 3: Update Deployment Script (`deploy-flink-local.sh`)
Replace SQL Client logic with JAR submission. Exec into JobManager to run:
```bash
#!/bin/bash

# Create tables via SQL Client (DDL is synchronous, no persistence needed)
docker-compose exec cdc-local-flink-jobmanager bin/sql-client.sh embedded -f /opt/flink/jobs/business-events-routing-local-docker.sql  # But extract only CREATEs if needed

# Submit the streaming job JAR detached
docker-compose exec cdc-local-flink-jobmanager bin/flink run \
  -m cdc-local-flink-jobmanager:6123 \  # JobManager address
  -c com.example.BusinessEventsRoutingJob \  # Entry class
  -d \  # Detached for persistence
  /opt/flink/jobs/business-events-routing-job.jar
```

- **Why Detached?** `-d` submits the job and exits the client, but the job remains RUNNING in the cluster (visible in `flink list` or Web UI at localhost:8082).
- **Verification**: 
  - `docker-compose exec cdc-local-flink-jobmanager bin/flink list` → Shows 1 RUNNING job.
  - Produce events to `raw-event-headers` → Confirm continuous routing to sinks (e.g., via Kafka consumers).
  - If job fails (e.g., missing JARs), check logs in Web UI or `docker logs`.

### Testing and Evolution Strategy
- **Local Testing**: Run with sample events; validate against Spring Boot pipeline. Use ELK-like local logging for APM simulation.
- **Production Migration**: In EKS, package this JAR in your CI/CD (e.g., via GitHub Actions/ Jenkins), deploy via Flink Kubernetes Operator for active-active (regional JobManagers with HA via ZooKeeper). Integrate with AIM for cross-account, PingID auth, and Vault for Kafka creds. For scaling, adjust `parallelism.default` or per-operator via annotations. Test failover by simulating region outage—CDC and Confluent Kafka ensure no data loss.
- **Alternatives if JAR is Overkill**: If upgrading to Flink 1.20+ (where FLIP-316 may land for application-mode SQL submission), revisit Gateway. Or keep sessions alive via a dedicated container running SQL Client interactively (less ideal for automation).
