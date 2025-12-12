# Performance Test Experiments

## Goal

Discover as many aspects of different implementations of an event ingestion API using multiple infrastructure, language and protocols options.

A comprehensive performance comparison of producer API implementations using k6 load testing. This repository focuses on comparing throughput, latency, and scalability across different technology stacks, protocols, and deployment models (containerized and serverless).

## Overview

This project compares the performance characteristics of multiple producer API implementations:

### Containerized APIs (6 implementations)

1. **producer-api-java-rest** - Spring Boot REST API (Java, Spring WebFlux, R2DBC)
2. **producer-api-java-grpc** - Java gRPC API (Java, Spring Boot, R2DBC)
3. **producer-api-rust-rest** - Rust REST API (Rust, Axum, sqlx)
4. **producer-api-rust-grpc** - Rust gRPC API (Rust, Tonic, sqlx)
5. **producer-api-go-rest** - Go REST API (Go, Gin, pgx)
6. **producer-api-go-grpc** - Go gRPC API (Go, gRPC, pgx)

### Serverless Lambda APIs (2 implementations)

7. **producer-api-go-rest-lambda** - AWS Lambda REST API (Go, API Gateway HTTP API)
8. **producer-api-go-grpc-lambda** - AWS Lambda gRPC API (Go, API Gateway HTTP API, gRPC-Web)

All APIs implement the same event processing functionality, allowing for fair performance comparison across different technology stacks, protocols, and deployment models.

**Note:** This is a performance testing experiment. While basic authentication infrastructure is available (see [Authentication & Secrets](#authentication--secrets) section), it is not fully implemented across all APIs. The focus remains on performance comparison rather than production-ready security features.

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Java 17+ (for Java APIs)
- Rust 1.70+ (for Rust APIs)
- PostgreSQL 15+ (via Docker)
- Python 3.7+ (for test scripts and utilities)
- **Disk Space**: See [System Requirements](#infrastructure-and-requirements) section for disk space requirements by test type

**Python Dependencies:**
- `psycopg2` - PostgreSQL adapter (for metrics database)
- `PyJWT` - JWT token generation (optional, for auth testing)

Install Python dependencies:
```bash
pip install psycopg2-binary PyJWT
```

### Start Services

All producer APIs use Docker Compose profiles, allowing you to start only the services you need:

```bash
# Start PostgreSQL only (no APIs)
docker-compose up -d postgres-large

# Start a specific API (example: Java REST)
docker-compose --profile producer-java-rest up -d postgres-large producer-api-java-rest

# Start multiple APIs
docker-compose --profile producer-java-rest --profile producer-rust-rest up -d postgres-large producer-api-java-rest producer-api-rust-rest

# Start all APIs at once
docker-compose --profile producer-java-rest --profile producer-java-grpc --profile producer-rust-rest --profile producer-rust-grpc --profile producer-go-rest --profile producer-go-grpc up -d
```

**Note:** All producer APIs use profiles, so they won't start by default. Use `--profile <profile-name>` to start specific services.

### Run Performance Tests

```terminal
python load-test/shared/run-tests.py smoke --payload-size 400b --payload-size 4k
```

![Test Runner Demo](docs/test-runner-all-apis-demo.gif)

**Using the Python Test Runner (Recommended):**

```bash
cd load-test/shared

# Run smoke tests for all APIs with multiple payload sizes
python run-tests.py smoke --payload-size 400b --payload-size 4k --payload-size 8k

# Run full tests for a specific API
python run-tests.py full --api producer-api-go-rest

# Run saturation tests
python run-tests.py saturation
```

**Using the Shell Script (Legacy):**

```bash
cd load-test/shared

# Run smoke tests only
./run-sequential-throughput-tests.sh smoke

# Run sequential throughput tests
./run-sequential-throughput-tests.sh full

# Run saturation tests to find maximum throughput
./run-sequential-throughput-tests.sh saturation
```

### Lambda API Testing

Lambda APIs can be tested both locally (using SAM Local) and in AWS. For detailed Lambda deployment and testing instructions, see:
- [Lambda REST API README](producer-api-go-rest-lambda/README.md)
- [Lambda gRPC API README](producer-api-go-grpc-lambda/README.md)
- [Terraform README](terraform/README.md) for infrastructure deployment

## API Implementations

### Summary

#### Containerized APIs

| API | Protocol | Port | Language | Framework | Database Driver |
|-----|----------|------|----------|-----------|-----------------|
| producer-api-java-rest | REST | 8081 | Java | Spring Boot (WebFlux) | R2DBC |
| producer-api-java-grpc | gRPC | 9090 | Java | Spring Boot | R2DBC |
| producer-api-rust-rest | REST | 8081 | Rust | Axum | sqlx |
| producer-api-rust-grpc | gRPC | 9090 | Rust | Tonic | sqlx |
| producer-api-go-rest | REST | 9083 | Go | Gin | pgx |
| producer-api-go-grpc | gRPC | 9092 | Go | gRPC | pgx |

#### Serverless Lambda APIs

| API | Protocol | Deployment | Language | Framework | Database Driver |
|-----|----------|------------|----------|-----------|-----------------|
| producer-api-go-rest-lambda | REST | AWS Lambda + API Gateway | Go | API Gateway HTTP API | pgx |
| producer-api-go-grpc-lambda | gRPC | AWS Lambda + API Gateway | Go | API Gateway HTTP API (gRPC-Web) | pgx |

### Common API Information

All APIs implement the same event processing functionality. See the [Event Model](#event-model) section for event structure and supported event types.

#### REST API Endpoints

All REST APIs provide the following endpoints:

- **POST `/api/v1/events`** - Process a single event. See [Event Model](#event-model) section for request/response format.
  - Response: `200 OK` (success), `400 Bad Request` (invalid data), `500 Internal Server Error` (processing error)

- **POST `/api/v1/events/bulk`** - Process multiple events in a single request (available in Rust REST and Go REST)
  - Request: Array of event objects
  - Response: `{"success": true, "message": "...", "processedCount": N, "failedCount": 0, "batchId": "...", "processingTimeMs": N}`

- **GET `/api/v1/events/health`** - Health check endpoint
  - Response: `200 OK` with health status message

### Individual API Details

Each API has its own README with detailed information:

**Containerized APIs:**
- **[Producer API - Java REST](producer-api-java-rest/README.md)** - Spring Boot REST API (WebFlux, R2DBC)
- **[Producer API - Java gRPC](producer-api-java-grpc/README.md)** - Java gRPC API (Spring Boot, R2DBC)
- **[Producer API - Rust REST](producer-api-rust-rest/README.md)** - Rust REST API (Axum, sqlx)
- **[Producer API - Rust gRPC](producer-api-rust-grpc/README.md)** - Rust gRPC API (Tonic, sqlx)
- **[Producer API - Go REST](producer-api-go-rest/README.md)** - Go REST API (Gin, pgx) - *Also available as [Lambda version](producer-api-go-rest-lambda/README.md)*
- **[Producer API - Go gRPC](producer-api-go-grpc/README.md)** - Go gRPC API (gRPC, pgx) - *Also available as [Lambda version](producer-api-go-grpc-lambda/README.md)*

**Serverless Lambda APIs:**
- **[Producer API - Go REST Lambda](producer-api-go-rest-lambda/README.md)** - AWS Lambda REST API (API Gateway HTTP API)
- **[Producer API - Go gRPC Lambda](producer-api-go-grpc-lambda/README.md)** - AWS Lambda gRPC API (API Gateway HTTP API, gRPC-Web)

## Performance Testing

### Testing Tool: k6

This repository uses **k6** as the primary performance testing tool. k6 is a modern, developer-friendly load testing tool that provides:

- Native gRPC support
- Docker-based execution (no local installation required)
- Comprehensive metrics and reporting
- JavaScript-based test scripts

### Test Types

1. **Smoke Tests**: Quick validation (1 VU, 5 iterations, ~0.5-1 second k6 execution, ~22-30 seconds total per API)
2. **Full Tests**: Baseline performance (10 → 50 → 100 → 200 VUs, ~11 minutes k6 execution, ~12-13 minutes total per API)
3. **Saturation Tests**: Maximum throughput (10 → 50 → 100 → 200 → 500 → 1000 → 2000 VUs, ~14 minutes k6 execution, ~15-16 minutes total per API)

**Approximate Test Timings:**

| Test Type | Per API Duration | Total (All 6 APIs) | With All Payload Sizes (4k, 8k, 32k, 64k) |
|-----------|------------------|-------------------|-------------------------------------------|
| Smoke Tests | ~22-30 seconds | ~2-3 minutes | ~10-15 minutes |
| Full Tests | ~12-13 minutes | ~72-78 minutes | ~6-6.5 hours |
| Saturation Tests | ~15-16 minutes | ~90-96 minutes | ~7.5-8 hours |

**Calculation Details:**

- **Smoke Tests**:
  - **k6 execution**: 1 VU × 5 iterations = ~0.5-1 second (5 API calls × ~50-200ms each + 0.1s sleep per call)
  - **Overhead per API**: ~22-30 seconds
    - Stop previous API: ~2-3s
    - Clear database: ~1-2s
    - Start API: ~5-10s
    - Wait for startup: 3s
    - Health check: ~1-2s
    - Event verification: 8s
    - Test request wait: 1s (REST only)
    - Stop API: ~2-3s
  - **Total per API**: ~22-30 seconds (k6 execution is negligible compared to overhead)
  - **Total (6 APIs)**: ~2-3 minutes (not 5-10 minutes as previously estimated)
  - **With all payload sizes**: 5 payload sizes × ~2-3 minutes = ~10-15 minutes

- **Full Tests**:
  - **k6 execution**: 2m + 2m + 2m + 5m = 11 minutes (sum of all phase durations)
  - **Overhead per API**: ~70-80 seconds
    - Stop previous API: ~2-3s
    - Clear database: ~1-2s
    - Start API: ~5-10s
    - Wait for startup: 5s
    - Health check: ~1-2s
    - Event verification: 60s
    - Test request wait: 3s (REST only)
    - k6 buffer: 30s
    - Stop API: ~2-3s
  - **Total per API**: ~12-13 minutes (11 minutes k6 + ~1-1.5 minutes overhead)
  - **Total (6 APIs)**: ~72-78 minutes (11 minutes × 6 = 66 minutes + ~12-18 minutes overhead)
  - **With all payload sizes**: 5 payload sizes × ~72-78 minutes = ~6-6.5 hours

- **Saturation Tests**:
  - **k6 execution**: 2m × 7 phases = 14 minutes (sum of all phase durations)
  - **Overhead per API**: ~70-80 seconds (same as full tests)
    - Stop previous API: ~2-3s
    - Clear database: ~1-2s
    - Start API: ~5-10s
    - Wait for startup: 5s
    - Health check: ~1-2s
    - Event verification: 60s
    - Test request wait: 3s (REST only)
    - k6 buffer: 30s
    - Stop API: ~2-3s
  - **Total per API**: ~15-16 minutes (14 minutes k6 + ~1-1.5 minutes overhead)
  - **Total (6 APIs)**: ~90-96 minutes (14 minutes × 6 = 84 minutes + ~12-18 minutes overhead)
  - **With all payload sizes**: 5 payload sizes × ~90-96 minutes = ~7.5-8 hours

**Notes:**
- **k6 execution time**: The actual time k6 spends running the test (sum of all phase durations for full/saturation tests, or iterations for smoke tests)
- **Overhead**: Time spent on setup, teardown, health checks, event verification, and other infrastructure operations
- **Total duration**: k6 execution time + overhead per API
- **With all payload sizes**: Tests run sequentially for each payload size (default, 4k, 8k, 32k, 64k), multiplying the time by 5
- **Important**: For smoke tests, the k6 execution time (~0.5-1 second) is negligible compared to overhead (~22-30 seconds). For full and saturation tests, overhead is relatively small (~1-1.5 minutes) compared to k6 execution time (11-14 minutes)

### Test Phases (Stages)

k6 uses **stages** (not scenarios) to define load patterns. Each test mode has different stages that gradually increase the number of virtual users (VUs) to measure throughput, latency, and system behavior under increasing load.

**Smoke Test:**
- 1 virtual user
- 5 iterations total
- ~5-10 seconds duration

**Full Test (4 phases):**
1. **Phase 1 - Baseline**: 2 minutes at 10 VUs
2. **Phase 2 - Mid-load**: 2 minutes at 50 VUs
3. **Phase 3 - High-load**: 2 minutes at 100 VUs
4. **Phase 4 - Higher-load**: 5 minutes at 200 VUs

**Saturation Test (7 phases):**
1. **Phase 1 - Baseline**: 2 minutes at 10 VUs
2. **Phase 2 - Mid-load**: 2 minutes at 50 VUs
3. **Phase 3 - High-load**: 2 minutes at 100 VUs
4. **Phase 4 - Very High**: 2 minutes at 200 VUs
5. **Phase 5 - Extreme**: 2 minutes at 500 VUs
6. **Phase 6 - Maximum**: 2 minutes at 1000 VUs
7. **Phase 7 - Saturation**: 2 minutes at 2000 VUs

### Test Scripts

The k6 test scripts are located in `load-test/k6/`:

- **`rest-api-test.js`**: REST API test script (used for producer-api-java-rest, producer-api-rust-rest, and producer-api-go-rest)
- **`grpc-api-test.js`**: gRPC API test script (used for producer-api-java-grpc, producer-api-rust-grpc, and producer-api-go-grpc)
- **`shared/helpers.js`**: Shared utilities for event generation
- **`config.js`**: Centralized test configuration

### Test Execution

Tests run **sequentially** (one API at a time) to ensure fair comparison: stop all APIs, clear database, start target API, verify health, run k6 test, collect metrics, then repeat for next API.

### Test Payloads

The k6 tests use dynamically generated event payloads with configurable sizes. Payloads are generated per request using random values to simulate realistic event ingestion patterns.

**Default Payload Size (when PAYLOAD_SIZE not specified):**

- **CarCreated**: ~350-400 bytes (includes model name, year, timestamps, UUIDs)
- **LoanCreated**: ~400-450 bytes (includes balance, lastPaidDate, timestamps, UUIDs)
- **LoanPaymentSubmitted**: ~450-500 bytes (includes balance, paymentAmount, lastPaidDate, timestamps, UUIDs)
- **ServiceDone**: ~350-400 bytes (includes serviceCost, timestamps, UUIDs)

**Configurable Payload Sizes:**

The test framework supports configurable payload sizes to test performance with different payload sizes:
- **4k** - 4 kilobytes (4,096 bytes)
- **8k** - 8 kilobytes (8,192 bytes)
- **32k** - 32 kilobytes (32,768 bytes)
- **64k** - 64 kilobytes (65,536 bytes)

When a payload size is specified, the base event structure is expanded with nested JSON objects, arrays, and additional metadata to reach the target size. This includes realistic data structures such as:
- Owner information with addresses
- Insurance details
- Maintenance history
- Service records
- Payment history (for loan entities)
- Additional metadata and padding

**Payload Structure:**

Each payload contains an event header (UUID, event name, timestamps) and an event body with a single entity containing attributes. For larger payload sizes, the `updatedAttributes` field is expanded with nested structures to reach the target size.

**Event Types:** Four event types are randomly selected during test execution: `CarCreated`, `LoanCreated`, `LoanPaymentSubmitted`, and `ServiceDone`.

**Running Tests with Different Payload Sizes:**

```bash
# Run tests with all payload sizes (4k, 8k, 32k, 64k) - default behavior
./run-sequential-throughput-tests.sh smoke

# Run tests with a specific payload size
./run-sequential-throughput-tests.sh smoke producer-api-java-rest 8k

# Run full tests with 32k payloads for all APIs
./run-sequential-throughput-tests.sh full '' 32k
```

### Test Results

Test results are saved to `load-test/results/throughput-sequential/<api_name>/` and include:
- JSON metrics files
- Summary reports
- Comparison reports

**Sample Comparison Report**: See `docs/sample-comparison-report.html` for an example of the generated HTML comparison report showing performance metrics across all APIs.

### Metrics and Thresholds

**HTTP Metrics (REST APIs):**

| Metric | Description | Thresholds |
|--------|-------------|------------|
| `http_reqs` | Total HTTP requests | None |
| `http_req_duration` | Response time | p(95) < 2000ms, p(99) < 5000ms |
| `http_req_failed` | Error rate | rate < 0.05 (5%) |
| `errors` | Custom error rate | None |

**gRPC Metrics (gRPC APIs):**

| Metric | Description | Thresholds |
|--------|-------------|------------|
| `grpc_reqs` | Total gRPC requests | None |
| `grpc_req_duration` | Response time | p(95) < 2000ms, p(99) < 5000ms |
| `grpc_req_failed` | Error rate | None (monitored but no threshold) |
| `errors` | Custom error rate | None |

**Resource Utilization Metrics:**

Resource utilization metrics (CPU and memory) are automatically collected during **full** and **saturation** tests. These metrics provide insights into how efficiently each API uses system resources.

**Collection Details:**
- **Collection Method**: Docker stats API (sampled every 5 seconds)
- **Metrics Collected**:
  - CPU usage percentage
  - Memory usage percentage
  - Memory used (MB)
  - Memory limit (MB)
- **Storage**: CSV files saved alongside k6 JSON results
- **File Format**: `{api-name}-{test-mode}-{timestamp}-metrics.csv`

**Metrics Analyzed:**
- Overall Metrics: Average CPU %, Peak CPU %, Average memory %, Peak memory %, Average memory used (MB), Peak memory used (MB)
- Per-Phase Metrics: Average CPU % per phase, Peak CPU % per phase, Average memory (MB) per phase, Peak memory (MB) per phase, Number of requests per phase
- Derived Metrics:
  - **CPU % per Request**: `(avg CPU % × phase duration) / total requests in phase` - Lower is better, indicates CPU efficiency
  - **RAM MB per Request**: `(avg memory MB × phase duration) / total requests in phase` - Lower is better, indicates memory efficiency

Resource utilization metrics are included in:
- **Markdown Reports**: Tables showing overall and per-phase resource usage
- **HTML Reports**: Interactive charts using Chart.js showing per-phase CPU usage, memory usage, and derived metrics

**Database Query Performance Metrics:**

Database query performance metrics are automatically collected during **full** and **saturation** tests (not smoke tests). These metrics provide insights into database query efficiency and connection pool utilization.

**Collection Details:**
- **Collection Method**: PostgreSQL `pg_stat_statements` extension
- **When Collected**: After test completion (snapshot of query statistics)
- **Metrics Collected**:
  - Top queries by total execution time
  - Query execution statistics (mean, min, max, stddev)
  - Cache hit ratios
  - Connection pool statistics (active, idle, waiting connections)
- **Storage**: Stored in `performance_metrics` database and displayed in HTML reports

**Metrics Analyzed:**
- **Top Queries**: Top 10 queries per API by total execution time
- **Query Performance**: Mean execution time, min/max execution times, standard deviation
- **Cache Efficiency**: Cache hit ratio percentage (higher is better)
- **Connection Pool**: Total, active, idle, and waiting connections

Database query metrics are included in:
- **HTML Reports**: "Database Query Performance Metrics" section showing top queries and connection pool statistics per API

**Note**: Database metrics collection requires `pg_stat_statements` extension to be enabled in PostgreSQL (configured automatically in `docker-compose.yml`). Metrics are reset before each test run to ensure accurate per-test statistics.

### Test Limitations

These tests do not account for networking infrastructure overhead. All services communicate within an isolated Docker bridge network, which provides minimal latency and no external network factors. The performance results reflect application-level performance in this controlled environment and do not represent real-world network conditions, including WAN latency, network congestion, load balancers, API gateways, or other production networking infrastructure that would typically be present in a deployed system.

## Authentication & Secrets

The test framework includes infrastructure for testing authentication and secrets management performance impact, though full implementation is still in progress.

### Authentication Infrastructure

**JWT Authentication Support:**
- **k6 Test Scripts**: Support for JWT tokens via `AUTH_ENABLED` and `JWT_TOKEN` environment variables
- **Go REST API**: Basic JWT authentication middleware (placeholder for full validation)
- **Test Helper**: `load-test/shared/jwt-test-helper.py` for generating test JWT tokens

**Usage:**
```bash
# Generate a test JWT token
TOKEN=$(python3 load-test/shared/jwt-test-helper.py generate)

# Run tests with authentication enabled
AUTH_ENABLED=true JWT_TOKEN=$TOKEN ./run-sequential-throughput-tests.sh smoke
```

**Configuration:**
- Set `AUTH_ENABLED=true` in k6 test environment to enable JWT token validation
- Set `JWT_TOKEN=<token>` to provide the JWT token for requests
- Go REST API reads `AUTH_ENABLED` and `JWT_SECRET_KEY` environment variables

### Secrets Management Infrastructure

**Mock Secrets Service:**
- **Service**: `load-test/shared/secrets-mock-service.py` - HTTP server simulating remote secrets store
- **Features**: Configurable delays, failure rates, and timeouts for testing resilience
- **API**: REST API at `/secrets/{name}` endpoint

**Usage:**
```bash
# Start mock secrets service
python3 load-test/shared/secrets-mock-service.py 8080 &

# Configure service behavior via environment variables
SECRETS_SERVICE_DELAY_MS=100 \
SECRETS_SERVICE_FAILURE_RATE=0.1 \
SECRETS_SERVICE_TIMEOUT_RATE=0.05 \
python3 load-test/shared/secrets-mock-service.py 8080
```

**Configuration Options:**
- `SECRETS_SERVICE_DELAY_MS`: Artificial delay in milliseconds (default: 0)
- `SECRETS_SERVICE_FAILURE_RATE`: Failure rate 0.0-1.0 (default: 0.0)
- `SECRETS_SERVICE_TIMEOUT_RATE`: Timeout rate 0.0-1.0 (default: 0.0)

**Note**: Full integration of secrets management into APIs is pending. The infrastructure is ready for testing once APIs implement secrets abstraction.

### Future Enhancements

Planned enhancements include:
- Complete JWT validation implementation (signature verification, expiration checks)
- Secrets abstraction in APIs (environment variables vs remote secrets store)
- Test profiles for different auth/secrets modes (no-auth, auth-only, auth+secrets)
- Metrics collection for auth/secrets timing overhead
- Fault injection scenarios for resilience testing

See `load-test/EXPANDED_TESTING_STRATEGY.md` for detailed implementation status and roadmap.

### Troubleshooting

**Common Issues:**

1. **Container Build Failures**
   - Ensure Docker is running
   - Check Docker Compose version compatibility
   - Review container logs: `docker-compose logs k6-throughput`

2. **Test Failures**
   - Check API health: Ensure APIs are running and healthy
   - Review API logs: `docker-compose logs <api-name>`
   - Check database connectivity
   - Verify network connectivity between containers

3. **High Error Rates**
   - Check API resource limits (CPU, memory)
   - Review database performance
   - Check for network issues
   - Verify API configuration

4. **Low Throughput**
   - Check system resources (CPU, memory, network)
   - Review database performance
   - Check for bottlenecks in API code
   - Verify test configuration

5. **Database Clearing Failures / Disk Space Issues**
   - If you see "No space left on device" errors when clearing the database, Docker may be running low on disk space
   - See [Docker Disk Space Cleanup](#docker-disk-space-cleanup) section for detailed cleanup steps

**Debugging:**

To debug test execution:

1. **View k6 Container Logs**:
   ```bash
   docker-compose logs k6-throughput
   ```

2. **Run Tests Manually**:
   ```bash
   docker-compose --profile k6-test run --rm k6-throughput \
     k6 run /k6/scripts/rest-api-test.js \
     -e TEST_MODE=smoke \
     -e HOST=producer-api-java-rest \
     -e PORT=8081
   ```

3. **Check API Logs**:
   ```bash
   docker-compose logs -f producer-api
   ```

## Docker Disk Space Cleanup

If you encounter "No space left on device" errors, use these cleanup commands:

### Quick Cleanup

```bash
# Check disk usage
docker system df

# Remove unused resources (keeps volumes)
docker system prune -a --filter "until=24h"

# Immediate cleanup (keeps volumes)
docker system prune -a
```

### Database Cleanup

```bash
# Clear application database (done automatically between tests)
docker-compose exec postgres-large psql -U postgres -d car_entities -c "TRUNCATE TABLE car_entities CASCADE;"

# Clean up old metrics data (older than 30 days)
docker-compose exec postgres-metrics psql -U postgres -d performance_metrics -c "DELETE FROM test_runs WHERE started_at < NOW() - INTERVAL '30 days';"
```

### Advanced Cleanup

```bash
# Remove build cache
docker builder prune --filter "until=24h"

# Remove unused images
docker image prune -a --filter "until=24h"

# Remove unused containers
docker container prune --filter "until=24h"
```

**Warning**: Using `--volumes` flag will delete all unused volumes, including database data. The test script automatically checks disk space before running tests.

## Infrastructure and Requirements

All services run in Docker containers on local infrastructure. The following resource allocations are configured in `docker-compose.yml`:

- **PostgreSQL Database**: 4GB memory limit, 4 CPUs (1GB memory and 1 CPU reserved)
- **Each API Service**: 2GB memory limit, 2 CPUs (1GB memory and 1 CPU reserved)
- **k6 Test Runner**: 2GB memory limit, 2 CPUs (512MB memory and 0.5 CPU reserved)

All services communicate via a Docker bridge network, providing isolated container-to-container communication. These are local Docker containers running on your development machine, not production-grade infrastructure. Performance results should be interpreted in this context and may differ significantly in production environments with different hardware, network topology, and resource constraints.

### Disk Space Requirements

The test suite automatically checks Docker disk space before running tests and warns if insufficient space is available. The following are estimated disk space requirements per API test run:

#### Smoke Tests

- **Per API**: ~5MB
- **All 6 APIs**: ~36MB
- **Recommended free space**: ~50MB

Smoke tests are quick validation tests with minimal data generation.

#### Full Tests

- **Per API (default payload)**: ~150MB
- **Per API (4k payload)**: ~200MB
- **Per API (8k payload)**: ~300MB
- **Per API (32k payload)**: ~500MB
- **Per API (64k payload)**: ~800MB
- **All 6 APIs (default payload)**: ~1.1GB
- **All 6 APIs (all payload sizes)**: ~10.8GB
- **Recommended free space**: ~15GB (for all payload sizes)

Full tests run for approximately 11 minutes per API and generate moderate amounts of test data, database records, JSON result files, and metrics.

#### Saturation Tests

- **Per API (default payload)**: ~200MB
- **Per API (4k payload)**: ~300MB
- **Per API (8k payload)**: ~500MB
- **Per API (32k payload)**: ~1GB
- **Per API (64k payload)**: ~1.5GB
- **All 6 APIs (default payload)**: ~1.4GB
- **All 6 APIs (all payload sizes)**: ~21.6GB
- **Recommended free space**: ~30GB (for all payload sizes)

Saturation tests run for approximately 14 minutes per API and generate the highest volume of test data as they push APIs to their maximum throughput capacity.

**Note:** These estimates include:

- Database data growth during test execution
- JSON result files from k6
- Metrics CSV files
- Container logs
- Temporary Docker build artifacts

The test script includes a 50% safety margin when checking available space. If you encounter "No space left on device" errors, see the [Docker Disk Space Cleanup](#docker-disk-space-cleanup) section for cleanup instructions.

## Event Processing Logic

The API follows a standard event processing workflow:
1. **Validation**: Validates event structure and required fields
2. **Entity Check**: Determines if entities exist or need to be created
3. **Update/Create**: Updates existing entities or creates new ones
4. **JSON Processing**: Handles JSONB data storage and updates
5. **Error Handling**: Comprehensive error handling and logging

This logic is consistent across all producer API implementations.

## Event Model

### Event Structure

Events follow a standardized structure with header and body sections:

```json
{
  "eventHeader": {
    "uuid": "550e8400-e29b-41d4-a716-446655440000",
    "eventName": "LoanPaymentSubmitted",
    "createdDate": "2024-01-15T10:30:00Z",
    "savedDate": "2024-01-15T10:30:05Z",
    "eventType": "LoanPaymentSubmitted"
  },
  "eventBody": {
    "entities": [
      {
        "entityType": "Loan",
        "entityId": "loan-12345",
        "updatedAttributes": {
          "balance": 24439.75,
          "lastPaidDate": "2024-01-15T10:30:00Z"
        }
      }
    ]
  }
}
```

### Supported Event Types

- **LoanPaymentSubmitted**: Updates loan balance and payment date
- **CarServiceDone**: Adds service records to car entities
- **LoanCreated**: Creates new loan entities
- **CarCreated**: Creates new car entities

### Entity Types

- **Car**: Vehicle information with service records and loans
- **Loan**: Financial loan information
- **LoanPayment**: Payment transaction records
- **ServiceRecord**: Vehicle service history
