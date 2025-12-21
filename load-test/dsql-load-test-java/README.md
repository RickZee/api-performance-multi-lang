# DSQL Load Test - Java Implementation

A Java-based load testing tool for measuring DSQL (Aurora Data API) insert performance using parallel threads. This implementation provides the same functionality as the Python Lambda-based load test, but runs directly on a bastion host or local machine.

## Status

✅ **Completed:**
- Java project structure with Maven
- DSQL connection manager using AWS DSQL JDBC Connector
- Event generators supporting all event types and configurable payload sizes
- Both scenarios implemented (Individual and Batch inserts)
- Dockerfile and deployment script
- Full configuration parity with Lambda load test

## Overview

This project implements two test scenarios to measure inserts into the `business_events` table in DSQL:

1. **Scenario 1: Individual Inserts** - Parallel threads, each looping N times and performing M individual INSERT statements per iteration
2. **Scenario 2: Batch Inserts** - Parallel threads, each looping N times and performing 1 batch INSERT statement with configurable rows per iteration

Both scenarios use configurable loop iterations to simulate sustained high-load scenarios.

### Data Model

The load test inserts events into the `car_entities_schema.business_events` table with the following schema:

```sql
CREATE TABLE car_entities_schema.business_events (
    id VARCHAR(255) PRIMARY KEY,
    event_name VARCHAR(255) NOT NULL,
    event_type VARCHAR(255),
    created_date TIMESTAMP WITH TIME ZONE,
    saved_date TIMESTAMP WITH TIME ZONE,
    event_data TEXT NOT NULL  -- entire event JSON as TEXT (DSQL doesn't support JSONB)
);
```

**Note**: DSQL (Aurora Data API) has significant limitations compared to regular PostgreSQL:
- **Does not support JSONB** - Uses `TEXT` instead for JSON storage
- Does not support FOREIGN KEY constraints
- Does not support CREATE INDEX (indexes must be created separately via ASYNC syntax or not at all)
- Limited PostgreSQL feature set

The `event_data` column stores the complete event as TEXT (JSON string), which means:
- JSON is stored as plain text (not binary format)
- No native JSON indexing support (unlike JSONB in regular PostgreSQL)
- JSON operations require parsing the TEXT value

## Configuration

The Java load test supports the same configuration parameters as the Lambda load test, configured via environment variables.

### Environment Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `DSQL_HOST` | DSQL endpoint hostname | `vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws` | `your-cluster.dsql-fnh4.us-east-1.on.aws` |
| `DSQL_PORT` | DSQL port | `5432` | `5432` |
| `DATABASE_NAME` | Database name | `postgres` | `postgres` |
| `IAM_USERNAME` | IAM database user | `lambda_dsql_user` | `lambda_dsql_user` |
| `AWS_REGION` | AWS region | `us-east-1` | `us-east-1` |
| `SCENARIO` | Scenario to run: `1`, `2`, `both`, `individual`, or `batch` | `both` | `1` |
| `THREADS` | Number of parallel threads | `5` | `10` |
| `ITERATIONS` | Number of loop iterations per thread | `2` | `100` |
| `COUNT` | For Scenario 1: inserts per iteration<br>For Scenario 2: rows per batch | `1` | `10` |
| `EVENT_TYPE` | Event type to generate | `CarCreated` | `LoanCreated` |
| `PAYLOAD_SIZE` | Event payload size | `null` (default ~0.5-0.7 KB) | `4k` |

### Event Types

The load test supports four event types, matching the Lambda implementation:

- **CarCreated** - Car creation events with vehicle details
- **LoanCreated** - Loan creation events (requires carId)
- **LoanPaymentSubmitted** - Loan payment events (requires loanId)
- **CarServiceDone** - Car service events (requires carId)
- **random** - Randomly selects from all event types

### Payload Size Configuration

Event sizes are configurable via the `PAYLOAD_SIZE` environment variable. Size control is achieved by expanding `description` fields in the JSON schema, matching the approach used in the Python Lambda implementation.

**Supported Values:**
- **Default (null)**: ~0.5-0.7 KB per event - basic event data only
  - CarCreated: ~0.67 KB (687 bytes)
  - LoanCreated: ~0.69 KB (711 bytes)
  - LoanPaymentSubmitted: ~0.53 KB (539 bytes)
  - CarServiceDone: ~0.68 KB (698 bytes)

- **4k** (4,096 bytes): ~4 KB per event - adds nested structures (owner, insurance, maintenance, features, serviceHistory) with expanded descriptions
- **8k** (8,192 bytes): ~8 KB per event - expands all nested structures with more description text
- **32k** (32,768 bytes): ~32 KB per event - large events with extensive description fields
- **64k** (65,536 bytes): ~64 KB per event - very large events for testing TEXT storage performance
- **200k** (204,800 bytes): ~200 KB per event - extra-large events for stress testing
- **500k** (512,000 bytes): ~500 KB per event - maximum size events for extreme testing

**Description-Based Size Control**: The generator uses the `description` attribute from the JSON schema to control payload size. Description fields are expanded with realistic text across:
- Main entity `description` field
- Nested object descriptions (`owner.description`, `insurance.description`, `maintenance.description`, etc.)
- Array item descriptions (service history, payment history, parts, etc.)

For batch inserts (Scenario 2) with default size, a single INSERT statement with 100 rows contains approximately **50-70 KB** of TEXT data (JSON stored as text). With 4k payload size, it would be approximately **400 KB** per batch insert. With 200k payload size, it would be approximately **20 MB** per batch insert.

**Note**: Events are stored as TEXT in DSQL (DSQL doesn't support JSONB).

### Scenario Naming

The `SCENARIO` environment variable supports both numeric and named formats for compatibility:

- **Numeric**: `1` (individual), `2` (batch), `both` (runs both)
- **Named**: `individual` (same as `1`), `batch` (same as `2`), `both` (runs both)

## Configuration Comparison

| Parameter | Lambda Load Test | Java Load Test | Notes |
|-----------|------------------|----------------|-------|
| Connection | Environment variables | Environment variables | Same |
| Scenario | `scenario` in payload | `SCENARIO` env var | Java uses env vars |
| Threads/Concurrency | `num_lambdas` in config | `THREADS` env var | Java uses threads instead of Lambdas |
| Iterations | `iterations` in payload | `ITERATIONS` env var | Same concept |
| Count/Batch Size | `count`/`rows_per_batch` in payload | `COUNT` env var | Same concept |
| Event Type | `event_type` in payload | `EVENT_TYPE` env var | Same values |
| Payload Size | `payload_size` in payload | `PAYLOAD_SIZE` env var | Same values |

## Usage Examples

### Basic Test (Default Configuration)

```bash
cd load-test/dsql-load-test-java
./deploy-to-bastion.sh
```

This runs both scenarios with default settings:
- 5 threads
- 2 iterations per thread
- 1 insert per iteration (Scenario 1) or 1 row per batch (Scenario 2)
- CarCreated events
- Default payload size (~0.5-0.7 KB)

### Custom Configuration

```bash
export SCENARIO=1
export THREADS=10
export ITERATIONS=100
export COUNT=10
export EVENT_TYPE=CarCreated
export PAYLOAD_SIZE=4k

cd load-test/dsql-load-test-java
./deploy-to-bastion.sh
```

### Run Scenario 2 with Large Payloads

```bash
export SCENARIO=2
export THREADS=5
export ITERATIONS=10
export COUNT=100
export EVENT_TYPE=LoanCreated
export PAYLOAD_SIZE=32k

cd load-test/dsql-load-test-java
./deploy-to-bastion.sh
```

### Test All Event Types

```bash
# Test CarCreated
export EVENT_TYPE=CarCreated
./deploy-to-bastion.sh

# Test LoanCreated
export EVENT_TYPE=LoanCreated
./deploy-to-bastion.sh

# Test LoanPaymentSubmitted
export EVENT_TYPE=LoanPaymentSubmitted
./deploy-to-bastion.sh

# Test CarServiceDone
export EVENT_TYPE=CarServiceDone
./deploy-to-bastion.sh

# Test random event types
export EVENT_TYPE=random
./deploy-to-bastion.sh
```

### Test Different Payload Sizes

```bash
# Small events (default)
export PAYLOAD_SIZE=
./deploy-to-bastion.sh

# 4KB events
export PAYLOAD_SIZE=4k
./deploy-to-bastion.sh

# 32KB events
export PAYLOAD_SIZE=32k
./deploy-to-bastion.sh

# 200KB events
export PAYLOAD_SIZE=200k
./deploy-to-bastion.sh
```

## Event Structure

Events follow a standardized structure with `eventHeader` and `entities`, matching the Lambda implementation:

```json
{
  "eventHeader": {
    "uuid": "d75a9b47-66d4-435b-956e-3184db68555b",
    "eventName": "Car Created",
    "eventType": "CarCreated",
    "createdDate": "2025-12-19T20:39:17.937238Z",
    "savedDate": "2025-12-19T20:39:17.937238Z"
  },
  "entities": [{
    "entityHeader": {
      "entityId": "CAR-20251219-79",
      "entityType": "Car",
      "createdAt": "2025-12-19T20:39:17.937238Z",
      "updatedAt": "2025-12-19T20:39:17.937238Z"
    },
    "id": "CAR-20251219-79",
    "vin": "BENYFPPYPV9T7AH9A",
    "make": "BMW",
    "model": "X5",
    "year": 2025,
    "color": "Deep Blue",
    "mileage": 30105
    // ... additional entity-specific fields
  }]
}
```

### Insert Examples

**Individual Insert (Scenario 1):**

```sql
INSERT INTO car_entities_schema.business_events (id, event_name, event_type, created_date, saved_date, event_data)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (id) DO NOTHING;
```

**Batch Insert (Scenario 2):**

```sql
INSERT INTO car_entities_schema.business_events (id, event_name, event_type, created_date, saved_date, event_data)
VALUES ($1, $2, $3, $4, $5, $6), ($7, $8, $9, $10, $11, $12), ... (100 rows)
ON CONFLICT (id) DO NOTHING;
```

## Project Structure

```
load-test/dsql-load-test-java/
├── src/main/java/com/loadtest/dsql/
│   ├── DSQLLoadTest.java          # Main test class
│   ├── DSQLConnection.java        # Connection manager (uses AWS DSQL JDBC Connector)
│   ├── EventGenerator.java        # Event generators (all event types + payload size support)
│   └── EventRepository.java       # Database repository
├── pom.xml                        # Maven configuration
├── Dockerfile                     # Container build
├── deploy-to-bastion.sh          # Deployment script
└── README.md                      # This file
```

## Prerequisites

- Java 17+
- Maven 3.8+
- AWS CLI configured with appropriate credentials
- Access to Aurora DSQL cluster
- IAM permissions for DSQL connection (via EC2 instance profile or IAM role)
- Docker (for containerized deployment)

## Deployment

### Deploy to Bastion Host

The `deploy-to-bastion.sh` script builds the Java application, packages it, and deploys it to the bastion host via AWS SSM:

```bash
cd load-test/dsql-load-test-java
./deploy-to-bastion.sh
```

The script:
1. Builds the Maven project
2. Creates a deployment package
3. Uploads to S3 (if configured) or builds directly on bastion
4. Executes via AWS SSM on the bastion host
5. Verifies IAM grants before running

### Local Execution

To run locally (requires DSQL access and IAM credentials):

```bash
export DSQL_HOST=your-cluster.dsql-fnh4.us-east-1.on.aws
export DATABASE_NAME=postgres
export IAM_USERNAME=your_iam_user
export AWS_REGION=us-east-1
export SCENARIO=1
export THREADS=5
export ITERATIONS=10
export COUNT=1
export EVENT_TYPE=CarCreated
export PAYLOAD_SIZE=4k

mvn clean package -DskipTests
java -jar target/dsql-load-test-1.0.0.jar
```

## Implementation Details

### AWS DSQL JDBC Connector

The implementation uses the official AWS DSQL JDBC Connector (`software.amazon.dsql:aurora-dsql-jdbc-connector`) which:
- Automatically handles IAM token generation
- Manages token refresh and expiration
- Simplifies connection management
- Uses `jdbc:aws-dsql:postgresql://` URL prefix

### Connection Pooling

Uses HikariCP for connection pooling:
- Maximum pool size: 5 connections per thread
- Connection timeout: 30 seconds
- Idle timeout: 10 minutes
- Max lifetime: 30 minutes

### Event Generation

The `EventGenerator` class:
- Supports all 4 event types (CarCreated, LoanCreated, LoanPaymentSubmitted, CarServiceDone)
- Implements payload size expansion via description field expansion
- Matches Python Lambda implementation behavior
- Generates realistic random data

## Troubleshooting

### Connection Issues

If you encounter connection errors:
1. Verify IAM grants are configured: `scripts/grant-bastion-dsql-access.sh`
2. Check EC2 instance profile has DSQL permissions
3. Verify DSQL endpoint and region are correct
4. Ensure network connectivity to DSQL endpoint

### Performance Issues

For better performance:
- Increase `THREADS` for more parallelism
- Adjust `ITERATIONS` and `COUNT` based on test duration needs
- Monitor connection pool usage
- Consider batch size vs. individual inserts for your use case

## Comparison with Lambda Load Test

The Java implementation provides the same functionality as the Lambda load test but runs on a single host:

| Aspect | Lambda Load Test | Java Load Test |
|--------|------------------|----------------|
| **Execution Model** | Distributed (1000+ Lambdas) | Single host (multiple threads) |
| **Scalability** | Very high (thousands of parallel executions) | Limited by host resources |
| **Setup Complexity** | Requires Lambda deployment | Simpler (single host) |
| **Cost** | Pay per invocation | Fixed host cost |
| **Use Case** | Maximum scale testing | Development, debugging, smaller scale tests |
| **Configuration** | Payload parameters | Environment variables |

Both implementations generate the same events and support the same configuration options, making them interchangeable for testing different scenarios.
