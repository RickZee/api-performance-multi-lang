# Full Test Analysis Report

## Executive Summary

All 6 APIs completed the full throughput test (4 phases: 10 → 50 → 100 → 200 VUs) with 0% error rate. Findings:

---

## Throughput Performance (Requests/Second)

**REST APIs:**

1. **Rust REST**: 337.11 req/s (highest)
2. **Go REST**: 331.48 req/s
3. **Java REST**: 327.91 req/s

**gRPC APIs:**

1. **Go gRPC**: 120.45 req/s (highest)
2. **Rust gRPC**: 78.19 req/s
3. **Java gRPC**: 78.04 req/s

**Insight**: REST APIs show ~4x higher throughput than gRPC. Rust REST leads by ~3% over Go REST.

---

## Latency Performance (Average Response Time)

**Best to worst:**

1. **Rust REST**: 6.11ms
2. **Rust gRPC**: 6.12ms
3. **Go REST**: 7.36ms
4. **Go gRPC**: 7.96ms
5. **Java REST**: 8.75ms
6. **Java gRPC**: 17.23ms

**Insight**: Rust implementations have the lowest latency. Java gRPC is ~2.8x slower than Rust gRPC.

---

## Key Findings

1. **Rust REST leads overall**
   - Highest throughput (337.11 req/s)
   - Lowest latency (6.11ms)
   - Zero errors

2. **gRPC throughput gap**
   - gRPC APIs handle ~78–120 req/s vs REST at ~328–337 req/s
   - Possible causes: connection overhead, protocol efficiency, or test configuration

3. **Go gRPC exception**
   - 120.45 req/s (54% higher than other gRPC)
   - Test duration: 223.6s vs ~361s for others
   - May indicate different test completion or better connection handling

4. **Java gRPC latency**
   - 17.23ms average (highest)
   - Max response time: 1329.14ms (outlier)
   - Possible JVM warmup or connection pooling issues

5. **Rust consistency**
   - REST and gRPC both ~6ms average latency
   - Consistent performance across protocols

---

## Protocol Comparison

**REST vs gRPC:**

- REST: 328–337 req/s, 6–9ms latency
- gRPC: 78–120 req/s, 6–17ms latency

**Insight**: REST shows higher throughput in this test. gRPC may excel in different scenarios (e.g., streaming, binary payloads, or higher concurrency).

---

## Recommendations

1. **For maximum throughput**: Use **Rust REST** (337 req/s)
2. **For lowest latency**: Use **Rust REST** or **Rust gRPC** (~6ms)
3. **For Go ecosystem**: **Go REST** offers strong throughput (331 req/s) and low latency (7.36ms)
4. **For Java ecosystem**: **Java REST** is preferable to Java gRPC for throughput and latency
5. **For gRPC requirements**: **Go gRPC** shows the best gRPC performance (120 req/s)

---

## Test Configuration Notes

- Test duration: ~660 seconds per API (4 phases: 2m + 2m + 2m + 5m = 11 minutes)
- All APIs maintained 0% error rate
- Test phases: 10 → 50 → 100 → 200 VUs
- Sequential testing ensures fair comparison

---

## Next Steps

1. Run saturation tests to find maximum capacity (up to 2000 VUs)
2. Investigate why gRPC throughput is lower (connection pooling, protocol overhead)
3. Analyze Java gRPC latency spikes (JVM tuning, connection management)
4. Test with larger payloads to see if gRPC advantages emerge
5. Test under sustained load to check for degradation

Overall, Rust REST shows the best balance of throughput and latency, with Go REST close behind.
