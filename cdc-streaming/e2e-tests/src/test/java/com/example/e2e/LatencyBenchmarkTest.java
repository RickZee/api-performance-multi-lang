package com.example.e2e;

import com.example.e2e.fixtures.TestEventGenerator;
import com.example.e2e.model.EventHeader;
import com.example.e2e.utils.KafkaTestUtils;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Latency benchmark tests to measure P50, P95, P99 latency percentiles.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class LatencyBenchmarkTest {
    
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
    
    /**
     * Measure latency percentiles (P50, P95, P99) for event processing.
     */
    @Test
    void testLatencyPercentiles() throws Exception {
        int eventCount = 100;
        List<EventHeader> testEvents = TestEventGenerator.generateMixedEventBatch(eventCount);
        List<Long> latencies = new ArrayList<>();
        
        // Measure latency for each event
        for (EventHeader event : testEvents) {
            long publishTime = System.currentTimeMillis();
            kafkaUtils.publishTestEvent(sourceTopic, event);
            
            // Wait for event to appear in appropriate filtered topic
            String targetTopic = getTargetTopic(event.getEventType());
            List<EventHeader> receivedEvents = kafkaUtils.consumeEvents(
                targetTopic, 1, Duration.ofSeconds(30)
            );
            
            if (!receivedEvents.isEmpty()) {
                long receiveTime = System.currentTimeMillis();
                long latency = receiveTime - publishTime;
                latencies.add(latency);
            }
        }
        
        // Calculate percentiles
        Collections.sort(latencies);
        long p50 = percentile(latencies, 50);
        long p95 = percentile(latencies, 95);
        long p99 = percentile(latencies, 99);
        
        System.out.println("Latency Statistics:");
        System.out.println("  P50: " + p50 + "ms");
        System.out.println("  P95: " + p95 + "ms");
        System.out.println("  P99: " + p99 + "ms");
        System.out.println("  Min: " + (latencies.isEmpty() ? 0 : latencies.get(0)) + "ms");
        System.out.println("  Max: " + (latencies.isEmpty() ? 0 : latencies.get(latencies.size() - 1)) + "ms");
        System.out.println("  Sample size: " + latencies.size());
        
        // Assert SLA targets
        assertThat(p50).as("P50 latency should be < 50ms").isLessThan(50);
        assertThat(p95).as("P95 latency should be < 200ms").isLessThan(200);
        assertThat(p99).as("P99 latency should be < 500ms").isLessThan(500);
    }
    
    /**
     * Measure latency at different load levels (50%, 80%, 100% capacity).
     */
    @Test
    void testLatencyUnderLoad() throws Exception {
        int[] loadLevels = {50, 80, 100}; // events per second
        int testDurationSeconds = 10;
        
        for (int loadLevel : loadLevels) {
            System.out.println("\nTesting at " + loadLevel + " events/sec load level");
            List<Long> latencies = new ArrayList<>();
            
            long startTime = System.currentTimeMillis();
            long endTime = startTime + (testDurationSeconds * 1000);
            int eventCount = 0;
            
            while (System.currentTimeMillis() < endTime) {
                EventHeader event = TestEventGenerator.generateCarCreatedEvent("load-test-" + eventCount);
                long publishTime = System.currentTimeMillis();
                kafkaUtils.publishTestEvent(sourceTopic, event);
                
                // Wait for event
                List<EventHeader> receivedEvents = kafkaUtils.consumeEvents(
                    "filtered-car-created-events", 1, Duration.ofSeconds(5)
                );
                
                if (!receivedEvents.isEmpty()) {
                    long receiveTime = System.currentTimeMillis();
                    latencies.add(receiveTime - publishTime);
                }
                
                eventCount++;
                
                // Rate limiting: wait to maintain target load
                long expectedInterval = 1000 / loadLevel;
                long elapsed = System.currentTimeMillis() - publishTime;
                if (elapsed < expectedInterval) {
                    Thread.sleep(expectedInterval - elapsed);
                }
            }
            
            if (!latencies.isEmpty()) {
                Collections.sort(latencies);
                long p50 = percentile(latencies, 50);
                long p95 = percentile(latencies, 95);
                long p99 = percentile(latencies, 99);
                
                System.out.println("  P50: " + p50 + "ms, P95: " + p95 + "ms, P99: " + p99 + "ms");
                
                // Latency should not degrade significantly at higher loads
                assertThat(p99).as("P99 latency at " + loadLevel + "% load should be < 1000ms")
                    .isLessThan(1000);
            }
        }
    }
    
    /**
     * Compare latency across different event types.
     */
    @Test
    void testLatencyByEventType() throws Exception {
        String[] eventTypes = {"CarCreated", "LoanCreated", "LoanPaymentSubmitted", "CarServiceDone"};
        int eventsPerType = 20;
        
        for (String eventType : eventTypes) {
            List<Long> latencies = new ArrayList<>();
            
            for (int i = 0; i < eventsPerType; i++) {
                EventHeader event = generateEventByType(eventType, "latency-type-" + i);
                long publishTime = System.currentTimeMillis();
                kafkaUtils.publishTestEvent(sourceTopic, event);
                
                String targetTopic = getTargetTopic(eventType);
                List<EventHeader> receivedEvents = kafkaUtils.consumeEvents(
                    targetTopic, 1, Duration.ofSeconds(30)
                );
                
                if (!receivedEvents.isEmpty()) {
                    long receiveTime = System.currentTimeMillis();
                    latencies.add(receiveTime - publishTime);
                }
            }
            
            if (!latencies.isEmpty()) {
                Collections.sort(latencies);
                long p50 = percentile(latencies, 50);
                long p95 = percentile(latencies, 95);
                
                System.out.println(eventType + " latency - P50: " + p50 + "ms, P95: " + p95 + "ms");
                
                // All event types should have similar latency
                assertThat(p95).as("P95 latency for " + eventType + " should be < 500ms")
                    .isLessThan(500);
            }
        }
    }
    
    /**
     * Test latency with network jitter simulation.
     * Note: This is a simplified test - real network jitter would require network manipulation tools.
     */
    @Test
    void testLatencyWithJitter() throws Exception {
        int eventCount = 50;
        List<Long> latencies = new ArrayList<>();
        
        for (int i = 0; i < eventCount; i++) {
            EventHeader event = TestEventGenerator.generateCarCreatedEvent("jitter-test-" + i);
            
            // Simulate jitter by adding random delay before publishing
            long jitterDelay = (long) (Math.random() * 10); // 0-10ms jitter
            Thread.sleep(jitterDelay);
            
            long publishTime = System.currentTimeMillis();
            kafkaUtils.publishTestEvent(sourceTopic, event);
            
            List<EventHeader> receivedEvents = kafkaUtils.consumeEvents(
                "filtered-car-created-events", 1, Duration.ofSeconds(30)
            );
            
            if (!receivedEvents.isEmpty()) {
                long receiveTime = System.currentTimeMillis();
                latencies.add(receiveTime - publishTime);
            }
        }
        
        if (!latencies.isEmpty()) {
            Collections.sort(latencies);
            long p99 = percentile(latencies, 99);
            
            System.out.println("Latency with jitter - P99: " + p99 + "ms");
            
            // Jitter should not cause excessive latency
            assertThat(p99).as("P99 latency with jitter should be < 1000ms")
                .isLessThan(1000);
        }
    }
    
    /**
     * Calculate percentile from sorted list.
     */
    private long percentile(List<Long> sortedList, int percentile) {
        if (sortedList.isEmpty()) {
            return 0;
        }
        int index = (int) Math.ceil((percentile / 100.0) * sortedList.size()) - 1;
        return sortedList.get(Math.max(0, Math.min(index, sortedList.size() - 1)));
    }
    
    /**
     * Get target topic for event type.
     */
    private String getTargetTopic(String eventType) {
        switch (eventType) {
            case "CarCreated":
                return "filtered-car-created-events";
            case "LoanCreated":
                return "filtered-loan-created-events";
            case "LoanPaymentSubmitted":
                return "filtered-loan-payment-submitted-events";
            case "CarServiceDone":
                return "filtered-service-events";
            default:
                return "filtered-car-created-events";
        }
    }
    
    /**
     * Generate event by type.
     */
    private EventHeader generateEventByType(String eventType, String eventId) {
        switch (eventType) {
            case "CarCreated":
                return TestEventGenerator.generateCarCreatedEvent(eventId);
            case "LoanCreated":
                return TestEventGenerator.generateLoanCreatedEvent(eventId);
            case "LoanPaymentSubmitted":
                return TestEventGenerator.generateLoanPaymentEvent(eventId);
            case "CarServiceDone":
                return TestEventGenerator.generateServiceEvent(eventId);
            default:
                return TestEventGenerator.generateCarCreatedEvent(eventId);
        }
    }
}
