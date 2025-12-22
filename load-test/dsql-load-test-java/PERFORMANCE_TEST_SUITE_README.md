# DSQL Performance Test Suite

## Overview

Comprehensive performance testing framework for DSQL that systematically tests performance across multiple dimensions (thread counts, batch sizes, loop sizes, payload sizes), collects structured data, and generates visualizations.

## Quick Start

1. **Run the test suite:**
   ```bash
   cd load-test/dsql-load-test-java
   ./run-performance-suite.sh
   ```

2. **Analyze results:**
   ```bash
   python3 analyze-results.py results/latest
   ```

3. **Generate HTML report:**
   ```bash
   python3 generate-report.py results/latest
   ```

## Test Matrix

The suite runs **32 focused tests** (24 standard + 4 super heavy + 4 extreme scaling) using a one-factor-at-a-time approach, optimized for speed while still discovering DSQL limits:

### Scenario 1: Individual Inserts

- **Thread Scaling** (5 tests): Threads: [1, 10, 25, 50, 100]
  - Fixed: iterations=20, count=1, payload=default
- **Loop Impact** (4 tests): Iterations: [10, 20, 50, 100]
  - Fixed: threads=10, count=1, payload=default
- **Payload Impact** (3 tests): Payload: [default, 4k, 32k]
  - Fixed: threads=10, iterations=20, count=1
- **Super Heavy Tests** (2 tests):
  - Threads=500, iterations=10, count=20, payload=default
  - Threads=1000, iterations=10, count=20, payload=default

### Scenario 2: Batch Inserts

- **Thread Scaling** (5 tests): Threads: [1, 10, 25, 50, 100]
  - Fixed: iterations=20, batch_size=10, payload=default
- **Batch Impact** (4 tests): Batch Size: [1, 10, 25, 50]
  - Fixed: threads=10, iterations=20, payload=default
- **Payload Impact** (3 tests): Payload: [default, 4k, 32k]
  - Fixed: threads=10, iterations=20, batch_size=10
- **Super Heavy Tests** (2 tests):
  - Threads=500, iterations=5, batch_size=100, payload=default
  - Threads=1000, iterations=5, batch_size=100, payload=default
- **Extreme Scaling Tests** (4 tests):
  - Threads=500, iterations=10, batch_size=500, payload=default
  - Threads=1000, iterations=10, batch_size=500, payload=default
  - Threads=2000, iterations=5, batch_size=1000, payload=default
  - Threads=5000, iterations=2, batch_size=1000, payload=default

## Optimization Strategy

This test suite is optimized to **discover DSQL limits quickly** rather than stress test with millions of inserts:

- **Reduced Iterations**: Standard tests use 20 iterations (vs 100) - 5x faster
- **Optimized Ranges**: Loop impact tests use [10, 20, 50, 100] instead of [10, 100, 1000, 5000]
- **Focused Payloads**: Removed 200k payload tests (too slow, 32k is sufficient to discover impact)
- **Optimized Super Heavy**: Reduced from 2.5M-5M inserts to 100K-500K inserts while maintaining high concurrency
- **Dynamic Connection Pool**: Pool size scales with thread count (min 10, max 1000) to prevent connection starvation
- **Large Batch Sizes**: Supports batch sizes up to 1000 rows (validated against PostgreSQL parameter limits)

**Expected Test Durations:**
- Standard tests: ~1-3 minutes each
- Super heavy tests: ~10-15 minutes each
- Extreme scaling tests: ~15-30 minutes each (high concurrency)
- Total suite time: ~2-4 hours (depending on instance type and DSQL performance)

**What We Still Discover:**
- Maximum throughput at different thread counts
- Optimal batch size for throughput
- Payload size impact on throughput
- Concurrency limits (500-1000 threads)
- Connection pool behavior under high load

## Configuration

Edit `test-config.json` to modify test parameters. The configuration uses a baseline approach where one dimension is varied at a time.

## Results

Results are stored in `results/{timestamp}/` with:
- Individual test JSON files
- Summary CSV
- Performance charts (PNG)
- HTML report

## Dependencies

- Java 17+
- Maven 3.8+
- Python 3.8+ with: pandas, matplotlib, seaborn, jinja2
- jq (for JSON processing)

Install Python dependencies:
```bash
pip install -r requirements.txt
```

## Test Methodology

### Thread Management

**Thread Pool Creation:**
- Uses Java's `ExecutorService` with a fixed thread pool
- Pool size equals the number of threads specified (e.g., 10, 100, 500, 1000)
- All threads start concurrently and execute in parallel

**Thread Execution:**
- Each thread runs as a separate `Callable` task
- Threads are submitted to the executor and execute concurrently
- Each thread gets a unique `threadIndex` (0 to threads-1)
- Main thread waits for all threads to complete using `future.get()`

**Connection Management:**
- Each thread gets its own database connection from a HikariCP connection pool
- Pool size: Dynamic based on thread count (min 10, max 1000)
  - Formula: `min(max(threads/2, 10), 1000)`
  - Can be overridden via `MAX_POOL_SIZE` environment variable
  - For high concurrency tests (500-5000 threads), pool size increases significantly to prevent connection starvation
- Connections are reused efficiently from the pool
- Each thread uses one connection for its entire execution lifecycle
- Pool metrics (active, idle, waiting threads) are logged after each scenario

### Success Monitoring for Inserts

**Individual Inserts (Scenario 1):**
- Uses `AtomicInteger` for thread-safe success/error counting
- Success: `executeUpdate()` returns > 0 (row was inserted)
- Error: Exception caught → increments error counter
- `ON CONFLICT DO NOTHING` returns 0 (not counted as success or error)

**Batch Inserts (Scenario 2):**
- Success: `executeUpdate()` returns number of rows inserted
- Error: Exception caught → error count incremented by batch size
- Batch insert returns total rows inserted in single call

**Progress Monitoring:**
- Per-thread progress logging every 10% of iterations
- Real-time metrics: success count, error count, current rate
- Thread-level metrics collected throughout execution

**Final Metrics Collection:**
- Each thread returns a `TestResult` with:
  - `successCount`: Total successful inserts
  - `errorCount`: Total errors encountered
  - `durationMs`: Thread execution time
  - `insertsPerSecond`: Thread-level throughput
- Aggregate metrics calculated from all thread results:
  - Total success across all threads
  - Total errors across all threads
  - Average inserts/second per thread
  - Overall throughput (total success / total duration)

### Key Design Decisions

**Thread Safety:**
- `AtomicInteger` for counters (thread-safe increment operations)
- Each thread has its own connection (no connection sharing between threads)
- HikariCP pool handles connection concurrency safely

**Error Handling:**
- Try-catch around each insert operation
- Errors don't stop thread execution (continues with next insert)
- All errors are counted and reported in final results

**Performance Tracking:**
- Per-thread metrics (success, errors, duration, rate)
- Aggregate metrics (total success, total errors, overall throughput)
- Real-time progress logging during execution

**Connection Pooling:**
- HikariCP pool with dynamic size (10-1000 connections based on thread count)
- Pool size scales with concurrency: `min(max(threads/2, 10), 1000)`
- Prevents connection starvation in high concurrency scenarios (500-5000 threads)
- Connections reused efficiently across operations
- Automatic connection lifecycle management
- Connection validation enabled (SELECT 1)
- Pre-warmed connections for high-concurrency tests (pool size >= 100)

This methodology provides:
- True parallel execution (all threads run concurrently)
- Accurate success/error tracking (per-operation monitoring)
- Detailed performance metrics (per-thread and aggregate)
- Resilient execution (errors don't stop the test)

## Files

- `test-config.json` - Test matrix configuration
- `run-performance-suite.sh` - Test execution script
- `analyze-results.py` - Chart generation script
- `generate-report.py` - HTML report generator
- `PerformanceMetrics.java` - Metrics data model
- `TestResultsCollector.java` - Results collection and export

## EC2 Instance Requirements

### Instance Type Recommendations

The test suite automatically manages EC2 instance lifecycle (starts before tests, stops after completion) to minimize costs.

**Recommended Instance Type: m5a.2xlarge**
- **Cost**: $0.344/hour (~$8.26/day)
- **Specs**: 8 vCPU, 32 GB RAM
- **Cost Efficiency**: $0.0430/vCPU (only 3% more expensive than T3, with dedicated CPU)
- **Rationale**: Best balance of cost and performance for 1000-2000 thread tests

**Requirements by Test Scale:**
- **500-1000 threads**: Minimum t3.xlarge (4 vCPU, 16 GB RAM) - $0.17/hour
  - Better: m5a.xlarge (4 vCPU, 16 GB RAM) - $0.17/hour (dedicated CPU)
- **1000-2000 threads**: Minimum t3.2xlarge (8 vCPU, 32 GB RAM) - $0.33/hour
  - **Recommended: m5a.2xlarge (8 vCPU, 32 GB RAM) - $0.34/hour** (dedicated CPU)
- **2000-5000 threads**: Minimum m5a.4xlarge (16 vCPU, 64 GB RAM) - $0.69/hour
  - Note: 5000 threads may require multiple instances or larger instance

**Cost Optimization:**
- Instance automatically starts before tests begin
- Instance automatically stops immediately after tests complete (via EXIT trap)
- Estimated cost per test run: ~$0.34/hour × test duration (typically 2-4 hours = $0.68-$1.36)

**Terraform Configuration:**
- Default instance type is set to `m5a.2xlarge` in `terraform/variables.tf`
- Can be overridden via `bastion_instance_type` variable

## Performance Tuning Guidelines

### Connection Pool Sizing

**Default Behavior:**
- Pool size = `min(max(threads/2, 10), 1000)`
- Example: 1000 threads → 500 connections, 5000 threads → 1000 connections

**Manual Override:**
- Set `MAX_POOL_SIZE` environment variable to override default calculation
- Example: `export MAX_POOL_SIZE=500` before running tests

**Recommendations:**
- For 500-1000 threads: Pool size 250-500
- For 1000-2000 threads: Pool size 500-1000
- For 2000+ threads: Pool size 1000 (maximum)

### Batch Size Optimization

**Supported Batch Sizes:**
- Maximum: 10,000 rows per batch (PostgreSQL parameter limit: 65,535 parameters)
- Recommended for extreme scaling: 500-1000 rows per batch
- Larger batches reduce round trips but increase memory usage

**Validation:**
- Batch size is automatically validated against PostgreSQL limits
- Error thrown if batch size exceeds 10,000 rows

### Troubleshooting High Concurrency

**Connection Pool Exhaustion:**
- Symptoms: High number of threads awaiting connection
- Solution: Increase `MAX_POOL_SIZE` or reduce thread count
- Monitor: Check pool metrics in test output

**Memory Issues:**
- Symptoms: OutOfMemoryError during tests
- Solution: Increase EC2 instance RAM or reduce batch size
- Monitor: Check instance CloudWatch metrics

**Timeout Issues:**
- Symptoms: Connection timeout errors
- Solution: Connection timeout is set to 60 seconds (increased from 30s)
- Monitor: Check connection acquisition time in pool metrics

**Instance Type Mismatch:**
- Symptoms: Tests fail or run very slowly
- Solution: Ensure instance type is m5a.2xlarge or larger for extreme scaling tests
- Check: Test runner validates instance type and warns if mismatch
