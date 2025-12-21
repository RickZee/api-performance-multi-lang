package com.loadtest.dsql;

import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.ArrayList;
import java.util.List;

/**
 * Main load test class for DSQL.
 */
public class DSQLLoadTest {
    private static final Logger LOGGER = LoggerFactory.getLogger(DSQLLoadTest.class);
    
    private final DSQLConnection connection;
    private final String eventType;
    private final Integer payloadSize;
    
    public DSQLLoadTest(DSQLConnection connection, String eventType, Integer payloadSize) {
        this.connection = connection;
        this.eventType = eventType;
        this.payloadSize = payloadSize;
    }
    
    /**
     * Run Scenario 1: Individual inserts
     */
    public TestResult runScenario1(int iterations, int insertsPerIteration, int threadIndex) {
        LOGGER.info("Starting Scenario 1: thread={}, iterations={}, insertsPerIter={}, eventType={}, payloadSize={}", 
                   threadIndex, iterations, insertsPerIteration, eventType, payloadSize);
        
        long startTime = System.currentTimeMillis();
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger errorCount = new AtomicInteger(0);
        int totalExpected = iterations * insertsPerIteration;
        int logInterval = Math.max(1, iterations / 10); // Log every 10% progress
        
        try (Connection conn = connection.getConnection()) {
            for (int i = 0; i < iterations; i++) {
                for (int j = 0; j < insertsPerIteration; j++) {
                    try {
                        String eventId = String.format("load-test-individual-%d-%d-%d-%s", 
                                                       threadIndex, i, j, UUID.randomUUID().toString());
                        ObjectNode event = generateEvent(eventType, threadIndex, i, j, payloadSize);
                        
                        int inserted = EventRepository.insertIndividual(conn, eventId, event);
                        if (inserted > 0) {
                            successCount.incrementAndGet();
                        }
                    } catch (Exception e) {
                        LOGGER.error("Error inserting event: {}", e.getMessage(), e);
                        errorCount.incrementAndGet();
                    }
                }
                
                // Log progress every N iterations
                if ((i + 1) % logInterval == 0 || (i + 1) == iterations) {
                    int currentProgress = (i + 1) * insertsPerIteration;
                    double percentComplete = (currentProgress * 100.0) / totalExpected;
                    long elapsed = System.currentTimeMillis() - startTime;
                    double currentRate = currentProgress > 0 ? (currentProgress * 1000.0) / elapsed : 0;
                    LOGGER.info("Thread {} progress: {}/{} ({:.1f}%) - Success: {}, Errors: {}, Rate: {:.2f} inserts/sec", 
                               threadIndex, currentProgress, totalExpected, percentComplete, 
                               successCount.get(), errorCount.get(), currentRate);
                }
            }
        } catch (Exception e) {
            LOGGER.error("Connection error: {}", e.getMessage(), e);
            errorCount.addAndGet(iterations * insertsPerIteration);
        }
        
        long durationMs = System.currentTimeMillis() - startTime;
        double insertsPerSecond = (successCount.get() * 1000.0) / durationMs;
        
        LOGGER.info("Thread {} completed: Success={}, Errors={}, Duration={}ms, Rate={:.2f} inserts/sec", 
                   threadIndex, successCount.get(), errorCount.get(), durationMs, insertsPerSecond);
        
        return new TestResult(successCount.get(), errorCount.get(), durationMs, insertsPerSecond);
    }
    
    /**
     * Run Scenario 2: Batch inserts
     */
    public TestResult runScenario2(int iterations, int batchSize, int threadIndex) {
        LOGGER.info("Starting Scenario 2: thread={}, iterations={}, batchSize={}, eventType={}, payloadSize={}", 
                   threadIndex, iterations, batchSize, eventType, payloadSize);
        
        long startTime = System.currentTimeMillis();
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger errorCount = new AtomicInteger(0);
        int totalExpected = iterations * batchSize;
        int logInterval = Math.max(1, iterations / 10); // Log every 10% progress
        
        try (Connection conn = connection.getConnection()) {
            for (int i = 0; i < iterations; i++) {
                try {
                    String[] eventIds = new String[batchSize];
                    ObjectNode[] events = new ObjectNode[batchSize];
                    
                    for (int j = 0; j < batchSize; j++) {
                        eventIds[j] = String.format("load-test-batch-%d-%d-%d-%s", 
                                                    threadIndex, i, j, UUID.randomUUID().toString());
                        events[j] = generateEvent(eventType, threadIndex, i, j, payloadSize);
                    }
                    
                    int inserted = EventRepository.insertBatch(conn, eventIds, events);
                    successCount.addAndGet(inserted);
                } catch (Exception e) {
                    LOGGER.error("Error in batch insert: {}", e.getMessage(), e);
                    errorCount.addAndGet(batchSize);
                }
                
                // Log progress every N iterations
                if ((i + 1) % logInterval == 0 || (i + 1) == iterations) {
                    int currentProgress = (i + 1) * batchSize;
                    double percentComplete = (currentProgress * 100.0) / totalExpected;
                    long elapsed = System.currentTimeMillis() - startTime;
                    double currentRate = currentProgress > 0 ? (currentProgress * 1000.0) / elapsed : 0;
                    LOGGER.info("Thread {} progress: {}/{} ({:.1f}%) - Success: {}, Errors: {}, Rate: {:.2f} inserts/sec", 
                               threadIndex, currentProgress, totalExpected, percentComplete, 
                               successCount.get(), errorCount.get(), currentRate);
                }
            }
        } catch (Exception e) {
            LOGGER.error("Connection error: {}", e.getMessage(), e);
            errorCount.addAndGet(iterations * batchSize);
        }
        
        long durationMs = System.currentTimeMillis() - startTime;
        double insertsPerSecond = (successCount.get() * 1000.0) / durationMs;
        
        LOGGER.info("Thread {} completed: Success={}, Errors={}, Duration={}ms, Rate={:.2f} inserts/sec", 
                   threadIndex, successCount.get(), errorCount.get(), durationMs, insertsPerSecond);
        
        return new TestResult(successCount.get(), errorCount.get(), durationMs, insertsPerSecond);
    }
    
    /**
     * Generate event based on event type.
     */
    private ObjectNode generateEvent(String eventType, int threadIndex, int iteration, int insertIndex, Integer payloadSize) {
        if (eventType == null) {
            eventType = "CarCreated";
        }
        
        switch (eventType) {
            case "LoanCreated":
                String carId = "CAR-" + threadIndex + "-" + iteration + "-" + insertIndex;
                return EventGenerator.generateLoanCreatedEvent(carId, null, payloadSize);
            case "LoanPaymentSubmitted":
                String loanId = "LOAN-" + threadIndex + "-" + iteration + "-" + insertIndex;
                return EventGenerator.generateLoanPaymentEvent(loanId, null, payloadSize);
            case "CarServiceDone":
                String carIdForService = "CAR-" + threadIndex + "-" + iteration + "-" + insertIndex;
                return EventGenerator.generateCarServiceEvent(carIdForService, null, payloadSize);
            case "random":
                String[] types = {"CarCreated", "LoanCreated", "LoanPaymentSubmitted", "CarServiceDone"};
                String randomType = types[new java.util.Random().nextInt(types.length)];
                return generateEvent(randomType, threadIndex, iteration, insertIndex, payloadSize);
            case "CarCreated":
            default:
                return EventGenerator.generateCarCreatedEvent(null, payloadSize);
        }
    }
    
    /**
     * Run parallel load test
     */
    public static void main(String[] args) {
        // Get configuration from environment variables
        String dsqlHost = System.getenv("DSQL_HOST");
        String portStr = System.getenv("DSQL_PORT");
        String databaseName = System.getenv("DATABASE_NAME");
        String iamUsername = System.getenv("IAM_USERNAME");
        String region = System.getenv("AWS_REGION");
        String scenario = System.getenv("SCENARIO");
        String threadsStr = System.getenv("THREADS");
        String iterationsStr = System.getenv("ITERATIONS");
        String countStr = System.getenv("COUNT");
        String eventType = System.getenv("EVENT_TYPE");
        String payloadSizeStr = System.getenv("PAYLOAD_SIZE");
        String outputDir = System.getenv("OUTPUT_DIR");
        String testId = System.getenv("TEST_ID");
        
        // Defaults
        if (dsqlHost == null) dsqlHost = "vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws";
        if (portStr == null) portStr = "5432";
        if (databaseName == null) databaseName = "postgres";
        if (iamUsername == null) iamUsername = "lambda_dsql_user";
        if (region == null) region = "us-east-1";
        if (scenario == null) scenario = "both";
        if (threadsStr == null) threadsStr = "5";
        if (iterationsStr == null) iterationsStr = "2";
        if (countStr == null) countStr = "1";
        if (eventType == null) eventType = "CarCreated";
        
        // Parse payload size
        Integer payloadSize = EventGenerator.parsePayloadSize(payloadSizeStr);
        if (payloadSize == null && payloadSizeStr != null) {
            // Try to get from environment if not parsed
            payloadSize = EventGenerator.getTargetPayloadSize();
        }
        
        // Normalize scenario names (support both "1"/"2" and "individual"/"batch")
        if ("individual".equalsIgnoreCase(scenario)) {
            scenario = "1";
        } else if ("batch".equalsIgnoreCase(scenario)) {
            scenario = "2";
        }
        
        int port = Integer.parseInt(portStr);
        int threads = Integer.parseInt(threadsStr);
        int iterations = Integer.parseInt(iterationsStr);
        int count = Integer.parseInt(countStr);
        
        // Generate test ID if not provided
        if (testId == null || testId.isEmpty()) {
            testId = String.format("test-%s-threads%d-loops%d-count%d-%s", 
                                  scenario, threads, iterations, count, 
                                  payloadSize != null ? payloadSize + "bytes" : "default");
        }
        
        System.out.println("DSQL Load Test Configuration:");
        System.out.println("  Test ID: " + testId);
        System.out.println("  Host: " + dsqlHost);
        System.out.println("  Port: " + port);
        System.out.println("  Database: " + databaseName);
        System.out.println("  IAM User: " + iamUsername);
        System.out.println("  Region: " + region);
        System.out.println("  Scenario: " + scenario);
        System.out.println("  Threads: " + threads);
        System.out.println("  Iterations: " + iterations);
        System.out.println("  Count: " + count);
        System.out.println("  Event Type: " + eventType);
        if (payloadSize != null) {
            System.out.println("  Payload Size: " + payloadSize + " bytes (" + (payloadSize / 1024) + " KB)");
        } else {
            System.out.println("  Payload Size: default (~0.5-0.7 KB)");
        }
        if (outputDir != null && !outputDir.isEmpty()) {
            System.out.println("  Output Directory: " + outputDir);
        }
        System.out.println();
        
        // Initialize results collector
        TestResultsCollector collector = null;
        if (outputDir != null && !outputDir.isEmpty()) {
            collector = new TestResultsCollector(outputDir, testId);
            int scenarioNum = "1".equals(scenario) ? 1 : ("2".equals(scenario) ? 2 : 0);
            collector.setConfiguration(scenarioNum, threads, iterations, count, eventType, payloadSize,
                                       dsqlHost, databaseName, iamUsername, region);
        }
        
        DSQLConnection connection = new DSQLConnection(dsqlHost, port, databaseName, iamUsername, region);
        DSQLLoadTest test = new DSQLLoadTest(connection, eventType, payloadSize);
        
        ExecutorService executor = Executors.newFixedThreadPool(threads);
        List<Future<TestResult>> futures = new ArrayList<>();
        
        try {
            // Scenario 1: Individual inserts
            if ("1".equals(scenario) || "both".equals(scenario)) {
                System.out.println("=== Scenario 1: Individual Inserts ===");
                System.out.println("Starting " + threads + " threads, " + iterations + " iterations each, " + count + " inserts per iteration");
                int expectedRows1 = threads * iterations * count;
                System.out.println("Expected total: " + expectedRows1 + " rows");
                System.out.println();
                
                long startTime = System.currentTimeMillis();
                
                for (int i = 0; i < threads; i++) {
                    final int threadIndex = i;
                    futures.add(executor.submit(() -> test.runScenario1(iterations, count, threadIndex)));
                    if ((i + 1) % 10 == 0 || (i + 1) == threads) {
                        System.out.println("Started " + (i + 1) + "/" + threads + " threads...");
                    }
                }
                
                System.out.println("All threads started. Waiting for completion...");
                System.out.println();
                
                List<TestResult> results1 = new ArrayList<>();
                int completed = 0;
                for (Future<TestResult> future : futures) {
                    results1.add(future.get());
                    completed++;
                    if (completed % 10 == 0 || completed == threads) {
                        System.out.println("Completed " + completed + "/" + threads + " threads...");
                    }
                }
                
                long totalDuration = System.currentTimeMillis() - startTime;
                printResults("Scenario 1", results1, totalDuration);
                
                // Record results
                if (collector != null) {
                    int totalSuccess = results1.stream().mapToInt(r -> r.successCount).sum();
                    int totalErrors = results1.stream().mapToInt(r -> r.errorCount).sum();
                    double avgRate = results1.stream().mapToDouble(r -> r.insertsPerSecond).average().orElse(0);
                    double throughput = totalDuration > 0 ? (totalSuccess * 1000.0) / totalDuration : 0;
                    collector.recordScenarioResult(1, totalSuccess, totalErrors, totalDuration, 
                                                   throughput, avgRate, expectedRows1, totalSuccess, results1);
                }
                
                futures.clear();
            }
            
            // Scenario 2: Batch inserts
            if ("2".equals(scenario) || "both".equals(scenario)) {
                System.out.println("\n=== Scenario 2: Batch Inserts ===");
                System.out.println("Starting " + threads + " threads, " + iterations + " iterations each, " + count + " rows per batch");
                int expectedRows2 = threads * iterations * count;
                System.out.println("Expected total: " + expectedRows2 + " rows");
                System.out.println();
                
                long startTime = System.currentTimeMillis();
                
                for (int i = 0; i < threads; i++) {
                    final int threadIndex = i;
                    futures.add(executor.submit(() -> test.runScenario2(iterations, count, threadIndex)));
                    if ((i + 1) % 10 == 0 || (i + 1) == threads) {
                        System.out.println("Started " + (i + 1) + "/" + threads + " threads...");
                    }
                }
                
                System.out.println("All threads started. Waiting for completion...");
                System.out.println();
                
                List<TestResult> results2 = new ArrayList<>();
                int completed = 0;
                for (Future<TestResult> future : futures) {
                    results2.add(future.get());
                    completed++;
                    if (completed % 10 == 0 || completed == threads) {
                        System.out.println("Completed " + completed + "/" + threads + " threads...");
                    }
                }
                
                long totalDuration = System.currentTimeMillis() - startTime;
                printResults("Scenario 2", results2, totalDuration);
                
                // Record results
                if (collector != null) {
                    int totalSuccess = results2.stream().mapToInt(r -> r.successCount).sum();
                    int totalErrors = results2.stream().mapToInt(r -> r.errorCount).sum();
                    double avgRate = results2.stream().mapToDouble(r -> r.insertsPerSecond).average().orElse(0);
                    double throughput = totalDuration > 0 ? (totalSuccess * 1000.0) / totalDuration : 0;
                    collector.recordScenarioResult(2, totalSuccess, totalErrors, totalDuration, 
                                                   throughput, avgRate, expectedRows2, totalSuccess, results2);
                }
            }
            
            // Export results to JSON
            if (collector != null) {
                try {
                    // Calculate total expected and actual for validation
                    int totalExpected = 0;
                    int totalActual = 0;
                    if ("1".equals(scenario) || "both".equals(scenario)) {
                        totalExpected += threads * iterations * count;
                        if (collector.getMetrics().getResults() != null && 
                            collector.getMetrics().getResults().getScenario1() != null) {
                            totalActual += collector.getMetrics().getResults().getScenario1().getActualRows();
                        }
                    }
                    if ("2".equals(scenario) || "both".equals(scenario)) {
                        totalExpected += threads * iterations * count;
                        if (collector.getMetrics().getResults() != null && 
                            collector.getMetrics().getResults().getScenario2() != null) {
                            totalActual += collector.getMetrics().getResults().getScenario2().getActualRows();
                        }
                    }
                    collector.setDatabaseValidation(totalExpected, totalActual);
                    
                    collector.exportToJson();
                    System.out.println("\nResults exported to: " + outputDir + "/" + testId + ".json");
                } catch (Exception e) {
                    LOGGER.error("Failed to export results: {}", e.getMessage(), e);
                }
            }
            
        } catch (Exception e) {
            System.err.println("Test execution error: " + e.getMessage());
            e.printStackTrace();
        } finally {
            executor.shutdown();
            connection.close();
        }
    }
    
    private static void printResults(String scenarioName, List<TestResult> results, long totalDuration) {
        int totalSuccess = results.stream().mapToInt(r -> r.successCount).sum();
        int totalErrors = results.stream().mapToInt(r -> r.errorCount).sum();
        double avgInsertsPerSecond = results.stream().mapToDouble(r -> r.insertsPerSecond).average().orElse(0);
        double overallThroughput = totalDuration > 0 ? (totalSuccess * 1000.0) / totalDuration : 0;
        
        System.out.println();
        System.out.println(scenarioName + " Results:");
        System.out.println("  Total Success: " + totalSuccess);
        System.out.println("  Total Errors: " + totalErrors);
        System.out.println("  Total Duration: " + totalDuration + " ms");
        System.out.printf("  Avg Inserts/Second: %.2f%n", avgInsertsPerSecond);
        System.out.printf("  Overall Throughput: %.2f inserts/second%n", overallThroughput);
    }
    
    static class TestResult {
        final int successCount;
        final int errorCount;
        final long durationMs;
        final double insertsPerSecond;
        
        TestResult(int successCount, int errorCount, long durationMs, double insertsPerSecond) {
            this.successCount = successCount;
            this.errorCount = errorCount;
            this.durationMs = durationMs;
            this.insertsPerSecond = insertsPerSecond;
        }
    }
}

