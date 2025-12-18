# Test Data Guide

This guide provides detailed information about test event structures, test data generation, and sample events used in the CDC streaming test suite.

## Event Types

The test suite uses 4 primary event types that correspond to the filtered topics:

### 1. CarCreated Event

**Routes to**: `filtered-car-created-events`

**Structure**:
```json
{
  "id": "event-123",
  "event_name": "CarCreated",
  "event_type": "CarCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "header_data": "{\"uuid\":\"event-123\",\"eventName\":\"CarCreated\",\"eventType\":\"CarCreated\",\"createdDate\":\"2024-01-15T10:30:00Z\",\"savedDate\":\"2024-01-15T10:30:05Z\"}",
  "__op": "c",
  "__table": "event_headers",
  "__ts_ms": 1705312205000
}
```

**Filter Criteria**: `event_type = 'CarCreated' AND __op = 'c'`

### 2. LoanCreated Event

**Routes to**: `filtered-loan-created-events`

**Structure**:
```json
{
  "id": "event-456",
  "event_name": "LoanCreated",
  "event_type": "LoanCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "header_data": "{\"uuid\":\"event-456\",\"eventName\":\"LoanCreated\",\"eventType\":\"LoanCreated\",\"createdDate\":\"2024-01-15T10:30:00Z\",\"savedDate\":\"2024-01-15T10:30:05Z\"}",
  "__op": "c",
  "__table": "event_headers",
  "__ts_ms": 1705312205000
}
```

**Filter Criteria**: `event_type = 'LoanCreated' AND __op = 'c'`

### 3. LoanPaymentSubmitted Event

**Routes to**: `filtered-loan-payment-submitted-events`

**Structure**:
```json
{
  "id": "event-789",
  "event_name": "LoanPaymentSubmitted",
  "event_type": "LoanPaymentSubmitted",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "header_data": "{\"uuid\":\"event-789\",\"eventName\":\"LoanPaymentSubmitted\",\"eventType\":\"LoanPaymentSubmitted\",\"createdDate\":\"2024-01-15T10:30:00Z\",\"savedDate\":\"2024-01-15T10:30:05Z\"}",
  "__op": "c",
  "__table": "event_headers",
  "__ts_ms": 1705312205000
}
```

**Filter Criteria**: `event_type = 'LoanPaymentSubmitted' AND __op = 'c'`

### 4. CarServiceDone Event

**Routes to**: `filtered-service-events`

**Structure**:
```json
{
  "id": "event-012",
  "event_name": "CarServiceDone",
  "event_type": "CarServiceDone",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "header_data": "{\"uuid\":\"event-012\",\"eventName\":\"CarServiceDone\",\"eventType\":\"CarServiceDone\",\"createdDate\":\"2024-01-15T10:30:00Z\",\"savedDate\":\"2024-01-15T10:30:05Z\"}",
  "__op": "c",
  "__table": "event_headers",
  "__ts_ms": 1705312205000
}
```

**Filter Criteria**: `event_type = 'CarServiceDone' AND __op = 'c'`

## Test Data Generation

### Using TestEventGenerator

The `TestEventGenerator` utility class provides methods to generate test events:

```java
import com.example.e2e.fixtures.TestEventGenerator;
import com.example.e2e.model.EventHeader;

// Generate single event
EventHeader carEvent = TestEventGenerator.generateCarCreatedEvent("event-id-001");
EventHeader loanEvent = TestEventGenerator.generateLoanCreatedEvent("event-id-002");
EventHeader paymentEvent = TestEventGenerator.generateLoanPaymentEvent("event-id-003");
EventHeader serviceEvent = TestEventGenerator.generateServiceEvent("event-id-004");

// Generate batch of mixed events
List<EventHeader> mixedEvents = TestEventGenerator.generateMixedEventBatch(100);

// Generate batch of specific type
List<EventHeader> carEvents = TestEventGenerator.generateEventBatch("CarCreated", 50);
```

### Custom Event Creation

For custom events, use the `EventHeader.builder()`:

```java
EventHeader customEvent = EventHeader.builder()
    .id("custom-event-001")
    .eventName("CustomEvent")
    .eventType("CustomEvent")
    .createdDate(Instant.now().toString())
    .savedDate(Instant.now().toString())
    .headerData("{\"uuid\":\"custom-event-001\",\"eventType\":\"CustomEvent\"}")
    .op("c")
    .table("event_headers")
    .tsMs(Instant.now().toEpochMilli())
    .build();
```

### Batch Generation

Generate batches for load testing:

```java
// Generate 1000 mixed events
List<EventHeader> largeBatch = TestEventGenerator.generateMixedEventBatch(1000);

// Generate sequential events
List<EventHeader> sequentialEvents = TestEventGenerator.generateLoanCreatedEventBatch(
    "LoanCreated", 100
);
```

## Sample Events

### Valid Event Examples

#### Standard CarCreated Event

```json
{
  "id": "car-001",
  "event_name": "CarCreated",
  "event_type": "CarCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "header_data": "{\"uuid\":\"car-001\",\"eventName\":\"CarCreated\",\"eventType\":\"CarCreated\",\"createdDate\":\"2024-01-15T10:30:00Z\",\"savedDate\":\"2024-01-15T10:30:05Z\"}",
  "__op": "c",
  "__table": "event_headers",
  "__ts_ms": 1705312205000
}
```

#### Update Operation Event (Filtered Out)

```json
{
  "id": "car-001",
  "event_name": "CarCreated",
  "event_type": "CarCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:35:00Z",
  "header_data": "{\"uuid\":\"car-001\",\"eventName\":\"CarCreated\",\"eventType\":\"CarCreated\"}",
  "__op": "u",
  "__table": "event_headers",
  "__ts_ms": 1705312500000
}
```

*Note: Update operations (`__op = 'u'`) are filtered out for CarCreated, LoanCreated, and LoanPaymentSubmitted events.*

### Edge Case Examples

#### Empty Header Data

```json
{
  "id": "edge-empty-001",
  "event_name": "CarCreated",
  "event_type": "CarCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "header_data": "{}",
  "__op": "c",
  "__table": "event_headers",
  "__ts_ms": 1705312205000
}
```

#### Large Header Data (>1MB)

```json
{
  "id": "edge-large-001",
  "event_name": "CarCreated",
  "event_type": "CarCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "header_data": "{\"uuid\":\"edge-large-001\",\"largeField\":\"<1MB of data>\"}",
  "__op": "c",
  "__table": "event_headers",
  "__ts_ms": 1705312205000
}
```

#### Special Characters

```json
{
  "id": "edge-special-001",
  "event_name": "CarCreated-测试-émoji-🚗",
  "event_type": "CarCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "header_data": "{\"uuid\":\"edge-special-001\",\"eventName\":\"CarCreated-测试-émoji-🚗\"}",
  "__op": "c",
  "__table": "event_headers",
  "__ts_ms": 1705312205000
}
```

#### Null Event Type (Filtered Out)

```json
{
  "id": "edge-null-001",
  "event_name": "CarCreated",
  "event_type": null,
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "header_data": "{\"uuid\":\"edge-null-001\"}",
  "__op": "c",
  "__table": "event_headers",
  "__ts_ms": 1705312205000
}
```

### Invalid Event Examples

#### Malformed JSON in header_data

```json
{
  "id": "invalid-001",
  "event_name": "CarCreated",
  "event_type": "CarCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "header_data": "{invalid json}",
  "__op": "c",
  "__table": "event_headers",
  "__ts_ms": 1705312205000
}
```

*Note: Invalid JSON should be handled gracefully (filtered out or sent to DLQ).*

## Event Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | String | Yes | Unique event identifier |
| `event_name` | String | Yes | Human-readable event name |
| `event_type` | String | Yes | Event type for filtering |
| `created_date` | String (ISO-8601) | Yes | Event creation timestamp |
| `saved_date` | String (ISO-8601) | Yes | Event save timestamp |
| `header_data` | String (JSON) | Yes | Event header JSON structure |
| `__op` | String | Yes | CDC operation: 'c'=create, 'u'=update, 'd'=delete |
| `__table` | String | Yes | Source table name |
| `__ts_ms` | Long | Yes | CDC timestamp in milliseconds |

## Test Data Best Practices

1. **Unique IDs**: Always use unique event IDs to avoid conflicts
2. **Realistic Timestamps**: Use current timestamps or realistic time sequences
3. **Valid JSON**: Ensure `header_data` contains valid JSON
4. **Consistent Format**: Follow the standard event structure
5. **Edge Cases**: Include edge cases in test data
6. **Batch Sizes**: Use appropriate batch sizes for test scenarios
7. **Cleanup**: Clean up test data after tests complete

## Test Data Files

Sample event files are available in:
- `e2e-tests/src/test/resources/test-events/car-created.json`
- `e2e-tests/src/test/resources/test-events/loan-created.json`
- `e2e-tests/src/test/resources/test-events/loan-payment.json`
- `e2e-tests/src/test/resources/test-events/service-done.json`

## Loading Test Data from Files

```java
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.InputStream;

ObjectMapper mapper = new ObjectMapper();
InputStream is = getClass().getResourceAsStream("/test-events/car-created.json");
EventHeader event = mapper.readValue(is, EventHeader.class);
```

## Generating Test Data Scripts

Use the provided scripts for generating test data:

```bash
# Generate test events
cd cdc-streaming/e2e-tests/scripts
./generate-test-events.sh --count 1000 --type mixed
```

See `e2e-tests/scripts/` for available scripts.
