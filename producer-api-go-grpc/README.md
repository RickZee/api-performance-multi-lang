# Producer API - Go gRPC

Go implementation of the Producer API gRPC service.

## Features

- gRPC API for processing events
- PostgreSQL database integration using pgx
- Event processing with entity creation and updates
- Health check endpoint
- Structured logging with zap
- Docker support

## gRPC Service

### ProcessEvent

Process a single event with entity updates.

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

### HealthCheck

Health check endpoint.

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

## Configuration

The application uses environment variables for configuration:

- `DATABASE_URL`: PostgreSQL connection string (default: `postgresql://postgres:password@localhost:5432/car_entities`)
- `GRPC_SERVER_PORT`: gRPC server port (default: `7090`)
- `LOG_LEVEL`: Logging level - `debug`, `info`, `warn`, `error` (default: `info`)

## Running Locally

1. Generate proto files:
```bash
chmod +x scripts/generate-proto.sh
./scripts/generate-proto.sh
```

2. Ensure PostgreSQL is running and accessible
3. Set environment variables (or use defaults)
4. Run migrations (they run automatically on startup)
5. Start the server:

```bash
go run cmd/server/main.go
```

## Building

```bash
# Generate proto files first
./scripts/generate-proto.sh

# Build
go build -o producer-api-go-grpc ./cmd/server
```

## Docker

Build the Docker image (proto generation is done automatically):

```bash
docker build -t producer-api-go-grpc .
```

Run the container:

```bash
docker run -p 7090:7090 \
  -e DATABASE_URL=postgresql://postgres:password@host.docker.internal:5432/car_entities \
  -e GRPC_SERVER_PORT=7090 \
  -e LOG_LEVEL=info \
  producer-api-go-grpc
```

## Testing

### Integration Tests

Run integration tests:

```bash
go test ./tests/...
```

Integration tests require a running PostgreSQL instance. Set the `DATABASE_URL` environment variable to point to your test database.

## Architecture

- `cmd/server/`: Main application entry point
- `internal/config/`: Configuration management
- `internal/service/`: Business logic and gRPC service implementation
- `internal/models/`: Data models (Entity, etc.)
- `internal/repository/`: Database repository layer
- `proto/`: Protocol Buffer definitions and generated code
- `migrations/`: SQL migration files
- `tests/`: Integration tests

## Proto Generation

The proto files need to be generated before building. The Docker build process handles this automatically, but for local development:

1. Install protoc (Protocol Buffers compiler)
2. Install Go plugins:
   ```bash
   go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
   go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
   ```
3. Run the generation script:
   ```bash
   ./scripts/generate-proto.sh
   ```

