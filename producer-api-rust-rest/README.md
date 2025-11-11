# Producer API Rust

A high-performance RESTful API for processing events and updating entities in PostgreSQL, built with Rust and Axum.

## Features

- **Event Processing**: Accepts events with headers and entity updates
- **Database Integration**: Uses sqlx for async PostgreSQL access with compile-time SQL checking
- **Reactive Programming**: Built with Tokio async runtime for non-blocking I/O
- **Validation**: Comprehensive input validation using validator crate
- **Error Handling**: Structured error handling with thiserror and anyhow
- **Performance**: Native Rust performance with minimal overhead

## API Endpoints

### POST /api/v1/events
Processes an event containing entity updates.

**Request Body:**
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

**Response:**
- `200 OK`: Event processed successfully
- `400 Bad Request`: Invalid event data
- `500 Internal Server Error`: Processing error

### POST /api/v1/events/bulk
Processes multiple events in a single request.

**Request Body:**
```json
[
  {
    "eventHeader": { ... },
    "eventBody": { ... }
  },
  ...
]
```

**Response:**
```json
{
  "success": true,
  "message": "All events processed successfully",
  "processedCount": 2,
  "failedCount": 0,
  "batchId": "batch-1234567890",
  "processingTimeMs": 100
}
```

### GET /api/v1/events/health
Health check endpoint.

**Response:**
- `200 OK`: `{"status": "healthy", "message": "Producer API is healthy"}`

## Database Schema

The API uses the same database schema as all other producer APIs. See the main [README.md](../README.md) for schema details.

## Prerequisites

- Rust 1.75 or later
- PostgreSQL database
- Cargo (Rust package manager)

## Running the Application

### Local Development

1. Set environment variables:
```bash
export DATABASE_URL="postgresql://postgres:password@localhost:5432/car_entities"
export SERVER_PORT=8081
export RUST_LOG=info
```

2. Run migrations (if using sqlx-cli):
```bash
sqlx migrate run
```

3. Run the application:
```bash
cargo run
```

### Docker

```bash
# Build the image
docker build -t producer-api-rust .

# Run the container
docker run -p 8081:8081 \
  -e DATABASE_URL="postgresql://postgres:password@host.docker.internal:5432/car_entities" \
  -e SERVER_PORT=8081 \
  producer-api-rust
```

### Docker Compose

The service is already configured in the main `docker-compose.yml`. Start it with:

```bash
docker-compose --profile producer-rust-rest up -d postgres-large producer-api-rust-rest
```

## Configuration

The application can be configured via environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `postgresql://postgres:password@localhost:5432/car_entities` |
| `SERVER_PORT` | Server port | `8081` |
| `RUST_LOG` | Logging level | `info` |

## Architecture

- **Handler Layer**: HTTP request/response handling with Axum
- **Service Layer**: Business logic for event processing
- **Repository Layer**: Data access using sqlx
- **Model Layer**: Data models and DTOs
- **Error Handling**: Structured error types with thiserror

## Event Processing Logic

The API follows the same event processing workflow as all other producer APIs. See [producer-api-java-rest/README.md](../producer-api-java-rest/README.md#event-processing-logic) for details.

## Testing

```bash
# Run unit tests
cargo test

# Run with output
cargo test -- --nocapture
```

## Performance

Rust's zero-cost abstractions and async runtime provide:
- Lower memory footprint compared to JVM-based solutions
- Faster startup time
- Higher throughput for concurrent requests
- Better resource utilization

## Comparison with Other Implementations

This Rust implementation provides the same functionality as all other producer API implementations with:
- Same API endpoints and behavior
- Same database schema and operations
- Equivalent error handling and validation
- Better performance characteristics due to Rust's zero-cost abstractions

