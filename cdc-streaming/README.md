# CDC Streaming System

> Real-time database change capture and event streaming with intelligent filtering and routing

A configurable streaming architecture that captures PostgreSQL database changes and routes filtered events to consumer-specific Kafka topics using Confluent Cloud and Flink SQL.

## What It Does

```text
PostgreSQL → CDC Connector → Kafka → Stream Processor → Filtered Topics → Consumers
```

The system automatically:

- **Captures** database changes via CDC
- **Streams** events to Kafka
- **Filters** events by type using Flink SQL or Spring Boot Kafka Streams
- **Routes** filtered events to processor-specific topics (with `-flink` or `-spring` suffix)
- **Enables** consumers to distinguish which processor created events

**Stream Processors:**
- **Flink SQL** (Confluent Cloud): Writes to `filtered-*-events-flink` topics
- **Spring Boot Kafka Streams**: Writes to `filtered-*-events-spring` topics

Consumers subscribe to the appropriate topic based on which processor is active.

## Visual Overview

<img src="screenshots/1-connector.png" alt="PostgreSQL CDC Connector Configuration" width="800"/>

*PostgreSQL CDC Source Connector configuration in Confluent Cloud*

<img src="screenshots/2-main-topic-lineage.png" alt="Main Topic Lineage" width="800"/>

*Data lineage showing the flow from PostgreSQL CDC connector through Kafka topics*

<img src="screenshots/3-all-topics.png" alt="All Topics Overview" width="800"/>

*Overview of all Kafka topics in the system*

<img src="screenshots/4-flink-insert-statement.png" alt="Flink Insert Statement" width="800"/>

*Flink SQL insert statement for filtering and routing events*

<img src="screenshots/5-consumer-log.png" alt="Consumer Application Logs" width="800"/>

*Example consumer application logs showing event processing*

## Quick Start

### Prerequisites

- **Confluent Cloud account** ([sign up](https://confluent.cloud))
- **Confluent CLI** (`brew install confluentinc/tap/cli`)
- **PostgreSQL database** (Aurora PostgreSQL or self-managed)
- **Network connectivity** between Confluent Cloud and PostgreSQL
- **AWS CLI** configured with appropriate credentials (for bastion host access)

### Setup Steps

1. **Follow the [Confluent Cloud Setup Guide](CONFLUENT_CLOUD_SETUP_GUIDE.md)**
   - Create environment and Kafka cluster
   - Set up Schema Registry
   - Create Flink compute pool
   - Deploy CDC connector
   - Deploy Flink SQL statements

2. **Verify the Pipeline**

   ```bash
   # Check connector status
   confluent connector describe postgres-source-connector
   
   # Check Flink statements
   confluent flink statement list --compute-pool <compute-pool-id>
   
   # Verify topics have messages
   confluent kafka topic consume raw-event-headers --max-messages 5
   ```

3. **Monitor in Confluent Cloud Console**
   - Navigate to <https://confluent.cloud>
   - View connectors, topics, and Flink statements
   - Monitor metrics and throughput

4. **Access Database via Bastion Host** (Optional)

   The bastion host provides secure access to the DSQL database for validation and debugging.

   **Note**: DSQL is only accessible from within the VPC. You must connect via the bastion host (recommended) or install `psql` locally and use IAM authentication.

   **Quick Query Script (Non-Interactive - Recommended):**

   ```bash
   # Run default table count query (no psql needed locally)
   ./scripts/query-dsql.sh
   
   # Or run a custom query
   ./scripts/query-dsql.sh "SELECT COUNT(*) FROM business_events WHERE created_date > NOW() - INTERVAL '1 hour';"
   ```

   **Interactive Connection via Bastion Host:**

   ```bash
   # Use the interactive connection script (connects via SSM)
   ./scripts/connect-dsql.sh
   
   # Once connected to bastion host, run these commands (shown by script):
   export DSQL_HOST=vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws
   export AWS_REGION=us-east-1
   export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)
   psql -h $DSQL_HOST -U admin -d postgres -p 5432
   
   # Example queries to verify events
   -- Count events by table
   SELECT 'business_events' as table_name, COUNT(*) as count FROM business_events
   UNION ALL SELECT 'event_headers', COUNT(*) FROM event_headers
   UNION ALL SELECT 'car_entities', COUNT(*) FROM car_entities
   UNION ALL SELECT 'loan_entities', COUNT(*) FROM loan_entities
   UNION ALL SELECT 'loan_payment_entities', COUNT(*) FROM loan_payment_entities
   UNION ALL SELECT 'service_record_entities', COUNT(*) FROM service_record_entities
   ORDER BY table_name;
   
   -- View recent events
   SELECT id, event_name, event_type, created_date 
   FROM business_events 
   ORDER BY created_date DESC 
   LIMIT 10;
   ```

   **Local Connection (Requires psql Installation):**

   If you want to connect directly from your local machine, install `psql` first:

   ```bash
   # macOS
   brew install postgresql@16
   
   # Then connect (DSQL must be publicly accessible)
   export DSQL_HOST=$(cd terraform && terraform output -raw aurora_dsql_host)
   export AWS_REGION=us-east-1
   export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)
   psql -h $DSQL_HOST -U admin -d postgres -p 5432
   ```

   **Note**: Direct local connection only works if DSQL is configured as publicly accessible. The bastion host method works regardless of public access settings.

## Key Features

- **Real-time CDC** from PostgreSQL to Kafka
- **Intelligent Filtering** via Flink SQL
- **Auto-scaling** with Confluent Cloud Flink
- **Schema Management** with Schema Registry
- **Multi-topic Routing** to consumer-specific topics
- **Fully Managed** infrastructure (Confluent Cloud)

## Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System architecture, data flow, and component details |
| [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md) | Complete step-by-step setup guide |
| [BACKEND_IMPLEMENTATION.md](BACKEND_IMPLEMENTATION.md) | Back-end infrastructure (Lambda, Aurora, RDS Proxy) |
| [ADVANCED_USE_CASES.md](ADVANCED_USE_CASES.md) | Advanced monitoring, testing, and configuration |
| [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md) | Disaster recovery procedures |

## Configuration

### Filter Configuration

**Dynamic Filter Configuration (Recommended)**

Filters can be managed through a unified JSON configuration file:

- `config/filters.json` - Unified filter configuration (single source of truth)
- `scripts/filters/generate-filters.sh` - Generate Flink SQL and Spring YAML from config
- `scripts/filters/validate-filters.sh` - Validate filter configuration
- `scripts/filters/deploy-flink-filters.sh` - Deploy filters to Flink
- `scripts/filters/deploy-spring-filters.sh` - Deploy filters to Spring Boot

See [FILTER_CONFIGURATION.md](docs/FILTER_CONFIGURATION.md) for complete documentation.

**Legacy Manual Configuration**

Filtering rules can also be defined manually in Flink SQL files:

- `flink-jobs/business-events-routing-confluent-cloud.sql` - Main routing job (streams from event_headers)
- `flink-jobs/generated/business-events-routing-confluent-cloud-generated.sql` - Auto-generated from filters.json

### Connector Configuration

Connector configuration files:

- `connectors/postgres-cdc-source-v2-debezium-event-headers-confluent-cloud.json` - Recommended connector

For detailed configuration, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Data Model

The system uses a **hybrid data model** combining:

- **Relational columns** for efficient filtering (`id`, `event_type`, `event_name`)
- **JSONB column** (`header_data`) for event header structure
- **Note**: Only header information is streamed. Entity information must be queried from the database separately if needed.

**Example Event Structure:**

See [`data/schemas/event/samples/loan-created-event.json`](../data/schemas/event/samples/loan-created-event.json) for a complete example.

**Schema Definitions:**

- Event schema: [`data/schemas/event/event.json`](../data/schemas/event/event.json)
- Entity schemas: [`data/schemas/entity/car.json`](../data/schemas/entity/car.json), [`data/schemas/entity/loan.json`](../data/schemas/entity/loan.json)
- Sample data: [`data/entities/car/car-large.json`](../data/entities/car/car-large.json)

For complete schema definitions, see the [data folder README](../data/README.md).

## Testing

### Basic Test Event Generation

```bash
cd cdc-streaming/scripts
./generate-test-data-from-examples.sh
```

### Load Testing with k6

```bash
# Send 100 events of each type
k6 run --env HOST=producer-api-java-rest --env PORT=8081 \
  --env EVENTS_PER_TYPE=100 \
  ../../load-test/k6/send-batch-events.js
```

For advanced testing scenarios including parallel execution and high-throughput testing, see [ADVANCED_USE_CASES.md](ADVANCED_USE_CASES.md).

## Monitoring

### Confluent Cloud Console

Monitor everything via the web console:

- **Connectors**: Status, throughput, errors
- **Topics**: Message counts, throughput, consumer lag
- **Flink Statements**: Processing metrics, latency, backpressure
- **Consumer Groups**: Lag, offsets, throughput

Access at: <https://confluent.cloud> → Your Environment

### Quick CLI Checks

```bash
# Check connector
confluent connector describe postgres-source-connector

# Check topics
confluent kafka topic list

# Check Flink statements
confluent flink statement list --compute-pool <compute-pool-id>
```

### Event Headers CDC Verification

To quickly verify that CDC is capturing changes from the `event_headers` table:

```bash
# Quick verification script (checks connector, topics, Flink, replication slots)
./cdc-streaming/scripts/quick-verify-event-headers-cdc.sh

# Monitor the full pipeline
./cdc-streaming/scripts/monitor-pipeline.sh

# Verify replication slot specifically
./cdc-streaming/scripts/verify-event-headers-replication-slot.sh
```

The verification scripts check:
- CDC connector is running and configured for `event_headers` table
- `raw-event-headers` topic exists and receives messages
- Flink SQL statements are processing events
- Database replication slot exists and is active (if database credentials provided)

### Database Validation via Bastion Host

To verify events are being stored in the database, use one of these methods:

**Option 1: Quick Query Script (Non-Interactive - Recommended, No psql needed locally)**

The script runs queries via the bastion host, so you don't need `psql` installed locally:

```bash
# Run default table count query (shows counts for all tables)
./scripts/query-dsql.sh

# Run a custom query
./scripts/query-dsql.sh "SELECT COUNT(*) as total_events FROM business_events;"

# Query recent events
./scripts/query-dsql.sh "SELECT id, event_name, event_type, created_date FROM business_events ORDER BY created_date DESC LIMIT 10;"
```

**Option 2: Interactive Connection via Bastion Host**

Connect to the bastion host (which has `psql` pre-installed):

```bash
# Connect interactively to the bastion host via SSM
./scripts/connect-dsql.sh

# The script will display connection commands. Once connected to bastion host, run:
# (psql is already installed on the bastion host)
export DSQL_HOST=vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws
export AWS_REGION=us-east-1
export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)
psql -h $DSQL_HOST -U admin -d postgres -p 5432

# Then run queries interactively
SELECT 'business_events' as table_name, COUNT(*) as count FROM business_events
UNION ALL SELECT 'event_headers', COUNT(*) FROM event_headers
UNION ALL SELECT 'car_entities', COUNT(*) FROM car_entities
UNION ALL SELECT 'loan_entities', COUNT(*) FROM loan_entities
UNION ALL SELECT 'loan_payment_entities', COUNT(*) FROM loan_payment_entities
UNION ALL SELECT 'service_record_entities', COUNT(*) FROM service_record_entities
ORDER BY table_name;
```

**Option 3: Local Connection (Requires psql Installation)**

If you want to connect directly from your local machine, install `psql` first:

```bash
# Install psql (macOS)
brew install postgresql@16

# Or if postgresql@16 not available:
brew install postgresql

# Then connect (requires DSQL to be publicly accessible)
export DSQL_HOST=$(cd terraform && terraform output -raw aurora_dsql_host)
export AWS_REGION=us-east-1
export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)
psql -h $DSQL_HOST -U admin -d postgres -p 5432
```

**Note**: Options 1 and 2 work regardless of DSQL public access settings since they connect via the bastion host within the VPC. Option 3 requires DSQL to be publicly accessible and `psql` installed locally.

For detailed monitoring commands and REST API integration, see [ADVANCED_USE_CASES.md](ADVANCED_USE_CASES.md).

## Architecture

```text
┌─────────────┐
│ PostgreSQL  │
│ business_   │
│ events      │
└──────┬──────┘
       │ CDC
       ▼
┌─────────────┐
│   Kafka     │
│ raw-business│
│  -events    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Flink SQL   │
│  Filtering  │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────┐
│   Filtered Topics           │
│ • filtered-loan-created-    │
│   events                    │
│ • filtered-car-created-     │
│   events                    │
│ • filtered-service-events   │
└──────┬──────────────────────┘
       │
       ▼
┌─────────────┐
│  Consumers  │
└─────────────┘
```

For detailed architecture documentation, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Related Documentation

- **[ARCHITECTURE.md](ARCHITECTURE.md)**: Complete system architecture and data flow
- **[CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md)**: Step-by-step setup instructions
- **[BACKEND_IMPLEMENTATION.md](BACKEND_IMPLEMENTATION.md)**: Back-end infrastructure details
- **[ADVANCED_USE_CASES.md](ADVANCED_USE_CASES.md)**: Advanced monitoring, testing, and configuration
- **[DISASTER_RECOVERY.md](DISASTER_RECOVERY.md)**: Disaster recovery procedures
