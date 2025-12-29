# Integration Test Execution Guide

## ✅ Validation Complete

All integration tests have been validated:
- ✅ Test files present and correct
- ✅ Compilation successful
- ✅ Dependencies resolved
- ✅ Docker configuration valid
- ✅ Test event generators working

## Quick Start

### 1. Verify Prerequisites

```bash
cd cdc-streaming
./scripts/setup-jenkins-local.sh
```

### 2. Run Complete CI/CD Demo

```bash
./scripts/demo-ci-cd.sh
```

This will:
1. Check prerequisites
2. Start Docker infrastructure
3. Run all tests
4. Generate reports
5. Clean up

## Manual Execution

If you prefer step-by-step control:

### Step 1: Start Infrastructure

```bash
cd cdc-streaming

# Start Kafka, Schema Registry, Mock API
docker-compose -f docker-compose.integration-test.yml up -d kafka schema-registry mock-confluent-api

# Wait for Kafka (check every 2 seconds, max 60 seconds)
timeout 60 bash -c 'until docker exec int-test-kafka kafka-topics --bootstrap-server localhost:9092 --list &>/dev/null; do sleep 2; done'

# Initialize topics
docker-compose -f docker-compose.integration-test.yml up init-topics
```

### Step 2: Build and Start Services

```bash
# Build images
docker-compose -f docker-compose.integration-test.yml build metadata-service stream-processor

# Start services
docker-compose -f docker-compose.integration-test.yml up -d metadata-service stream-processor

# Wait for services to be healthy
timeout 60 bash -c 'until curl -sf http://localhost:8080/api/v1/health && curl -sf http://localhost:8083/actuator/health; do sleep 2; done'
```

### Step 3: Run Tests

```bash
cd e2e-tests

# Run all new integration tests
./gradlew test --tests "com.example.e2e.local.*" --tests "com.example.e2e.schema.*"

# Or run specific test classes
./gradlew test --tests "com.example.e2e.local.LocalKafkaIntegrationTest"
./gradlew test --tests "com.example.e2e.local.FilterLifecycleLocalTest"
./gradlew test --tests "com.example.e2e.local.StreamProcessorLocalTest"
./gradlew test --tests "com.example.e2e.schema.NonBreakingSchemaTest"
./gradlew test --tests "com.example.e2e.schema.BreakingSchemaChangeTest"
```

### Step 4: View Results

```bash
# Open HTML report
open build/reports/tests/test/index.html

# Or view in terminal
cat build/test-results/test/*.xml | grep -E "(testsuite|testcase)" | head -20
```

### Step 5: Cleanup

```bash
cd ..
docker-compose -f docker-compose.integration-test.yml down
docker-compose -f docker-compose.integration-test.yml --profile v2 down
```

## Test Classes Overview

### LocalKafkaIntegrationTest (5 tests)
- `testCarCreatedEventRouting` - Verifies CarCreated events route correctly
- `testLoanCreatedEventRouting` - Verifies LoanCreated events route correctly
- `testLoanPaymentEventRouting` - Verifies LoanPaymentSubmitted events route correctly
- `testServiceEventRouting` - Verifies CarServiceDone events route correctly
- `testMultipleEventTypesBatch` - Verifies batch processing of mixed event types

### FilterLifecycleLocalTest (4 tests)
- `testCreateFilter` - Creates filter via Metadata Service API
- `testListFilters` - Lists all filters
- `testGenerateSQL` - Generates Flink SQL from filter configuration
- `testHealthCheck` - Verifies Metadata Service health

### StreamProcessorLocalTest (4 tests)
- `testEventRoutingToCorrectTopic` - Verifies events route to correct topics
- `testNonMatchingEventsFiltered` - Verifies unmatched events are filtered out
- `testStreamProcessorHealth` - Verifies Stream Processor health endpoint
- `testHighThroughputProcessing` - Tests processing 100+ events

### NonBreakingSchemaTest (4 tests)
- `testAddOptionalFieldToEvent` - Tests backward compatible field addition
- `testNewEventTypeWithNewFilter` - Tests adding new event type
- `testWidenFieldTypeCompatibility` - Tests type widening compatibility
- `testBackwardCompatibleEventProcessing` - Tests old format still works

### BreakingSchemaChangeTest (3 tests)
- `testV2SystemDeploysInParallel` - Verifies V2 system deploys alongside V1
- `testV1V2Isolation` - Verifies V1 and V2 systems are isolated
- `testGradualMigrationFromV1ToV2` - Tests gradual migration scenario

**Total: 20 tests**

## Troubleshooting Commands

### Check Service Status

```bash
# List running containers
docker ps --filter "name=int-test-"

# Check service health
curl http://localhost:8080/api/v1/health
curl http://localhost:8083/actuator/health

# Check Kafka topics
docker exec int-test-kafka kafka-topics --bootstrap-server localhost:9092 --list
```

### View Logs

```bash
# Kafka logs
docker-compose -f docker-compose.integration-test.yml logs kafka

# Metadata Service logs
docker-compose -f docker-compose.integration-test.yml logs metadata-service

# Stream Processor logs
docker-compose -f docker-compose.integration-test.yml logs stream-processor

# All logs
docker-compose -f docker-compose.integration-test.yml logs
```

### Debug Test Issues

```bash
# Run troubleshooting script
./scripts/troubleshoot-tests.sh

# Validate test structure
./scripts/validate-tests.sh

# Check test compilation
cd e2e-tests
./gradlew compileTestJava --no-daemon --info
```

## Expected Behavior

### Successful Test Run

1. **Infrastructure starts** - Kafka, Schema Registry, Mock API running
2. **Topics created** - All required topics exist
3. **Services start** - Metadata Service and Stream Processor healthy
4. **Tests execute** - All 20 tests run
5. **Events flow** - Events published → filtered → consumed
6. **Reports generated** - HTML and JUnit XML reports created

### Test Execution Flow

```
Test → Publish Event → raw-event-headers → Stream Processor → 
Filtered Topic → Consume Event → Assert
```

## Common Issues and Solutions

### Issue: "Connection refused" errors

**Cause**: Services not started or not healthy

**Solution**:
```bash
# Check services
docker ps | grep int-test-

# Restart services
docker-compose -f docker-compose.integration-test.yml restart

# Check logs for errors
docker-compose -f docker-compose.integration-test.yml logs
```

### Issue: "Topic not found" errors

**Cause**: Topics not initialized

**Solution**:
```bash
docker-compose -f docker-compose.integration-test.yml up init-topics
```

### Issue: Tests timeout

**Cause**: Services not processing events fast enough

**Solution**:
1. Verify services are healthy
2. Check stream processor logs for errors
3. Increase timeout in test if needed
4. Verify Kafka has messages: `docker exec int-test-kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic raw-event-headers --from-beginning --max-messages 5`

### Issue: No events consumed

**Cause**: Stream processor not filtering/routing correctly

**Solution**:
1. Check stream processor logs
2. Verify filter configuration is loaded
3. Check if events match filter conditions
4. Verify topics exist and have partitions

## Performance Expectations

- **Event Processing**: < 1 second per event
- **Batch Processing**: 100 events in < 10 seconds
- **Service Startup**: < 30 seconds
- **Test Execution**: < 5 minutes for all tests

## Next Steps After Tests Pass

1. Review test reports
2. Check test coverage
3. Run performance benchmarks
4. Deploy to staging environment
5. Set up Jenkins pipeline

