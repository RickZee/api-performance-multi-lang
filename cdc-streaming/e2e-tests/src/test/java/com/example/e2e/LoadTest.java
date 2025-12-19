package com.example.e2e;

import com.example.e2e.fixtures.TestEventGenerator;
import com.example.e2e.model.EventHeader;
import com.example.e2e.utils.KafkaTestUtils;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Load tests for sustained load, ramp-up, spike load, and backpressure scenarios.
 * 
 * Note: For production load testing, consider using JMeter or Gatling.
 * This test provides basic load testing capabilities.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class LoadTest {
    
    private KafkaTestUtils kafkaUtils;
    private String sourceTopic = "raw-event-headers";
    private String processor; // "flink", "spring", or "both"
    
    @BeforeAll
    void setUp() {
        String bootstrapServers = System.getenv("CONFLUENT_BOOTSTRAP_SERVERS");
        String apiKey = System.getenv("CONFLUENT_API_KEY");
        String apiSecret = System.getenv("CONFLUENT_API_SECRET");
        
        if (bootstrapServers == null || apiKey == null || apiSecret == null) {
            throw new IllegalStateException(
                "Required environment variables not set: CONFLUENT_BOOTSTRAP_SERVERS, CONFLUENT_API_KEY, CONFLUENT_API_SECRET"
            );
        }
        
        kafkaUtils = new KafkaTestUtils(bootstrapServers, apiKey, apiSecret);
        
        // Get processor from environment variable, default to "spring"
        processor = System.getenv("TEST_PROCESSOR");
        if (processor == null || processor.isEmpty()) {
            processor = "spring";
        }
    }
    
    /**
     * Get topic name with processor suffix.
     */
    private String getTopic(String baseName, String processor) {
        return baseName + "-" + processor;
    }
    
    /**
     * Test ramp-up load: gradually increase from 1K to 50K events/sec.
     */
    @Test
    void testRampUpLoad() throws Exception {
        int[] rampUpLevels = {1000, 5000, 10000, 20000, 30000, 40000, 50000}; // events per second
        int durationPerLevel = 10; // seconds per level
        AtomicInteger totalPublished = new AtomicInteger(0);
        AtomicInteger totalProcessed = new AtomicInteger(0);
        
        System.out.println("Starting ramp-up load test...");
        
        for (int targetRate : rampUpLevels) {
            System.out.println("Ramping up to " + targetRate + " events/sec");
            
            long startTime = System.currentTimeMillis();
            long endTime = startTime + (durationPerLevel * 1000);
            int eventsInLevel = 0;
            
            while (System.currentTimeMillis() < endTime) {
                EventHeader event = TestEventGenerator.generateCarCreatedEvent(
                    "rampup-" + targetRate + "-" + eventsInLevel
                );
                kafkaUtils.publishTestEvent(sourceTopic, event);
                totalPublished.incrementAndGet();
                eventsInLevel++;
                
                // Rate limiting
                long expectedInterval = 1000 / targetRate;
                long elapsed = System.currentTimeMillis() - startTime;
                long expectedEvents = (elapsed / 1000) * targetRate;
                
                if (eventsInLevel < expectedEvents) {
                    // On track, continue
                } else {
                    // Ahead of schedule, wait
                    Thread.sleep(expectedInterval);
                }
            }
            
            System.out.println("  Published " + eventsInLevel + " events at " + targetRate + " events/sec");
        }
        
        // Wait for processing
        System.out.println("Waiting for events to be processed...");
        Thread.sleep(60000); // 1 minute
        
        // Verify events were processed
        List<EventHeader> processedEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-car-created-events", processor), totalPublished.get(), Duration.ofSeconds(120)
        );
        
        totalProcessed.set(processedEvents.size());
        
        System.out.println("Ramp-up test results:");
        System.out.println("  Published: " + totalPublished.get());
        System.out.println("  Processed: " + totalProcessed.get());
        
        // Should process most events (allow some margin for timing)
        assertThat(totalProcessed.get())
            .as("Should process at least 80% of events during ramp-up")
            .isGreaterThan((int) (totalPublished.get() * 0.8));
    }
    
    /**
     * Test spike load: sudden burst of 100K events.
     */
    @Test
    void testSpikeLoad() throws Exception {
        int spikeSize = 100000;
        System.out.println("Starting spike load test with " + spikeSize + " events...");
        
        long publishStartTime = System.currentTimeMillis();
        
        // Publish events as fast as possible
        ExecutorService executor = Executors.newFixedThreadPool(10);
        List<CompletableFuture<Void>> futures = new ArrayList<>();
        AtomicInteger published = new AtomicInteger(0);
        
        for (int i = 0; i < spikeSize; i++) {
            final int eventId = i;
            CompletableFuture<Void> future = CompletableFuture.runAsync(() -> {
                try {
                    EventHeader event = TestEventGenerator.generateCarCreatedEvent(
                        "spike-" + eventId
                    );
                    kafkaUtils.publishTestEvent(sourceTopic, event);
                    published.incrementAndGet();
                } catch (Exception e) {
                    System.err.println("Error publishing event " + eventId + ": " + e.getMessage());
                }
            }, executor);
            futures.add(future);
        }
        
        // Wait for all publishes to complete
        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();
        executor.shutdown();
        
        long publishEndTime = System.currentTimeMillis();
        long publishDuration = publishEndTime - publishStartTime;
        double publishRate = (published.get() * 1000.0) / publishDuration;
        
        System.out.println("Spike load published:");
        System.out.println("  Events: " + published.get());
        System.out.println("  Duration: " + publishDuration + "ms");
        System.out.println("  Rate: " + publishRate + " events/sec");
        
        // Wait for processing
        System.out.println("Waiting for spike events to be processed...");
        Thread.sleep(120000); // 2 minutes
        
        // Verify events were processed
        List<EventHeader> processedEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-car-created-events", processor), spikeSize, Duration.ofSeconds(300)
        );
        
        System.out.println("Spike load processed: " + processedEvents.size() + " events");
        
        // Should process most events
        assertThat(processedEvents.size())
            .as("Should process at least 70% of spike events")
            .isGreaterThan((int) (spikeSize * 0.7));
    }
    
    /**
     * Endurance test: sustained load for 1 hour.
     * Note: This test runs for 1 hour. Consider using @Timeout annotation or running separately.
     */
    @Test
    void testEnduranceTest() throws Exception {
        int targetRate = 10000; // events per second
        int testDurationMinutes = 5; // Reduced for CI/CD, use 60 for full endurance test
        int testDurationSeconds = testDurationMinutes * 60;
        
        System.out.println("Starting endurance test: " + targetRate + " events/sec for " + 
                         testDurationMinutes + " minutes");
        
        long startTime = System.currentTimeMillis();
        long endTime = startTime + (testDurationSeconds * 1000);
        AtomicInteger published = new AtomicInteger(0);
        AtomicInteger errors = new AtomicInteger(0);
        
        while (System.currentTimeMillis() < endTime) {
            try {
                EventHeader event = TestEventGenerator.generateMixedEventBatch(1).get(0);
                event.setId("endurance-" + published.get());
                kafkaUtils.publishTestEvent(sourceTopic, event);
                published.incrementAndGet();
                
                // Rate limiting
                long expectedInterval = 1000 / targetRate;
                Thread.sleep(expectedInterval);
            } catch (Exception e) {
                errors.incrementAndGet();
                System.err.println("Error during endurance test: " + e.getMessage());
            }
        }
        
        long actualDuration = System.currentTimeMillis() - startTime;
        double actualRate = (published.get() * 1000.0) / actualDuration;
        
        System.out.println("Endurance test results:");
        System.out.println("  Published: " + published.get() + " events");
        System.out.println("  Duration: " + (actualDuration / 1000) + " seconds");
        System.out.println("  Actual rate: " + actualRate + " events/sec");
        System.out.println("  Errors: " + errors.get());
        
        // Wait for final processing
        Thread.sleep(30000);
        
        // Verify system is still processing
        List<EventHeader> recentEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-car-created-events", processor), 100, Duration.ofSeconds(60)
        );
        
        assertThat(recentEvents.size())
            .as("Should continue processing during endurance test")
            .isGreaterThan(0);
        
        // Error rate should be low
        double errorRate = (errors.get() * 100.0) / published.get();
        assertThat(errorRate)
            .as("Error rate should be < 1%")
            .isLessThan(1.0);
    }
    
    /**
     * Test recovery after backpressure: verify system recovers after overload.
     */
    @Test
    void testRecoveryAfterBackpressure() throws Exception {
        // First, create backpressure with high load
        System.out.println("Creating backpressure with high load...");
        int overloadSize = 50000;
        
        // Use unique prefix for backpressure test to avoid conflicts
        String uniquePrefix = "backpressure-" + System.currentTimeMillis() + "-";
        long overloadStart = System.currentTimeMillis();
        for (int i = 0; i < overloadSize; i++) {
            EventHeader event = TestEventGenerator.generateCarCreatedEvent(uniquePrefix + i);
            try {
                kafkaUtils.publishTestEvent(sourceTopic, event);
            } catch (Exception e) {
                // If we hit timeout during backpressure, that's expected - continue
                if (i % 1000 == 0) {
                    System.out.println("  Published " + i + " events (some may have timed out due to backpressure)");
                }
                // Continue publishing - backpressure is expected
                continue;
            }
            
            if (i % 1000 == 0) {
                System.out.println("  Published " + i + " events");
            }
        }
        long overloadEnd = System.currentTimeMillis();
        
        System.out.println("Overload published " + overloadSize + " events in " + 
                         (overloadEnd - overloadStart) + "ms");
        
        // Wait for system to process (may take time due to backpressure)
        System.out.println("Waiting for system to process overload...");
        Thread.sleep(120000); // 2 minutes
        
        // Now test recovery: publish normal load
        System.out.println("Testing recovery with normal load...");
        int normalLoadSize = 100;
        // Use unique prefix for recovery test events
        String recoveryPrefix = "recovery-" + System.currentTimeMillis() + "-";
        List<EventHeader> normalEvents = TestEventGenerator.generateMixedEventBatch(normalLoadSize);
        // Update event IDs to use unique prefix
        for (int i = 0; i < normalEvents.size(); i++) {
            EventHeader event = normalEvents.get(i);
            EventHeader updatedEvent = EventHeader.builder()
                .id(recoveryPrefix + i)
                .eventName(event.getEventName())
                .eventType(event.getEventType())
                .createdDate(event.getCreatedDate())
                .savedDate(event.getSavedDate())
                .headerData(event.getHeaderData())
                .op(event.getOp())
                .table(event.getTable())
                .tsMs(event.getTsMs())
                .build();
            normalEvents.set(i, updatedEvent);
        }
        
        long recoveryStart = System.currentTimeMillis();
        kafkaUtils.publishTestEvents(sourceTopic, normalEvents);
        long recoveryEnd = System.currentTimeMillis();
        
        // Wait for normal load to be processed
        Thread.sleep(30000);
        
        // Verify normal load is processed quickly (recovery)
        // Use unique prefix to filter out historical events
        List<EventHeader> recoveredEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-car-created-events", processor), normalLoadSize, Duration.ofSeconds(60)
        );
        // Filter by recovery prefix
        recoveredEvents = recoveredEvents.stream()
            .filter(e -> e.getId() != null && e.getId().startsWith(recoveryPrefix))
            .collect(java.util.stream.Collectors.toList());
        
        long recoveryTime = System.currentTimeMillis() - recoveryStart;
        
        System.out.println("Recovery test results:");
        System.out.println("  Normal load processed: " + recoveredEvents.size() + " events");
        System.out.println("  Recovery time: " + recoveryTime + "ms");
        
        // Should process normal load after recovery
        assertThat(recoveredEvents.size())
            .as("Should process normal load after backpressure recovery")
            .isGreaterThan((int)(normalLoadSize * 0.8));
    }
    
    /**
     * Test concurrent load from multiple producers.
     */
    @Test
    void testConcurrentProducers() throws Exception {
        int numProducers = 5;
        int eventsPerProducer = 1000;
        
        System.out.println("Testing " + numProducers + " concurrent producers...");
        
        ExecutorService executor = Executors.newFixedThreadPool(numProducers);
        List<CompletableFuture<Integer>> futures = new ArrayList<>();
        
        for (int producerId = 0; producerId < numProducers; producerId++) {
            final int pid = producerId;
            CompletableFuture<Integer> future = CompletableFuture.supplyAsync(() -> {
                int published = 0;
                try {
                    for (int i = 0; i < eventsPerProducer; i++) {
                        EventHeader event = TestEventGenerator.generateCarCreatedEvent(
                            "concurrent-p" + pid + "-" + i
                        );
                        kafkaUtils.publishTestEvent(sourceTopic, event);
                        published++;
                    }
                } catch (Exception e) {
                    System.err.println("Producer " + pid + " error: " + e.getMessage());
                }
                return published;
            }, executor);
            futures.add(future);
        }
        
        // Wait for all producers
        int totalPublished = futures.stream()
            .mapToInt(f -> {
                try {
                    return f.get();
                } catch (Exception e) {
                    return 0;
                }
            })
            .sum();
        
        executor.shutdown();
        
        System.out.println("Concurrent producers published: " + totalPublished + " events");
        
        // Wait for processing
        Thread.sleep(60000);
        
        // Verify events were processed
        List<EventHeader> processedEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-car-created-events", processor), totalPublished, Duration.ofSeconds(120)
        );
        
        System.out.println("Concurrent producers processed: " + processedEvents.size() + " events");
        
        assertThat(processedEvents.size())
            .as("Should process events from concurrent producers")
            .isGreaterThan((int)(totalPublished * 0.8));
    }
}
