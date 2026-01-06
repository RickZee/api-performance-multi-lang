# Metadata Service (Java)

A Spring Boot-based metadata service that provides centralized schema validation for event ingestion APIs, filter management, Flink SQL generation, and Confluent Cloud deployment capabilities.

## Features

- **Git-based Schema Management**: Pulls latest schemas from versioned git repository structure (`schemas/v1/`, `schemas/v2/`, etc.)
- **JSON Schema Validation**: Validates events against JSON Schema Draft 2020-12 with `$ref` resolution
- **Backward Compatibility**: Supports multiple schema versions simultaneously with automatic compatibility checking
- **Filter Management**: CRUD operations for Flink filter configurations
- **SQL Generation**: Generates Flink SQL from filter configurations
- **Confluent Cloud Deployment**: Deploys filters to Confluent Cloud Flink

## Quick Start

### Prerequisites

- Java 17+
- Gradle 7+
- PostgreSQL 12+ (for filter storage)
- Docker (optional, for containerized deployment)

#### Configuration

The service can be configured via environment variables or `application.yml`. For a complete list of configuration options, see the [Configuration Reference](METADATA_SERVICE_DOCUMENTATION.md#9-configuration-reference) in the comprehensive documentation.

**Required Environment Variables:**

- `GIT_REPOSITORY` - Git repository URL containing schemas (required)
- `DATABASE_URL` - PostgreSQL connection URL (default: `jdbc:postgresql://localhost:5432/metadata_service`)

### Running Locally

```bash
# Set required environment variables
export GIT_REPOSITORY=file:///path/to/data
export DATABASE_URL=jdbc:postgresql://localhost:5432/metadata_service
export DATABASE_USERNAME=postgres
export DATABASE_PASSWORD=postgres

# Run the service
./gradlew bootRun
```

**Note:** The service requires PostgreSQL for filter storage. Database schema is automatically created on first startup using Flyway migrations.

### Running with Docker

```bash
docker-compose --profile metadata-service-java up -d
```

## API Endpoints

For detailed API documentation including request/response examples, see the [API Reference](METADATA_SERVICE_DOCUMENTATION.md#6-api-reference) section.

**Key Endpoints:**
- `POST /api/v1/validate` - Validate events
- `GET /api/v1/schemas/:version` - Get schemas
- `POST /api/v1/filters` - Filter management
- `GET /api/v1/health` - Health check

## Building

```bash
./gradlew build
```

## Testing

For comprehensive testing information including test catalog, coverage reports, and how to run specific test suites, see the [Testing Guide](docs/TESTING.md).

**Quick Start:**
```bash
./gradlew test
```

## Documentation

- **[Comprehensive Documentation](METADATA_SERVICE_DOCUMENTATION.md)** - Complete service documentation including architecture, API reference, configuration, and workflows
- **[Testing Guide](METADATA_SERVICE_TESTING.md)** - Testing documentation including test catalog, coverage reports, and implementation details
