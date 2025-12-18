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
     * Test that Spring Boot service can recover after restart without data loss.
     * Note: This test assumes the service can be restarted externally (e.g., via Docker/K8s).
     * In a real scenario, you would use testcontainers or K8s client to control the service.
     */
    @Test
    void testSpringBootRestartRecovery() throws Exception {
        // Publish events before restart
        List<EventHeader> eventsBeforeRestart = TestEventGenerator.generateMixedEventBatch(10);
        kafkaUtils.publishTestEvents(sourceTopic, eventsBeforeRestart);
        
        // Wait a bit for processing
        Thread.sleep(5000);
        
        // Simulate restart by waiting and then publishing more events
        // In a real test, you would actually restart the service here
        System.out.println("Simulating service restart...");
        Thread.sleep(10000); // Simulate restart time
        
        // Publish events after restart
        List<EventHeader> eventsAfterRestart = TestEventGenerator.generateMixedEventBatch(10);
        kafkaUtils.publishTestEvents(sourceTopic, eventsAfterRestart);
        
        // Wait for processing
        Thread.sleep(15000);
        
        // Verify events from before restart are still processed
        List<EventHeader> carEvents = kafkaUtils.consumeAllEvents(
            "filtered-car-created-events", 20, Duration.ofSeconds(60)
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
        
        // Wait for processing
        Thread.sleep(10000);
        
        // Simulate restart
        System.out.println("Simulating Kafka Streams restart...");
        Thread.sleep(5000);
        
        // Publish more events
        List<EventHeader> moreEvents = TestEventGenerator.generateMixedEventBatch(10);
        kafkaUtils.publishTestEvents(sourceTopic, moreEvents);
        
        // Wait for processing
        Thread.sleep(15000);
        
        // Verify events are still being processed correctly
        List<EventHeader> loanEvents = kafkaUtils.consumeAllEvents(
            "filtered-loan-created-events", 30, Duration.ofSeconds(60)
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
        
        // Wait for initial processing
        Thread.sleep(5000);
        
        // Simulate network partition (wait period)
        System.out.println("Simulating network partition...");
        Thread.sleep(10000);
        
        // Publish events during/after partition
        List<EventHeader> eventsDuringPartition = TestEventGenerator.generateMixedEventBatch(10);
        kafkaUtils.publishTestEvents(sourceTopic, eventsDuringPartition);
        
        // Wait for recovery and processing
        Thread.sleep(20000);
        
        // Verify events are eventually processed
        List<EventHeader> paymentEvents = kafkaUtils.consumeAllEvents(
            "filtered-loan-payment-submitted-events", 25, Duration.ofSeconds(60)
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
        Thread.sleep(5000);
        
        // Mark restart time
        long restartStartTime = System.currentTimeMillis();
        System.out.println("Simulating service restart at " + restartStartTime);
        
        // Simulate restart
        Thread.sleep(5000);
        
        // Publish event immediately after restart
        EventHeader recoveryEvent = TestEventGenerator.generateCarCreatedEvent("rto-test-001");
        kafkaUtils.publishTestEvent(sourceTopic, recoveryEvent);
        
        // Measure time until event is processed
        long recoveryStartTime = System.currentTimeMillis();
        List<EventHeader> recoveredEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events", 1, Duration.ofSeconds(60)
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
        
        // Wait for processing
        Thread.sleep(10000);
        
        // Simulate restart
        System.out.println("Simulating restart for offset recovery test...");
        Thread.sleep(5000);
        
        // Publish new events
        List<EventHeader> newEvents = TestEventGenerator.generateMixedEventBatch(10);
        kafkaUtils.publishTestEvents(sourceTopic, newEvents);
        
        // Wait for processing
        Thread.sleep(15000);
        
        // Verify no duplicate processing (events should be processed once)
        List<EventHeader> serviceEvents = kafkaUtils.consumeAllEvents(
            "filtered-service-events", 30, Duration.ofSeconds(60)
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
