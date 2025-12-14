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
- Docker (optional, for containerized deployment)

### Configuration

The service can be configured via environment variables or `application.yml`:

**Environment Variables:**

- `GIT_REPOSITORY` - Git repository URL containing schemas (required)
- `GIT_BRANCH` - Git branch to use (default: `main`)
- `LOCAL_CACHE_DIR` - Local directory for schema cache (default: `/tmp/schema-cache`)
- `SERVER_PORT` - HTTP server port (default: `8080`)
- `DEFAULT_VERSION` - Default schema version to use (default: `latest`)
- `STRICT_MODE` - Enable strict validation mode (default: `true`)

### Running Locally

```bash
# Set required environment variables
export GIT_REPOSITORY=file:///path/to/data

# Run the service
./gradlew bootRun
```

### Running with Docker

```bash
docker-compose --profile metadata-service-java up -d
```

## API Endpoints

### Validation

- `POST /api/v1/validate` - Validate a single event
- `POST /api/v1/validate/bulk` - Validate multiple events

### Schemas

- `GET /api/v1/schemas/versions` - List available schema versions
- `GET /api/v1/schemas/:version` - Get schema by version

### Filters

- `POST /api/v1/filters` - Create filter
- `GET /api/v1/filters` - List filters
- `GET /api/v1/filters/:id` - Get filter
- `PUT /api/v1/filters/:id` - Update filter
- `DELETE /api/v1/filters/:id` - Delete filter
- `POST /api/v1/filters/:id/generate` - Generate SQL
- `POST /api/v1/filters/:id/validate` - Validate SQL
- `POST /api/v1/filters/:id/approve` - Approve filter
- `POST /api/v1/filters/:id/deploy` - Deploy filter
- `GET /api/v1/filters/:id/status` - Get filter status

### Health

- `GET /api/v1/health` - Health check

## Building

```bash
./gradlew build
```

## Testing

```bash
./gradlew test
```
