# 🚀 API Performance Test Report

## Test Information

- **Test Mode:** FULL
- **Test Date:** 2025-11-11 11:24:56
- **Test Type:** Sequential (one API at a time)
- **Total APIs Tested:** 6

## 📊 Executive Summary

| API | Protocol | Status | Total Requests | Success | Errors | Error Rate | Throughput (req/s) | Avg Response (ms) | Min (ms) | Max (ms) | P95 (ms) |
|-----|----------|--------|----------------|---------|--------|------------|-------------------|-------------------|----------|----------|----------|
| **Java REST** | REST | ✅ PASS | 118078 | 118078 | 0 | 0.00% | **327.91** | 8.75 | 0.43 | 201.94 | 19.37 |
| **Java gRPC** | gRPC | ✅ PASS | 28231 | 28231 | 0 | 0.00% | **78.04** | 17.23 | 0.67 | 1329.14 | 72.43 |
| **Rust REST** | REST | ✅ PASS | 121376 | 121376 | 0 | 0.00% | **337.11** | 6.11 | 0.35 | 210.38 | 15.97 |
| **Rust gRPC** | gRPC | ✅ PASS | 28231 | 28231 | 0 | 0.00% | **78.19** | 6.12 | 0.41 | 201.69 | 16.02 |
| **Go REST** | REST | ✅ PASS | 119355 | 119355 | 0 | 0.00% | **331.48** | 7.36 | 0.25 | 225.22 | 16.29 |
| **Go gRPC** | gRPC | ✅ PASS | 26930 | 26930 | 0 | 0.00% | **120.45** | 7.96 | 0.36 | 372.85 | 21.76 |

## 📊 Comparison Analysis

### Performance Rankings

- **Highest Throughput:** **Rust REST** with 337.11 req/s
- **Lowest Latency:** **Rust REST** with 6.11 ms average response time
- **Most Reliable:** **Java REST** with 0.00% error rate

### Protocol Comparison

#### REST vs gRPC

- **Throughput:** REST APIs average 332.17 req/s, gRPC APIs average 92.23 req/s
- **Latency:** REST APIs average 7.41 ms, gRPC APIs average 10.44 ms
- **Analysis:** gRPC shows 72.2% lower throughput and 40.9% higher latency compared to REST

### Language Comparison

#### Java vs Rust vs Go

- **Throughput:** Java (202.97 req/s), Rust (207.65 req/s), Go (225.97 req/s)
- **Latency:** Java (12.99 ms), Rust (6.12 ms), Go (7.66 ms)
- **Best Throughput:** **Go** (225.97 req/s)
- **Best Latency:** **Rust** (6.12 ms)

### Key Insights

- Significant throughput variation (76.9%) across APIs, indicating performance differences
- Rust REST is 64.5% faster than Java gRPC in terms of average latency
- All APIs achieved 0% error rate, demonstrating excellent reliability
- REST shows higher throughput, making it better for high-volume scenarios

### Recommendations

- **For Maximum Throughput:** Choose **Rust REST** (337.11 req/s)
- **For Lowest Latency:** Choose **Rust REST** (6.11 ms average)
- **For Reliability:** All APIs show 0% error rate - excellent reliability across the board

## 📋 Detailed Results

### Java REST (REST)

| Metric | Value |
|--------|-------|
| Total Requests | **118078** |
| Successful Requests | ✅ 118078 |
| Failed Requests | ❌ 0 |
| Error Rate | 0.00% |
| Test Duration | 360.09 seconds |
| Throughput | **327.91 req/s** |
| Average Response Time | 8.75 ms |
| Min Response Time | 0.43 ms |
| Max Response Time | 201.94 ms |
| P95 Response Time | 19.37 ms |
| P99 Response Time | 33.72 ms |

*Source: producer-api-java-rest-throughput-20251111_103443.json*

### Java gRPC (gRPC)

| Metric | Value |
|--------|-------|
| Total Requests | **28231** |
| Successful Requests | ✅ 28231 |
| Failed Requests | ❌ 0 |
| Error Rate | 0.00% |
| Test Duration | 361.77 seconds |
| Throughput | **78.04 req/s** |
| Average Response Time | 17.23 ms |
| Min Response Time | 0.67 ms |
| Max Response Time | 1329.14 ms |
| P95 Response Time | 72.43 ms |
| P99 Response Time | 109.04 ms |

*Source: producer-api-java-grpc-throughput-20251111_103443.json*

### Rust REST (REST)

| Metric | Value |
|--------|-------|
| Total Requests | **121376** |
| Successful Requests | ✅ 121376 |
| Failed Requests | ❌ 0 |
| Error Rate | 0.00% |
| Test Duration | 360.04 seconds |
| Throughput | **337.11 req/s** |
| Average Response Time | 6.11 ms |
| Min Response Time | 0.35 ms |
| Max Response Time | 210.38 ms |
| P95 Response Time | 15.97 ms |
| P99 Response Time | 38.53 ms |

*Source: producer-api-rust-rest-throughput-20251111_103443.json*

### Rust gRPC (gRPC)

| Metric | Value |
|--------|-------|
| Total Requests | **28231** |
| Successful Requests | ✅ 28231 |
| Failed Requests | ❌ 0 |
| Error Rate | 0.00% |
| Test Duration | 361.06 seconds |
| Throughput | **78.19 req/s** |
| Average Response Time | 6.12 ms |
| Min Response Time | 0.41 ms |
| Max Response Time | 201.69 ms |
| P95 Response Time | 16.02 ms |
| P99 Response Time | 55.04 ms |

*Source: producer-api-rust-grpc-throughput-20251111_103443.json*

### Go REST (REST)

| Metric | Value |
|--------|-------|
| Total Requests | **119355** |
| Successful Requests | ✅ 119355 |
| Failed Requests | ❌ 0 |
| Error Rate | 0.00% |
| Test Duration | 360.07 seconds |
| Throughput | **331.48 req/s** |
| Average Response Time | 7.36 ms |
| Min Response Time | 0.25 ms |
| Max Response Time | 225.22 ms |
| P95 Response Time | 16.29 ms |
| P99 Response Time | 21.03 ms |

*Source: producer-api-go-rest-throughput-20251111_103443.json*

### Go gRPC (gRPC)

| Metric | Value |
|--------|-------|
| Total Requests | **26930** |
| Successful Requests | ✅ 26930 |
| Failed Requests | ❌ 0 |
| Error Rate | 0.00% |
| Test Duration | 223.57 seconds |
| Throughput | **120.45 req/s** |
| Average Response Time | 7.96 ms |
| Min Response Time | 0.36 ms |
| Max Response Time | 372.85 ms |
| P95 Response Time | 21.76 ms |
| P99 Response Time | 72.42 ms |

*Source: producer-api-go-grpc-throughput-20251111_103443.json*

---

*Generated by k6 Performance Testing Framework*  
*Report generated at 2025-11-11 11:24:56*

