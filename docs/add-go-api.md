# Go Producer APIs Implementation Plan

## Overview

Create Go implementations of the producer APIs (REST and gRPC) with the same functionality as the Rust versions, including comprehensive testing and k6 load testing support.

## Architecture Decisions

- **REST API**: Gin framework with `database/sql` + `pgx` driver
- **gRPC API**: Standard Go gRPC with `database/sql` + `pgx` driver
- **Ports**: 9083 (REST), 9092 (gRPC) - starting with "9" as requested
- **Testing**: Unit tests, integration tests, and k6 throughput tests

## Implementation Tasks

### 1. Go REST API (`producer-api-go-rest`)

#### 1.1 Project Structure

- Create `producer-api-go-rest/` directory
- Set up Go module (`go.mod`)
- Create directory structure:
                - `cmd/server/` - main application entry point
                - `internal/config/` - configuration management
                - `internal/handlers/` - HTTP handlers (event, health)
                - `internal/models/` - data models (Event, Entity, etc.)
                - `internal/repository/` - database repository layer
                - `internal/service/` - business logic layer
                - `internal/errors/` - error handling
                - `migrations/` - SQL migration files
                - `tests/` - integration tests

#### 1.2 Core Components

- **Config** (`internal/config/config.go`): Load from environment variables (DATABASE_URL, SERVER_PORT, LOG_LEVEL)
- **Models** (`internal/models/`): Event, EventHeader, EventBody, EntityUpdate, CarEntity structs with JSON tags
- **Repository** (`internal/repository/car_entity_repo.go`): Database operations using pgx
                - `FindByEntityTypeAndID()`
                - `ExistsByEntityTypeAndID()`
                - `Create()`
                - `Update()`
- **Service** (`internal/service/event_processing.go`): Business logic
                - `ProcessEvent()` - handle single event
                - `ProcessEntityUpdate()` - create or update entity
                - `CreateNewEntity()` - insert new entity
                - `UpdateExistingEntity()` - merge and update existing entity
- **Handlers** (`internal/handlers/`):
                - `event.go`: POST `/api/v1/events`, POST `/api/v1/events/bulk`
                - `health.go`: GET `/api/v1/events/health`
- **Error Handling** (`internal/errors/app_error.go`): Custom error types with HTTP status mapping

#### 1.3 Main Application (`cmd/server/main.go`)

- Initialize database connection pool (pgxpool)
- Run migrations
- Set up Gin router with CORS
- Register handlers
- Start HTTP server on port 9083

#### 1.4 Database Migrations

- Copy `migrations/001_initial_schema.sql` from Rust version
- Implement migration runner in Go

#### 1.5 Testing

- **Unit Tests**: Test service and repository layers with mocks
- **Integration Tests** (`tests/integration_test.go`): 
                - Test event processing with new entity
                - Test event processing with existing entity
                - Test multiple entities in one event
                - Test bulk events
                - Test validation errors
                - Test health check

#### 1.6 Docker Support

- Create `Dockerfile` (multi-stage build)
- Create `.dockerignore`
- Update `docker-compose.yml` with `producer-api-go-rest` service

### 2. Go gRPC API (`producer-api-go-grpc`)

#### 2.1 Project Structure

- Create `producer-api-go-grpc/` directory
- Set up Go module (`go.mod`)
- Create directory structure similar to REST API
- Add `proto/` directory for Protocol Buffer definitions

#### 2.2 Protocol Buffers

- Copy `proto/event_service.proto` from Rust gRPC version
- Generate Go code using `protoc` with `protoc-gen-go` and `protoc-gen-go-grpc`
- Create `scripts/generate-proto.sh` for code generation

#### 2.3 Core Components

- **Config** (`internal/config/config.go`): GRPC_SERVER_PORT environment variable
- **Repository**: Reuse same repository pattern as REST API
- **Service** (`internal/service/event_processing.go`): Same business logic, adapted for gRPC input/output
- **gRPC Service** (`internal/service/event_service.go`): Implement `EventServiceServer` interface
                - `ProcessEvent()` - handle gRPC EventRequest
                - `HealthCheck()` - handle gRPC HealthRequest

#### 2.4 Main Application (`cmd/server/main.go`)

- Initialize database connection pool
- Run migrations
- Create gRPC server
- Register EventService
- Start gRPC server on port 9092

#### 2.5 Testing

- **Unit Tests**: Test service and repository layers
- **Integration Tests** (`tests/integration_test.go`):
                - Test ProcessEvent with new entity
                - Test ProcessEvent with existing entity
                - Test HealthCheck
                - Test validation errors

#### 2.6 Docker Support

- Create `Dockerfile` (include protoc for proto generation)
- Update `docker-compose.yml` with `producer-api-go-grpc` service

### 3. k6 Test Updates

#### 3.1 Update Configuration

- Update `load-test/k6/config.js`:
                - Add `producer-api-go-rest` configuration (port 9083)
                - Add `producer-api-go-grpc` configuration (port 9092, proto file path)

#### 3.2 Proto File Setup

- Copy proto file to `load-test/k6/proto/go-grpc/event_service.proto`
- Ensure k6 can load the proto file for gRPC tests

#### 3.3 Test Scripts

- Verify `rest-api-test.js` works with Go REST API
- Verify `grpc-api-test.js` works with Go gRPC API
- No changes needed if helpers are generic enough

### 4. Docker Compose Updates

#### 4.1 Add Go REST Service

```yaml
producer-api-go-rest:
  build: ./producer-api-go
  container_name: producer-api-go
  ports:
  - "9083:9083"
  environment:
    DATABASE_URL: postgresql://postgres:password@postgres-large:5432/car_entities
    SERVER_PORT: 9083
    LOG_LEVEL: info
  profiles:
  - producer-go
```

#### 4.2 Add Go gRPC Service

```yaml
producer-api-go-grpc:
  build: ./producer-api-go-grpc
  container_name: producer-api-go-grpc
  ports:
  - "9092:9092"
  environment:
    DATABASE_URL: postgresql://postgres:password@postgres-large:5432/car_entities
    GRPC_SERVER_PORT: 9092
    LOG_LEVEL: info
  profiles:
  - producer-go-grpc
```

#### 4.3 Update k6 Service

- Add volume mount for Go gRPC proto file: `./producer-api-go-grpc/proto:/k6/proto/go-grpc:ro`

### 5. Documentation

#### 5.1 README Files

- Create `producer-api-go-rest/README.md` with:
                - API endpoints documentation
                - Running instructions
                - Testing instructions
                - Docker instructions
- Create `producer-api-go-grpc/README.md` with:
                - gRPC service documentation
                - Running instructions
                - Testing instructions
                - Docker instructions

### 6. Dependencies

#### 6.1 Go REST API Dependencies

- `github.com/gin-gonic/gin` - Web framework
- `github.com/jackc/pgx/v5` - PostgreSQL driver
- `github.com/jackc/pgx/v5/pgxpool` - Connection pooling
- `github.com/joho/godotenv` - Environment variable loading
- `go.uber.org/zap` or `log/slog` - Logging

#### 6.2 Go gRPC API Dependencies

- `google.golang.org/grpc` - gRPC framework
- `google.golang.org/protobuf` - Protocol Buffers
- `github.com/jackc/pgx/v5` - PostgreSQL driver
- `github.com/jackc/pgx/v5/pgxpool` - Connection pooling
- `github.com/joho/godotenv` - Environment variable loading
- `go.uber.org/zap` or `log/slog` - Logging

## Key Implementation Details

### Date/Time Handling

- Support both ISO 8601 strings and Unix timestamps (milliseconds) in event headers
- Use `time.Time` for timestamps
- Custom JSON unmarshaler for flexible date parsing

### JSON Merging

- When updating existing entities, merge JSON objects
- Use `encoding/json` to parse, merge, and serialize

### Error Handling

- Custom error types with appropriate HTTP/gRPC status codes
- Structured logging for errors
- Consistent error response format

### Connection Pooling

- Use pgxpool for connection management
- Configure max connections (10, matching Rust)
- Proper connection lifecycle management

### Logging

- Use structured logging (zap or slog)
- Log event processing milestones
- Log persisted event count every 10 events (matching Rust)

## Testing Strategy

### Unit Tests

- Mock repository layer
- Test service logic in isolation
- Test validation logic
- Test error handling

### Integration Tests

- Use real database (Docker PostgreSQL)
- Test full request/response cycle
- Test database operations
- Test error scenarios

### k6 Tests

- Smoke tests (10 VUs, 30s)
- Full tests (3 phases: 10, 50, 100 VUs)
- Saturation tests (7 phases: up to 2000 VUs)
- Measure throughput, latency, error rates

## Files to Create

### REST API

- `producer-api-go-rest/go.mod`
- `producer-api-go-rest/go.sum`
- `producer-api-go-rest/cmd/server/main.go`
- `producer-api-go-rest/internal/config/config.go`
- `producer-api-go-rest/internal/models/event.go`
- `producer-api-go-rest/internal/models/entity.go`
- `producer-api-go-rest/internal/repository/car_entity_repo.go`
- `producer-api-go-rest/internal/service/event_processing.go`
- `producer-api-go-rest/internal/handlers/event.go`
- `producer-api-go-rest/internal/handlers/health.go`
- `producer-api-go-rest/internal/errors/app_error.go`
- `producer-api-go-rest/migrations/001_initial_schema.sql`
- `producer-api-go-rest/tests/integration_test.go`
- `producer-api-go-rest/Dockerfile`
- `producer-api-go-rest/.dockerignore`
- `producer-api-go-rest/README.md`

### gRPC API

- `producer-api-go-grpc/go.mod`
- `producer-api-go-grpc/go.sum`
- `producer-api-go-grpc/cmd/server/main.go`
- `producer-api-go-grpc/internal/config/config.go`
- `producer-api-go-grpc/internal/repository/car_entity_repo.go`
- `producer-api-go-grpc/internal/service/event_processing.go`
- `producer-api-go-grpc/internal/service/event_service.go`
- `producer-api-go-grpc/proto/event_service.proto`
- `producer-api-go-grpc/scripts/generate-proto.sh`
- `producer-api-go-grpc/tests/integration_test.go`
- `producer-api-go-grpc/Dockerfile`
- `producer-api-go-grpc/.dockerignore`
- `producer-api-go-grpc/README.md`

### Test Updates

- `load-test/k6/config.js` (update)
- `load-test/k6/proto/go-grpc/event_service.proto` (copy)
- `docker-compose.yml` (update)