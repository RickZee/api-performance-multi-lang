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
        
        // Wait for processing
        Thread.sleep(30000);
        
        // Measure consumption time
        long startConsume = System.currentTimeMillis();
        List<EventHeader> carEvents = kafkaUtils.consumeAllEvents(
            "filtered-car-created-events", eventCount, Duration.ofSeconds(60)
        );
        List<EventHeader> loanEvents = kafkaUtils.consumeAllEvents(
            "filtered-loan-created-events", eventCount, Duration.ofSeconds(60)
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
        EventHeader testEvent = TestEventGenerator.generateCarCreatedEvent("perf-latency-001");
        
        // Measure end-to-end latency
        long publishTime = System.currentTimeMillis();
        kafkaUtils.publishTestEvent(sourceTopic, testEvent);
        
        // Wait for event to appear in filtered topic
        List<EventHeader> carEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events", 1, Duration.ofSeconds(30)
        );
        long receiveTime = System.currentTimeMillis();
        
        long latency = receiveTime - publishTime;
        
        System.out.println("End-to-end latency: " + latency + "ms");
        
        // Assert latency is within acceptable range (< 5 seconds)
        assertThat(latency).isLessThan(5000);
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
        
        // Wait for processing
        Thread.sleep(30000);
        
        // Verify events were processed
        List<EventHeader> carEvents = kafkaUtils.consumeAllEvents(
            "filtered-car-created-events", 100, Duration.ofSeconds(60)
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
        
        // Wait for processing (longer for large batch)
        Thread.sleep(60000);
        
        // Verify events are eventually processed
        List<EventHeader> carEvents = kafkaUtils.consumeAllEvents(
            "filtered-car-created-events", largeBatchSize, Duration.ofSeconds(120)
        );
        List<EventHeader> loanEvents = kafkaUtils.consumeAllEvents(
            "filtered-loan-created-events", largeBatchSize, Duration.ofSeconds(120)
        );
        
        int totalProcessed = carEvents.size() + loanEvents.size();
        
        // Should process most events (allow some margin)
        assertThat(totalProcessed).isGreaterThan(largeBatchSize * 0.8);
    }
}
