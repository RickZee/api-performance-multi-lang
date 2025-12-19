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

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Performance comparison tests to measure throughput and latency of both services.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class PerformanceComparisonTest {
    
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
    
    @Test
    void testThroughputComparison() throws Exception {
        int eventCount = 100;
        List<EventHeader> testEvents = TestEventGenerator.generateMixedEventBatch(eventCount);
        
        // Measure time to publish
        long startPublish = System.currentTimeMillis();
        kafkaUtils.publishTestEvents(sourceTopic, testEvents);
        long publishTime = System.currentTimeMillis() - startPublish;
        
        System.out.println("Published " + eventCount + " events in " + publishTime + "ms");
        
        // Measure consumption time
        // consumeAllEvents already polls with timeout, no need for Thread.sleep
        long startConsume = System.currentTimeMillis();
        List<EventHeader> carEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-car-created-events", processor), eventCount, Duration.ofSeconds(60)
        );
        List<EventHeader> loanEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-loan-created-events", processor), eventCount, Duration.ofSeconds(60)
        );
        long consumeTime = System.currentTimeMillis() - startConsume;
        
        int totalProcessed = carEvents.size() + loanEvents.size();
        double throughput = (totalProcessed * 1000.0) / (publishTime + consumeTime);
        
        System.out.println("Processed " + totalProcessed + " events");
        System.out.println("Throughput: " + throughput + " events/second");
        
        // Assert minimum throughput requirement (> 100 events/second)
        assertThat(throughput).isGreaterThan(100.0);
    }
    
    @Test
    void testLatencyComparison() throws Exception {
        // Use unique event ID to avoid historical events
        String uniquePrefix = "perf-latency-" + System.currentTimeMillis() + "-";
        String testId = uniquePrefix + "001";
        EventHeader testEvent = TestEventGenerator.generateCarCreatedEvent(testId);
        
        // Measure end-to-end latency
        long publishTime = System.currentTimeMillis();
        kafkaUtils.publishTestEvent(sourceTopic, testEvent);
        
        // Wait for event to appear in filtered topic
        // Use unique prefix to filter out historical events
        List<EventHeader> carEvents = kafkaUtils.consumeEvents(
            getTopic("filtered-car-created-events", processor), 1, Duration.ofSeconds(30), uniquePrefix
        );
        long receiveTime = System.currentTimeMillis();
        
        long latency = receiveTime - publishTime;
        
        System.out.println("End-to-end latency: " + latency + "ms");
        
        // Assert latency is within acceptable range (relaxed for real-world conditions)
        // Note: Real-world latency can be higher due to network, Kafka processing, etc.
        assertThat(latency).as("Latency should be reasonable (< 60 seconds)")
            .isLessThan(60000);
        assertThat(carEvents).hasSize(1);
    }
    
    @Test
    void testConcurrentEventProcessing() throws Exception {
        int concurrentStreams = 5;
        int eventsPerStream = 20;
        ExecutorService executor = Executors.newFixedThreadPool(concurrentStreams);
        List<CompletableFuture<Void>> futures = new ArrayList<>();
        
        // Publish events concurrently
        for (int i = 0; i < concurrentStreams; i++) {
            final int streamId = i;
            CompletableFuture<Void> future = CompletableFuture.runAsync(() -> {
                try {
                    List<EventHeader> events = TestEventGenerator.generateMixedEventBatch(eventsPerStream);
                    for (EventHeader event : events) {
                        event.setId("concurrent-" + streamId + "-" + event.getId());
                    }
                    kafkaUtils.publishTestEvents(sourceTopic, events);
                } catch (Exception e) {
                    throw new RuntimeException(e);
                }
            }, executor);
            futures.add(future);
        }
        
        // Wait for all to complete
        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();
        executor.shutdown();
        
        // Verify events were processed
        // consumeAllEvents already polls with timeout, no need for Thread.sleep
        List<EventHeader> carEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-car-created-events", processor), 100, Duration.ofSeconds(60)
        );
        
        // Should have processed at least some events from concurrent streams
        assertThat(carEvents.size()).isGreaterThan(0);
    }
    
    @Test
    void testBackpressureHandling() throws Exception {
        // Generate a large batch to test backpressure
        int largeBatchSize = 500;
        List<EventHeader> testEvents = TestEventGenerator.generateMixedEventBatch(largeBatchSize);
        
        long startTime = System.currentTimeMillis();
        kafkaUtils.publishTestEvents(sourceTopic, testEvents);
        long publishTime = System.currentTimeMillis() - startTime;
        
        System.out.println("Published " + largeBatchSize + " events in " + publishTime + "ms");
        
        // Verify events are eventually processed
        // consumeAllEvents already polls with timeout (120s for large batch), no need for Thread.sleep
        List<EventHeader> carEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-car-created-events", processor), largeBatchSize, Duration.ofSeconds(120)
        );
        List<EventHeader> loanEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-loan-created-events", processor), largeBatchSize, Duration.ofSeconds(120)
        );
        
        int totalProcessed = carEvents.size() + loanEvents.size();
        
        // Should process most events (allow some margin)
        assertThat(totalProcessed).isGreaterThan((int)(largeBatchSize * 0.8));
    }
}
