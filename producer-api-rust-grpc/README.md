# Producer API Rust gRPC

A high-performance gRPC API for processing events and updating entities in PostgreSQL, built with Rust and Tonic.

## Features

- **Event Processing**: Accepts events with headers and entity updates via gRPC
- **Database Integration**: Uses sqlx for async PostgreSQL access with compile-time SQL checking
- **Protocol Buffers**: Efficient binary serialization with Protocol Buffers
- **HTTP/2 Support**: Multiplexing and streaming capabilities
- **Type Safety**: Strong typing with generated code from proto definitions
- **Performance**: Lower latency and higher throughput than REST

## gRPC Service Definition

The gRPC service is defined in `proto/event_service.proto`:

```protobuf
service EventService {
  rpc ProcessEvent(EventRequest) returns (EventResponse);
  rpc HealthCheck(HealthRequest) returns (HealthResponse);
}
```

## Service Methods

### ProcessEvent
Processes an event containing entity updates.

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
Health check service method.

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

## Database Schema

The API uses the same database schema as all other producer APIs. See the main [README.md](../README.md) for schema details.

## Prerequisites

- Rust 1.75 or later
- PostgreSQL database
- Cargo (Rust package manager)
- Protocol Buffer compiler (protoc) - included in build process

## Running the Application

### Local Development

1. Set environment variables:
```bash
export DATABASE_URL="postgresql://postgres:password@localhost:5432/car_entities"
export GRPC_SERVER_PORT=9090
export RUST_LOG=info
```

2. Run migrations (if using sqlx-cli):
```bash
sqlx migrate run --source ../producer-api-rust/migrations
```

3. Run the application:
```bash
cargo run
```

### Docker

```bash
# Build the image
docker build -t producer-api-rust-grpc .

# Run the container
docker run -p 9090:9090 \
  -e DATABASE_URL="postgresql://postgres:password@host.docker.internal:5432/car_entities" \
  -e GRPC_SERVER_PORT=9090 \
  producer-api-rust-grpc
```

### Docker Compose

The service is already configured in the main `docker-compose.yml`. Start it with:

```bash
docker-compose --profile producer-rust-grpc up -d postgres-large producer-api-rust-grpc
```

## Configuration

The application can be configured via environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `postgresql://postgres:password@localhost:5432/car_entities` |
| `GRPC_SERVER_PORT` | gRPC server port | `9090` |
| `RUST_LOG` | Logging level | `info` |

## Architecture

- **Service Layer**: gRPC service implementation with Tonic
- **Business Logic**: Event processing service (duplicated from REST version)
- **Repository Layer**: Data access using sqlx
- **Error Handling**: Structured error types with conversion to gRPC Status

## Event Processing Logic

The API follows the same event processing workflow as all other producer APIs. The main difference is error handling, which uses gRPC status codes instead of HTTP status codes. See [producer-api-java-rest/README.md](../producer-api-java-rest/README.md#event-processing-logic) for the standard workflow.

## Testing

```bash
# Run unit tests
cargo test

# Run with output
cargo test -- --nocapture
```

## gRPC Client Example

### Using grpcurl

```bash
# Health check
grpcurl -plaintext localhost:9090 com.example.grpc.EventService/HealthCheck

# Process event
grpcurl -plaintext -d '{
  "event_header": {
    "event_name": "LoanPaymentSubmitted"
  },
  "event_body": {
    "entities": [{
      "entity_type": "Loan",
      "entity_id": "loan-12345",
      "updated_attributes": {
        "balance": "24439.75"
      }
    }]
  }
}' localhost:9090 com.example.grpc.EventService/ProcessEvent
```

## Performance

gRPC provides several advantages over REST:
- **Binary Protocol**: More efficient serialization than JSON
- **HTTP/2**: Multiplexing and header compression
- **Streaming**: Support for streaming requests and responses
- **Type Safety**: Compile-time type checking with generated code

## Comparison with Other Implementations

This Rust implementation provides the same functionality as all other producer API gRPC implementations with:
- Same proto definition and service methods
- Same database schema and operations
- Equivalent error handling and validation
- Better performance characteristics due to Rust's zero-cost abstractions

