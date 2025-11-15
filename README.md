# Performance Test Experiments

## Goal

Discover as many aspects of different implementations of an event ingestion API using multiple infrastructure, language and protocols options.

A comprehensive performance comparison of 6 producer API implementations using k6 load testing. This repository focuses on comparing throughput, latency, and scalability across different technology stacks and protocols.

## Overview

This project compares the performance characteristics of 6 different producer API implementations:

1. **producer-api-java-rest** - Spring Boot REST API (Java, Spring WebFlux, R2DBC)
2. **producer-api-java-grpc** - Java gRPC API (Java, Spring Boot, R2DBC)
3. **producer-api-rust-rest** - Rust REST API (Rust, Axum, sqlx)
4. **producer-api-rust-grpc** - Rust gRPC API (Rust, Tonic, sqlx)
5. **producer-api-go-rest** - Go REST API (Go, Gin, pgx)
6. **producer-api-go-grpc** - Go gRPC API (Go, gRPC, pgx)

All APIs implement the same event processing functionality, allowing for fair performance comparison across different technology stacks and protocols.

**Important:** This is a simple, non-production experiment that lacks logging, authentication and authorization.

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Java 17+ (for Java APIs)
- Rust 1.70+ (for Rust APIs)
- PostgreSQL 15+ (via Docker)

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

**Note:** See the [Docker Services](#-docker-services) section below for a complete list of available profiles and ports.

### Run Performance Tests

```bash
cd load-test/shared

# Run smoke tests only
./run-sequential-throughput-tests.sh smoke

# Run sequential throughput tests
./run-sequential-throughput-tests.sh full

# Run saturation tests to find maximum throughput
./run-sequential-throughput-tests.sh saturation
```

## API Implementations

### Summary

| API | Protocol | Port | Language | Framework | Database Driver |
|-----|----------|------|----------|-----------|-----------------|
| producer-api-java-rest | REST | 8081 | Java | Spring Boot (WebFlux) | R2DBC |
| producer-api-java-grpc | gRPC | 9090 | Java | Spring Boot | R2DBC |
| producer-api-rust-rest | REST | 8081 | Rust | Axum | sqlx |
| producer-api-rust-grpc | gRPC | 9090 | Rust | Tonic | sqlx |
| producer-api-go-rest | REST | 9083 | Go | Gin | pgx |
| producer-api-go-grpc | gRPC | 9092 | Go | gRPC | pgx |

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

#### gRPC Service Definition

All gRPC APIs implement the same service:

```protobuf
service EventService {
  rpc ProcessEvent(EventRequest) returns (EventResponse);
  rpc HealthCheck(HealthRequest) returns (HealthResponse);
}
```

**ProcessEvent** - Processes an event containing entity updates.

**Request:**
```protobuf
message EventRequest {
  EventHeader event_header = 1;
  EventBody event_body = 2;
}
```

**Response:**
```protobuf
message EventResponse {
  bool success = 1;
  string message = 2;
}
```

**HealthCheck** - Health check service method.

**Request:**
```protobuf
message HealthRequest {
  string service = 1;
}
```

**Response:**
```protobuf
message HealthResponse {
  bool healthy = 1;
  string message = 2;
}
```

### Common Development

#### Configuration

Most APIs use environment variables for configuration. Common variables:

- `DATABASE_URL` - PostgreSQL connection string (default: `postgresql://postgres:password@localhost:5432/car_entities`)
- `SERVER_PORT` / `GRPC_SERVER_PORT` - Server port (varies by API)
- `LOG_LEVEL` / `RUST_LOG` - Logging level (`debug`, `info`, `warn`, `error`)

Java APIs use `application.yml` for configuration instead of environment variables.

#### Docker Compose

All APIs are configured in `docker-compose.yml` with profiles. See the [Docker Services](#-docker-services) section for details on starting services.

For local Docker builds:
```bash
docker build -t <api-name> .
docker run -p <port>:<port> <api-name>
```

#### Running Locally

General workflow:
1. Ensure PostgreSQL is running
2. Set environment variables or update config files
3. Run migrations (if required)
4. Start the server using language-specific commands

See individual API sections below for language-specific build and run commands.

### Individual API Details

### Producer API - Java REST

Spring Boot RESTful API using Spring WebFlux (reactive) and R2DBC for non-blocking I/O. Port: **8081**.

**Key Features:** Reactive programming with Spring WebFlux, comprehensive Bean Validation, Spring Data R2DBC.

**Configuration:** Uses `application.yml` (see [Common Development](#common-development) section).

**Build & Run:**
```bash
./gradlew bootRun    # Run locally
./gradlew test       # Run tests
./gradlew build      # Build JAR
```

### Producer API - Java gRPC

Java gRPC API using Spring Boot and R2DBC. Port: **9090**. Proto file: `src/main/proto/event_service.proto`.

**Key Features:** Protocol Buffers for efficient serialization, HTTP/2 support, type-safe generated code.

**Configuration:** Uses `application.yml` (see [Common Development](#common-development) section).

**Build & Run:**
```bash
./gradlew bootRun    # Run locally
./gradlew test       # Run tests
./gradlew build      # Build JAR
```

### Producer API - Rust REST

High-performance RESTful API built with Rust, Axum, and sqlx. Port: **8081**. Supports bulk event processing.

**Key Features:** Native Rust performance, Tokio async runtime, compile-time SQL checking with sqlx, structured error handling (thiserror/anyhow), validator crate for input validation.

**Configuration:** Environment variables (see [Common Development](#common-development) section).

**Build & Run:**
```bash
export DATABASE_URL="postgresql://postgres:password@localhost:5432/car_entities"
export SERVER_PORT=8081
export RUST_LOG=info
sqlx migrate run    # Run migrations (if using sqlx-cli)
cargo run           # Run application
```

### Producer API - Rust gRPC

High-performance gRPC API built with Rust, Tonic, and sqlx. Port: **9090**. Proto file: `proto/event_service.proto`.

**Key Features:** Protocol Buffers, HTTP/2 support, Tokio async runtime, compile-time SQL checking with sqlx, structured error handling.

**Configuration:** Environment variables (see [Common Development](#common-development) section).

**Build & Run:**
```bash
export DATABASE_URL="postgresql://postgres:password@localhost:5432/car_entities"
export GRPC_SERVER_PORT=9090
export RUST_LOG=info
sqlx migrate run --source ../producer-api-rust/migrations    # Run migrations (if using sqlx-cli)
cargo run                                                    # Run application
```

### Producer API - Go REST

Go REST API using Gin framework and pgx. Port: **9083**. Supports bulk event processing.

**Key Features:** Structured logging with zap, automatic migrations on startup, flexible date/time parsing (ISO 8601 and Unix timestamps), JSON merging for entity updates.

**Configuration:** Environment variables (see [Common Development](#common-development) section).

**Build & Run:**
```bash
go run cmd/server/main.go    # Run locally
go build -o producer-api-go ./cmd/server    # Build binary
```

### Producer API - Go gRPC

Go gRPC API using pgx. Port: **9092**. Proto file: `proto/event_service.proto`.

**Key Features:** Structured logging with zap, automatic migrations on startup, automatic proto generation in Docker builds.

**Configuration:** Environment variables (see [Common Development](#common-development) section).

**Build & Run:**
```bash
# Generate proto files first (for local development)
chmod +x scripts/generate-proto.sh
./scripts/generate-proto.sh

go run cmd/server/main.go    # Run locally
go build -o producer-api-go-grpc ./cmd/server    # Build binary
```

**Proto Generation (Local Development):**
1. Install protoc (Protocol Buffers compiler)
2. Install Go plugins:
   ```bash
   go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
   go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
   ```
3. Run: `./scripts/generate-proto.sh`

## Performance Testing

### Testing Tool: k6

This repository uses **k6** as the primary performance testing tool. k6 is a modern, developer-friendly load testing tool that provides:

- Native gRPC support
- Docker-based execution (no local installation required)
- Comprehensive metrics and reporting
- JavaScript-based test scripts

### Test Types

1. **Smoke Tests**: Quick validation (1 VU, 5 iterations, ~5-10 seconds)
2. **Full Tests**: Baseline performance (10 → 50 → 100 → 200 VUs, ~11 minutes)
3. **Saturation Tests**: Maximum throughput (10 → 50 → 100 → 200 → 500 → 1000 → 2000 VUs, ~14 minutes)

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

### Test Execution Flow

Tests run **sequentially** (one API at a time) to ensure fair comparison:

1. **Stop all APIs**: Ensures no resource competition
2. **Clear database**: Fresh state for each test
3. **Start target API**: Start only the API being tested
4. **Health check**: Verify API is healthy and ready
5. **Wait for event processing**: Verify API can process events
6. **Run k6 test**: Execute the appropriate test script
7. **Collect metrics**: Save results to JSON files
8. **Stop API**: Clean up before next test
9. **Repeat**: Move to next API

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

### API Configurations

Each API has specific configuration for host, port, protocol, and endpoints.

**REST API Configurations:**

| API | Host | Port | Path | Protocol |
|-----|------|------|------|----------|
| producer-api-java-rest | producer-api-java-rest | 8081 | /api/v1/events | HTTP |
| producer-api-rust-rest | producer-api-rust-rest | 8081 | /api/v1/events | HTTP |
| producer-api-go-rest | producer-api-go-rest | 9083 | /api/v1/events | HTTP |

**gRPC API Configurations:**

| API | Host | Port | Service | Method | Proto File |
|-----|------|------|---------|--------|------------|
| producer-api-java-grpc | producer-api-java-grpc | 9090 | com.example.grpc.EventService | ProcessEvent | /k6/proto/java-grpc/event_service.proto |
| producer-api-rust-grpc | producer-api-rust-grpc | 9090 | com.example.grpc.EventService | ProcessEvent | /k6/proto/rust-grpc/event_service.proto |
| producer-api-go-grpc | producer-api-go-grpc | 9092 | com.example.grpc.EventService | ProcessEvent | /k6/proto/go-grpc/event_service.proto |

**Note**: Host names are Docker service names, accessible within the Docker network.

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

### Test Limitations

These tests do not account for networking infrastructure overhead. All services communicate within an isolated Docker bridge network, which provides minimal latency and no external network factors. The performance results reflect application-level performance in this controlled environment and do not represent real-world network conditions, including WAN latency, network congestion, load balancers, API gateways, or other production networking infrastructure that would typically be present in a deployed system.

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

Docker can consume significant disk space over time, especially when running multiple test iterations. If you encounter "No space left on device" errors or want to free up disk space, use these cleanup commands:

### Check Docker Disk Usage

```bash
# View Docker disk usage breakdown
docker system df

# View detailed disk usage by component
docker system df -v
```

### Cleanup Options

#### 1. Remove Unused Containers, Networks, and Images

```bash
# Remove all stopped containers, unused networks, and dangling images
docker system prune

# Also remove unused images (not just dangling ones)
docker system prune -a

# Remove everything including volumes (⚠️ WARNING: This will delete all volumes)
docker system prune -a --volumes
```

#### 2. Remove Unused Images

```bash
# Remove dangling images (untagged images)
docker image prune

# Remove all unused images (not just dangling)
docker image prune -a

# Remove images older than 24 hours
docker image prune -a --filter "until=24h"
```

#### 3. Remove Unused Containers

```bash
# Remove all stopped containers
docker container prune

# Remove containers stopped for more than 24 hours
docker container prune --filter "until=24h"
```

#### 4. Remove Unused Volumes

```bash
# Remove all unused volumes (⚠️ WARNING: This will delete data in unused volumes)
docker volume prune

# Remove volumes not used by any containers
docker volume prune --filter "label!=keep"
```

#### 5. Remove Build Cache

```bash
# Remove all build cache
docker builder prune

# Remove build cache older than 24 hours
docker builder prune --filter "until=24h"
```

### Comprehensive Cleanup Script

For a complete cleanup (removes all unused containers, networks, images, and build cache, but **keeps volumes**):

```bash
# Safe cleanup - keeps volumes
docker system prune -a --filter "until=24h"

# Or for immediate cleanup
docker system prune -a
```

### Cleanup Application Database Data

If the application database (`postgres-large`) has accumulated too much test data:

```bash
# Connect to the database and check size
docker-compose exec postgres-large psql -U postgres -d car_entities -c "SELECT COUNT(*) FROM car_entities;"

# Clear the car_entities table (done automatically between tests, but can be done manually)
docker-compose exec postgres-large psql -U postgres -d car_entities -c "TRUNCATE TABLE car_entities CASCADE;"

# If TRUNCATE fails due to disk space, delete in batches
docker-compose exec postgres-large psql -U postgres -d car_entities -c "DELETE FROM car_entities WHERE ctid IN (SELECT ctid FROM car_entities LIMIT 10000);"
# Repeat the above command until all records are deleted
```

### Cleanup Metrics Database Data

To clean up old test runs from the metrics database:

```bash
# Connect to metrics database and check test runs
docker-compose exec postgres-metrics psql -U postgres -d performance_metrics -c "SELECT COUNT(*) FROM test_runs;"

# Delete test runs older than 30 days
docker-compose exec postgres-metrics psql -U postgres -d performance_metrics -c "DELETE FROM test_runs WHERE started_at < NOW() - INTERVAL '30 days';"

# Delete test runs for a specific API
docker-compose exec postgres-metrics psql -U postgres -d performance_metrics -c "DELETE FROM test_runs WHERE api_name = 'producer-api-java-rest';"

# Delete all test runs (⚠️ WARNING: This will delete all test data)
docker-compose exec postgres-metrics psql -U postgres -d performance_metrics -c "TRUNCATE TABLE test_runs CASCADE;"
```

### Recommended Cleanup Schedule

- **After each test session**: Run `docker system prune` to remove stopped containers and unused images
- **Weekly**: Run `docker system prune -a --filter "until=24h"` to remove unused resources older than 24 hours
- **Monthly**: Review and clean up old metrics data using SQL commands (see [Cleanup Metrics Database Data](#cleanup-metrics-database-data))
- **As needed**: If you encounter disk space issues, run comprehensive cleanup: `docker system prune -a`

### Disk Space Monitoring

```bash
# Check overall disk usage
df -h

# Check Docker-specific disk usage
docker system df

# Check size of specific Docker volumes
docker volume ls
docker volume inspect <volume_name>
```

### Notes

- **Volumes**: Be careful when using `--volumes` flag as it will delete all unused volumes, including database data
- **Images**: Removing images will require rebuilding them on next use, which may take time
- **Build Cache**: Removing build cache will slow down subsequent builds but can free significant space
- **Metrics Database**: When deleting test runs, related metrics (performance_metrics, resource_metrics, test_phases) are automatically deleted due to CASCADE foreign key constraints

## Performance Results

### Full Test Results

All 6 APIs completed the full throughput test (4 phases: 10 → 50 → 100 → 200 VUs) with 0% error rate.

**Throughput Performance (Requests/Second):**

**REST APIs:**
1. **Rust REST**: 337.11 req/s (highest)
2. **Go REST**: 331.48 req/s
3. **Java REST**: 327.91 req/s

**gRPC APIs:**
1. **Go gRPC**: 120.45 req/s (highest)
2. **Rust gRPC**: 78.19 req/s
3. **Java gRPC**: 78.04 req/s

**Insight**: REST APIs show ~4x higher throughput than gRPC. Rust REST leads by ~3% over Go REST.

**Latency Performance (Average Response Time):**

1. **Rust REST**: 6.11ms
2. **Rust gRPC**: 6.12ms
3. **Go REST**: 7.36ms
4. **Go gRPC**: 7.96ms
5. **Java REST**: 8.75ms
6. **Java gRPC**: 17.23ms

**Insight**: Rust implementations have the lowest latency. Java gRPC is ~2.8x slower than Rust gRPC.

**Key Findings:**
1. **Rust REST leads overall** - Highest throughput (337.11 req/s) and lowest latency (6.11ms) with zero errors
2. **gRPC throughput gap** - gRPC APIs handle ~78–120 req/s vs REST at ~328–337 req/s
3. **Go gRPC exception** - 120.45 req/s (54% higher than other gRPC)
4. **Java gRPC latency** - 17.23ms average (highest), possible JVM warmup or connection pooling issues
5. **Rust consistency** - REST and gRPC both ~6ms average latency

### Saturation Test Results

All 6 APIs completed saturation tests (7 phases: 10 → 50 → 100 → 200 → 500 → 1000 → 2000 VUs) with 0% error rate.

**Maximum Throughput Performance (Requests/Second):**

**REST APIs:**
1. **Rust REST**: 2,492.98 req/s (highest)
2. **Java REST**: 2,258.64 req/s
3. **Go REST**: 2,151.35 req/s

**gRPC APIs:**
1. **Go gRPC**: 95.81 req/s (highest)
2. **Java gRPC**: 54.22 req/s
3. **Rust gRPC**: 46.59 req/s

**Insight**: REST APIs achieved ~26x higher throughput than gRPC. Rust REST leads by ~10% over Java REST.

**Latency Performance (Average Response Time):**

1. **Rust gRPC**: 9.11ms
2. **Java gRPC**: 9.75ms
3. **Rust REST**: 53.92ms
4. **Go REST**: 54.34ms
5. **Go gRPC**: 13.48ms
6. **Java REST**: 74.00ms

**Insight**: gRPC APIs show lower average latency (~9–13ms) than REST (~54–74ms), but REST handles much higher throughput.

**Test Duration Analysis:**

**Full test duration (840s = ~14 min):**
- **Rust REST**: 840.2s (completed all phases)
- **Java REST**: 840.7s (completed all phases)
- **Go REST**: 840.2s (completed all phases)

**Early termination (connection limits):**
- **Go gRPC**: 382.4s (~6.4 min) — stopped at ~500 VUs
- **Java gRPC**: 520.7s (~8.7 min) — stopped at ~500–1000 VUs
- **Rust gRPC**: 606.0s (~10.1 min) — stopped at ~1000 VUs

**Insight**: gRPC APIs hit connection limits before completing all phases, explaining lower total requests.

**Key Findings:**
1. **Rust REST leads overall** - Highest throughput: 2,492.98 req/s, good latency: 53.92ms, completed all 7 phases, zero errors
2. **REST vs gRPC throughput gap** - REST: 2,151–2,493 req/s, gRPC: 46–96 req/s, REST is ~26x higher
3. **gRPC connection exhaustion** - All gRPC APIs stopped early (382–606s vs 840s), pattern suggests persistent connection limits at high concurrency
4. **Latency trade-offs** - gRPC: lower latency (~9–13ms) but much lower throughput, REST: higher latency (~54–74ms) but much higher throughput
5. **Java REST latency** - 74.00ms average (highest among REST), possible JVM GC pauses or connection pool tuning needed
6. **Go gRPC performance** - Best gRPC throughput (95.81 req/s), stopped earliest (382s) but handled more requests than others before stopping

**Performance Comparison: Full vs Saturation Tests:**

| API | Full Test (100 VUs) | Saturation Test (2000 VUs) | Improvement |
|-----|---------------------|----------------------------|-------------|
| Rust REST | 337 req/s | 2,493 req/s | **7.4x** |
| Java REST | 328 req/s | 2,259 req/s | **6.9x** |
| Go REST | 331 req/s | 2,151 req/s | **6.5x** |
| Go gRPC | 120 req/s | 96 req/s | **-20%** (connection limits) |
| Java gRPC | 78 req/s | 54 req/s | **-31%** (connection limits) |
| Rust gRPC | 78 req/s | 47 req/s | **-40%** (connection limits) |

**Insight**: REST APIs scale well with increased load (6.5–7.4x improvement), while gRPC APIs hit connection limits and perform worse at saturation.

**gRPC Connection Limit Investigation:**

**Observations:**
- All gRPC APIs hit connection limits before completing saturation tests
- Go gRPC handled the most requests before stopping (36,634 vs 28,231)
- Pattern suggests system-level TCP connection limits, not application limits

**Recommendations:**
- Increase system connection limits (`ulimit -n`, `sysctl` parameters)
- Implement connection pooling/multiplexing in gRPC clients
- Test gRPC with fewer VUs to find optimal concurrency level
- Consider HTTP/2 connection reuse optimizations

### Summary

**Winner: Rust REST**
- Highest throughput: 2,492.98 req/s
- Good latency: 53.92ms
- Excellent scalability: 7.4x improvement from full to saturation
- Zero errors across all test phases

**Best gRPC: Go gRPC**
- Highest gRPC throughput: 95.81 req/s
- Better connection handling than Java/Rust gRPC
- Still limited by connection exhaustion at high VU counts

The saturation tests confirm that REST APIs scale much better under extreme load, while gRPC APIs are limited by connection management at high concurrency levels.

## Project Structure

```text
producer-api-performance/
├── producer-api-java-rest/    # Spring Boot REST API
├── producer-api-java-grpc/    # Java gRPC API
├── producer-api-rust-rest/    # Rust REST API
├── producer-api-rust-grpc/    # Rust gRPC API
├── producer-api-go-rest/      # Go REST API
├── producer-api-go-grpc/      # Go gRPC API
├── load-test/                 # k6 performance testing framework
│   ├── k6/                    # k6 test scripts
│   ├── shared/                # Test execution scripts
│   └── results/               # Test results
├── postgres/                  # Database initialization scripts
├── docker-compose.yml         # Docker services configuration
└── README.md                  # This file
```

## Docker Services

The `docker-compose.yml` includes:

- **postgres-large**: PostgreSQL 15 database for API data (always available, no profile, port 5432)
- **postgres-metrics**: PostgreSQL 15 database for performance metrics (always available, no profile, port 5433)
- **producer-api-java-rest**: Spring Boot REST API (port 8081, profile: `producer-java-rest`)
- **producer-api-java-grpc**: Java gRPC API (port 9090, profile: `producer-java-grpc`)
- **producer-api-rust-rest**: Rust REST API (port 8081, profile: `producer-rust-rest`)
- **producer-api-rust-grpc**: Rust gRPC API (port 9090, profile: `producer-rust-grpc`)
- **producer-api-go-rest**: Go REST API (port 9083, profile: `producer-go-rest`)
- **producer-api-go-grpc**: Go gRPC API (port 9092, profile: `producer-go-grpc`)
- **k6-throughput**: k6 test runner container (profile: `k6-test`)

**Note:** All producer APIs use profiles, so they won't start by default. Use `--profile <profile-name>` to start specific services. This allows you to run only the APIs you need, reducing resource usage. The `postgres-metrics` database is automatically started when running tests and stores all performance metrics.

## Infrastructure and Requirements

All services run in Docker containers on local infrastructure. The following resource allocations are configured in `docker-compose.yml`:

- **PostgreSQL Database**: 4GB memory limit, 4 CPUs (1GB memory and 1 CPU reserved)
- **Each API Service**: 2GB memory limit, 2 CPUs (1GB memory and 1 CPU reserved)
- **k6 Test Runner**: 2GB memory limit, 2 CPUs (512MB memory and 0.5 CPU reserved)

All services communicate via a Docker bridge network, providing isolated container-to-container communication. These are local Docker containers running on your development machine, not production-grade infrastructure. Performance results should be interpreted in this context and may differ significantly in production environments with different hardware, network topology, and resource constraints.

## Databases

### Application Database (`postgres-large`)

All APIs use PostgreSQL with the same schema:

- **Database**: `car_entities`
- **Table**: `car_entities` (id, entity_type, created_at, updated_at, data)
- **Initialization**: See `postgres/init-small.sql`
- **Port**: 5432

The database is automatically initialized when starting services with Docker Compose.

### Metrics Database (`postgres-metrics`)

A separate PostgreSQL database stores all performance test metrics:

- **Database**: `performance_metrics`
- **Port**: 5433 (external), 5432 (internal)
- **Schema**: See `load-test/shared/migrations/001_create_metrics_schema.sql`
- **Purpose**: Historical performance data, resource utilization, test run metadata

The metrics database is automatically initialized when starting the `postgres-metrics` service and is used by all test runs to store metrics data. The database stores:

- **Test Run Metadata**: API name, test mode, payload size, protocol, timestamps
- **Performance Metrics**: Throughput, latency, error rates, response times
- **Resource Metrics**: Time-series CPU and memory utilization data
- **Phase Metrics**: Per-phase metrics for multi-phase tests (full/saturation)

### Metrics Management Scripts

The `load-test/shared/` directory contains Python scripts for managing and querying the metrics database:

#### Quick Reference

```bash
cd load-test/shared

# List recent test runs
python3 metrics_list_runs.py

# Show database summary
python3 metrics_summary.py

# Export test run data
python3 metrics_export.py <test_run_id> output.json

# Cleanup old data (dry run)
python3 metrics_cleanup.py --days 30
```

#### Available Scripts

1. **`metrics_list_runs.py`** - List and filter test runs
   ```bash
   # Filter by API, mode, or payload size
   python3 metrics_list_runs.py --api producer-api-java-rest --mode smoke
   python3 metrics_list_runs.py --payload 4k --limit 20
   ```

2. **`metrics_export.py`** - Export test run data to JSON or CSV
   ```bash
   # Export to JSON (default)
   python3 metrics_export.py 42 results.json
   
   # Export to CSV
   python3 metrics_export.py 42 results.csv --format csv
   ```

3. **`metrics_cleanup.py`** - Remove old test data
   ```bash
   # Preview what would be deleted (dry run)
   python3 metrics_cleanup.py --days 30
   
   # Actually delete runs older than 30 days
   python3 metrics_cleanup.py --days 30 --execute
   
   # Keep only 100 most recent runs per API
   python3 metrics_cleanup.py --keep 100 --execute
   ```

4. **`metrics_summary.py`** - Show database statistics
   ```bash
   # Overall summary
   python3 metrics_summary.py
   
   # Latest test run comparison by API
   python3 metrics_summary.py --comparison
   ```

### Database Configuration

The metrics database runs as a separate PostgreSQL service:

- **Service**: `postgres-metrics` (Docker Compose)
- **Port**: 5433 (external), 5432 (internal)
- **Database**: `performance_metrics`
- **Connection**: Automatically configured when running tests

### Database Schema

The database includes four main tables:

- **`test_runs`**: Test execution metadata (API, mode, payload, protocol, timestamps, status)
- **`performance_metrics`**: Aggregated performance data (throughput, latency, error rates)
- **`resource_metrics`**: Time-series resource utilization (CPU, memory over time)
- **`test_phases`**: Phase-specific metrics for multi-phase tests

For detailed schema information, see `load-test/shared/migrations/001_create_metrics_schema.sql`.

### Reports and Data Access

- **HTML Reports**: Automatically query the database for resource metrics and display them in the "Overall Resource Usage" section
- **Comparison Reports**: Include resource utilization metrics from the database
- **CSV Backup**: Metrics are also saved to CSV files as backup/export format
- **Database Queries**: Use the management scripts or `db_client.py` for custom queries

### Environment Variables

Scripts use these environment variables (with defaults):
- `DB_HOST=postgres-metrics`
- `DB_PORT=5432`
- `DB_NAME=performance_metrics`
- `DB_USER=postgres`
- `DB_PASSWORD=password`

### Examples

```bash
# Find all smoke tests for a specific API
python3 metrics_list_runs.py --api producer-api-rust-rest --mode smoke

# Export latest test run for analysis
LATEST_ID=$(python3 metrics_list_runs.py --api producer-api-java-rest --limit 1 | grep -E '^[0-9]+' | head -1 | awk '{print $1}')
python3 metrics_export.py $LATEST_ID latest_run.json

# Monitor database growth
python3 metrics_summary.py --comparison
```

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
