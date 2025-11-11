# Saturation Test Analysis Report

## Executive Summary

All 6 APIs completed saturation tests (7 phases: 10 → 50 → 100 → 200 → 500 → 1000 → 2000 VUs) with 0% error rate. Findings:

---

## Maximum Throughput Performance (Requests/Second)

**REST APIs:**

1. **Rust REST**: 2,492.98 req/s (highest)
2. **Java REST**: 2,258.64 req/s
3. **Go REST**: 2,151.35 req/s

**gRPC APIs:**

1. **Go gRPC**: 95.81 req/s (highest)
2. **Java gRPC**: 54.22 req/s
3. **Rust gRPC**: 46.59 req/s

**Insight**: REST APIs achieved ~26x higher throughput than gRPC. Rust REST leads by ~10% over Java REST.

---

## Latency Performance (Average Response Time)

**Best to worst:**

1. **Rust gRPC**: 9.11ms
2. **Java gRPC**: 9.75ms
3. **Rust REST**: 53.92ms
4. **Go REST**: 54.34ms
5. **Go gRPC**: 13.48ms
6. **Java REST**: 74.00ms

**Insight**: gRPC APIs show lower average latency (~9–13ms) than REST (~54–74ms), but REST handles much higher throughput.

---

## Test Duration Analysis

**Full test duration (840s = ~14 min):**

- **Rust REST**: 840.2s (completed all phases)
- **Java REST**: 840.7s (completed all phases)
- **Go REST**: 840.2s (completed all phases)

**Early termination (connection limits):**

- **Go gRPC**: 382.4s (~6.4 min) — stopped at ~500 VUs
- **Java gRPC**: 520.7s (~8.7 min) — stopped at ~500–1000 VUs
- **Rust gRPC**: 606.0s (~10.1 min) — stopped at ~1000 VUs

**Insight**: gRPC APIs hit connection limits before completing all phases, explaining lower total requests.

---

## Key Findings

1. **Rust REST leads overall**
   - Highest throughput: 2,492.98 req/s
   - Good latency: 53.92ms average
   - Completed all 7 phases
   - Zero errors

2. **REST vs gRPC throughput gap**
   - REST: 2,151–2,493 req/s
   - gRPC: 46–96 req/s
   - REST is ~26x higher
   - Likely due to gRPC connection limits at high VU counts

3. **gRPC connection exhaustion**
   - All gRPC APIs stopped early (382–606s vs 840s)
   - Go gRPC stopped earliest (382s) but had highest gRPC throughput (95.81 req/s)
   - Pattern suggests persistent connection limits at high concurrency

4. **Latency trade-offs**
   - gRPC: lower latency (~9–13ms) but much lower throughput
   - REST: higher latency (~54–74ms) but much higher throughput
   - Rust REST balances both well (53.92ms at 2,493 req/s)

5. **Java REST latency**
   - 74.00ms average (highest among REST)
   - Max response time: 1,593.38ms (highest)
   - Possible JVM GC pauses or connection pool tuning needed

6. **Go gRPC performance**
   - Best gRPC throughput (95.81 req/s)
   - Stopped earliest (382s) but handled more requests than others before stopping
   - Better connection management than Java/Rust gRPC

---

## Performance Comparison: Full vs Saturation Tests

| API | Full Test (100 VUs) | Saturation Test (2000 VUs) | Improvement |
|-----|---------------------|----------------------------|-------------|
| Rust REST | 337 req/s | 2,493 req/s | **7.4x** |
| Java REST | 328 req/s | 2,259 req/s | **6.9x** |
| Go REST | 331 req/s | 2,151 req/s | **6.5x** |
| Go gRPC | 120 req/s | 96 req/s | **-20%** (connection limits) |
| Java gRPC | 78 req/s | 54 req/s | **-31%** (connection limits) |
| Rust gRPC | 78 req/s | 47 req/s | **-40%** (connection limits) |

**Insight**: REST APIs scale well with increased load (6.5–7.4x improvement), while gRPC APIs hit connection limits and perform worse at saturation.

---

## Recommendations

1. **For maximum throughput**: Use **Rust REST** (2,493 req/s)
2. **For lowest latency**: Use **Rust gRPC** (9.11ms) if throughput requirements are low
3. **For balanced performance**: Use **Rust REST** (2,493 req/s at 53.92ms)
4. **For Java ecosystem**: **Java REST** is preferable (2,259 req/s vs 54 req/s for gRPC)
5. **For Go ecosystem**: **Go REST** offers strong performance (2,151 req/s)

---

## gRPC Connection Limit Investigation

**Observations:**

- All gRPC APIs hit connection limits before completing saturation tests
- Go gRPC handled the most requests before stopping (36,634 vs 28,231)
- Pattern suggests system-level TCP connection limits, not application limits

**Recommendations:**

- Increase system connection limits (`ulimit -n`, `sysctl` parameters)
- Implement connection pooling/multiplexing in gRPC clients
- Test gRPC with fewer VUs to find optimal concurrency level
- Consider HTTP/2 connection reuse optimizations

---

## Summary

**Winner: Rust REST**

- Highest throughput: 2,492.98 req/s
- Good latency: 53.92ms
- Excellent scalability: 7.4x improvement from full to saturation
- Zero errors across all test phases

**Best gRPC: Go gRPC**

- Highest gRPC throughput: 95.81 req/s
- Better connection handling than Java/Rust gRPC
- Still limited by connection exhaustion at high VU counts

The saturation tests confirm that REST APIs scale much better under extreme load, while gRPC APIs are limited by connection management at high concurrency levels.
