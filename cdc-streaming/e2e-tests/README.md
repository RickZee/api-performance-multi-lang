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

# Error handling tests
./gradlew test --tests ErrorHandlingTest
```

### Run with Test Reports

```bash
./gradlew test --info
```

## Test Categories

### 1. Functional Parity Tests

Verifies both Flink and Spring Boot services produce identical output for the same input:

- `testCarCreatedEventRouting`: Verify CarCreated events route correctly
- `testLoanCreatedEventRouting`: Verify LoanCreated events route correctly
- `testLoanPaymentEventRouting`: Verify LoanPaymentSubmitted events route correctly
- `testServiceEventRouting`: Verify CarServiceDone events route correctly
- `testEventFilteringByOp`: Verify only `__op='c'` events are processed
- `testEventStructurePreservation`: Verify all fields are preserved
- `testMultipleEventTypesBatch`: Test batch processing with mixed event types
- `testNullAndInvalidEvents`: Verify invalid events are handled gracefully

### 2. Full Pipeline Tests

Tests complete flow from Producer API through CDC to filtered topics:

- `testEndToEndCarCreatedFlow`: Complete car creation flow
- `testEndToEndLoanCreatedFlow`: Complete loan creation flow
- `testEndToEndLoanPaymentFlow`: Complete loan payment flow
- `testEndToEndServiceFlow`: Complete service event flow
- `testBulkEventProcessing`: Process 100+ events
- `testEventOrdering`: Verify events maintain order
- `testEventIdempotency`: Verify duplicate event handling

### 3. Performance Comparison Tests

Compares performance characteristics:

- `testThroughputComparison`: Measure events/second
- `testLatencyComparison`: Measure end-to-end latency
- `testConcurrentEventProcessing`: Test with concurrent streams
- `testBackpressureHandling`: Test behavior under high load

### 4. Error Handling Tests

Verifies resilience:

- `testInvalidEventHandling`: Send malformed events
- `testEventWithMissingFields`: Test events with missing fields
- `testConsumerGroupOffsetManagement`: Verify offset management

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

### Tests Timeout

- Increase timeout values in test configuration
- Check that Flink SQL statements are running
- Verify Spring Boot service is healthy

### No Events Consumed

- Verify topics exist and have messages
- Check consumer group configuration
- Ensure stream processors are running

## Continuous Integration

These tests should be run:

- On every pull request
- Before merging to main
- As part of nightly builds
- Before production deployments

## Notes

- Tests use real Confluent Cloud Kafka (not embedded)
- Spring Boot service runs in Docker Compose
- Flink SQL statements must be deployed separately
- Tests may take several minutes to complete due to real Kafka operations

