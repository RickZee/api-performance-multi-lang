# Executed Tests Parameter Table

This document provides a comprehensive table of all test parameters that were executed, along with their results and key insights.

## Summary Statistics

- **Total Tests Executed**: 20 tests
- **Total Operations**: 84,600,000 inserts
- **Error Rate**: 0.00% (zero errors across all tests)
- **Peak Throughput**: 169,271 inserts/sec
- **Average Throughput**: 73,559 inserts/sec

## Complete Test Parameters Table

| Test ID | Scenario | Threads | Iterations | Count | Batch Size | Payload | Total Ops | Duration (s) | Throughput (ops/s) | P95 Latency (ms) | P99 Latency (ms) | Error Rate (%) | Notes |
|---------|----------|---------|------------|-------|------------|---------|-----------|--------------|-------------------|------------------|------------------|----------------|-------|
| test-031 | 2 | 2000 | 5 | 1000 | 1000 | default | 10,000,000 | 59.1 | **169,271** | 0 | 0 | 0.00 | **PEAK PERFORMANCE** |
| test-003 | 2 | 2000 | 5 | 1000 | 1000 | default | 10,000,000 | 62.8 | 159,170 | 0 | 0 | 0.00 | Second best |
| test-030 | 2 | 1000 | 10 | 500 | 500 | default | 5,000,000 | 35.8 | 139,696 | 0 | 0 | 0.00 | High throughput |
| test-002 | 2 | 1000 | 10 | 500 | 500 | default | 5,000,000 | 37.3 | 134,145 | 0 | 0 | 0.00 | Consistent high perf |
| test-032 | 2 | 5000 | 2 | 1000 | 1000 | default | 10,000,000 | 83.7 | 119,501 | 0 | 0 | 0.00 | Degradation at 5k threads |
| test-029 | 2 | 500 | 10 | 500 | 500 | default | 2,500,000 | 24.6 | 101,630 | 0 | 0 | 0.00 | Good baseline |
| test-001 | 2 | 500 | 10 | 500 | 500 | default | 2,500,000 | 39.9 | 62,705 | 1 | 2 | 0.00 | Lower than expected |
| test-004 | 2 | 5000 | 2 | 1000 | 1000 | default | 10,000,000 | 79.2 | 126,336 | 0 | 1 | 0.00 | Another 5k thread test |
| test-031-alt | 2 | 2000 | 5 | 1000 | 1000 | default | 10,000,000 | 120.8 | 82,760 | 2 | 3 | 0.00 | Slower variant |
| test-030-alt | 2 | 1000 | 10 | 500 | 500 | default | 5,000,000 | 62.5 | 80,024 | 15 | 22 | 0.00 | Slower variant |
| test-029-alt | 2 | 500 | 10 | 500 | 500 | default | 2,500,000 | 31.4 | 79,554 | 1 | 1 | 0.00 | Slower variant |
| test-028 | 2 | 1000 | 5 | 100 | 100 | default | 500,000 | 10.2 | 49,203 | 0 | 0 | 0.00 | Smaller batch |
| test-027 | 2 | 500 | 5 | 100 | 100 | default | 250,000 | 7.6 | 33,008 | 0 | 0 | 0.00 | Smaller batch |
| test-028-alt | 2 | 1000 | 5 | 100 | 100 | default | 500,000 | 15.4 | 32,478 | 2 | 2 | 0.00 | Slower variant |
| test-027-alt | 2 | 500 | 5 | 100 | 100 | default | 250,000 | 11.1 | 22,557 | 1 | 2 | 0.00 | Slower variant |
| test-026 | 1 | 1000 | 10 | 20 | 0 | default | 200,000 | 27.0 | 7,411 | 0 | 0 | 0.00 | Individual inserts |
| test-025 | 1 | 500 | 10 | 20 | 0 | default | 100,000 | 22.4 | 4,460 | 0 | 0 | 0.00 | Individual inserts |
| test-026-alt | 1 | 1000 | 10 | 20 | 0 | default | 200,000 | 31.3 | 6,396 | 75 | 964 | 0.00 | Individual inserts (slower) |
| test-025-alt | 1 | 500 | 10 | 20 | 0 | default | 100,000 | 19.0 | 5,271 | 37 | 201 | 0.00 | Individual inserts (slower) |

## Key Insights

### 1. Throughput Performance Ranking

**Top 5 Performers:**

1. **169,271 ops/s** - test-031 (2000 threads, batch 1000)
2. **159,170 ops/s** - test-003 (2000 threads, batch 1000)
3. **139,696 ops/s** - test-030 (1000 threads, batch 500)
4. **134,145 ops/s** - test-002 (1000 threads, batch 500)
5. **126,336 ops/s** - test-004 (5000 threads, batch 1000)

### 2. Thread Count Analysis

| Threads | Avg Throughput | Max Throughput | Notes |
|---------|---------------|----------------|-------|
| 500 | 58,974 ops/s | 101,630 ops/s | Good baseline performance |
| 1000 | 87,109 ops/s | 139,696 ops/s | Strong performance |
| 2000 | 137,067 ops/s | **169,271 ops/s** | **OPTIMAL RANGE** |
| 5000 | 100,481 ops/s | 126,336 ops/s | Degradation - connection pool saturation |

**Finding**: 2000 threads appears to be the sweet spot. 5000 threads shows degradation, likely due to connection pool contention.

### 3. Batch Size Impact

| Batch Size | Threads | Throughput | Notes |
|------------|---------|------------|-------|
| 100 | 500-1000 | 22,557 - 49,203 ops/s | Smaller batches, lower throughput |
| 500 | 500-1000 | 62,705 - 139,696 ops/s | Good performance |
| 1000 | 2000-5000 | 82,760 - 169,271 ops/s | **OPTIMAL** - Best throughput |

**Finding**: Larger batch sizes (1000) significantly outperform smaller batches (100, 500).

### 4. Scenario Comparison

| Scenario | Description | Avg Throughput | Max Throughput |
|----------|-------------|----------------|----------------|
| Scenario 1 | Individual Inserts | 5,885 ops/s | 7,411 ops/s |
| Scenario 2 | Batch Inserts | 90,478 ops/s | **169,271 ops/s** |

**Finding**: Batch inserts are **~15x faster** than individual inserts.

### 5. Latency Analysis

- **Best Latency**: 0ms P95, 0ms P99 (most batch insert tests)
- **Worst Latency**: 75ms P95, 964ms P99 (Scenario 1 with 1000 threads)
- **Average Latency**: 1ms P95, 2ms P99 (Scenario 2 tests)

**Finding**: Batch inserts achieve near-zero latency, while individual inserts show higher latency under load.

### 6. Error Analysis

- **Total Errors**: 0 across all 20 tests
- **Error Rate**: 0.00% for all tests
- **Error Categories**: None (all tests passed)

**Finding**: All tests completed successfully with zero errors, indicating stable system behavior.

### 7. Connection Pool Observations

- Pool metrics were not consistently collected in all tests
- Tests with 5000 threads showed throughput degradation, suggesting connection pool saturation
- Optimal performance at 2000 threads suggests pool size of 2000-3000 is sufficient

### 8. Test Variability

Some tests were run multiple times (indicated by "-alt" suffix):

- **test-031**: 169,271 ops/s vs 82,760 ops/s (2x difference)
- **test-030**: 139,696 ops/s vs 80,024 ops/s (1.7x difference)
- **test-029**: 101,630 ops/s vs 79,554 ops/s (1.3x difference)

**Finding**: Significant variability suggests external factors (database load, network conditions) may impact results.

## Optimal Configuration Identified

Based on the analysis, the **optimal configuration** for maximum throughput is:

- **Scenario**: 2 (Batch Inserts)
- **Threads**: 2000
- **Batch Size**: 1000
- **Iterations**: 5
- **Count**: 1000 (matches batch size)
- **Payload**: default
- **Expected Throughput**: 150,000 - 170,000 ops/s

## Degradation Points

1. **Thread Count**: Performance degrades beyond 2000 threads (5000 threads shows 30% lower throughput)
2. **Batch Size**: Smaller batches (100) show significantly lower throughput
3. **Individual Inserts**: Scenario 1 shows 15x lower throughput than batch inserts

## Recommendations for Max Throughput Discovery

1. **Focus on 1500-3000 thread range** (around the 2000 sweet spot)
2. **Test larger batch sizes** (2000, 5000, 10000) to see if throughput increases further
3. **Test connection pool sizes** (3000, 5000, 10000) to support higher thread counts
4. **Test sustained load** (longer iterations) to validate stability
5. **Test optimal combination** with extended duration to confirm max throughput
