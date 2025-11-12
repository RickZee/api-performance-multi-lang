# Performance Test Experiments

## Goal - discover as many aspects of different implementations of an event ingestion API using multiple infrastructure, language and protocols options

A comprehensive performance comparison of 6 producer API implementations using k6 load testing. This repository focuses on comparing throughput, latency, and scalability across different technology stacks and protocols.

## 🎯 Overview

This project compares the performance characteristics of 6 different producer API implementations:

1. **producer-api-java-rest** - Spring Boot REST API (Java, Spring WebFlux, R2DBC)
2. **producer-api-java-grpc** - Java gRPC API (Java, Spring Boot, R2DBC)
3. **producer-api-rust-rest** - Rust REST API (Rust, Axum, sqlx)
4. **producer-api-rust-grpc** - Rust gRPC API (Rust, Tonic, sqlx)
5. **producer-api-go-rest** - Go REST API (Go, Gin, pgx)
6. **producer-api-go-grpc** - Go gRPC API (Go, gRPC, pgx)

All APIs implement the same event processing functionality, allowing for fair performance comparison across different technology stacks and protocols.

**Important:** This is a simple, non-production experiment that lacks logging, authentication and authorization.

## 🚀 Quick Start

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

## 📊 Performance Testing

### Testing Tool: k6

This repository uses **k6** as the primary performance testing tool. k6 is a modern, developer-friendly load testing tool that provides (supersedes jmeter):

- Native gRPC support
- Docker-based execution (no local installation required)
- Comprehensive metrics and reporting
- JavaScript-based test scripts

### Test Types

1. **Smoke Tests**: Quick validation (10 VUs, 30 seconds)
2. **Full Tests**: Baseline performance (10 → 50 → 100 → 200 VUs, ~11 minutes)
3. **Saturation Tests**: Maximum throughput (10 → 50 → 100 → 200 → 500 → 1000 → 2000 VUs, ~14 minutes)

### Test Execution

Tests run sequentially (one API at a time) to ensure fair comparison:

- Database is automatically cleared between API tests
- Same test conditions for all APIs
- Consistent environment and resources

### Test Limitations

These tests do not account for networking infrastructure overhead. All services communicate within an isolated Docker bridge network, which provides minimal latency and no external network factors. The performance results reflect application-level performance in this controlled environment and do not represent real-world network conditions, including WAN latency, network congestion, load balancers, API gateways, or other production networking infrastructure that would typically be present in a deployed system.

### Results

Test results are saved to `load-test/results/throughput-sequential/<api_name>/` and include:

- JSON metrics files
- Summary reports
- Comparison reports

**Sample Comparison Report**: See [docs/sample-comparison-report.html](docs/sample-comparison-report.html) for an example of the generated HTML comparison report showing performance metrics across all APIs.

For detailed testing information, see [load-test/THROUGHPUT-TESTING-GUIDE.md](load-test/THROUGHPUT-TESTING-GUIDE.md).

**k6 Test Scenarios Documentation**: See [load-test/k6/K6-SCENARIOS-DOCUMENTATION.md](load-test/k6/K6-SCENARIOS-DOCUMENTATION.md) for comprehensive documentation of all k6 test scenarios, test modes, phases, API configurations, and metrics.

## 📁 Project Structure

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

### API Documentation

- [producer-api-java-rest/README.md](producer-api-java-rest/README.md) - Spring Boot REST API
- [producer-api-java-grpc/README.md](producer-api-java-grpc/README.md) - Java gRPC API
- [producer-api-rust-rest/README.md](producer-api-rust-rest/README.md) - Rust REST API
- [producer-api-rust-grpc/README.md](producer-api-rust-grpc/README.md) - Rust gRPC API
- [producer-api-go-rest/README.md](producer-api-go-rest/README.md) - Go REST API
- [producer-api-go-grpc/README.md](producer-api-go-grpc/README.md) - Go gRPC API
- [load-test/README.md](load-test/README.md) - Performance testing framework
- [load-test/k6/K6-SCENARIOS-DOCUMENTATION.md](load-test/k6/K6-SCENARIOS-DOCUMENTATION.md) - Complete k6 test scenarios, modes, and configurations documentation

## 📈 Performance Metrics

The k6 tests measure:

- **Throughput**: Requests per second (RPS)
- **Latency**: Response time (p50, p95, p99)
- **Error Rate**: Percentage of failed requests
- **Virtual Users**: Optimal parallelism level
- **Breaking Point**: Maximum sustainable load

## 🗄️ Database

All APIs use PostgreSQL with the same schema:

- **Database**: `car_entities`
- **Table**: `car_entities` (id, entity_type, created_at, updated_at, data)
- **Initialization**: See `postgres/init-small.sql`

The database is automatically initialized when starting services with Docker Compose.

## 🐳 Docker Services

The `docker-compose.yml` includes:

- **postgres-large**: PostgreSQL 15 database (always available, no profile)
- **producer-api-java-rest**: Spring Boot REST API (port 9081, profile: `producer-java-rest`)
- **producer-api-java-grpc**: Java gRPC API (port 9090, profile: `producer-java-grpc`)
- **producer-api-rust-rest**: Rust REST API (port 9082, profile: `producer-rust-rest`)
- **producer-api-rust-grpc**: Rust gRPC API (port 9091, profile: `producer-rust-grpc`)
- **producer-api-go-rest**: Go REST API (port 9083, profile: `producer-go-rest`)
- **producer-api-go-grpc**: Go gRPC API (port 9092, profile: `producer-go-grpc`)
- **k6-throughput**: k6 test runner container (profile: `k6-test`)

**Note:** All producer APIs use profiles, so they won't start by default. Use `--profile <profile-name>` to start specific services. This allows you to run only the APIs you need, reducing resource usage.

## 🖥️ Infrastructure and Requirements

All services run in Docker containers on local infrastructure. The following resource allocations are configured in `docker-compose.yml`:

- **PostgreSQL Database**: 4GB memory limit, 4 CPUs (1GB memory and 1 CPU reserved)
- **Each API Service**: 2GB memory limit, 2 CPUs (1GB memory and 1 CPU reserved)
- **k6 Test Runner**: 2GB memory limit, 2 CPUs (512MB memory and 0.5 CPU reserved)

All services communicate via a Docker bridge network, providing isolated container-to-container communication. These are local Docker containers running on your development machine, not production-grade infrastructure. Performance results should be interpreted in this context and may differ significantly in production environments with different hardware, network topology, and resource constraints.
