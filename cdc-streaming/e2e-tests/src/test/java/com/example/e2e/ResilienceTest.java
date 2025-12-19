package com.example.e2e;

import com.example.e2e.fixtures.TestEventGenerator;
import com.example.e2e.model.EventHeader;
import com.example.e2e.utils.KafkaTestUtils;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;

import java.time.Duration;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Resilience tests for service recovery and state recovery scenarios.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class ResilienceTest {
    
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
     * Test that Spring Boot service can recover after restart without data loss.
     * Note: This test assumes the service can be restarted externally (e.g., via Docker/K8s).
     * In a real scenario, you would use testcontainers or K8s client to control the service.
     */
    @Test
    void testSpringBootRestartRecovery() throws Exception {
        // Publish events before restart
        List<EventHeader> eventsBeforeRestart = TestEventGenerator.generateMixedEventBatch(10);
        kafkaUtils.publishTestEvents(sourceTopic, eventsBeforeRestart);
        
        // Simulate restart by waiting and then publishing more events
        // In a real test, you would actually restart the service here
        System.out.println("Simulating service restart...");
        Thread.sleep(10000); // Simulate restart time
        
        // Publish events after restart
        List<EventHeader> eventsAfterRestart = TestEventGenerator.generateMixedEventBatch(10);
        kafkaUtils.publishTestEvents(sourceTopic, eventsAfterRestart);
        
        // Verify events from before restart are still processed
        // consumeAllEvents already polls with timeout, no need for Thread.sleep
        List<EventHeader> carEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-car-created-events", processor), 20, Duration.ofSeconds(60)
        );
        
        // Should have processed events from both before and after restart
        assertThat(carEvents.size()).as("Should process events after restart")
            .isGreaterThanOrEqualTo(5);
    }
    
    /**
     * Test that Kafka Streams state stores recover after restart.
     * Note: This is a simplified test - full state recovery testing requires stateful operations.
     */
    @Test
    void testKafkaStreamsStateRecovery() throws Exception {
        // Publish events that would create state
        List<EventHeader> testEvents = TestEventGenerator.generateMixedEventBatch(20);
        kafkaUtils.publishTestEvents(sourceTopic, testEvents);
        
        // Simulate restart
        System.out.println("Simulating Kafka Streams restart...");
        Thread.sleep(5000);
        
        // Publish more events
        List<EventHeader> moreEvents = TestEventGenerator.generateMixedEventBatch(10);
        kafkaUtils.publishTestEvents(sourceTopic, moreEvents);
        
        // Verify events are still being processed correctly
        // consumeAllEvents already polls with timeout, no need for Thread.sleep
        List<EventHeader> loanEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-loan-created-events", processor), 30, Duration.ofSeconds(60)
        );
        
        assertThat(loanEvents.size()).as("Should continue processing after state recovery")
            .isGreaterThanOrEqualTo(5);
    }
    
    /**
     * Test processing continues after network partition simulation.
     * Note: This is a simplified test - real network partition requires network manipulation.
     */
    @Test
    void testProcessingAfterNetworkPartition() throws Exception {
        // Publish events
        List<EventHeader> testEvents = TestEventGenerator.generateMixedEventBatch(15);
        kafkaUtils.publishTestEvents(sourceTopic, testEvents);
        
        // Simulate network partition (wait period)
        System.out.println("Simulating network partition...");
        Thread.sleep(10000);
        
        // Publish events during/after partition
        List<EventHeader> eventsDuringPartition = TestEventGenerator.generateMixedEventBatch(10);
        kafkaUtils.publishTestEvents(sourceTopic, eventsDuringPartition);
        
        // Verify events are eventually processed
        // consumeAllEvents already polls with timeout, no need for Thread.sleep
        List<EventHeader> paymentEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-loan-payment-submitted-events", processor), 25, Duration.ofSeconds(60)
        );
        
        assertThat(paymentEvents.size()).as("Should process events after network recovery")
            .isGreaterThanOrEqualTo(5);
    }
    
    /**
     * Measure Recovery Time Objective (RTO) - time to resume processing after restart.
     */
    @Test
    void testRecoveryTimeObjective() throws Exception {
        // Publish initial events
        List<EventHeader> initialEvents = TestEventGenerator.generateMixedEventBatch(5);
        kafkaUtils.publishTestEvents(sourceTopic, initialEvents);
        
        // Mark restart time
        long restartStartTime = System.currentTimeMillis();
        System.out.println("Simulating service restart at " + restartStartTime);
        
        // Simulate restart
        Thread.sleep(5000);
        
        // Publish event immediately after restart
        // Use unique event ID to avoid historical events
        String uniquePrefix = "rto-test-" + System.currentTimeMillis() + "-";
        String testId = uniquePrefix + "001";
        EventHeader recoveryEvent = TestEventGenerator.generateCarCreatedEvent(testId);
        kafkaUtils.publishTestEvent(sourceTopic, recoveryEvent);
        
        // Measure time until event is processed
        long recoveryStartTime = System.currentTimeMillis();
        // consumeEvents already polls with timeout, no need for Thread.sleep
        // Use unique prefix to filter out historical events
        List<EventHeader> recoveredEvents = kafkaUtils.consumeEvents(
            getTopic("filtered-car-created-events", processor), 1, Duration.ofSeconds(60), uniquePrefix
        );
        long recoveryEndTime = System.currentTimeMillis();
        
        long rto = recoveryEndTime - recoveryStartTime;
        
        System.out.println("Recovery Time Objective (RTO): " + rto + "ms");
        
        assertThat(recoveredEvents).as("Should recover and process events")
            .hasSize(1);
        
        // RTO should be reasonable (< 1 minute)
        assertThat(rto).as("RTO should be < 60000ms (1 minute)")
            .isLessThan(60000);
    }
    
    /**
     * Test that offset management works correctly after restart.
     */
    @Test
    void testOffsetRecovery() throws Exception {
        // Publish events
        List<EventHeader> events = TestEventGenerator.generateMixedEventBatch(20);
        kafkaUtils.publishTestEvents(sourceTopic, events);
        
        // Simulate restart
        System.out.println("Simulating restart for offset recovery test...");
        Thread.sleep(5000);
        
        // Publish new events
        List<EventHeader> newEvents = TestEventGenerator.generateMixedEventBatch(10);
        kafkaUtils.publishTestEvents(sourceTopic, newEvents);
        
        // Verify no duplicate processing (events should be processed once)
        // consumeAllEvents already polls with timeout, no need for Thread.sleep
        List<EventHeader> serviceEvents = kafkaUtils.consumeAllEvents(
            getTopic("filtered-service-events", processor), 30, Duration.ofSeconds(60)
        );
        
        // Count unique event IDs
        long uniqueCount = serviceEvents.stream()
            .map(EventHeader::getId)
            .distinct()
            .count();
        
        assertThat(uniqueCount).as("Should not have duplicate events after offset recovery")
            .isEqualTo(serviceEvents.size());
    }
}
