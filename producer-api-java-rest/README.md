# Producer API

A Spring Boot RESTful API for processing events and updating entities in PostgreSQL.

## Features

- **Event Processing**: Accepts events with headers and entity updates
- **Database Integration**: Uses R2DBC to connect to PostgreSQL
- **Reactive Programming**: Built with Spring WebFlux for non-blocking I/O
- **Validation**: Comprehensive input validation using Bean Validation
- **Testing**: Unit and integration tests included

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

### GET /api/v1/events/health
Health check endpoint.

**Response:**
- `200 OK`: "Producer API is healthy"

## Database Schema

The API uses the same database schema as all other producer APIs. See the main [README.md](../README.md) for schema details.

## Running the Application

### Prerequisites
- Java 17
- PostgreSQL database
- Gradle

### Local Development
1. Start PostgreSQL database
2. Update `application.yml` with your database connection details
3. Run: `./gradlew bootRun`

### Docker
```bash
docker build -t producer-api .
docker run -p 8081:8081 producer-api
```

### Docker Compose
```bash
docker-compose --profile producer-java-rest up -d postgres-large producer-api-java-rest
```

## Testing

### Unit Tests
```bash
./gradlew test
```

### Integration Tests
The integration tests use H2 in-memory database for testing.

### Manual Testing
Use the provided test script:
```bash
./test-api.sh
```

## Configuration

The application can be configured via `application.yml`:

```yaml
spring:
  r2dbc:
    url: r2dbc:postgresql://localhost:5432/car_entities
    username: postgres
    password: password

server:
  port: 8081
```

## Architecture

- **Controller Layer**: Handles HTTP requests and responses
- **Service Layer**: Business logic for event processing
- **Repository Layer**: Data access using Spring Data R2DBC
- **Entity Layer**: Data model representing database entities
- **DTO Layer**: Data transfer objects for API requests/responses

## Event Processing Logic

The API follows a standard event processing workflow:
1. **Validation**: Validates event structure and required fields
2. **Entity Check**: Determines if entities exist or need to be created
3. **Update/Create**: Updates existing entities or creates new ones
4. **JSON Processing**: Handles JSONB data storage and updates
5. **Error Handling**: Comprehensive error handling and logging

This logic is consistent across all producer API implementations.

## Event Model

### Event Structure

Events follow a standardized structure with header and body sections:

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

### Supported Event Types

- **LoanPaymentSubmitted**: Updates loan balance and payment date
- **CarServiceDone**: Adds service records to car entities
- **LoanCreated**: Creates new loan entities
- **CarCreated**: Creates new car entities

### Entity Types

- **Car**: Vehicle information with service records and loans
- **Loan**: Financial loan information
- **LoanPayment**: Payment transaction records
- **ServiceRecord**: Vehicle service history

## Performance Characteristics

### Expected Performance
- **Response Time**: < 500ms average, < 1000ms 95th percentile
- **Throughput**: > 100 requests/second
- **Success Rate**: > 95% under load

### Load Testing
```bash
# Run k6 throughput tests
cd ../load-test/shared
./run-sequential-throughput-tests.sh smoke
```

## Related Documentation

- **[Performance Testing](../load-test/README.md)**: k6-based performance testing framework
- **[Throughput Testing Guide](../load-test/THROUGHPUT-TESTING-GUIDE.md)**: Detailed k6 testing guide
