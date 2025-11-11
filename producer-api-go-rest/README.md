# Producer API - Go REST

Go implementation of the Producer API REST service using Gin framework.

## Features

- RESTful API for processing events
- PostgreSQL database integration using pgx
- Event processing with entity creation and updates
- Bulk event processing
- Health check endpoint
- Structured logging with zap
- Docker support

## API Endpoints

### POST `/api/v1/events`

Process a single event.

**Request Body:**
```json
{
  "eventHeader": {
    "uuid": "optional-uuid",
    "eventName": "CarCreated",
    "createdDate": "2024-01-01T00:00:00Z",
    "savedDate": "2024-01-01T00:00:00Z",
    "eventType": "optional-type"
  },
  "eventBody": {
    "entities": [
      {
        "entityType": "car",
        "entityId": "car-123",
        "updatedAttributes": {
          "make": "Toyota",
          "model": "Camry",
          "year": 2024
        }
      }
    ]
  }
}
```

**Response:**
```json
{
  "success": true,
  "message": "Event processed successfully"
}
```

### POST `/api/v1/events/bulk`

Process multiple events in a single request.

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
  "processedCount": 10,
  "failedCount": 0,
  "batchId": "batch-1234567890",
  "processingTimeMs": 100
}
```

### GET `/api/v1/events/health`

Health check endpoint.

**Response:**
```json
{
  "status": "healthy",
  "message": "Producer API is healthy"
}
```

## Configuration

The application uses environment variables for configuration:

- `DATABASE_URL`: PostgreSQL connection string (default: `postgresql://postgres:password@localhost:5432/car_entities`)
- `SERVER_PORT`: Server port (default: `9083`)
- `LOG_LEVEL`: Logging level - `debug`, `info`, `warn`, `error` (default: `info`)

## Running Locally

1. Ensure PostgreSQL is running and accessible
2. Set environment variables (or use defaults)
3. Run migrations (they run automatically on startup)
4. Start the server:

```bash
go run cmd/server/main.go
```

## Building

```bash
go build -o producer-api-go ./cmd/server
```

## Docker

Build the Docker image:

```bash
docker build -t producer-api-go .
```

Run the container:

```bash
docker run -p 9083:9083 \
  -e DATABASE_URL=postgresql://postgres:password@host.docker.internal:5432/car_entities \
  -e SERVER_PORT=9083 \
  -e LOG_LEVEL=info \
  producer-api-go
```

### Docker Compose

The service is already configured in the main `docker-compose.yml`. Start it with:

```bash
docker-compose --profile producer-go-rest up -d postgres-large producer-api-go-rest
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
- `internal/handlers/`: HTTP handlers (event, health)
- `internal/models/`: Data models (Event, Entity, etc.)
- `internal/repository/`: Database repository layer
- `internal/service/`: Business logic layer
- `internal/errors/`: Error handling
- `migrations/`: SQL migration files
- `tests/`: Integration tests

## Date/Time Handling

The API supports flexible date/time parsing:
- ISO 8601 strings (RFC3339, RFC3339Nano, and common variants)
- Unix timestamps in milliseconds (as strings or numbers)

## JSON Merging

When updating existing entities, the API merges JSON objects. New attributes are added, and existing attributes are updated with new values.

