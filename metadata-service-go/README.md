# Metadata Service - Schema Validation

A standalone microservice that provides centralized schema validation for event ingestion APIs. The service pulls JSON schemas from a git repository, validates events against versioned schemas, and implements backward compatibility rules for non-breaking changes.

## Features

- **Git-based Schema Management**: Pulls latest schemas from versioned git repository structure (`schemas/v1/`, `schemas/v2/`, etc.)
- **JSON Schema Validation**: Validates events against JSON Schema Draft 2020-12 with `$ref` resolution
- **Backward Compatibility**: Supports multiple schema versions simultaneously with automatic compatibility checking
- **Centralized Validation**: All producer APIs call the metadata service for consistent validation
- **Non-blocking Updates**: Background git sync with in-memory caching for fast validation

## Quick Start

### Prerequisites

- Go 1.21+
- Git (for schema repository access)
- Docker (optional, for containerized deployment)

### Configuration

The service can be configured via environment variables or a YAML config file:

**Environment Variables:**
- `GIT_REPOSITORY` - Git repository URL containing schemas (required)
- `GIT_BRANCH` - Git branch to use (default: `main`)
- `LOCAL_CACHE_DIR` - Local directory for schema cache (default: `/tmp/schema-cache`)
- `SERVER_PORT` - HTTP server port (default: `8080`)
- `DEFAULT_VERSION` - Default schema version to use (default: `latest`)
- `STRICT_MODE` - Enable strict validation mode (default: `true`)

**Config File (optional):**
Create a `config.yaml` file:

```yaml
git:
  repository: "https://github.com/org/schema-repo.git"
  branch: "main"
  pull_interval: "5m"
  local_cache_dir: "/tmp/schema-cache"

validation:
  default_version: "latest"
  accepted_versions: ["v1", "v2"]
  strict_mode: true

server:
  port: 8080
  grpc_port: 9090
```

### Running Locally

```bash
# Set required environment variables
export GIT_REPOSITORY=https://github.com/your-org/schema-repo.git

# Run the service
go run cmd/server/main.go
```

### Running with Docker

```bash
# Build and run
docker-compose --profile metadata-service up -d metadata-service

# Or with custom repository
GIT_REPOSITORY=https://github.com/your-org/schema-repo.git \
docker-compose --profile metadata-service up -d metadata-service
```

## API Endpoints

### POST `/api/v1/validate`

Validate a single event against the schema.

**Request:**
```json
{
  "event": {
    "eventHeader": { ... },
    "entities": [ ... ]
  },
  "version": "v1"  // Optional: specific version to validate against
}
```

**Response:**
```json
{
  "valid": true,
  "version": "v1",
  "errors": []  // Only present if valid is false
}
```

### POST `/api/v1/validate/bulk`

Validate multiple events in a single request.

**Request:**
```json
{
  "events": [
    { "eventHeader": { ... }, "entities": [ ... ] },
    { "eventHeader": { ... }, "entities": [ ... ] }
  ],
  "version": "v1"  // Optional
}
```

**Response:**
```json
{
  "results": [
    { "valid": true, "version": "v1", "errors": [] },
    { "valid": false, "version": "v1", "errors": [...] }
  ],
  "summary": {
    "total": 2,
    "valid": 1,
    "invalid": 1
  }
}
```

### GET `/api/v1/schemas/versions`

List all available schema versions.

**Response:**
```json
{
  "versions": ["v1", "v2"],
  "default": "latest"
}
```

### GET `/api/v1/schemas/:version`

Get a specific schema by version.

**Query Parameters:**
- `type` - Schema type: `event` (default) or entity name (e.g., `car`, `loan`)

**Example:**
```
GET /api/v1/schemas/v1?type=event
GET /api/v1/schemas/v1?type=car
```

**Response:**
```json
{
  "version": "v1",
  "schema": { ... }
}
```

### GET `/api/v1/health`

Health check endpoint.

**Response:**
```json
{
  "status": "healthy",
  "version": "v1"
}
```

## Schema Repository Structure

The service expects schemas to be organized in a versioned directory structure:

```
schemas/
├── v1/
│   ├── event/
│   │   ├── event.json
│   │   └── event-header.json
│   └── entity/
│       ├── entity-header.json
│       ├── car.json
│       ├── loan.json
│       └── ...
├── v2/
│   ├── event/
│   └── entity/
└── metadata.json  # Optional: version metadata and compatibility rules
```

## Backward Compatibility

The service implements a **multi-version acceptance** approach:

1. **Schema Version Detection**: Automatically detects schema versions from git repo structure
2. **Version Compatibility Matrix**: Maintains compatibility rules between versions
3. **Event Version Inference**: Attempts to infer event version from structure or accepts explicit version header
4. **Gradual Migration**: Supports running multiple versions simultaneously during migrations

### Compatibility Rules

**Non-Breaking Changes** (automatically accepted):
- Adding optional properties (not in `required` array)
- Relaxing `minimum`/`maximum` constraints
- Adding new enum values
- Making required fields optional
- Changing `additionalProperties: false` to `true`

**Breaking Changes** (rejected):
- Removing required properties
- Adding new required properties
- Removing enum values
- Tightening constraints (e.g., smaller max value)
- Changing property types

## Integration with Producer APIs

Each producer API should call the metadata service before processing events. See the integration examples in:
- `producer-api-go-rest` - Go REST API integration
- `producer-api-python-rest-lambda-pg` - Python Lambda integration (PostgreSQL)

## Development

### Building

```bash
go build -o metadata-service ./cmd/server
```

### Testing

```bash
go test ./...
```

## Troubleshooting

### Schema Sync Issues

If schemas are not updating:
1. Check git repository access (SSH keys or HTTPS credentials)
2. Verify branch name is correct
3. Check logs for git pull errors
4. Ensure `LOCAL_CACHE_DIR` has write permissions

### Validation Failures

If validation is failing unexpectedly:
1. Check schema version is correct
2. Verify event structure matches schema
3. Review validation errors in response
4. Check if strict mode is enabled

### Service Unavailable

If producer APIs cannot reach the metadata service:
1. Verify service is running: `curl http://localhost:8080/api/v1/health`
2. Check network connectivity (Docker network if using containers)
3. Verify port is not blocked by firewall
4. Check service logs for errors

