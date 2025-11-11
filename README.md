# Performance Test Experiments

## Goal - discover as many aspects of different implementations of an event ingestion API using multiple infrastructure, language and protocols options

A comprehensive performance comparison of 4 producer API implementations using k6 load testing. This repository focuses on comparing throughput, latency, and scalability across different technology stacks and protocols.

## 🎯 Overview

This project compares the performance characteristics of 4 different producer API implementations:

1. **producer-api** - Spring Boot REST API (Java, Spring WebFlux, R2DBC)
2. **producer-api-grpc** - Java gRPC API (Java, Spring Boot, R2DBC)
3. **producer-api-rust** - Rust REST API (Rust, Axum, sqlx)
4. **producer-api-rust-grpc** - Rust gRPC API (Rust, Tonic, sqlx)

All APIs implement the same event processing functionality, allowing for fair performance comparison across different technology stacks and protocols.

## 🏗️ Architecture

### API Implementations

| API | Language | Framework | Protocol | Port | Database |
|-----|----------|-----------|----------|------|----------|
| producer-api | Java | Spring Boot (WebFlux) | REST | 9081 | PostgreSQL (R2DBC) |
| producer-api-grpc | Java | Spring Boot | gRPC | 9090 | PostgreSQL (R2DBC) |
| producer-api-rust | Rust | Axum | REST | 9082 | PostgreSQL (sqlx) |
| producer-api-rust-grpc | Rust | Tonic | gRPC | 9091 | PostgreSQL (sqlx) |

### Common Functionality

All APIs implement:
- Event processing with headers and entity updates
- PostgreSQL database integration
- Health check endpoints
- Event validation and error handling
- Entity creation and updates

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose
- Java 17+ (for Java APIs)
- Rust 1.70+ (for Rust APIs)
- PostgreSQL 15+ (via Docker)

### Start All Services

```bash
# Start PostgreSQL and all 4 producer APIs
docker-compose up --build -d

# Verify services are running
docker-compose ps

# Check health endpoints
curl http://localhost:9081/api/v1/events/health  # Spring Boot REST
curl http://localhost:9082/api/v1/events/health  # Rust REST
# gRPC health checks require gRPC client
```

### Run Performance Tests

```bash
cd load-test/shared

# Run sequential throughput tests (recommended)
./run-sequential-throughput-tests.sh full

# Run saturation tests to find maximum throughput
./run-sequential-throughput-tests.sh saturation

# Run smoke tests only
./run-sequential-throughput-tests.sh smoke
```

## 📊 Performance Testing

### Testing Tool: k6

This repository uses **k6** as the primary performance testing tool. k6 is a modern, developer-friendly load testing tool that provides:

- Native gRPC support
- Docker-based execution (no local installation required)
- Comprehensive metrics and reporting
- JavaScript-based test scripts

### Test Types

1. **Smoke Tests**: Quick validation (10 VUs, 30 seconds)
2. **Full Tests**: Baseline performance (10 → 50 → 100 VUs, ~6 minutes)
3. **Saturation Tests**: Maximum throughput (10 → 50 → 100 → 200 → 500 → 1000 → 2000 VUs, ~14 minutes)

### Test Execution

Tests run sequentially (one API at a time) to ensure fair comparison:
- Database is automatically cleared between API tests
- Same test conditions for all APIs
- Consistent environment and resources

### Results

Test results are saved to `load-test/results/throughput-sequential/<api_name>/` and include:
- JSON metrics files
- Summary reports
- Comparison reports

For detailed testing information, see [load-test/THROUGHPUT-TESTING-GUIDE.md](load-test/THROUGHPUT-TESTING-GUIDE.md).

## 📁 Project Structure

```
producer-api-performance/
├── producer-api/              # Spring Boot REST API
├── producer-api-grpc/         # Java gRPC API
├── producer-api-rust/         # Rust REST API
├── producer-api-rust-grpc/    # Rust gRPC API
├── load-test/                 # k6 performance testing framework
│   ├── k6/                    # k6 test scripts
│   ├── shared/                # Test execution scripts
│   └── results/               # Test results
├── postgres/                  # Database initialization scripts
├── docker-compose.yml         # Docker services configuration
└── README.md                  # This file
```

## 🔧 Development

### Building Individual APIs

```bash
# Spring Boot APIs
cd producer-api
./gradlew build

cd producer-api-grpc
./gradlew build

# Rust APIs
cd producer-api-rust
cargo build --release

cd producer-api-rust-grpc
cargo build --release
```

### Running Tests

Each API includes unit and integration tests:

```bash
# Java APIs
./gradlew test

# Rust APIs
cargo test
```

### API Documentation

- [producer-api/README.md](producer-api/README.md) - Spring Boot REST API
- [producer-api-grpc/README.md](producer-api-grpc/README.md) - Java gRPC API
- [producer-api-rust/README.md](producer-api-rust/README.md) - Rust REST API
- [producer-api-rust-grpc/README.md](producer-api-rust-grpc/README.md) - Rust gRPC API
- [load-test/README.md](load-test/README.md) - Performance testing framework

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

- **postgres-large**: PostgreSQL 15 database
- **producer-api**: Spring Boot REST API (port 9081)
- **producer-api-grpc**: Java gRPC API (port 9090)
- **producer-api-rust**: Rust REST API (port 9082)
- **producer-api-rust-grpc**: Rust gRPC API (port 9091)
- **k6-throughput**: k6 test runner container

## 📚 Additional Resources

- [k6 Documentation](https://k6.io/docs/)
- [Spring Boot Documentation](https://spring.io/projects/spring-boot)
- [Rust Documentation](https://www.rust-lang.org/learn)
- [gRPC Documentation](https://grpc.io/docs/)

## 🤝 Contributing

This is a performance testing repository. Contributions should focus on:
- Improving test accuracy and coverage
- Adding new performance metrics
- Optimizing API implementations for comparison
- Documentation improvements

## 📝 License

See individual API directories for license information.

