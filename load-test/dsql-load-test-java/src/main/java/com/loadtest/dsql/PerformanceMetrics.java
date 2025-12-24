package com.loadtest.dsql;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.Instant;
import java.util.Map;

/**
 * Performance metrics data model for test results.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public class PerformanceMetrics {
    
    @JsonProperty("test_id")
    private String testId;
    
    @JsonProperty("timestamp")
    private String timestamp;
    
    @JsonProperty("configuration")
    private TestConfiguration configuration;
    
    @JsonProperty("results")
    private TestResults results;
    
        @JsonProperty("database_validation")
        private DatabaseValidation databaseValidation;
        
    @JsonProperty("pool_metrics")
    private PoolMetrics poolMetrics;
    
    @JsonProperty("system_metrics")
    private SystemMetrics systemMetrics;
    
    public PerformanceMetrics() {
        this.timestamp = Instant.now().toString();
    }
    
    public String getTestId() {
        return testId;
    }
    
    public void setTestId(String testId) {
        this.testId = testId;
    }
    
    public String getTimestamp() {
        return timestamp;
    }
    
    public void setTimestamp(String timestamp) {
        this.timestamp = timestamp;
    }
    
    public TestConfiguration getConfiguration() {
        return configuration;
    }
    
    public void setConfiguration(TestConfiguration configuration) {
        this.configuration = configuration;
    }
    
    public TestResults getResults() {
        return results;
    }
    
    public void setResults(TestResults results) {
        this.results = results;
    }
    
    public DatabaseValidation getDatabaseValidation() {
        return databaseValidation;
    }
    
    public void setDatabaseValidation(DatabaseValidation databaseValidation) {
        this.databaseValidation = databaseValidation;
    }
    
    public PoolMetrics getPoolMetrics() {
        return poolMetrics;
    }
    
    public void setPoolMetrics(PoolMetrics poolMetrics) {
        this.poolMetrics = poolMetrics;
    }
    
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class TestConfiguration {
        @JsonProperty("scenario")
        private Integer scenario;
        
        @JsonProperty("threads")
        private Integer threads;
        
        @JsonProperty("iterations")
        private Integer iterations;
        
        @JsonProperty("count")
        private Integer count;
        
        @JsonProperty("batch_size")
        private Integer batchSize;
        
        @JsonProperty("event_type")
        private String eventType;
        
        @JsonProperty("payload_size")
        private String payloadSize;
        
        @JsonProperty("dsql_host")
        private String dsqlHost;
        
        @JsonProperty("database_name")
        private String databaseName;
        
        @JsonProperty("iam_username")
        private String iamUsername;
        
        @JsonProperty("aws_region")
        private String awsRegion;
        
        // Getters and setters
        public Integer getScenario() { return scenario; }
        public void setScenario(Integer scenario) { this.scenario = scenario; }
        
        public Integer getThreads() { return threads; }
        public void setThreads(Integer threads) { this.threads = threads; }
        
        public Integer getIterations() { return iterations; }
        public void setIterations(Integer iterations) { this.iterations = iterations; }
        
        public Integer getCount() { return count; }
        public void setCount(Integer count) { this.count = count; }
        
        public Integer getBatchSize() { return batchSize; }
        public void setBatchSize(Integer batchSize) { this.batchSize = batchSize; }
        
        public String getEventType() { return eventType; }
        public void setEventType(String eventType) { this.eventType = eventType; }
        
        public String getPayloadSize() { return payloadSize; }
        public void setPayloadSize(String payloadSize) { this.payloadSize = payloadSize; }
        
        public String getDsqlHost() { return dsqlHost; }
        public void setDsqlHost(String dsqlHost) { this.dsqlHost = dsqlHost; }
        
        public String getDatabaseName() { return databaseName; }
        public void setDatabaseName(String databaseName) { this.databaseName = databaseName; }
        
        public String getIamUsername() { return iamUsername; }
        public void setIamUsername(String iamUsername) { this.iamUsername = iamUsername; }
        
        public String getAwsRegion() { return awsRegion; }
        public void setAwsRegion(String awsRegion) { this.awsRegion = awsRegion; }
    }
    
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class TestResults {
        @JsonProperty("scenario_1")
        private ScenarioResult scenario1;
        
        @JsonProperty("scenario_2")
        private ScenarioResult scenario2;
        
        public ScenarioResult getScenario1() { return scenario1; }
        public void setScenario1(ScenarioResult scenario1) { this.scenario1 = scenario1; }
        
        public ScenarioResult getScenario2() { return scenario2; }
        public void setScenario2(ScenarioResult scenario2) { this.scenario2 = scenario2; }
    }
    
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class ScenarioResult {
        @JsonProperty("total_success")
        private Integer totalSuccess;
        
        @JsonProperty("total_errors")
        private Integer totalErrors;
        
        @JsonProperty("errors_by_category")
        private Map<String, Integer> errorsByCategory;
        
        @JsonProperty("duration_ms")
        private Long durationMs;
        
        @JsonProperty("throughput_inserts_per_sec")
        private Double throughputInsertsPerSec;
        
        @JsonProperty("avg_inserts_per_sec")
        private Double avgInsertsPerSec;
        
        @JsonProperty("expected_rows")
        private Integer expectedRows;
        
        @JsonProperty("actual_rows")
        private Integer actualRows;
        
        @JsonProperty("thread_results")
        private Map<Integer, ThreadResult> threadResults;
        
        @JsonProperty("latency_stats")
        private LatencyStats latencyStats;
        
        // Getters and setters
        public Integer getTotalSuccess() { return totalSuccess; }
        public void setTotalSuccess(Integer totalSuccess) { this.totalSuccess = totalSuccess; }
        
        public Integer getTotalErrors() { return totalErrors; }
        public void setTotalErrors(Integer totalErrors) { this.totalErrors = totalErrors; }
        
        public Map<String, Integer> getErrorsByCategory() { return errorsByCategory; }
        public void setErrorsByCategory(Map<String, Integer> errorsByCategory) { this.errorsByCategory = errorsByCategory; }
        
        public Long getDurationMs() { return durationMs; }
        public void setDurationMs(Long durationMs) { this.durationMs = durationMs; }
        
        public Double getThroughputInsertsPerSec() { return throughputInsertsPerSec; }
        public void setThroughputInsertsPerSec(Double throughputInsertsPerSec) { this.throughputInsertsPerSec = throughputInsertsPerSec; }
        
        public Double getAvgInsertsPerSec() { return avgInsertsPerSec; }
        public void setAvgInsertsPerSec(Double avgInsertsPerSec) { this.avgInsertsPerSec = avgInsertsPerSec; }
        
        public Integer getExpectedRows() { return expectedRows; }
        public void setExpectedRows(Integer expectedRows) { this.expectedRows = expectedRows; }
        
        public Integer getActualRows() { return actualRows; }
        public void setActualRows(Integer actualRows) { this.actualRows = actualRows; }
        
        public Map<Integer, ThreadResult> getThreadResults() { return threadResults; }
        public void setThreadResults(Map<Integer, ThreadResult> threadResults) { this.threadResults = threadResults; }
        
        public LatencyStats getLatencyStats() { return latencyStats; }
        public void setLatencyStats(LatencyStats latencyStats) { this.latencyStats = latencyStats; }
    }
    
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class ThreadResult {
        @JsonProperty("thread_index")
        private Integer threadIndex;
        
        @JsonProperty("success_count")
        private Integer successCount;
        
        @JsonProperty("error_count")
        private Integer errorCount;
        
        @JsonProperty("duration_ms")
        private Long durationMs;
        
        @JsonProperty("inserts_per_sec")
        private Double insertsPerSec;
        
        @JsonProperty("min_latency_ms")
        private Long minLatencyMs;
        
        @JsonProperty("max_latency_ms")
        private Long maxLatencyMs;
        
        @JsonProperty("p50_latency_ms")
        private Long p50LatencyMs;
        
        @JsonProperty("p95_latency_ms")
        private Long p95LatencyMs;
        
        @JsonProperty("p99_latency_ms")
        private Long p99LatencyMs;
        
        // Getters and setters
        public Integer getThreadIndex() { return threadIndex; }
        public void setThreadIndex(Integer threadIndex) { this.threadIndex = threadIndex; }
        
        public Integer getSuccessCount() { return successCount; }
        public void setSuccessCount(Integer successCount) { this.successCount = successCount; }
        
        public Integer getErrorCount() { return errorCount; }
        public void setErrorCount(Integer errorCount) { this.errorCount = errorCount; }
        
        public Long getDurationMs() { return durationMs; }
        public void setDurationMs(Long durationMs) { this.durationMs = durationMs; }
        
        public Double getInsertsPerSec() { return insertsPerSec; }
        public void setInsertsPerSec(Double insertsPerSec) { this.insertsPerSec = insertsPerSec; }
        
        public Long getMinLatencyMs() { return minLatencyMs; }
        public void setMinLatencyMs(Long minLatencyMs) { this.minLatencyMs = minLatencyMs; }
        
        public Long getMaxLatencyMs() { return maxLatencyMs; }
        public void setMaxLatencyMs(Long maxLatencyMs) { this.maxLatencyMs = maxLatencyMs; }
        
        public Long getP50LatencyMs() { return p50LatencyMs; }
        public void setP50LatencyMs(Long p50LatencyMs) { this.p50LatencyMs = p50LatencyMs; }
        
        public Long getP95LatencyMs() { return p95LatencyMs; }
        public void setP95LatencyMs(Long p95LatencyMs) { this.p95LatencyMs = p95LatencyMs; }
        
        public Long getP99LatencyMs() { return p99LatencyMs; }
        public void setP99LatencyMs(Long p99LatencyMs) { this.p99LatencyMs = p99LatencyMs; }
    }
    
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class LatencyStats {
        @JsonProperty("min_latency_ms")
        private Long minLatencyMs;
        
        @JsonProperty("max_latency_ms")
        private Long maxLatencyMs;
        
        @JsonProperty("p50_latency_ms")
        private Long p50LatencyMs;
        
        @JsonProperty("p95_latency_ms")
        private Long p95LatencyMs;
        
        @JsonProperty("p99_latency_ms")
        private Long p99LatencyMs;
        
        // Getters and setters
        public Long getMinLatencyMs() { return minLatencyMs; }
        public void setMinLatencyMs(Long minLatencyMs) { this.minLatencyMs = minLatencyMs; }
        
        public Long getMaxLatencyMs() { return maxLatencyMs; }
        public void setMaxLatencyMs(Long maxLatencyMs) { this.maxLatencyMs = maxLatencyMs; }
        
        public Long getP50LatencyMs() { return p50LatencyMs; }
        public void setP50LatencyMs(Long p50LatencyMs) { this.p50LatencyMs = p50LatencyMs; }
        
        public Long getP95LatencyMs() { return p95LatencyMs; }
        public void setP95LatencyMs(Long p95LatencyMs) { this.p95LatencyMs = p95LatencyMs; }
        
        public Long getP99LatencyMs() { return p99LatencyMs; }
        public void setP99LatencyMs(Long p99LatencyMs) { this.p99LatencyMs = p99LatencyMs; }
    }
    
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class DatabaseValidation {
        @JsonProperty("expected")
        private Integer expected;
        
        @JsonProperty("actual")
        private Integer actual;
        
        @JsonProperty("status")
        private String status;
        
        // Getters and setters
        public Integer getExpected() { return expected; }
        public void setExpected(Integer expected) { this.expected = expected; }
        
        public Integer getActual() { return actual; }
        public void setActual(Integer actual) { this.actual = actual; }
        
        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
    }
    
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class PoolMetrics {
        @JsonProperty("active_connections")
        private Integer activeConnections;
        
        @JsonProperty("idle_connections")
        private Integer idleConnections;
        
        @JsonProperty("waiting_threads")
        private Integer waitingThreads;
        
        @JsonProperty("total_connections")
        private Integer totalConnections;
        
        @JsonProperty("max_pool_size")
        private Integer maxPoolSize;
        
        // Getters and setters
        public Integer getActiveConnections() { return activeConnections; }
        public void setActiveConnections(Integer activeConnections) { this.activeConnections = activeConnections; }
        
        public Integer getIdleConnections() { return idleConnections; }
        public void setIdleConnections(Integer idleConnections) { this.idleConnections = idleConnections; }
        
        public Integer getWaitingThreads() { return waitingThreads; }
        public void setWaitingThreads(Integer waitingThreads) { this.waitingThreads = waitingThreads; }
        
        public Integer getTotalConnections() { return totalConnections; }
        public void setTotalConnections(Integer totalConnections) { this.totalConnections = totalConnections; }
        
        public Integer getMaxPoolSize() { return maxPoolSize; }
        public void setMaxPoolSize(Integer maxPoolSize) { this.maxPoolSize = maxPoolSize; }
    }
    
    public SystemMetrics getSystemMetrics() { return systemMetrics; }
    public void setSystemMetrics(SystemMetrics systemMetrics) { this.systemMetrics = systemMetrics; }
}

