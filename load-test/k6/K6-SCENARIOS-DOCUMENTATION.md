# k6 Test Scenarios and Configurations Documentation

This document provides comprehensive documentation of all k6 test scenarios, configurations, and test modes used in the API performance testing framework.

## Table of Contents

1. [Overview](#overview)
2. [Test Scripts](#test-scripts)
3. [Test Modes](#test-modes)
4. [Test Phases (Stages)](#test-phases-stages)
5. [API Configurations](#api-configurations)
6. [Test Execution Flow](#test-execution-flow)
7. [Metrics and Thresholds](#metrics-and-thresholds)
8. [Event Payload Generation](#event-payload-generation)

## Overview

The k6 testing framework uses **stages** (not scenarios) to define load patterns. Each test mode has different stages that gradually increase the number of virtual users (VUs) to measure throughput, latency, and system behavior under increasing load.

**Key Components:**
- **2 Test Scripts**: REST API and gRPC API test scripts
- **3 Test Modes**: Smoke, Full, and Saturation
- **6 API Implementations**: Java REST, Java gRPC, Rust REST, Rust gRPC, Go REST, Go gRPC

## Test Scripts

### 1. REST API Test (`rest-api-test.js`)

**Purpose**: Tests REST API endpoints for all REST-based producer APIs.

**Target APIs:**
- `producer-api-java-rest` (Spring Boot REST)
- `producer-api-rust-rest` (Rust REST)
- `producer-api-go-rest` (Go REST)

**Test Flow:**
1. Generates a random event payload using `generateEventPayload()`
2. Sends HTTP POST request to `/api/v1/events`
3. Validates response:
   - Status code is 200
   - Response time < 5 seconds
4. Records custom error rate metric
5. Sleeps 0.1 seconds between requests

**Configuration:**
- **Protocol**: HTTP
- **Method**: POST
- **Content-Type**: `application/json`
- **Endpoint**: `/api/v1/events`

**Metrics Collected:**
- `http_reqs`: Total HTTP requests
- `http_req_duration`: Response time metrics (avg, min, max, p95, p99)
- `http_req_failed`: Error rate
- `errors`: Custom error rate metric

**Thresholds:**
- `http_req_duration`: p(95) < 2000ms, p(99) < 5000ms
- `http_req_failed`: rate < 0.05 (5% error rate)

### 2. gRPC API Test (`grpc-api-test.js`)

**Purpose**: Tests gRPC API endpoints for all gRPC-based producer APIs.

**Target APIs:**
- `producer-api-java-grpc` (Java gRPC)
- `producer-api-rust-grpc` (Rust gRPC)
- `producer-api-go-grpc` (Go gRPC)

**Test Flow:**
1. Loads protocol buffer definition file
2. Connects to gRPC server (connection reused across iterations)
3. Generates a gRPC event payload using `generateGrpcEventPayload()`
4. Invokes `ProcessEvent` method on `com.example.grpc.EventService`
5. Validates response:
   - Status is OK
   - Response has success field
6. Records custom error rate metric
7. Sleeps 0.1 seconds between requests
8. Closes connection in teardown

**Configuration:**
- **Protocol**: gRPC (plaintext, no TLS)
- **Service**: `com.example.grpc.EventService`
- **Method**: `ProcessEvent`
- **Proto Files**:
  - Java: `/k6/proto/java-grpc/event_service.proto`
  - Rust: `/k6/proto/rust-grpc/event_service.proto`
  - Go: `/k6/proto/go-grpc/event_service.proto`

**Metrics Collected:**
- `grpc_reqs`: Total gRPC requests
- `grpc_req_duration`: Response time metrics (avg, min, max, p95, p99)
- `grpc_req_failed`: Error rate
- `errors`: Custom error rate metric

**Thresholds:**
- `grpc_req_duration`: p(95) < 2000ms, p(99) < 5000ms

## Test Modes

The framework supports three test modes, each with different load patterns and durations.

### 1. Smoke Test Mode

**Purpose**: Quick validation to ensure APIs are functioning correctly before running full tests.

**Configuration:**
- **VUs**: 1 virtual user
- **Iterations**: 5 iterations total
- **Duration**: ~5-10 seconds
- **Use Case**: Pre-flight checks, CI/CD validation

**Execution:**
- Runs automatically before full or saturation tests
- Must pass (error rate < 5%) before proceeding to full tests
- Validates basic functionality and connectivity

**When to Use:**
- Quick validation after code changes
- Pre-check before running expensive full tests
- CI/CD pipeline integration

### 2. Full Test Mode

**Purpose**: Standard throughput test to identify optimal parallelism and breaking points.

**Configuration:**
- **Phases**: 4 stages with increasing load
- **Total Duration**: ~11 minutes per API
- **Load Pattern**: Gradual ramp-up

**Stages:**
1. **Phase 1 - Baseline**: 2 minutes at 10 VUs
2. **Phase 2 - Mid-load**: 2 minutes at 50 VUs
3. **Phase 3 - High-load**: 2 minutes at 100 VUs
4. **Phase 4 - Higher-load**: 5 minutes at 200 VUs

**Use Case:**
- Standard performance testing
- Identifying optimal concurrency levels
- Finding initial breaking points
- Production capacity planning

**When to Use:**
- Regular performance regression testing
- Comparing API implementations
- Capacity planning for production workloads

### 3. Saturation Test Mode

**Purpose**: Stress test to find absolute maximum throughput and true breaking points.

**Configuration:**
- **Phases**: 7 stages with aggressive load increase
- **Total Duration**: ~14 minutes per API
- **Load Pattern**: Aggressive ramp-up to saturation

**Stages:**
1. **Phase 1 - Baseline**: 2 minutes at 10 VUs
2. **Phase 2 - Mid-load**: 2 minutes at 50 VUs
3. **Phase 3 - High-load**: 2 minutes at 100 VUs
4. **Phase 4 - Very High**: 2 minutes at 200 VUs
5. **Phase 5 - Extreme**: 2 minutes at 500 VUs
6. **Phase 6 - Maximum**: 2 minutes at 1000 VUs
7. **Phase 7 - Saturation**: 2 minutes at 2000 VUs

**Use Case:**
- Finding absolute maximum throughput
- Identifying true breaking points
- Stress testing under extreme load
- Understanding system limits

**When to Use:**
- Deep performance analysis
- Finding system limits
- Stress testing before major releases
- Understanding behavior at scale

## Test Phases (Stages)

k6 uses **stages** (not scenarios) to define load patterns. Stages define how the number of virtual users changes over time.

### Stage Configuration

Stages are defined in `config.js` under `TEST_PHASES`:

```javascript
export const TEST_PHASES = {
    full: [
        { duration: '2m', target: 10 },   // Phase 1: Baseline
        { duration: '2m', target: 50 },   // Phase 2: Mid-load
        { duration: '2m', target: 100 },  // Phase 3: High-load
        { duration: '5m', target: 200 },  // Phase 4: Higher-load
    ],
    saturation: [
        { duration: '2m', target: 10 },    // Phase 1: Baseline
        { duration: '2m', target: 50 },    // Phase 2: Mid-load
        { duration: '2m', target: 100 },   // Phase 3: High-load
        { duration: '2m', target: 200 },   // Phase 4: Very High
        { duration: '2m', target: 500 },   // Phase 5: Extreme
        { duration: '2m', target: 1000 },  // Phase 6: Maximum
        { duration: '2m', target: 2000 },  // Phase 7: Saturation
    ],
};
```

### Stage Behavior

- **Duration**: How long the stage runs (e.g., '2m' = 2 minutes)
- **Target**: Target number of virtual users (VUs) for that stage
- **Ramp-up**: k6 automatically ramps up/down VUs to reach the target
- **Gradual**: VUs are added/removed gradually, not instantly

### Phase-by-Phase Analysis

Each phase provides insights:

1. **Baseline (10 VUs)**: Establishes baseline performance
2. **Mid-load (50 VUs)**: Tests moderate concurrency
3. **High-load (100 VUs)**: Tests high concurrency
4. **Higher-load (200 VUs)**: Tests very high concurrency (full mode: 5 minutes, saturation mode: 2 minutes)
5. **Extreme (500 VUs)**: Tests extreme concurrency (saturation only)
6. **Maximum (1000 VUs)**: Tests maximum concurrency (saturation only)
7. **Saturation (2000 VUs)**: Tests saturation point (saturation only)

## API Configurations

Each API has specific configuration for host, port, protocol, and endpoints.

### REST API Configurations

| API | Host | Port | Path | Protocol |
|-----|------|------|------|----------|
| producer-api-java-rest | producer-api-java-rest | 8081 | /api/v1/events | HTTP |
| producer-api-rust-rest | producer-api-rust-rest | 8081 | /api/v1/events | HTTP |
| producer-api-go-rest | producer-api-go-rest | 9083 | /api/v1/events | HTTP |

### gRPC API Configurations

| API | Host | Port | Service | Method | Proto File |
|-----|------|------|---------|--------|------------|
| producer-api-java-grpc | producer-api-java-grpc | 9090 | com.example.grpc.EventService | ProcessEvent | /k6/proto/java-grpc/event_service.proto |
| producer-api-rust-grpc | producer-api-rust-grpc | 9090 | com.example.grpc.EventService | ProcessEvent | /k6/proto/rust-grpc/event_service.proto |
| producer-api-go-grpc | producer-api-go-grpc | 9092 | com.example.grpc.EventService | ProcessEvent | /k6/proto/go-grpc/event_service.proto |

**Note**: Host names are Docker service names, accessible within the Docker network.

## Test Execution Flow

### Sequential Test Execution

Tests run **sequentially** (one API at a time) to ensure fair comparison:

1. **Stop all APIs**: Ensures no resource competition
2. **Clear database**: Fresh state for each test
3. **Start target API**: Start only the API being tested
4. **Health check**: Verify API is healthy and ready
5. **Wait for event processing**: Verify API can process events
6. **Run k6 test**: Execute the appropriate test script
7. **Collect metrics**: Save results to JSON files
8. **Stop API**: Clean up before next test
9. **Repeat**: Move to next API

### Test Script Selection

The test runner automatically selects the correct script based on protocol:

- **REST APIs** → `rest-api-test.js`
- **gRPC APIs** → `grpc-api-test.js`

### Environment Variables

Tests are configured via environment variables:

- `TEST_MODE`: `smoke`, `full`, or `saturation`
- `PROTOCOL`: `http` or `grpc`
- `HOST`: API hostname (Docker service name)
- `PORT`: API port
- `PATH`: REST API path (for REST tests)
- `PROTO_FILE`: Proto file path (for gRPC tests)
- `SERVICE`: gRPC service name (for gRPC tests)
- `METHOD`: gRPC method name (for gRPC tests)

## Metrics and Thresholds

### HTTP Metrics (REST APIs)

| Metric | Description | Thresholds |
|--------|-------------|------------|
| `http_reqs` | Total HTTP requests | None |
| `http_req_duration` | Response time | p(95) < 2000ms, p(99) < 5000ms |
| `http_req_failed` | Error rate | rate < 0.05 (5%) |
| `errors` | Custom error rate | None |

### gRPC Metrics (gRPC APIs)

| Metric | Description | Thresholds |
|--------|-------------|------------|
| `grpc_reqs` | Total gRPC requests | None |
| `grpc_req_duration` | Response time | p(95) < 2000ms, p(99) < 5000ms |
| `grpc_req_failed` | Error rate | None (monitored but no threshold) |
| `errors` | Custom error rate | None |

### Resource Utilization Metrics

Resource utilization metrics (CPU and memory) are automatically collected during **full** and **saturation** tests. These metrics provide insights into how efficiently each API uses system resources.

#### Collection Details

- **Collection Method**: Docker stats API (sampled every 5 seconds)
- **Metrics Collected**:
  - CPU usage percentage
  - Memory usage percentage
  - Memory used (MB)
  - Memory limit (MB)
- **Storage**: CSV files saved alongside k6 JSON results
- **File Format**: `{api-name}-{test-mode}-{timestamp}-metrics.csv`

#### Metrics Analyzed

**Overall Metrics:**
- Average CPU %
- Peak CPU %
- Average memory %
- Peak memory %
- Average memory used (MB)
- Peak memory used (MB)

**Per-Phase Metrics:**
- Average CPU % per phase
- Peak CPU % per phase
- Average memory (MB) per phase
- Peak memory (MB) per phase
- Number of requests per phase

**Derived Metrics:**
- **CPU % per Request**: `(avg CPU % × phase duration) / total requests in phase`
  - Lower is better - indicates CPU efficiency
  - Normalizes CPU usage by throughput
  - Measured in CPU percentage-seconds per request

- **RAM MB per Request**: `(avg memory MB × phase duration) / total requests in phase`
  - Lower is better - indicates memory efficiency
  - Normalizes memory usage by throughput
  - Measured in MB-seconds per request

#### Phase Mapping

Resource samples are automatically mapped to test phases based on timestamps:
- Phase boundaries are calculated from test start time and phase durations
- Each resource sample is assigned to the appropriate phase
- Phase transitions (ramp-up periods) are handled automatically

#### Report Integration

Resource utilization metrics are included in:
- **Markdown Reports**: Tables showing overall and per-phase resource usage
- **HTML Reports**: Interactive charts using Chart.js:
  - Per-phase CPU usage comparison (bar chart)
  - Per-phase memory usage comparison (bar chart)
  - CPU % per request comparison (bar chart)
  - RAM MB per request comparison (bar chart)

#### Interpreting Resource Charts

**CPU Usage Charts:**
- Shows how CPU usage scales with load (VU count)
- Higher CPU usage at higher VUs is expected
- Compare APIs to identify which is more CPU-efficient

**Memory Usage Charts:**
- Shows memory consumption patterns across phases
- Look for memory leaks (gradual increase over time)
- Compare peak memory usage across APIs

**Derived Metrics Charts:**
- **CPU % per Request**: Lower values indicate better CPU efficiency
  - Useful for comparing resource efficiency independent of throughput
  - Helps identify which API processes requests most efficiently

- **RAM MB per Request**: Lower values indicate better memory efficiency
  - Useful for comparing memory efficiency independent of throughput
  - Helps identify which API uses memory most efficiently

#### Example Use Cases

1. **Capacity Planning**: Use peak CPU/memory to estimate resource requirements
2. **Efficiency Comparison**: Use derived metrics to compare resource efficiency
3. **Bottleneck Identification**: High CPU with low throughput may indicate CPU bottleneck
4. **Memory Leak Detection**: Gradual memory increase across phases may indicate leaks

### Response Time Percentiles

- **p(95)**: 95th percentile - 95% of requests complete within this time
- **p(99)**: 99th percentile - 99% of requests complete within this time

### Threshold Behavior

- Thresholds are **validated** during test execution
- If thresholds are exceeded, k6 marks the test as failed
- Thresholds help identify performance regressions

## Event Payload Generation

Both test scripts generate realistic event payloads using helper functions.

### Event Types

Four event types are randomly selected:

1. **CarCreated**: Car entity creation event
2. **LoanCreated**: Loan entity creation event
3. **LoanPaymentSubmitted**: Loan payment submission event
4. **ServiceDone**: Service completion event

### REST Event Payload Structure

```json
{
  "eventHeader": {
    "uuid": "generated-uuid",
    "eventName": "CarCreated",
    "createdDate": "2024-01-01T00:00:00.000Z",
    "savedDate": "2024-01-01T00:00:00.000Z",
    "eventType": "CarCreated"
  },
  "eventBody": {
    "entities": [{
      "entityType": "Car",
      "entityId": "car-xxxxx-timestamp",
      "updatedAttributes": {
        "id": "car-xxxxx-timestamp",
        "timestamp": "2024-01-01T00:00:00.000Z",
        "model": "Model-xxxxxx",
        "year": 2024
      }
    }]
  }
}
```

### gRPC Event Payload Structure

```json
{
  "event_header": {
    "uuid": "generated-uuid",
    "event_name": "CarCreated",
    "created_date": "2024-01-01T00:00:00.000Z",
    "saved_date": "2024-01-01T00:00:00.000Z",
    "event_type": "CarCreated"
  },
  "event_body": {
    "entities": [{
      "entity_type": "Car",
      "entity_id": "car-xxxxx-timestamp",
      "updated_attributes": {
        "id": "car-xxxxx-timestamp",
        "timestamp": "2024-01-01T00:00:00.000Z",
        "model": "Model-xxxxxx",
        "year": "2024"
      }
    }]
  }
}
```

### Entity-Specific Attributes

**Car Events:**
- `model`: Random model name
- `year`: Random year (2010-2024)

**Loan/LoanPayment Events:**
- `balance`: Random balance (1000-51000)
- `lastPaidDate`: Timestamp
- `paymentAmount`: Random amount (100-2100) - LoanPayment only

**Service Events:**
- `serviceCost`: Random cost (50-550)

## Summary

### Test Scripts Summary

| Script | Protocol | APIs Tested | Duration (Full) | Duration (Saturation) |
|--------|----------|-------------|-----------------|----------------------|
| rest-api-test.js | HTTP | 3 REST APIs | ~11 min | ~14 min |
| grpc-api-test.js | gRPC | 3 gRPC APIs | ~11 min | ~14 min |

### Test Modes Summary

| Mode | VUs | Duration | Use Case |
|------|-----|----------|----------|
| Smoke | 1 | ~5-10s | Quick validation |
| Full | 10→50→100→200 | ~11 min | Standard testing |
| Saturation | 10→50→100→200→500→1000→2000 | ~14 min | Stress testing |

### Key Features

- ✅ **Sequential execution**: Fair comparison without resource competition
- ✅ **Automatic smoke tests**: Pre-flight validation before full tests
- ✅ **Multiple test modes**: Smoke, Full, and Saturation
- ✅ **Gradual load increase**: Stages ramp up VUs gradually
- ✅ **Comprehensive metrics**: Request counts, response times, error rates
- ✅ **Resource utilization tracking**: CPU and memory metrics per phase (full/saturation tests)
- ✅ **Derived efficiency metrics**: CPU % per request, RAM MB per request
- ✅ **Interactive charts**: Visual resource utilization analysis in HTML reports
- ✅ **Realistic payloads**: Random event generation with entity-specific attributes
- ✅ **Protocol support**: Both REST (HTTP) and gRPC
- ✅ **Threshold validation**: Automatic performance regression detection

## Running Tests

See the main [README.md](../README.md) for instructions on running tests.

**Quick Start:**
```bash
cd load-test/shared

# Smoke test (quick validation)
./run-sequential-throughput-tests.sh smoke

# Full test (standard throughput)
./run-sequential-throughput-tests.sh full

# Saturation test (stress test)
./run-sequential-throughput-tests.sh saturation
```

## Customization

To customize test scenarios:

1. **Modify test phases**: Edit `config.js` → `TEST_PHASES`
2. **Change thresholds**: Edit `config.js` → `getTestOptions()`
3. **Modify test logic**: Edit `rest-api-test.js` or `grpc-api-test.js`
4. **Change payload generation**: Edit `shared/helpers.js`

## Additional Resources

- [k6 Documentation](https://k6.io/docs/)
- [k6 Stages Documentation](https://k6.io/docs/using-k6/k6-options/reference/#stages)
- [THROUGHPUT-TESTING-GUIDE.md](../THROUGHPUT-TESTING-GUIDE.md)
- [README.md](../README.md)

