# E2E Tests for Flink and Spring Boot Stream Processors

Comprehensive end-to-end tests that verify functional parity between Flink SQL and Spring Boot Kafka Streams services, test the full pipeline from Producer API through CDC to filtered topics, and validate major functionality.

## Test Architecture

The test suite includes:

1. **Functional Parity Tests**: Verify both services produce identical output
2. **Full Pipeline Tests**: Test complete flow from Producer API → CDC → Kafka → Stream Processor → Filtered Topics
3. **Performance Comparison Tests**: Measure throughput and latency
4. **Error Handling Tests**: Verify resilience and error handling

## Prerequisites

- Confluent Cloud account with Kafka cluster
- Confluent Cloud API key/secret
- Docker and Docker Compose
- Java 17+
- Flink SQL statements deployed to Confluent Cloud
- Spring Boot stream processor service (can be started via Docker Compose)

## Setup

### 1. Set Environment Variables

```bash
export CONFLUENT_BOOTSTRAP_SERVERS=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
export CONFLUENT_API_KEY=your-api-key
export CONFLUENT_API_SECRET=your-api-secret
```

### 2. Start Spring Boot Stream Processor

```bash
./scripts/setup-test-environment.sh
```

Or manually:

```bash
docker-compose -f docker-compose.test.yml up -d
```

### 3. Verify Flink SQL Statements are Running

Ensure your Flink SQL statements are deployed and running in Confluent Cloud. The tests assume:
- Source topic: `raw-event-headers`
- Filtered topics: `filtered-car-created-events`, `filtered-loan-created-events`, `filtered-loan-payment-submitted-events`, `filtered-service-events`

## Running Tests

### Run All Tests

```bash
./gradlew test
```

### Run Specific Test Suite

```bash
# Functional parity tests
./gradlew test --tests FunctionalParityTest

# Full pipeline tests
./gradlew test --tests FullPipelineTest

# Performance comparison tests
./gradlew test --tests PerformanceComparisonTest

# Latency benchmark tests
./gradlew test --tests LatencyBenchmarkTest

# Load tests
./gradlew test --tests LoadTest

# Resilience tests
./gradlew test --tests ResilienceTest

# Schema evolution tests
./gradlew test --tests SchemaEvolutionTest

# Edge case tests
./gradlew test --tests EdgeCaseTest

# Error handling tests
./gradlew test --tests ErrorHandlingTest

# Metrics validation tests
./gradlew test --tests MetricsValidationTest
```

### Run with Test Reports

```bash
./gradlew test --info
```

## Test Categories

### Functional Tests

| Test Class | Purpose | Key Test Cases |
|------------|---------|----------------|
| `FunctionalParityTest` | Verify Flink/Spring output parity | Event routing, structure preservation, batch processing |
| `FullPipelineTest` | End-to-end flow validation | Complete flows, bulk processing, ordering, idempotency |
| `SchemaEvolutionTest` | Schema compatibility | Backward/forward compatibility, unknown fields |
| `EdgeCaseTest` | Boundary conditions | Null, empty, large payloads, special characters |
| `ErrorHandlingTest` | Error scenarios | Invalid events, missing fields, offset management |

### Performance Tests

| Test Class | Purpose | Key Test Cases |
|------------|---------|----------------|
| `PerformanceComparisonTest` | Throughput comparison | Throughput, latency, concurrent processing, backpressure |
| `LatencyBenchmarkTest` | Latency percentiles | P50/P95/P99, latency under load, by event type |
| `LoadTest` | Sustained load testing | Ramp-up, spike load, endurance, recovery after backpressure |

### Resilience Tests

| Test Class | Purpose | Key Test Cases |
|------------|---------|----------------|
| `ResilienceTest` | Recovery scenarios | Service restart, state recovery, network partition, RTO |
| `ChaosTest` | Failure injection | Pod termination, broker failure, resource exhaustion |
| `DeadLetterQueueTest` | DLQ validation | Malformed events, deserialization errors, retry |

### Observability Tests

| Test Class | Purpose | Key Test Cases |
|------------|---------|----------------|
| `MetricsValidationTest` | Prometheus metrics | Metrics exposure, Kafka Streams metrics, custom metrics |
| `HealthCheckTest` | K8s probes | Liveness, readiness, Kafka Streams health |
| `ObservabilityTest` | Logging/tracing | Structured logging, distributed tracing, correlation |

## SLA Targets

The test suite validates the following SLA targets:

| Metric | Target | Test Class |
|--------|--------|------------|
| **Throughput** | >= 10,000 events/second | `PerformanceComparisonTest`, `LoadTest` |
| **Latency P50** | < 50ms | `LatencyBenchmarkTest` |
| **Latency P95** | < 200ms | `LatencyBenchmarkTest` |
| **Latency P99** | < 500ms | `LatencyBenchmarkTest` |
| **Error Rate** | < 0.01% | `ErrorHandlingTest`, `LoadTest` |
| **Recovery Time (RTO)** | < 1 minute | `ResilienceTest` |
| **Data Loss** | 0% | `ResilienceTest`, `FullPipelineTest` |

## Performance Baseline Results

*Note: Update these baselines after running performance tests*

| Metric | Flink SQL | Spring Boot | Target |
|--------|----------|-------------|--------|
| Throughput | TBD events/sec | TBD events/sec | >= 10,000 |
| Latency P50 | TBD ms | TBD ms | < 50ms |
| Latency P95 | TBD ms | TBD ms | < 200ms |
| Latency P99 | TBD ms | TBD ms | < 500ms |

## Test Utilities

### KafkaTestUtils

Utility class for Kafka operations:

- `publishTestEvent(topic, event)`: Publish event to Kafka
- `publishTestEvents(topic, events)`: Publish multiple events
- `consumeEvents(topic, count, timeout)`: Consume events from topic
- `consumeAllEvents(topic, maxCount, timeout)`: Consume all available events
- `waitForTopic(topic, timeout)`: Wait for topic to be available
- `getTopicMessageCount(topic, timeout)`: Get message count

### ComparisonUtils

Utility class for comparing events:

- `compareEventStructures(event1, event2)`: Compare two events
- `compareEventBatches(batch1, batch2)`: Compare event batches
- `assertEventParity(flinkEvents, springEvents)`: Assert events are identical

### TestEventGenerator

Generator for test events:

- `generateCarCreatedEvent(id)`: Generate CarCreated event
- `generateLoanCreatedEvent(id)`: Generate LoanCreated event
- `generateLoanPaymentEvent(id)`: Generate LoanPaymentSubmitted event
- `generateServiceEvent(id)`: Generate CarServiceDone event
- `generateMixedEventBatch(count)`: Generate batch of mixed events
- `generateEventBatch(eventType, count)`: Generate batch of specific type

## Cleanup

After running tests:

```bash
./scripts/cleanup-test-environment.sh
```

Or manually:

```bash
docker-compose -f docker-compose.test.yml down
```

## Troubleshooting

### Tests Fail with Connection Errors

- Verify Confluent Cloud credentials are correct
- Check that Kafka cluster is accessible
- Ensure topics exist in Confluent Cloud
- Verify network connectivity to Confluent Cloud

### Tests Timeout

- Increase timeout values in test configuration
- Check that Flink SQL statements are running
- Verify Spring Boot service is healthy
- Check Kafka consumer lag: events may be queued

### No Events Consumed

- Verify topics exist and have messages
- Check consumer group configuration
- Ensure stream processors are running
- Verify event filtering logic matches expected event types
- Check consumer group offsets: may need to reset to `earliest`

### Performance Tests Fail SLA

- Check Kafka cluster capacity (CKU level)
- Verify network latency to Confluent Cloud
- Review Flink compute resources (CFU)
- Check Spring Boot service resources (CPU/memory)
- Consider increasing partitions for better parallelism

### Metrics Tests Fail

- Verify Spring Boot Actuator is enabled
- Check `application.yml` for metrics configuration
- Ensure Prometheus endpoint is accessible: `curl http://localhost:8080/actuator/prometheus`
- Verify custom metrics are implemented in Spring Boot service

For more detailed troubleshooting, see [TESTING.md](../TESTING.md) and [TEST_RUNBOOK.md](../docs/TEST_RUNBOOK.md).

## Continuous Integration

These tests should be run:

- On every pull request
- Before merging to main
- As part of nightly builds
- Before production deployments

## Related Documentation

- [TESTING.md](../TESTING.md): Comprehensive test documentation
- [Performance Testing Guide](docs/PERFORMANCE_TESTING.md): Performance test methodology
- [Resilience Testing Guide](docs/RESILIENCE_TESTING.md): Recovery and chaos testing
- [Test Data Guide](docs/TEST_DATA.md): Test event structures and generation
- [Test Runbook](../docs/TEST_RUNBOOK.md): Test execution procedures

## Notes

- Tests use real Confluent Cloud Kafka (not embedded)
- Spring Boot service runs in Docker Compose
- Flink SQL statements must be deployed separately
- Tests may take several minutes to complete due to real Kafka operations
- Performance tests may take 30-60 minutes depending on configuration
- Load tests and endurance tests may take 1+ hour
