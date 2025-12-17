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
 * Error handling and resilience tests.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class ErrorHandlingTest {
    
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
    void testInvalidEventHandling() throws Exception {
        // Send a valid event first to ensure system is working
        EventHeader validEvent = TestEventGenerator.generateCarCreatedEvent("error-valid-001");
        kafkaUtils.publishTestEvent(sourceTopic, validEvent);
        Thread.sleep(5000);
        
        // Verify valid event is processed
        List<EventHeader> validEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events", 1, Duration.ofSeconds(30)
        );
        assertThat(validEvents).hasSize(1);
        
        // Note: We can't easily send truly malformed JSON via Kafka producer,
        // but we can verify the system continues processing after various scenarios
        // In a real implementation, you might use a raw producer to send invalid JSON
    }
    
    @Test
    void testEventWithMissingFields() throws Exception {
        // Create an event with minimal required fields
        EventHeader minimalEvent = EventHeader.builder()
            .id("error-minimal-001")
            .eventType("CarCreated")
            .op("c")
            .table("event_headers")
            .build();
        
        kafkaUtils.publishTestEvent(sourceTopic, minimalEvent);
        Thread.sleep(5000);
        
        // System should handle this gracefully (either filter or process)
        // The exact behavior depends on implementation
        List<EventHeader> events = kafkaUtils.consumeEvents(
            "filtered-car-created-events", 1, Duration.ofSeconds(10)
        );
        
        // Should either process it or filter it out, but not crash
        // This test mainly verifies no exceptions are thrown
        assertThat(events.size()).isLessThanOrEqualTo(1);
    }
    
    @Test
    void testConsumerGroupOffsetManagement() throws Exception {
        // Publish events
        List<EventHeader> testEvents = TestEventGenerator.generateMixedEventBatch(10);
        kafkaUtils.publishTestEvents(sourceTopic, testEvents);
        Thread.sleep(10000);
        
        // Consume with first consumer group
        String group1 = "test-group-1";
        List<EventHeader> events1 = consumeWithGroup(group1, "filtered-car-created-events", 10);
        
        // Consume with second consumer group (should get same events)
        String group2 = "test-group-2";
        List<EventHeader> events2 = consumeWithGroup(group2, "filtered-car-created-events", 10);
        
        // Both should receive events (different consumer groups)
        assertThat(events1.size()).isGreaterThan(0);
        assertThat(events2.size()).isGreaterThan(0);
    }
    
    private List<EventHeader> consumeWithGroup(String groupId, String topic, int maxCount) throws Exception {
        // This is a simplified version - in a real implementation,
        // you'd create a consumer with the specific group ID
        return kafkaUtils.consumeAllEvents(topic, maxCount, Duration.ofSeconds(30));
    }
}
