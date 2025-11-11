# Throughput and Parallelism Testing Guide

## Overview

This guide explains how to use the k6 throughput tests to determine the maximum sustainable throughput and optimal parallelism level for each producer API implementation.

## Test Methodology

### Test Strategy

The throughput tests use a **simplified ramp-up strategy** to gradually increase load and identify:

- **Maximum Throughput**: Highest sustainable requests per second
- **Optimal Parallelism**: Virtual user count where throughput peaks
- **Breaking Point**: Virtual user count where performance degrades significantly

### Test Phases

Each test includes multiple phases with increasing virtual user (VU) counts:

**Smoke Test**:
- 10 VUs, 30 seconds (quick validation)

**Full Test** (4 phases):
1. **Phase 1: Baseline** (10 VUs, 2 minutes)
   - Establishes baseline performance
   - Verifies system is healthy

2. **Phase 2: Mid-load** (50 VUs, 2 minutes)
   - Tests moderate load handling
   - Identifies performance characteristics

3. **Phase 3: High-load** (100 VUs, 2 minutes)
   - Tests high load capacity
   - Identifies breaking points

4. **Phase 4: Higher-load** (200 VUs, 5 minutes)
   - Tests very high load capacity
   - Extended duration for sustained performance analysis

**Saturation Test** (7 phases - finds absolute maximum throughput):
1. **Phase 1: Baseline** (10 VUs, 2 minutes)
2. **Phase 2: Mid-load** (50 VUs, 2 minutes)
3. **Phase 3: High-load** (100 VUs, 2 minutes)
4. **Phase 4: Very High** (200 VUs, 2 minutes)
5. **Phase 5: Extreme** (500 VUs, 2 minutes)
6. **Phase 6: Maximum** (1000 VUs, 2 minutes)
7. **Phase 7: Saturation** (2000 VUs, 2 minutes)

Each phase runs for a fixed duration to measure sustained performance at that parallelism level.

### Test Duration

- **Smoke Test**: ~30 seconds per API
- **Full Test**: ~11 minutes per API
- **Saturation Test**: ~14 minutes per API
- **Total Test Time**: 
  - ~44 minutes for all 4 APIs (full tests)
  - ~56 minutes for all 4 APIs (saturation tests)

## Producer API Implementations

The tests cover all 4 producer API implementations:

1. **producer-api-java-rest** - Spring Boot REST (port 9081)
2. **producer-api-java-grpc** - Java gRPC (port 9090)
3. **producer-api-rust-rest** - Rust REST (port 9082)
4. **producer-api-rust-grpc** - Rust gRPC (port 9091)

## Running the Tests

### Prerequisites

1. Docker and Docker Compose must be installed and running
2. All producer APIs must be available (either running or will be started by the test script)
3. PostgreSQL database must be accessible (will be started automatically for sequential tests)

**Note**: k6 is executed in Docker containers - no local k6 installation required!

### Smoke Tests (Automatic Pre-flight Check)

When running full or saturation tests, smoke tests are **automatically executed first** to verify basic functionality:

- Smoke tests run with 10 VUs for 30 seconds
- Validates error rate < 5% and success rate > 95%
- If smoke tests fail, full or saturation tests are aborted

### Running All Tests

#### Sequential Tests (Recommended - One API at a Time)

The sequential test runner manages Docker containers automatically:

**Full Tests:**
```bash
cd load-test/shared
./run-sequential-throughput-tests.sh full
```

**Saturation Tests (Find Maximum Throughput):**
```bash
cd load-test/shared
./run-sequential-throughput-tests.sh saturation
```

This will:

1. **Automatically run smoke tests first** for all APIs
2. If smoke tests pass, run throughput tests sequentially
3. Clear database between each API test for fair comparison
4. Run tests one API at a time in Docker
5. Execute k6 in Docker containers
6. Generate JSON result files and summary reports
7. Save results to `load-test/results/throughput-sequential/<api_name>/`

#### Smoke Tests Only

To run only smoke tests:

```bash
cd load-test/shared
./run-sequential-throughput-tests.sh smoke
```


## Test Results

### Result Files

Each test run generates:

1. **JSON Results** (`<api-name>-throughput-<timestamp>.json`)
   - Complete k6 metrics in JSON format
   - Includes all performance metrics, timestamps, and metadata

2. **Summary Report** (`<api-name>-throughput-<timestamp>.txt`)
   - Human-readable summary of test execution
   - Includes key metrics and status

3. **Comparison Report** (`comparison-report-<timestamp>.md`)
   - Markdown report comparing all APIs
   - Includes summary table and detailed metrics

### Key Metrics

The tests measure:

- **Throughput**: Requests per second (req/s)
- **Response Time**: Average, min, max, p95, p99 latencies
- **Error Rate**: Percentage of failed requests
- **Virtual Users**: Number of concurrent users simulated
- **Test Duration**: Total test execution time

### Result Locations

- **Sequential Tests**: `load-test/results/throughput-sequential/<api_name>/`
- **Comparison Reports**: `load-test/results/throughput-sequential/comparison-report-*.md`

## Understanding Results

### Test Type Selection

- **Smoke Test**: Use for quick validation that APIs are working correctly
- **Full Test**: Use to identify optimal parallelism and general performance characteristics (up to 100 VUs)
- **Saturation Test**: Use to find the absolute maximum throughput and identify true breaking points (up to 2000 VUs)

### Throughput Analysis

- **Higher is better**: More requests per second indicates better performance
- **Consistency**: Stable throughput across phases indicates good scalability
- **Degradation**: Decreasing throughput with higher VUs may indicate bottlenecks
- **Saturation Point**: In saturation tests, look for the phase where throughput plateaus or error rates spike (> 10%) - this indicates maximum capacity

### Response Time Analysis

- **Lower is better**: Faster response times indicate better performance
- **Percentiles**: p95 and p99 show tail latency (important for user experience)
- **Spikes**: Sudden increases may indicate resource exhaustion

### Error Rate Analysis

- **Target**: < 5% error rate is acceptable
- **Zero errors**: Ideal, but may not be realistic under high load
- **Increasing errors**: May indicate system limits or configuration issues

## k6 Test Scripts

### Test Script Structure

The k6 test scripts are located in `load-test/k6/`:

- **`rest-api-test.js`**: REST API test script (used for producer-api-java-rest, producer-api-rust-rest, and producer-api-go-rest)
- **`grpc-api-test.js`**: gRPC API test script (used for producer-api-java-grpc, producer-api-rust-grpc, and producer-api-go-grpc)
- **`shared/helpers.js`**: Shared utilities for event generation
- **`config.js`**: Centralized test configuration

### Configuration

Test configuration is managed through:

1. **Environment Variables**: Set by the test runner script
   - `TEST_MODE`: `smoke`, `full`, or `saturation`
   - `HOST`: API hostname (Docker service name)
   - `PORT`: API port
   - `PROTO_FILE`: Proto file path (gRPC only)
   - `SERVICE`: gRPC service name (gRPC only)
   - `METHOD`: gRPC method name (gRPC only)

2. **config.js**: Test phases and thresholds
   - Smoke test: 10 VUs, 30 seconds
   - Full test: 4 phases (10 → 50 → 100 → 200 VUs)
   - Saturation test: 7 phases (10 → 50 → 100 → 200 → 500 → 1000 → 2000 VUs)

### Customization

To modify test parameters:

1. Edit `load-test/k6/config.js` to change phases or thresholds
2. Edit test scripts in `load-test/k6/` to modify test logic
3. Rebuild the k6 Docker container if needed

## Troubleshooting

### Common Issues

1. **Container Build Failures**
   - Ensure Docker is running
   - Check Docker Compose version compatibility
   - Review container logs: `docker-compose logs k6-throughput`

2. **Test Failures**
   - Check API health: Ensure APIs are running and healthy
   - Review API logs: `docker-compose logs <api-name>`
   - Check database connectivity
   - Verify network connectivity between containers

3. **High Error Rates**
   - Check API resource limits (CPU, memory)
   - Review database performance
   - Check for network issues
   - Verify API configuration

4. **Low Throughput**
   - Check system resources (CPU, memory, network)
   - Review database performance
   - Check for bottlenecks in API code
   - Verify test configuration

### Debugging

To debug test execution:

1. **View k6 Container Logs**:
   ```bash
   docker-compose logs k6-throughput
   ```

2. **Run Tests Manually**:
   ```bash
   docker-compose --profile k6-test run --rm k6-throughput \
     k6 run /k6/scripts/rest-api-test.js \
     -e TEST_MODE=smoke \
     -e HOST=producer-api-java-rest \
     -e PORT=8081
   ```

3. **Check API Logs**:
   ```bash
   docker-compose logs -f producer-api
   ```

## Best Practices

1. **Always Run Smoke Tests First**: Verify basic functionality before full tests
2. **Run Sequential Tests for Comparison**: Ensures fair comparison without resource competition
3. **Clear Database Between Tests**: Ensures consistent starting conditions
4. **Monitor System Resources**: Watch CPU, memory, and network during tests
5. **Review Error Logs**: Investigate any errors or warnings
6. **Compare Multiple Runs**: Run tests multiple times to identify patterns

## Next Steps

After running throughput tests:

1. Review the comparison report to identify the best-performing API
2. Analyze detailed metrics to understand performance characteristics
3. Investigate any anomalies or unexpected results
4. Optimize APIs based on findings
5. Re-run tests to validate improvements

## Results as of Nov 10 21:11

Results summary
API	Throughput (req/s)	Avg Response Time (ms)	Total Requests	Error Rate
producer-api-rust-rest (Rust REST)	2,901.10	38.94	2,355,297	0.00%
producer-api-java-rest (Spring Boot REST)	2,665.79	53.52	2,162,547	0.00%
producer-api-rust-grpc (Rust gRPC)	133.18	5.94	28,231	0.00%
producer-api-java-grpc (Java gRPC)	78.11	4.76	28,231	0.00%
Findings
Highest throughput: producer-api-rust-rest (Rust REST) — 2,901 req/s
Lowest latency: producer-api-java-grpc (Java gRPC) — 4.76ms avg
Best balance: producer-api-rust-rest (Rust REST) — highest throughput (2,901 req/s) and low latency (38.94ms)
gRPC APIs: Hit connection limits earlier (connection errors at high load), resulting in lower total requests but very low latency
Notes
gRPC APIs hit system connection limits under extreme load (2000 VUs), causing "cannot assign requested address" errors
REST APIs handled the full saturation test better
All APIs maintained 0% error rate until hitting system limits


Analysis: Why Different Total Requests Between REST and gRPC APIs
Findings
Test durations:
REST APIs: ~13.5 minutes (full test completed)
producer-api-java-rest: 811.22 seconds
producer-api-rust-rest: 811.86 seconds
gRPC APIs: shorter (test stopped early)
producer-api-java-grpc: 361.45 seconds (6 minutes)
producer-api-rust-grpc: 211.98 seconds (3.5 minutes)
Total requests:
REST: ~2.1–2.3 million requests each
gRPC: ~28,000 requests each
Root cause: connection exhaustion
1. Connection model differences:
REST (HTTP/1.1): Stateless requests; connections are pooled and shorter-lived
gRPC (HTTP/2): Persistent connections per client; each VU maintains a long-lived connection
2. Connection limit exhaustion:
At high VU counts (500–2000), gRPC attempts to create many persistent connections
The system runs out of available TCP ports/connections
Errors observed: "cannot assign requested address"
Once limits are hit, new connections fail and the test effectively stops
3. Why gRPC stopped early:
The saturation test targets 2000 VUs
gRPC hit connection limits around phases 4–5 (200–500 VUs)
The test couldn't proceed, so it ended early
REST handled the full duration because HTTP connections are more efficiently pooled/reused
Evidence
From the code (grpc-api-test.js line 68-76):
// Connect to gRPC server (connection is reused across iterations)if (!client.connected) {    client.connect(`${apiHost}:${apiPort}`, {        plaintext: true,    });}
Each VU maintains a persistent gRPC connection. With 2000 VUs, that's 2000 persistent connections, which can exhaust system limits.
Implications
gRPC shows lower latency (4.76–5.94ms vs 38.94–53.52ms) but hits connection limits earlier
REST scales better to very high VU counts due to more efficient connection handling
The throughput difference (2,900 req/s vs 78–133 req/s) reflects the early termination of gRPC tests
Recommendations
Increase system connection limits (ulimit, sysctl)
Use connection pooling/multiplexing for gRPC
Reduce max VUs for gRPC tests to stay within limits
Compare at equivalent connection counts, not just VU counts
The results show REST APIs completed the full saturation test, while gRPC APIs hit system connection limits and stopped early, explaining the large difference in total requests.