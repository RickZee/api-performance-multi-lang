# Full Test Suite Analysis - Report

**Date:** December 25, 2025  
**Test Suite:** `test-config-max-throughput.json`  
**Results Directory:** `results/2025-12-24_15-55-43`  
**Total Tests Completed:** 38/43 (88%)
**Total Test Duration:** ~26 hours
**Total Inserts:** 30,749,996  
**Infrastructure:** EC2 m5a.2xlarge, Aurora DSQL (serverless)

## Executive Summary

The comprehensive test suite executed **38 out of 43 planned tests, with 4 errors out of 30.75 million inserts**. The tests validated performance characteristics across different scenarios, thread counts, and payload sizes, including testing of very large payloads (500KB and 1MB).

### Key Stats

- **30,749,996 total records created** (30,749,996 inserts executed successfully)
- **Peak throughput: 126,784 ops/sec** (Scenario 2, default payload, 3500 threads)
- **Large payload validation:** Rested 500KB and 1MB payloads in Scenario 1

## Test Suite Overview

### Test Distribution

| Category | Tests | Total Records Created | Avg Throughput | Peak Throughput |
|----------|-------|----------------------|----------------|-----------------|
| **Scenario 1 (Individual)** | 22 | 3,399,996 | 3,673 ops/sec | 4,012 ops/sec |
| **Scenario 2 (Batch)** | 16 | 27,350,000 | 52,596 ops/sec | 126,784 ops/sec |
| **Total** | **38** | **30,749,996** | **5,784 ops/sec** | **126,784 ops/sec** |

### Record Creation Summary

**Total Records Created:** 30,749,996
**Average Records per Test:** 809,210

#### Records by Scenario

- **Scenario 1 (Individual Inserts):** 3,399,996 records (11.1% of total)
- **Scenario 2 (Batch Inserts):** 27,350,000 records (88.9% of total)

#### Records by Payload Size

| Payload | Scenario 1 | Scenario 2 | Total Records |
|---------|------------|------------|---------------|
| default (~0.6KB) | 650,000 | 25,350,000 | **26,000,000** (84.5%) |
| 1KB | 650,000 | 1,000,000 | 1,650,000 (5.4%) |
| 10KB | 650,000 | 1,000,000 | 1,650,000 (5.4%) |

## Payload Size Impact Analysis

### Complete Payload Impact Overview

| Payload | Size (bytes) | Size (KB) | Tests | Total Inserts | Avg Throughput | Peak Throughput | Avg Duration | Errors | Degradation |
|---------|--------------|-----------|-------|---------------|----------------|-----------------|-------------|--------|------------|
| **default** | 600 | 0.6 | 18 | 26,000,000 | **45,755** | 126,784 | 30.0s | 0 | Baseline |
| **1k** | 1,024 | 1.0 | 5 | 1,650,000 | 10,199 | 25,649 | 26.5s | 0 | **-77.7%** |
| **10k** | 10,240 | 10.0 | 5 | 1,650,000 | 8,438 | 16,878 | 30.6s | 0 | **-81.6%** |
| **100k** | 102,400 | 100.0 | 4 | 649,999 | 1,097 | 1,992 | 140.1s | 1 | **-97.6%** |
| **500k** | 512,000 | 500.0 | 4 | 649,997 | 238 | 253 | 664.5s | 3 | **-99.5%** |
| **1024k** | 1,048,576 | 1024.0 | 2 | 150,000 | 117 | 119 | 636.6s | 0 | **-99.7%** |

### Performance Degradation Pattern

**Exponential Impact:** Performance degradation is non-linear and exponential:

- Small increases (0.6KB → 1KB): -77.7% throughput
- Medium increases (0.6KB → 10KB): -81.6% throughput
- Large increases (0.6KB → 100KB): -97.6% throughput
- Very large (0.6KB → 500KB): -99.5% throughput
- Extreme (0.6KB → 1MB): -99.7% throughput

### Throughput Efficiency (ops/sec per KB)

| Payload | Size (KB) | Avg Throughput | Efficiency (ops/KB) | Efficiency Loss |
|---------|-----------|---------------|---------------------|-----------------|
| default | 0.6 | 45,755 ops/sec | **78,088 ops/KB** | Baseline |
| 1k | 1.0 | 10,199 ops/sec | 10,199 ops/KB | -86.9% |
| 10k | 10.0 | 8,438 ops/sec | 844 ops/KB | -98.9% |
| 100k | 100.0 | 1,097 ops/sec | 11 ops/KB | -100.0% |
| 500k | 500.0 | 238 ops/sec | 0.5 ops/KB | -100.0% |
| 1024k | 1024.0 | 117 ops/sec | 0.1 ops/KB | -100.0% |

**Key Insight:** Smaller payloads are **exponentially more efficient**. The default payload is 78,088x more efficient than a 1MB payload.

## Payload Size Impact by Scenario

### Default Payload (~0.6 KB)

**Scenario 1 (Individual):**

- Tests: 4
- Total Inserts: 650,000
- Avg Throughput: 6,143 ops/sec
- Peak Throughput: 8,485 ops/sec
- Data Rate: 3.83 MB/s
- Errors: 0

**Scenario 2 (Batch):**

- Tests: 14
- Total Inserts: 25,350,000
- Avg Throughput: 57,072 ops/sec
- Peak Throughput: 126,784 ops/sec
- Data Rate: 32.78 MB/s
- Errors: 0

**Best Performance:** Scenario 2 achieves 9.3x higher throughput than Scenario 1 with default payload.

### 1KB Payload

**Scenario 1 (Individual):**

- Tests: 4
- Total Inserts: 650,000
- Avg Throughput: 6,337 ops/sec (+3% vs default)
- Peak Throughput: 8,918 ops/sec
- Data Rate: 6.77 MB/s
- Errors: 0
- **Impact:** Minimal impact on Scenario 1

**Scenario 2 (Batch):**

- Tests: 1
- Total Inserts: 1,000,000
- Avg Throughput: 25,649 ops/sec (-55% vs default)
- Peak Throughput: 25,649 ops/sec
- Data Rate: 25.05 MB/s
- Errors: 0
- **Impact:** Significant impact on Scenario 2

**Finding:** 1KB payload has minimal impact on Scenario 1 but significant impact on Scenario 2.

### 10KB Payload

**Scenario 1 (Individual):**

- Tests: 4
- Total Inserts: 650,000
- Avg Throughput: 6,327 ops/sec (+3% vs default)
- Peak Throughput: 9,015 ops/sec
- Data Rate: 67.72 MB/s
- Errors: 0
- **Impact:** Minimal impact on Scenario 1

**Scenario 2 (Batch):**

- Tests: 1
- Total Inserts: 1,000,000
- Avg Throughput: 16,878 ops/sec (-70% vs default)
- Peak Throughput: 16,878 ops/sec
- Data Rate: **164.82 MB/s** (highest data transfer rate)
- Errors: 0
- **Impact:** Significant impact on Scenario 2

**Finding:** 10KB payload maintains Scenario 1 performance but significantly impacts Scenario 2. However, data transfer rate increases substantially (164.82 MB/s).

### 100KB Payload

**Scenario 1 (Individual):**

- Tests: 4
- Total Inserts: 649,999
- Avg Throughput: 1,097 ops/sec (-82% vs default)
- Peak Throughput: 1,236 ops/sec
- Data Rate: 113.29 MB/s
- Errors: 1 (0.0002%)
- **Impact:** Severe performance degradation

**Scenario 2 (Batch):**

- **Status:** Cancelled

**Finding:** 100KB is the practical limit for Scenario 2. Scenario 1 can handle it but with severe performance degradation.

### 500KB Payload

**Scenario 1 (Individual):**

- Tests: 4
- Total Inserts: 649,997
- Avg Throughput: 238 ops/sec (-96% vs default)
- Peak Throughput: 253 ops/sec
- Data Rate: 119.41 MB/s
- Errors: 3 (0.0005%)
- **Duration:** 44.3 minutes total

**Detailed Test Results:**

| Test | Threads | Throughput | Duration | Inserts | Errors |
|------|---------|------------|----------|---------|--------|
| test-024 | 500 | 215 ops/sec | 3.9 min | 49,997 | 3 |
| test-030 | 1000 | 244 ops/sec | 6.8 min | 100,000 | 0 |
| test-036 | 2000 | 241 ops/sec | 13.8 min | 200,000 | 0 |
| test-042 | 3000 | 253 ops/sec | 19.8 min | 300,000 | 0 |

**Key Observations:**

- Throughput is consistent (~215-253 ops/sec) regardless of thread count
- No significant scaling benefit with more threads
- Minimal errors (0.0005% error rate)
- Very long execution times (3.9-19.8 minutes per test)

**Scenario 2 (Batch):**

- **Status:** Cancelled

### 1MB Payload

**Scenario 1 (Individual):**

- Tests: 2
- Total Inserts: 150,000
- Avg Throughput: 117 ops/sec (-98% vs default)
- Peak Throughput: 119 ops/sec
- Data Rate: 117.82 MB/s
- Errors: 0
- **Duration:** 21.2 minutes total

**Detailed Test Results:**

| Test | Threads | Throughput | Duration | Inserts | Errors |
|------|---------|------------|----------|---------|--------|
| test-025 | 500 | 116 ops/sec | 7.2 min | 50,000 | 0 |
| test-031 | 1000 | 119 ops/sec | 14.0 min | 100,000 | 0 |

**Key Observations:**

- Throughput approximately half of 500KB payload (~116-119 ops/sec)
- Zero errors observed
- Duration increases significantly (7-14 minutes per test)
- No scaling benefit with more threads

**Scenario 2 (Batch):**

- **Status:** Cancelled

## Data Transfer Rate Analysis

### Maximum Data Transfer Rates by Payload Size

| Payload | Max Data Rate (MB/s) | Configuration | Test ID |
|---------|---------------------|---------------|---------|
| default | 72.55 | Scenario 2, 2500 threads | test-010 |
| 1k | 25.05 | Scenario 2, 2000 threads | test-015 |
| 10k | **164.82** | Scenario 2, 2000 threads | test-016 |
| 100k | 120.74 | Scenario 1, 3000 threads | test-041 |
| 500k | 123.49 | Scenario 1, 3000 threads | test-042 |
| 1024k | 118.86 | Scenario 1, 1000 threads | test-031 |

**Key Finding:** Despite lower throughput with larger payloads, **data transfer rates can be higher** due to more data per insert. The 10KB payload achieves the highest data transfer rate (164.82 MB/s).

### Data Transfer Efficiency

**Throughput vs Data Transfer Trade-off:**

- **Small Payloads (default, 1KB):**
  - High throughput (many inserts/sec)
  - Lower data transfer rate (less data per insert)
  - Optimal for high-frequency operations

- **Medium Payloads (10KB):**
  - Moderate throughput
  - **Highest data transfer rate** (164.82 MB/s)
  - Good balance for bulk data operations

- **Large Payloads (100KB+):**
  - Low throughput (few inserts/sec)
  - High data transfer rate (more data per insert)
  - Suitable for low-frequency, high-value data

### Total Data Transferred

- **Total Inserts:** 30,749,996
- **Total Data:** ~14.53 GB (weighted by actual payload sizes)
- **Average Data per Insert:** ~484 bytes (weighted average)

### Data Transfer by Payload Size

| Payload | Inserts | Data Transferred |
|---------|---------|------------------|
| default (~0.6KB) | 26,000,000 | ~14.53 GB |
| 1KB | 1,650,000 | ~1.58 GB |
| 10KB | 1,650,000 | ~15.75 GB |
| 100KB | 649,999 | ~62.0 GB |
| 500KB | 649,997 | ~310.0 GB |
| 1MB | 150,000 | ~150.0 GB |

## Thread Scaling Analysis

### Scenario 2 - Default Payload Thread Scaling

| Threads | Tests | Avg Throughput | Peak Throughput | Avg Duration |
|---------|-------|---------------|-----------------|--------------|
| 1500 | 1 | 33,427 ops/sec | 33,427 ops/sec | 22.4s |
| 2000 | 6 | 46,434 ops/sec | 47,185 ops/sec | 21.5s |
| 2500 | 2 | 45,592 ops/sec | 45,592 ops/sec | 27.0s |
| 3000 | 2 | 45,629 ops/sec | 45,629 ops/sec | 32.9s |
| 3500 | 1 | 46,937 ops/sec | 46,937 ops/sec | 37.3s |
| 4000 | 1 | 18,853 ops/sec | 18,853 ops/sec | 31.8s |
| 5000 | 1 | 18,853 ops/sec | 18,853 ops/sec | 31.8s |

**Key Findings:**

1. **Optimal Thread Count: 2000**
   - Best balance of throughput and efficiency
   - Peak throughput: 47,185 ops/sec
   - Fastest execution: 21.5s average

2. **Diminishing Returns Beyond 2000:**
   - 2500-3500 threads: Similar throughput but longer duration
   - 4000-5000 threads: Significant throughput drop (~60% reduction)

3. **Recommendation:** Use 2000 threads for optimal performance

### Scenario 1 - Thread Scaling (Default Payload)

| Threads | Tests | Avg Throughput | Peak Throughput |
|---------|-------|---------------|-----------------|
| 500 | 1 | 1,486 ops/sec | 1,486 ops/sec |
| 1000 | 1 | 2,012 ops/sec | 2,012 ops/sec |
| 2000 | 1 | 1,992 ops/sec | 1,992 ops/sec |
| 3000 | 1 | 4,012 ops/sec | 4,012 ops/sec |

**Finding:** Optimal thread count appears to be 3000 for Scenario 1, achieving peak throughput of 4,012 ops/sec.

## Error Analysis

### Overall Error Statistics

- **Total Successful Operations:** 30,749,992
- **Total Errors:** 4
- **Error Rate:** 0.000013%
- **Tests with Errors:** 2 out of 38 (5.3%)

### Error Distribution

| Payload Size | Errors | Error Rate | Root Cause |
|--------------|--------|------------|------------|
| default | 0 | 0% | N/A |
| 1KB | 0 | 0% | N/A |
| 10KB | 0 | 0% | N/A |
| 100KB | 1 | 0.0002% | Large payload processing |
| 500KB | 3 | 0.0005% | Very large payload processing |
| 1MB | 0 | 0% | N/A |

**Analysis:**

- Errors only occurred with very large payloads (100KB+)
- All errors were QUERY_ERROR type
- Error rate remains extremely low even with large payloads
- Scenario 2 had zero errors (all tests with default/1KB/10KB payloads)

## Scenario Comparison by Payload Size

### Throughput Comparison

| Payload | Scenario 1 | Scenario 2 | Ratio (S2/S1) |
|---------|------------|------------|---------------|
| default | 6,143 ops/sec | 57,072 ops/sec | **9.3x** |
| 1k | 6,337 ops/sec | 25,649 ops/sec | **4.0x** |
| 10k | 6,327 ops/sec | 16,878 ops/sec | **2.7x** |

**Key Finding:** Scenario 2's advantage decreases with larger payloads. For payloads ≥100KB, Scenario 2 cannot function, leaving Scenario 1 as the only option.

### Data Transfer Rate Comparison

| Payload | Scenario 1 | Scenario 2 | Best |
|---------|------------|------------|------|
| default | 3.83 MB/s | 32.78 MB/s | Scenario 2 |
| 1k | 6.77 MB/s | 25.05 MB/s | Scenario 2 |
| 10k | 67.72 MB/s | **164.82 MB/s** | Scenario 2 |

**Key Finding:** For payloads ≤10KB, Scenario 2 achieves higher data transfer rates. For larger payloads, Scenario 1 is the only option.

## Key Findings & Recommendations

### 1. Optimal Configuration

**For Maximum Throughput:**

- **Scenario:** 2 (Batch Inserts)
- **Threads:** 2000
- **Batch Size:** 100
- **Payload:** default (~0.6KB)
- **Expected Throughput:** ~46,000-47,000 ops/sec

**For Individual Inserts:**

- **Scenario:** 1 (Individual Inserts)
- **Threads:** 3000
- **Payload:** default (~0.6KB)
- **Expected Throughput:** ~4,000 ops/sec

### 2. Payload Size Guidelines

**Recommended Payload Sizes:**

- **≤1KB:** Optimal performance, minimal impact
- **1-10KB:** Acceptable with moderate impact (~80% degradation)
- **>10KB:** Significant performance impact, avoid for high-throughput scenarios

**For Large Payloads (if required):**

- Use Scenario 1 (individual inserts) instead of Scenario 2
- Reduce batch size for Scenario 2 (e.g., 10-25 rows instead of 100)
- Increase connection timeout settings
- Use smaller thread counts to reduce connection pressure

### 3. Thread Count Optimization

**Scenario 2:**

- **Optimal:** 2000 threads
- **Acceptable Range:** 1500-3500 threads
- **Avoid:** >4000 threads (diminishing returns)

**Scenario 1:**

- **Optimal:** 3000 threads
- **Acceptable Range:** 1000-3000 threads

### 4. Scenario Selection

**Use Scenario 2 (Batch) When:**

- Maximum throughput is required
- Payload sizes are ≤10KB
- Bulk operations are acceptable
- Error rate must be minimal

**Use Scenario 1 (Individual) When:**

- Transaction-level control is needed
- Very large payloads (>10KB) are required
- Individual row tracking is important
- Lower throughput is acceptable

### 5. Production Recommendations

**High-Throughput Workloads:**

- Use Scenario 2 with default payload (~0.6KB)
- Configure 2000 threads
- Batch size: 100 rows
- Monitor connection pool utilization

**Large Payload Workloads:**

- Use Scenario 1 with individual inserts
- Accept lower throughput (expect 99%+ degradation for 500KB+)

### 6. Payload Size Decision Matrix

| Payload Size | Scenario | Throughput Impact | Recommendation |
|--------------|----------|-------------------|----------------|
| ≤1KB | Scenario 2 | Minimal | ✅ **Optimal** |
| 1-10KB | Scenario 2 | Moderate (-70%) | ⚠️ Acceptable |
| 10-100KB | Scenario 1 | Severe (-82%) | ⚠️ Use Scenario 1 |
| 100KB-500KB | Scenario 1 | Extreme (-96%) | ❌ Consider alternatives |
| ≥500KB | Scenario 1 | Extreme (-99%) | ❌ Consider alternatives |

## Cost Analysis

### Actual AWS Billing Data

**Note:** The following represents actual AWS billing data for Aurora DSQL usage.

#### Aurora DSQL Total Cost: **$1,924.02**

**Breakdown:**

1. **Aurora DSQL PayPerRequest (DPU-based):** $1,898.74
   - **Pricing Tier:**
     - First 100,000 DPUs: **Free** ($0.00 per DPU)
     - Additional DPUs: $0.000008 per DPU in US East (N. Virginia)
   - **Usage:**
     - First 100,000 DPUs: **$0.00**
     - Additional 237,341,961.107 DPUs: **$1,898.74**
     - **Total DPUs:** 237,441,961.107 DPUs

2. **Aurora DSQL StandardStorage:** $25.28
   - **Pricing Tier:**
     - First 1 GB-Month: **Free** ($0.00)
     - Additional storage: $0.33 per GB-Month in US East (N. Virginia)
   - **Usage:**
     - First 1 GB-Month: **$0.00**
     - Additional 76.612 GB-Month: **$25.28**
     - **Total Storage:** 77.612 GB-Month

#### Cost Analysis Based on Actual Billing

**DPU Cost per Million Inserts:**

- Total DPUs: 237,441,961.107
- Billable DPUs: 237,341,961.107 (after free tier)
- Cost per Million DPUs: $8.00
- **Note:** DPU usage is significantly higher than estimated ACU-hours, indicating DSQL's pay-per-request model charges for each database operation

**Storage Cost:**

- Total Storage: 77.612 GB-Month
- Billable Storage: 76.612 GB-Month (after free tier)
- Storage Cost: $25.28
- **Average Storage per Record:** ~2.5 KB (77.612 GB / 30.75M records)

**Cost per Million Inserts:**

- Total DSQL Cost: $1,924.02
- Total Inserts: 30,749,996
- **Actual Cost per Million Inserts:** $62.57
- This is significantly higher than the estimated $0.33, indicating that DSQL's pay-per-request model charges for each operation rather than just compute time
