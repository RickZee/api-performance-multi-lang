package com.loadtest.dsql;

import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.ArrayList;
import java.util.List;
import java.util.Collections;
import java.util.Map;
import java.util.HashMap;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Main load test class for DSQL.
 */
public class DSQLLoadTest {
    private static final Logger LOGGER = LoggerFactory.getLogger(DSQLLoadTest.class);
    
    private final DatabaseConnection connection;
    private final String eventType;
    private final Integer payloadSize;
    
    public DSQLLoadTest(DatabaseConnection connection, String eventType, Integer payloadSize) {
        this.connection = connection;
        this.eventType = eventType;
        this.payloadSize = payloadSize;
    }
    
    /**
     * Run Scenario 1: Individual inserts with connection resilience for extreme scaling.
     */
    public TestResult runScenario1(int iterations, int insertsPerIteration, int threadIndex) {
        return runScenario1(iterations, insertsPerIteration, threadIndex, 0);
    }
    
    /**
     * Run Scenario 1: Individual inserts with connection resilience for extreme scaling.
     * @param warmupIterations Number of warm-up iterations to run before measurement (not counted in metrics)
     */
    public TestResult runScenario1(int iterations, int insertsPerIteration, int threadIndex, int warmupIterations) {
        LOGGER.info("Starting Scenario 1: thread={}, iterations={}, insertsPerIter={}, eventType={}, payloadSize={}", 
                   threadIndex, iterations, insertsPerIteration, eventType, payloadSize);
        
        // Warm-up phase (not counted in metrics)
        if (warmupIterations > 0) {
            LOGGER.info("Thread {} running {} warm-up iterations", threadIndex, warmupIterations);
            Connection warmupConn = null;
            try {
                warmupConn = getConnectionWithRetry(threadIndex, new AtomicInteger(0));
                if (warmupConn != null) {
                    for (int w = 0; w < warmupIterations; w++) {
                        for (int j = 0; j < insertsPerIteration; j++) {
                            try {
                                String eventId = String.format("load-test-warmup-%d-%d-%d-%s", 
                                                               threadIndex, w, j, UUID.randomUUID().toString());
                                ObjectNode event = generateEvent(eventType, threadIndex, w, j, payloadSize);
                                EventRepository.insertIndividual(warmupConn, eventId, event);
                            } catch (Exception e) {
                                // Ignore warm-up errors
                            }
                        }
                    }
                }
            } catch (Exception e) {
                LOGGER.debug("Thread {} warm-up error (ignored): {}", threadIndex, e.getMessage());
            } finally {
                if (warmupConn != null) {
                    try {
                        warmupConn.close();
                    } catch (Exception ignore) {}
                }
            }
            LOGGER.info("Thread {} completed warm-up phase", threadIndex);
        }
        
        long startTime = System.currentTimeMillis();
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger errorCount = new AtomicInteger(0);
        AtomicInteger connectionRetries = new AtomicInteger(0);
        int totalExpected = iterations * insertsPerIteration;
        int logInterval = Math.max(1, iterations / 10); // Log every 10% progress
        List<Long> latencies = Collections.synchronizedList(new ArrayList<>());
        Map<ErrorCategory, AtomicInteger> errorsByCategory = new ConcurrentHashMap<>();
        
        Connection conn = null;
        try {
            conn = getConnectionWithRetry(threadIndex, connectionRetries);
            
            if (conn == null) {
                LOGGER.error("Thread {} could not get initial connection after retries", threadIndex);
                errorCount.addAndGet(totalExpected);
                return new TestResult(0, totalExpected, System.currentTimeMillis() - startTime, 0);
            }
            
            for (int i = 0; i < iterations; i++) {
                for (int j = 0; j < insertsPerIteration; j++) {
                    try {
                        // Validate connection before use
                        if (conn == null || conn.isClosed()) {
                            conn = getConnectionWithRetry(threadIndex, connectionRetries);
                            if (conn == null) {
                                errorCount.incrementAndGet();
                                continue;
                            }
                        }
                        
                        String eventId = String.format("load-test-individual-%d-%d-%d-%s", 
                                                       threadIndex, i, j, UUID.randomUUID().toString());
                        ObjectNode event = generateEvent(eventType, threadIndex, i, j, payloadSize);
                        
                        long opStartTime = System.currentTimeMillis();
                        int inserted = EventRepository.insertIndividual(conn, eventId, event);
                        long opLatency = System.currentTimeMillis() - opStartTime;
                        
                        // Validate insert only if executeUpdate returned 0 (might be conflict or failure)
                        // This avoids doubling database operations for successful inserts
                        if (inserted > 0) {
                            // Insert succeeded - count as success
                            successCount.incrementAndGet();
                            latencies.add(opLatency);
                        } else {
                            // Insert returned 0 - verify if it actually exists (might be ON CONFLICT DO NOTHING)
                            boolean verified = false;
                            try {
                                verified = EventRepository.verifyInsert(conn, eventId);
                            } catch (Exception verifyEx) {
                                LOGGER.debug("Thread {} failed to verify insert for {}: {}", threadIndex, eventId, verifyEx.getMessage());
                            }
                            
                            if (verified) {
                                // Row exists (likely conflict) - count as success
                                successCount.incrementAndGet();
                                latencies.add(opLatency);
                            } else {
                                // Insert actually failed - don't proceed
                                errorCount.incrementAndGet();
                                errorsByCategory.computeIfAbsent(ErrorCategory.QUERY_ERROR, k -> new AtomicInteger(0)).incrementAndGet();
                                LOGGER.warn("Thread {} insert failed for {}, not proceeding", threadIndex, eventId);
                            }
                        }
                    } catch (Exception e) {
                        LOGGER.debug("Thread {} error inserting event: {}", threadIndex, e.getMessage());
                        errorCount.incrementAndGet();
                        
                        // Categorize and track error
                        ErrorCategory category = ErrorCategory.categorize(e);
                        errorsByCategory.computeIfAbsent(category, k -> new AtomicInteger(0)).incrementAndGet();
                        
                        // Try to reconnect if the connection might be stale
                        if (conn != null) {
                            try {
                                conn.close();
                            } catch (Exception ignore) {}
                            conn = null;
                        }
                    }
                }
                
                // Log progress every N iterations
                if ((i + 1) % logInterval == 0 || (i + 1) == iterations) {
                    int currentProgress = (i + 1) * insertsPerIteration;
                    double percentComplete = (currentProgress * 100.0) / totalExpected;
                    long elapsed = System.currentTimeMillis() - startTime;
                    double currentRate = successCount.get() > 0 ? (successCount.get() * 1000.0) / elapsed : 0;
                    LOGGER.info("Thread {} progress: {}/{} ({:.1f}%) - Success: {}, Errors: {}, Rate: {:.2f} inserts/sec, Retries: {}", 
                               threadIndex, currentProgress, totalExpected, percentComplete, 
                               successCount.get(), errorCount.get(), currentRate, connectionRetries.get());
                }
            }
        } catch (Exception e) {
            LOGGER.error("Thread {} fatal error: {}", threadIndex, e.getMessage());
            // Only count remaining operations as errors
            int completed = successCount.get() + errorCount.get();
            int remaining = totalExpected - completed;
            errorCount.addAndGet(remaining);
        } finally {
            if (conn != null) {
                try {
                    conn.close();
                } catch (Exception ignore) {}
            }
        }
        
        long durationMs = System.currentTimeMillis() - startTime;
        double insertsPerSecond = durationMs > 0 ? (successCount.get() * 1000.0) / durationMs : 0;
        
        LOGGER.info("Thread {} completed: Success={}, Errors={}, Duration={}ms, Rate={:.2f} inserts/sec, ConnectionRetries={}", 
                   threadIndex, successCount.get(), errorCount.get(), durationMs, insertsPerSecond, connectionRetries.get());
        
        // Calculate latency percentiles
        long minLatency = 0, maxLatency = 0, p50 = 0, p95 = 0, p99 = 0;
        if (!latencies.isEmpty()) {
            Collections.sort(latencies);
            minLatency = latencies.get(0);
            maxLatency = latencies.get(latencies.size() - 1);
            p50 = latencies.get((int) (latencies.size() * 0.50));
            p95 = latencies.get((int) (latencies.size() * 0.95));
            p99 = latencies.get((int) (latencies.size() * 0.99));
        }
        
        // Convert error category map to string map for JSON serialization
        Map<String, Integer> errorsByCategoryMap = new HashMap<>();
        for (Map.Entry<ErrorCategory, AtomicInteger> entry : errorsByCategory.entrySet()) {
            errorsByCategoryMap.put(entry.getKey().name(), entry.getValue().get());
        }
        
        return new TestResult(successCount.get(), errorCount.get(), durationMs, insertsPerSecond,
                             minLatency, maxLatency, p50, p95, p99, errorsByCategoryMap);
    }
    
    /**
     * Run Scenario 2: Batch inserts with per-iteration connection resilience.
     * For extreme scaling, acquires fresh connections per iteration to handle pool contention.
     */
    public TestResult runScenario2(int iterations, int batchSize, int threadIndex) {
        return runScenario2(iterations, batchSize, threadIndex, 0);
    }
    
    /**
     * Run Scenario 2: Batch inserts with per-iteration connection resilience.
     * For extreme scaling, acquires fresh connections per iteration to handle pool contention.
     * @param warmupIterations Number of warm-up iterations to run before measurement (not counted in metrics)
     */
    public TestResult runScenario2(int iterations, int batchSize, int threadIndex, int warmupIterations) {
        LOGGER.info("Starting Scenario 2: thread={}, iterations={}, batchSize={}, eventType={}, payloadSize={}", 
                   threadIndex, iterations, batchSize, eventType, payloadSize);
        
        // Warm-up phase (not counted in metrics)
        if (warmupIterations > 0) {
            LOGGER.info("Thread {} running {} warm-up iterations", threadIndex, warmupIterations);
            Connection warmupConn = null;
            try {
                warmupConn = getConnectionWithRetry(threadIndex, new AtomicInteger(0));
                if (warmupConn != null) {
                    for (int w = 0; w < warmupIterations; w++) {
                        try {
                            String[] eventIds = new String[batchSize];
                            ObjectNode[] events = new ObjectNode[batchSize];
                            for (int j = 0; j < batchSize; j++) {
                                eventIds[j] = String.format("load-test-warmup-%d-%d-%d-%s", 
                                                            threadIndex, w, j, UUID.randomUUID().toString());
                                events[j] = generateEvent(eventType, threadIndex, w, j, payloadSize);
                            }
                            EventRepository.insertBatch(warmupConn, eventIds, events);
                        } catch (Exception e) {
                            // Ignore warm-up errors
                        }
                    }
                }
            } catch (Exception e) {
                LOGGER.debug("Thread {} warm-up error (ignored): {}", threadIndex, e.getMessage());
            } finally {
                if (warmupConn != null) {
                    try {
                        warmupConn.close();
                    } catch (Exception ignore) {}
                }
            }
            LOGGER.info("Thread {} completed warm-up phase", threadIndex);
        }
        
        long startTime = System.currentTimeMillis();
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger errorCount = new AtomicInteger(0);
        AtomicInteger connectionRetries = new AtomicInteger(0);
        int totalExpected = iterations * batchSize;
        int logInterval = Math.max(1, iterations / 10); // Log every 10% progress
        List<Long> latencies = Collections.synchronizedList(new ArrayList<>());
        Map<ErrorCategory, AtomicInteger> errorsByCategory = new ConcurrentHashMap<>();
        
        // Determine if we should use per-iteration connections (for extreme scaling)
        // This gives other threads a chance to get connections
        boolean usePerIterationConnections = iterations <= 20 && batchSize >= 100;
        
        Connection sharedConn = null;
        try {
            // For small iteration counts with large batches, use per-iteration connections
            // For high iteration counts, reuse connection to reduce overhead
            if (!usePerIterationConnections) {
                sharedConn = getConnectionWithRetry(threadIndex, connectionRetries);
            }
            
            for (int i = 0; i < iterations; i++) {
                Connection conn = null;
                boolean ownConnection = false;
                
                try {
                    // Get connection for this iteration
                    if (usePerIterationConnections) {
                        conn = getConnectionWithRetry(threadIndex, connectionRetries);
                        ownConnection = true;
                    } else {
                        conn = sharedConn;
                        // Validate shared connection is still valid
                        if (conn == null || conn.isClosed()) {
                            sharedConn = getConnectionWithRetry(threadIndex, connectionRetries);
                            conn = sharedConn;
                        }
                    }
                    
                    if (conn == null) {
                        LOGGER.warn("Thread {} iteration {}: Could not get connection, skipping batch", threadIndex, i);
                        errorCount.addAndGet(batchSize);
                        continue;
                    }
                    
                    String[] eventIds = new String[batchSize];
                    ObjectNode[] events = new ObjectNode[batchSize];
                    
                    for (int j = 0; j < batchSize; j++) {
                        eventIds[j] = String.format("load-test-batch-%d-%d-%d-%s", 
                                                    threadIndex, i, j, UUID.randomUUID().toString());
                        events[j] = generateEvent(eventType, threadIndex, i, j, payloadSize);
                    }
                    
                    long opStartTime = System.currentTimeMillis();
                    int inserted = EventRepository.insertBatch(conn, eventIds, events);
                    long opLatency = System.currentTimeMillis() - opStartTime;
                    
                    // Validate batch insert only if inserted count doesn't match expected
                    // This avoids doubling database operations for successful batches
                    if (inserted == events.length) {
                        // All inserts succeeded - count as success
                        successCount.addAndGet(inserted);
                        // For batch operations, record latency per row (average)
                        long latencyPerRow = opLatency / inserted;
                        for (int k = 0; k < inserted; k++) {
                            latencies.add(latencyPerRow);
                        }
                    } else if (inserted > 0) {
                        // Some inserts succeeded - verify which ones actually exist
                        int verified = 0;
                        try {
                            verified = EventRepository.verifyBatchInsert(conn, eventIds);
                        } catch (Exception verifyEx) {
                            LOGGER.debug("Thread {} failed to verify batch insert: {}", threadIndex, verifyEx.getMessage());
                            // Fallback: use inserted count
                            verified = inserted;
                        }
                        
                        if (verified > 0) {
                            successCount.addAndGet(verified);
                            long latencyPerRow = opLatency / verified;
                            for (int k = 0; k < verified; k++) {
                                latencies.add(latencyPerRow);
                            }
                            
                            if (verified < events.length) {
                                // Some inserts failed - don't proceed with failed ones
                                int failed = events.length - verified;
                                errorCount.addAndGet(failed);
                                errorsByCategory.computeIfAbsent(ErrorCategory.QUERY_ERROR, k -> new AtomicInteger(0)).addAndGet(failed);
                                LOGGER.warn("Thread {} batch insert: {} succeeded, {} failed", threadIndex, verified, failed);
                            }
                        } else {
                            // Verification failed - use inserted count as fallback
                            successCount.addAndGet(inserted);
                            errorCount.addAndGet(events.length - inserted);
                            long latencyPerRow = opLatency / Math.max(inserted, 1);
                            for (int k = 0; k < inserted; k++) {
                                latencies.add(latencyPerRow);
                            }
                        }
                    } else {
                        // All inserts returned 0 - verify if any actually exist
                        int verified = 0;
                        try {
                            verified = EventRepository.verifyBatchInsert(conn, eventIds);
                        } catch (Exception verifyEx) {
                            LOGGER.debug("Thread {} failed to verify batch insert: {}", threadIndex, verifyEx.getMessage());
                        }
                        
                        if (verified > 0) {
                            // Some rows exist (likely conflicts) - count as success
                            successCount.addAndGet(verified);
                            long latencyPerRow = opLatency / verified;
                            for (int k = 0; k < verified; k++) {
                                latencies.add(latencyPerRow);
                            }
                            if (verified < events.length) {
                                errorCount.addAndGet(events.length - verified);
                            }
                        } else {
                            // All inserts failed - don't proceed
                            errorCount.addAndGet(events.length);
                            errorsByCategory.computeIfAbsent(ErrorCategory.QUERY_ERROR, k -> new AtomicInteger(0)).addAndGet(events.length);
                            LOGGER.warn("Thread {} batch insert failed for all {} events", threadIndex, events.length);
                        }
                    }
                } catch (Exception e) {
                    LOGGER.debug("Thread {} iteration {} error: {}", threadIndex, i, e.getMessage());
                    errorCount.addAndGet(batchSize);
                    
                    // Categorize and track error
                    ErrorCategory category = ErrorCategory.categorize(e);
                    errorsByCategory.computeIfAbsent(category, k -> new AtomicInteger(0)).addAndGet(batchSize);
                    
                    // If shared connection failed, try to reconnect for next iteration
                    if (!usePerIterationConnections && sharedConn != null) {
                        try {
                            sharedConn.close();
                        } catch (Exception ignore) {}
                        sharedConn = null;
                    }
                } finally {
                    // Only close per-iteration connections
                    if (ownConnection && conn != null) {
                        try {
                            conn.close();
                        } catch (Exception ignore) {}
                    }
                }
                
                // Log progress every N iterations
                if ((i + 1) % logInterval == 0 || (i + 1) == iterations) {
                    int currentProgress = (i + 1) * batchSize;
                    double percentComplete = (currentProgress * 100.0) / totalExpected;
                    long elapsed = System.currentTimeMillis() - startTime;
                    double currentRate = successCount.get() > 0 ? (successCount.get() * 1000.0) / elapsed : 0;
                    LOGGER.info("Thread {} progress: {}/{} ({:.1f}%) - Success: {}, Errors: {}, Rate: {:.2f} inserts/sec, Retries: {}", 
                               threadIndex, currentProgress, totalExpected, percentComplete, 
                               successCount.get(), errorCount.get(), currentRate, connectionRetries.get());
                }
            }
        } catch (Exception e) {
            LOGGER.error("Thread {} fatal error: {}", threadIndex, e.getMessage());
            // Only count remaining iterations as errors
            int completedIterations = (successCount.get() + errorCount.get()) / batchSize;
            int remainingIterations = iterations - completedIterations;
            errorCount.addAndGet(remainingIterations * batchSize);
        } finally {
            if (sharedConn != null) {
                try {
                    sharedConn.close();
                } catch (Exception ignore) {}
            }
        }
        
        long durationMs = System.currentTimeMillis() - startTime;
        double insertsPerSecond = durationMs > 0 ? (successCount.get() * 1000.0) / durationMs : 0;
        
        LOGGER.info("Thread {} completed: Success={}, Errors={}, Duration={}ms, Rate={:.2f} inserts/sec, ConnectionRetries={}", 
                   threadIndex, successCount.get(), errorCount.get(), durationMs, insertsPerSecond, connectionRetries.get());
        
        // Calculate latency percentiles
        long minLatency = 0, maxLatency = 0, p50 = 0, p95 = 0, p99 = 0;
        if (!latencies.isEmpty()) {
            Collections.sort(latencies);
            minLatency = latencies.get(0);
            maxLatency = latencies.get(latencies.size() - 1);
            p50 = latencies.get((int) (latencies.size() * 0.50));
            p95 = latencies.get((int) (latencies.size() * 0.95));
            p99 = latencies.get((int) (latencies.size() * 0.99));
        }
        
        // Convert error category map to string map for JSON serialization
        Map<String, Integer> errorsByCategoryMap = new HashMap<>();
        for (Map.Entry<ErrorCategory, AtomicInteger> entry : errorsByCategory.entrySet()) {
            errorsByCategoryMap.put(entry.getKey().name(), entry.getValue().get());
        }
        
        return new TestResult(successCount.get(), errorCount.get(), durationMs, insertsPerSecond,
                             minLatency, maxLatency, p50, p95, p99, errorsByCategoryMap);
    }
    
    /**
     * Get connection with retry and exponential backoff.
     */
    private Connection getConnectionWithRetry(int threadIndex, AtomicInteger retryCounter) {
        // DSQL is extremely high-performance - minimal retries needed
        int maxAttempts = 1; // Single retry only (DSQL should work first time)
        long baseDelay = 10; // 10ms delay (DSQL responds in microseconds)
        
        for (int attempt = 0; attempt < maxAttempts; attempt++) {
            try {
                return connection.getConnection();
            } catch (Exception e) {
                retryCounter.incrementAndGet();
                if (attempt < maxAttempts - 1) {
                    // DSQL is extremely high-performance - minimal delay needed
                    // Use fixed small delay instead of exponential backoff
                    long delay = baseDelay;
                    LOGGER.debug("Thread {} connection attempt {} failed, retrying in {}ms", 
                               threadIndex, attempt + 1, delay);
                    try {
                        Thread.sleep(delay);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        return null;
                    }
                }
            }
        }
        LOGGER.warn("Thread {} exhausted all {} connection attempts", threadIndex, maxAttempts);
        return null;
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
     * Parse integer from environment variable with default fallback.
     */
    private static int parseEnvInt(String name, int defaultValue) {
        String value = System.getenv(name);
        if (value != null && !value.isEmpty()) {
            try {
                return Integer.parseInt(value);
            } catch (NumberFormatException e) {
                return defaultValue;
            }
        }
        return defaultValue;
    }
    
    /**
     * Run parallel load test
     */
    public static void main(String[] args) {
        // Get database type from environment (default: dsql for backward compatibility)
        String databaseType = System.getenv("DATABASE_TYPE");
        if (databaseType == null || databaseType.isEmpty()) {
            databaseType = "dsql";
        }
        
        // Get configuration from environment variables
        String scenario = System.getenv("SCENARIO");
        String threadsStr = System.getenv("THREADS");
        String iterationsStr = System.getenv("ITERATIONS");
        String countStr = System.getenv("COUNT");
        String eventType = System.getenv("EVENT_TYPE");
        String payloadSizeStr = System.getenv("PAYLOAD_SIZE");
        String outputDir = System.getenv("OUTPUT_DIR");
        String testId = System.getenv("TEST_ID");
        
        // Defaults
        if (scenario == null) scenario = "both";
        if (threadsStr == null) threadsStr = "5";
        if (iterationsStr == null) iterationsStr = "2";
        if (countStr == null) countStr = "1";
        if (eventType == null) eventType = "CarCreated";
        
        // Create appropriate connection based on database type
        DatabaseConnection connection;
        String connectionHost;
        String connectionDatabase;
        String connectionUser;
        String connectionRegion = null;
        
        if ("local".equalsIgnoreCase(databaseType)) {
            // Local Docker PostgreSQL configuration
            String localHost = System.getenv("LOCAL_HOST");
            if (localHost == null || localHost.isEmpty()) {
                localHost = "localhost";
            }
            String localPortStr = System.getenv("LOCAL_PORT");
            if (localPortStr == null || localPortStr.isEmpty()) {
                localPortStr = "5433";  // Default port for local Docker
            }
            String localUsername = System.getenv("LOCAL_USERNAME");
            if (localUsername == null || localUsername.isEmpty()) {
                localUsername = "postgres";
            }
            String localPassword = System.getenv("LOCAL_PASSWORD");
            if (localPassword == null || localPassword.isEmpty()) {
                localPassword = "password";
            }
            String databaseName = System.getenv("DATABASE_NAME");
            if (databaseName == null || databaseName.isEmpty()) {
                databaseName = "car_entities";
            }
            
            int localPort = Integer.parseInt(localPortStr);
            int threads = Integer.parseInt(threadsStr);
            // Local connections don't require SSL
            connection = new AuroraConnection(localHost, localPort, databaseName, localUsername, localPassword, false, threads);
            connectionHost = localHost;
            connectionDatabase = databaseName;
            connectionUser = localUsername;
        } else if ("aurora".equalsIgnoreCase(databaseType)) {
            // Aurora configuration
            String auroraHost = System.getenv("AURORA_HOST");
            if (auroraHost == null || auroraHost.isEmpty()) {
                auroraHost = System.getenv("AURORA_ENDPOINT");
            }
            String auroraPortStr = System.getenv("AURORA_PORT");
            if (auroraPortStr == null || auroraPortStr.isEmpty()) {
                auroraPortStr = "5432";
            }
            String auroraUsername = System.getenv("AURORA_USERNAME");
            String auroraPassword = System.getenv("AURORA_PASSWORD");
            String databaseName = System.getenv("DATABASE_NAME");
            
            if (auroraHost == null || auroraHost.isEmpty()) {
                System.err.println("Error: AURORA_HOST or AURORA_ENDPOINT environment variable is required for Aurora");
                System.exit(1);
            }
            if (auroraUsername == null || auroraUsername.isEmpty()) {
                System.err.println("Error: AURORA_USERNAME environment variable is required for Aurora");
                System.exit(1);
            }
            if (auroraPassword == null || auroraPassword.isEmpty()) {
                System.err.println("Error: AURORA_PASSWORD environment variable is required for Aurora");
                System.exit(1);
            }
            if (databaseName == null || databaseName.isEmpty()) {
                databaseName = "car_entities";
            }
            
            int auroraPort = Integer.parseInt(auroraPortStr);
            int threads = Integer.parseInt(threadsStr);
            connection = new AuroraConnection(auroraHost, auroraPort, databaseName, auroraUsername, auroraPassword, threads);
            connectionHost = auroraHost;
            connectionDatabase = databaseName;
            connectionUser = auroraUsername;
        } else {
            // DSQL configuration (default)
            String dsqlHost = System.getenv("DSQL_HOST");
            String portStr = System.getenv("DSQL_PORT");
            String databaseName = System.getenv("DATABASE_NAME");
            String iamUsername = System.getenv("IAM_USERNAME");
            String region = System.getenv("AWS_REGION");
            
            // Defaults for DSQL
            if (dsqlHost == null) dsqlHost = "vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws";
            if (portStr == null) portStr = "5432";
            if (databaseName == null) databaseName = "postgres";
            if (iamUsername == null) iamUsername = "lambda_dsql_user";
            if (region == null) region = "us-east-1";
            
            int port = Integer.parseInt(portStr);
            int threads = Integer.parseInt(threadsStr);
            connection = new DSQLConnection(dsqlHost, port, databaseName, iamUsername, region, threads);
            connectionHost = dsqlHost;
            connectionDatabase = databaseName;
            connectionUser = iamUsername;
            connectionRegion = region;
        }
        
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
        
        int threads = Integer.parseInt(threadsStr);
        int iterations = Integer.parseInt(iterationsStr);
        int count = Integer.parseInt(countStr);
        int warmupIterations = parseEnvInt("WARMUP_ITERATIONS", Math.max(2, iterations / 10)); // Default: 10% or min 2
        
        // Generate test ID if not provided
        if (testId == null || testId.isEmpty()) {
            testId = String.format("test-%s-threads%d-loops%d-count%d-%s", 
                                  scenario, threads, iterations, count, 
                                  payloadSize != null ? payloadSize + "bytes" : "default");
        }
        
        System.out.println("Database Load Test Configuration:");
        System.out.println("  Database Type: " + databaseType.toUpperCase());
        System.out.println("  Test ID: " + testId);
        System.out.println("  Host: " + connectionHost);
        System.out.println("  Database: " + connectionDatabase);
        System.out.println("  User: " + connectionUser);
        if (connectionRegion != null) {
            System.out.println("  Region: " + connectionRegion);
        }
        System.out.println("  Scenario: " + scenario);
        System.out.println("  Threads: " + threads);
        System.out.println("  Iterations: " + iterations);
        System.out.println("  Count: " + count);
        System.out.println("  Warm-up Iterations: " + warmupIterations);
        System.out.println("  Event Type: " + eventType);
        if (payloadSize != null) {
            System.out.println("  Payload Size: " + payloadSize + " bytes (" + (payloadSize / 1024) + " KB)");
        } else {
            System.out.println("  Payload Size: default (~0.5-0.7 KB)");
        }
        if (outputDir != null && !outputDir.isEmpty()) {
            System.out.println("  Output Directory: " + outputDir);
        }
        
        // Connection rate limiting (more conservative for Aurora)
        int connectionRateLimit = parseEnvInt("DSQL_CONNECTION_RATE_LIMIT", 
                                             "aurora".equalsIgnoreCase(databaseType) ? 50 : 100);
        long batchDelayMs = threads >= 1000 ? 50 : 0; // No delay for regular tests, 50ms only for extreme
        System.out.println("  Connection Rate Limit: " + connectionRateLimit + " threads/second");
        System.out.println();
        
        // Initialize results collector
        TestResultsCollector collector = null;
        if (outputDir != null && !outputDir.isEmpty()) {
            collector = new TestResultsCollector(outputDir, testId);
            int scenarioNum = "1".equals(scenario) ? 1 : ("2".equals(scenario) ? 2 : 0);
            collector.setConfiguration(scenarioNum, threads, iterations, count, eventType, payloadSize,
                                       connectionHost, connectionDatabase, connectionUser, connectionRegion);
        }
        
        // Create test instance
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
                
                // Submit threads in rate-limited batches to respect DSQL's 100 conn/sec limit
                for (int i = 0; i < threads; i++) {
                    final int threadIndex = i;
                    futures.add(executor.submit(() -> test.runScenario1(iterations, count, threadIndex, warmupIterations)));
                    
                    // Rate limit: pause after every batch to respect DSQL's 100 conn/sec limit
                    if ((i + 1) % connectionRateLimit == 0 && i < threads - 1) {
                        System.out.printf("Started %d/%d threads, pausing for rate limit...%n", i + 1, threads);
                        try {
                            Thread.sleep(batchDelayMs);
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                            System.err.println("Thread startup interrupted");
                            break;
                        }
                    } else if ((i + 1) % 10 == 0 || (i + 1) == threads) {
                        System.out.println("Started " + (i + 1) + "/" + threads + " threads...");
                    }
                }
                
                System.out.println("All threads started. Waiting for completion...");
                System.out.println();
                
                List<TestResult> results1 = new ArrayList<>();
                int completed = 0;
                // DSQL is extremely high-performance - but account for thread startup and connection pool init
                // Calculate timeout: iterations * count * 20ms per insert + 10s buffer for overhead
                // For basic tests: 20 iterations × 1 count × 20ms = 0.4s + 10s = 10.4s
                // For larger tests: up to 60s max
                long timeoutSeconds = Math.min(Math.max((iterations * count * 20L) / 1000 + 10, 15), 60);
                System.out.println("Waiting for threads to complete (timeout: " + timeoutSeconds + "s)...");
                for (Future<TestResult> future : futures) {
                    try {
                        results1.add(future.get(timeoutSeconds, TimeUnit.SECONDS));
                        completed++;
                        if (completed % 10 == 0 || completed == threads) {
                            System.out.println("Completed " + completed + "/" + threads + " threads...");
                        }
                    } catch (TimeoutException e) {
                        System.err.println("ERROR: Thread timed out after " + timeoutSeconds + " seconds!");
                        future.cancel(true);
                        // Create a failed result with minimal data
                        TestResult failedResult = new TestResult(0, count * iterations, 0, 0.0);
                        results1.add(failedResult);
                        completed++;
                    }
                }
                
                long totalDuration = System.currentTimeMillis() - startTime;
                
                // Log connection pool metrics
                DatabaseConnection.PoolMetrics poolMetrics = connection.getPoolMetrics();
                System.out.println("\n=== Connection Pool Metrics (Scenario 1) ===");
                System.out.println("  " + poolMetrics.toString());
                LOGGER.info("Connection pool metrics after Scenario 1: {}", poolMetrics);
                
                printResults("Scenario 1", results1, totalDuration);
                
                // Record results
                if (collector != null) {
                    // Store pool metrics
                    PerformanceMetrics.PoolMetrics metricsPoolMetrics = new PerformanceMetrics.PoolMetrics();
                    metricsPoolMetrics.setActiveConnections(poolMetrics.activeConnections);
                    metricsPoolMetrics.setIdleConnections(poolMetrics.idleConnections);
                    metricsPoolMetrics.setWaitingThreads(poolMetrics.threadsAwaitingConnection);
                    metricsPoolMetrics.setTotalConnections(poolMetrics.totalConnections);
                    metricsPoolMetrics.setMaxPoolSize(poolMetrics.maxPoolSize);
                    collector.setPoolMetrics(metricsPoolMetrics);
                    int totalSuccess = results1.stream().mapToInt(r -> r.successCount).sum();
                    int totalErrors = results1.stream().mapToInt(r -> r.errorCount).sum();
                    double avgRate = results1.stream().mapToDouble(r -> r.insertsPerSecond).average().orElse(0);
                    double throughput = totalDuration > 0 ? (totalSuccess * 1000.0) / totalDuration : 0;
                    
                    // Perform database validation
                    int actualRows = 0;
                    try (Connection validationConn = connection.getConnection()) {
                        actualRows = EventRepository.countAllLoadTestRows(validationConn);
                        System.out.println("Database validation: Found " + actualRows + " rows (expected: " + expectedRows1 + ")");
                    } catch (Exception e) {
                        LOGGER.warn("Failed to validate database rows: {}", e.getMessage());
                        actualRows = totalSuccess; // Fallback to success count
                    }
                    
                    collector.recordScenarioResult(1, totalSuccess, totalErrors, totalDuration, 
                                                   throughput, avgRate, expectedRows1, actualRows, results1);
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
                
                // Submit threads in rate-limited batches to respect DSQL's 100 conn/sec limit
                for (int i = 0; i < threads; i++) {
                    final int threadIndex = i;
                    futures.add(executor.submit(() -> test.runScenario2(iterations, count, threadIndex, warmupIterations)));
                    
                    // Rate limit: pause after every batch to respect DSQL's 100 conn/sec limit
                    if ((i + 1) % connectionRateLimit == 0 && i < threads - 1) {
                        System.out.printf("Started %d/%d threads, pausing for rate limit...%n", i + 1, threads);
                        try {
                            Thread.sleep(batchDelayMs);
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                            System.err.println("Thread startup interrupted");
                            break;
                        }
                    } else if ((i + 1) % 10 == 0 || (i + 1) == threads) {
                        System.out.println("Started " + (i + 1) + "/" + threads + " threads...");
                    }
                }
                
                System.out.println("All threads started. Waiting for completion...");
                System.out.println();
                
                List<TestResult> results2 = new ArrayList<>();
                int completed = 0;
                // DSQL is extremely high-performance - but account for thread startup and connection pool init
                // Calculate timeout: iterations * count * batch_size * 10ms per batch + 10s buffer for overhead
                // For basic tests: 20 iterations × 1 count × 10ms = 0.2s + 10s = 10.2s
                // For larger tests: up to 60s max
                long timeoutSeconds = Math.min(Math.max((iterations * count * 10L) / 1000 + 10, 15), 60);
                System.out.println("Waiting for threads to complete (timeout: " + timeoutSeconds + "s)...");
                for (Future<TestResult> future : futures) {
                    try {
                        results2.add(future.get(timeoutSeconds, TimeUnit.SECONDS));
                        completed++;
                        if (completed % 10 == 0 || completed == threads) {
                            System.out.println("Completed " + completed + "/" + threads + " threads...");
                        }
                    } catch (TimeoutException e) {
                        System.err.println("ERROR: Thread timed out after " + timeoutSeconds + " seconds!");
                        future.cancel(true);
                        // Create a failed result with minimal data
                        TestResult failedResult = new TestResult(0, count * iterations, 0, 0.0);
                        results2.add(failedResult);
                        completed++;
                    }
                }
                
                long totalDuration = System.currentTimeMillis() - startTime;
                
                // Log connection pool metrics
                DatabaseConnection.PoolMetrics poolMetrics = connection.getPoolMetrics();
                System.out.println("\n=== Connection Pool Metrics (Scenario 2) ===");
                System.out.println("  " + poolMetrics.toString());
                LOGGER.info("Connection pool metrics after Scenario 2: {}", poolMetrics);
                
                printResults("Scenario 2", results2, totalDuration);
                
                // Record results
                if (collector != null) {
                    // Store pool metrics
                    PerformanceMetrics.PoolMetrics metricsPoolMetrics = new PerformanceMetrics.PoolMetrics();
                    metricsPoolMetrics.setActiveConnections(poolMetrics.activeConnections);
                    metricsPoolMetrics.setIdleConnections(poolMetrics.idleConnections);
                    metricsPoolMetrics.setWaitingThreads(poolMetrics.threadsAwaitingConnection);
                    metricsPoolMetrics.setTotalConnections(poolMetrics.totalConnections);
                    metricsPoolMetrics.setMaxPoolSize(poolMetrics.maxPoolSize);
                    collector.setPoolMetrics(metricsPoolMetrics);
                    int totalSuccess = results2.stream().mapToInt(r -> r.successCount).sum();
                    int totalErrors = results2.stream().mapToInt(r -> r.errorCount).sum();
                    double avgRate = results2.stream().mapToDouble(r -> r.insertsPerSecond).average().orElse(0);
                    double throughput = totalDuration > 0 ? (totalSuccess * 1000.0) / totalDuration : 0;
                    
                    // Perform database validation
                    int actualRows = 0;
                    try (Connection validationConn = connection.getConnection()) {
                        actualRows = EventRepository.countAllLoadTestRows(validationConn);
                        System.out.println("Database validation: Found " + actualRows + " rows (expected: " + expectedRows2 + ")");
                    } catch (Exception e) {
                        LOGGER.warn("Failed to validate database rows: {}", e.getMessage());
                        actualRows = totalSuccess; // Fallback to success count
                    }
                    
                    collector.recordScenarioResult(2, totalSuccess, totalErrors, totalDuration, 
                                                   throughput, avgRate, expectedRows2, actualRows, results2);
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
        final long minLatencyMs;
        final long maxLatencyMs;
        final long p50LatencyMs;
        final long p95LatencyMs;
        final long p99LatencyMs;
        final Map<String, Integer> errorsByCategory;
        
        TestResult(int successCount, int errorCount, long durationMs, double insertsPerSecond) {
            this(successCount, errorCount, durationMs, insertsPerSecond, 0, 0, 0, 0, 0, new HashMap<>());
        }
        
        TestResult(int successCount, int errorCount, long durationMs, double insertsPerSecond,
                  long minLatencyMs, long maxLatencyMs, long p50LatencyMs, long p95LatencyMs, long p99LatencyMs,
                  Map<String, Integer> errorsByCategory) {
            this.successCount = successCount;
            this.errorCount = errorCount;
            this.durationMs = durationMs;
            this.insertsPerSecond = insertsPerSecond;
            this.minLatencyMs = minLatencyMs;
            this.maxLatencyMs = maxLatencyMs;
            this.p50LatencyMs = p50LatencyMs;
            this.p95LatencyMs = p95LatencyMs;
            this.p99LatencyMs = p99LatencyMs;
            this.errorsByCategory = errorsByCategory != null ? errorsByCategory : new HashMap<>();
        }
    }
}

