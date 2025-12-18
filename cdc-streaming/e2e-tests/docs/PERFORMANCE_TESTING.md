# Performance Testing Guide

This guide provides detailed methodology for performance testing of the CDC streaming architecture, including throughput, latency, and load testing procedures.

## Throughput Testing

### Test Methodology

Throughput testing measures the number of events processed per second by the stream processors.

**Key Metrics**:
- Events published per second
- Events processed per second
- Processing rate (events/sec)
- Consumer lag (if applicable)

### Baseline Establishment

1. **Warm-up Period**: Run initial load for 1-2 minutes to warm up JVM, Kafka, and processors
2. **Measurement Period**: Run sustained load for 5-10 minutes
3. **Cool-down Period**: Allow system to process remaining events

**Example Test**:
```java
@Test
void testSustainedThroughput() {
    int targetRate = 10000; // events/sec
    int durationSeconds = 300; // 5 minutes
    
    // Publish events at target rate
    // Measure actual processing rate
    // Compare against SLA target
}
```

### Scaling Considerations

- **Partition Count**: More partitions enable better parallelism
  - Test with 3, 6, 12 partitions
  - Measure throughput improvement
- **Processor Instances**: Multiple Spring Boot instances
  - Test with 1, 2, 4 instances
  - Measure linear scaling
- **Kafka Cluster Capacity**: CKU level affects throughput
  - Test with different CKU configurations
  - Measure cost vs. performance trade-off

## Latency Testing

### Measurement Methodology

Latency is measured as the time from event publication to event appearance in filtered topic.

**Measurement Points**:
1. **Publish Time**: `System.currentTimeMillis()` when event is published
2. **Receive Time**: `System.currentTimeMillis()` when event is consumed from filtered topic
3. **Latency**: `receiveTime - publishTime`

### Percentile Calculations

```java
// Sort latencies
Collections.sort(latencies);

// Calculate percentile
long p50 = percentile(latencies, 50);  // Median
long p95 = percentile(latencies, 95);  // 95th percentile
long p99 = percentile(latencies, 99);  // 99th percentile

private long percentile(List<Long> sortedList, int percentile) {
    int index = (int) Math.ceil((percentile / 100.0) * sortedList.size()) - 1;
    return sortedList.get(Math.max(0, Math.min(index, sortedList.size() - 1)));
}
```

### Network Considerations

- **Network Latency**: Account for network round-trip time to Confluent Cloud
  - Typical: 10-50ms depending on region
  - Measure baseline network latency separately
- **Jitter**: Network jitter can affect latency consistency
  - Test with simulated jitter
  - Measure impact on P95/P99 latencies
- **Geographic Distance**: Test from different regions
  - Measure latency from different test locations
  - Consider multi-region deployment

## Load Testing

### Ramp-up Strategies

**Gradual Ramp-up**:
1. Start at 1K events/sec
2. Increase by 5K events/sec every 10 seconds
3. Reach target rate (e.g., 50K events/sec)
4. Maintain target rate for 5 minutes

**Benefits**:
- Identifies breaking points gradually
- Allows system to adapt to load
- Reduces risk of overwhelming system

### Endurance Test Procedures

**Test Duration**: 1 hour (or longer for production validation)

**Procedure**:
1. Establish baseline throughput (e.g., 10K events/sec)
2. Run sustained load for 1 hour
3. Monitor:
   - Throughput consistency
   - Latency degradation
   - Error rate
   - Resource usage (CPU, memory, network)
4. Verify no memory leaks or performance degradation

**Success Criteria**:
- Throughput remains stable (±5%)
- Latency does not degrade significantly
- Error rate remains < 0.01%
- No memory leaks

### Resource Monitoring During Tests

**Key Metrics to Monitor**:
- **CPU Usage**: Should remain < 80% average
- **Memory Usage**: Should remain stable (no leaks)
- **Network I/O**: Monitor bandwidth usage
- **Kafka Consumer Lag**: Should remain low (< 1000 messages)
- **JVM GC**: Monitor GC frequency and pause times

**Tools**:
- Prometheus + Grafana for metrics
- JVM profiling tools (JProfiler, VisualVM)
- Kafka consumer lag monitoring

## Interpreting Results

### What Good Looks Like

**Throughput**:
- Consistent rate (±5% variance)
- Meets or exceeds SLA target (10K events/sec)
- Scales linearly with partitions/instances

**Latency**:
- P50 < 50ms
- P95 < 200ms
- P99 < 500ms
- Low variance (consistent performance)

**Error Rate**:
- < 0.01% errors
- No data loss
- All events eventually processed

### Warning Signs

**Throughput Issues**:
- Declining throughput over time
- High variance in processing rate
- Consumer lag increasing

**Latency Issues**:
- P95/P99 latencies increasing
- High variance in latency
- Latency spikes under load

**Resource Issues**:
- CPU usage > 90%
- Memory usage increasing (potential leak)
- High GC frequency/pause times
- Network saturation

### Optimization Recommendations

**If Throughput is Low**:
1. Increase partition count
2. Add more processor instances
3. Optimize Kafka producer/consumer settings
4. Review filtering logic efficiency
5. Consider Kafka cluster capacity upgrade

**If Latency is High**:
1. Reduce batch sizes
2. Optimize network path to Kafka
3. Review Kafka Streams configuration
4. Check for blocking operations
5. Consider regional deployment

**If Errors Occur**:
1. Review error logs
2. Check Kafka connectivity
3. Verify schema compatibility
4. Review resource limits
5. Check for backpressure

## Test Execution Best Practices

1. **Isolate Tests**: Run performance tests in isolation
2. **Warm-up**: Always include warm-up period
3. **Multiple Runs**: Run tests multiple times for consistency
4. **Baseline Comparison**: Compare against previous baselines
5. **Document Results**: Record all metrics and conditions
6. **Monitor Resources**: Always monitor system resources during tests
7. **Clean Environment**: Start with clean Kafka topics/offsets

## Example Test Execution

```bash
# Run throughput test
./gradlew test --tests PerformanceComparisonTest#testSustainedThroughput

# Run latency test
./gradlew test --tests LatencyBenchmarkTest#testLatencyPercentiles

# Run load test
./gradlew test --tests LoadTest#testRampUpLoad

# Run endurance test (long duration)
./gradlew test --tests LoadTest#testEnduranceTest
```

## Performance Test Checklist

- [ ] Environment variables configured
- [ ] Flink SQL statements deployed
- [ ] Spring Boot service running
- [ ] Topics created and accessible
- [ ] Baseline metrics recorded
- [ ] Resource monitoring enabled
- [ ] Test data prepared
- [ ] Warm-up period completed
- [ ] Test executed
- [ ] Results documented
- [ ] Comparison with SLA targets
- [ ] Optimization recommendations documented
