package com.loadtest.dsql;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.ObjectWriter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Collects and exports test results to JSON and CSV formats.
 */
public class TestResultsCollector {
    private static final Logger LOGGER = LoggerFactory.getLogger(TestResultsCollector.class);
    private static final ObjectMapper mapper = new ObjectMapper();
    private static final ObjectWriter writer = mapper.writerWithDefaultPrettyPrinter();
    
    private final String outputDir;
    private final String testId;
    private PerformanceMetrics metrics;
    
    public TestResultsCollector(String outputDir, String testId) {
        this.outputDir = outputDir;
        this.testId = testId;
        this.metrics = new PerformanceMetrics();
        this.metrics.setTestId(testId);
        this.metrics.setTimestamp(Instant.now().toString());
    }
    
    /**
     * Set test configuration.
     */
    public void setConfiguration(int scenario, int threads, int iterations, int count,
                                 String eventType, Integer payloadSize,
                                 String dsqlHost, String databaseName, String iamUsername, String awsRegion) {
        PerformanceMetrics.TestConfiguration config = new PerformanceMetrics.TestConfiguration();
        config.setScenario(scenario);
        config.setThreads(threads);
        config.setIterations(iterations);
        config.setCount(count);
        if (scenario == 2) {
            config.setBatchSize(count);
        }
        config.setEventType(eventType);
        config.setPayloadSize(payloadSize != null ? payloadSize + " bytes (" + (payloadSize / 1024) + " KB)" : "default");
        config.setDsqlHost(dsqlHost);
        config.setDatabaseName(databaseName);
        config.setIamUsername(iamUsername);
        config.setAwsRegion(awsRegion);
        
        metrics.setConfiguration(config);
    }
    
    /**
     * Record scenario results.
     */
    public void recordScenarioResult(int scenario, int totalSuccess, int totalErrors, 
                                     long durationMs, double throughput, double avgRate,
                                     int expectedRows, int actualRows,
                                     List<DSQLLoadTest.TestResult> threadResults) {
        PerformanceMetrics.TestResults testResults = metrics.getResults();
        if (testResults == null) {
            testResults = new PerformanceMetrics.TestResults();
            metrics.setResults(testResults);
        }
        
        PerformanceMetrics.ScenarioResult scenarioResult = new PerformanceMetrics.ScenarioResult();
        scenarioResult.setTotalSuccess(totalSuccess);
        scenarioResult.setTotalErrors(totalErrors);
        scenarioResult.setDurationMs(durationMs);
        scenarioResult.setThroughputInsertsPerSec(throughput);
        scenarioResult.setAvgInsertsPerSec(avgRate);
        scenarioResult.setExpectedRows(expectedRows);
        scenarioResult.setActualRows(actualRows);
        
        // Store per-thread results if available
        if (threadResults != null && !threadResults.isEmpty()) {
            Map<Integer, PerformanceMetrics.ThreadResult> threadMap = new HashMap<>();
            for (int i = 0; i < threadResults.size(); i++) {
                DSQLLoadTest.TestResult result = threadResults.get(i);
                PerformanceMetrics.ThreadResult threadResult = new PerformanceMetrics.ThreadResult();
                threadResult.setThreadIndex(i);
                threadResult.setSuccessCount(result.successCount);
                threadResult.setErrorCount(result.errorCount);
                threadResult.setDurationMs(result.durationMs);
                threadResult.setInsertsPerSec(result.insertsPerSecond);
                threadMap.put(i, threadResult);
            }
            scenarioResult.setThreadResults(threadMap);
        }
        
        if (scenario == 1) {
            testResults.setScenario1(scenarioResult);
        } else if (scenario == 2) {
            testResults.setScenario2(scenarioResult);
        }
    }
    
    /**
     * Set database validation results.
     */
    public void setDatabaseValidation(int expected, int actual) {
        PerformanceMetrics.DatabaseValidation validation = new PerformanceMetrics.DatabaseValidation();
        validation.setExpected(expected);
        validation.setActual(actual);
        validation.setStatus(expected == actual ? "PASSED" : 
                           (Math.abs(actual - expected) <= 10 ? "PASSED_WITH_TOLERANCE" : "FAILED"));
        metrics.setDatabaseValidation(validation);
    }
    
    /**
     * Export results to JSON file.
     */
    public void exportToJson() throws IOException {
        if (outputDir == null || outputDir.isEmpty()) {
            LOGGER.warn("Output directory not set, skipping JSON export");
            return;
        }
        
        // Create output directory if it doesn't exist
        Path dir = Paths.get(outputDir);
        Files.createDirectories(dir);
        
        // Generate filename
        String filename = String.format("%s.json", testId);
        File outputFile = dir.resolve(filename).toFile();
        
        // Write JSON
        writer.writeValue(outputFile, metrics);
        LOGGER.info("Exported test results to: {}", outputFile.getAbsolutePath());
    }
    
    /**
     * Export results to CSV (summary format).
     */
    public void exportToCsv(File csvFile) throws IOException {
        if (csvFile == null) {
            return;
        }
        
        boolean fileExists = csvFile.exists();
        
        try (FileWriter writer = new FileWriter(csvFile, true)) {
            // Write header if file is new
            if (!fileExists) {
                writer.append("test_id,timestamp,scenario,threads,iterations,count,batch_size,event_type,payload_size,")
                      .append("total_success,total_errors,duration_ms,throughput_inserts_per_sec,avg_inserts_per_sec,")
                      .append("expected_rows,actual_rows,validation_status\n");
            }
            
            // Write data
            PerformanceMetrics.TestConfiguration config = metrics.getConfiguration();
            PerformanceMetrics.TestResults results = metrics.getResults();
            
            if (results != null) {
                if (results.getScenario1() != null) {
                    writeCsvRow(writer, results.getScenario1(), 1, config);
                }
                if (results.getScenario2() != null) {
                    writeCsvRow(writer, results.getScenario2(), 2, config);
                }
            }
        }
    }
    
    private void writeCsvRow(FileWriter writer, PerformanceMetrics.ScenarioResult result, 
                            int scenario, PerformanceMetrics.TestConfiguration config) throws IOException {
        writer.append(escapeCsv(metrics.getTestId())).append(",")
              .append(escapeCsv(metrics.getTimestamp())).append(",")
              .append(String.valueOf(scenario)).append(",")
              .append(String.valueOf(config.getThreads())).append(",")
              .append(String.valueOf(config.getIterations())).append(",")
              .append(String.valueOf(config.getCount())).append(",")
              .append(config.getBatchSize() != null ? String.valueOf(config.getBatchSize()) : "").append(",")
              .append(escapeCsv(config.getEventType())).append(",")
              .append(escapeCsv(config.getPayloadSize())).append(",")
              .append(String.valueOf(result.getTotalSuccess())).append(",")
              .append(String.valueOf(result.getTotalErrors())).append(",")
              .append(String.valueOf(result.getDurationMs())).append(",")
              .append(String.valueOf(result.getThroughputInsertsPerSec())).append(",")
              .append(String.valueOf(result.getAvgInsertsPerSec())).append(",")
              .append(String.valueOf(result.getExpectedRows())).append(",")
              .append(String.valueOf(result.getActualRows())).append(",")
              .append(escapeCsv(metrics.getDatabaseValidation() != null ? 
                      metrics.getDatabaseValidation().getStatus() : "")).append("\n");
    }
    
    private String escapeCsv(String value) {
        if (value == null) {
            return "";
        }
        if (value.contains(",") || value.contains("\"") || value.contains("\n")) {
            return "\"" + value.replace("\"", "\"\"") + "\"";
        }
        return value;
    }
    
    public PerformanceMetrics getMetrics() {
        return metrics;
    }
}

