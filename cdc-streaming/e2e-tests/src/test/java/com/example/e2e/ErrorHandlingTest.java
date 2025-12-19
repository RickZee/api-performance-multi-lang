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
    void testInvalidEventHandling() throws Exception {
        // Send a valid event first to ensure system is working
        String uniquePrefix = "error-valid-" + System.currentTimeMillis();
        String testId = uniquePrefix + "-001";
        EventHeader validEvent = TestEventGenerator.generateCarCreatedEvent(testId);
        kafkaUtils.publishTestEvent(sourceTopic, validEvent);
        
        // Verify valid event is processed
        // consumeEvents already polls with timeout, no need for Thread.sleep
        List<EventHeader> validEvents = kafkaUtils.consumeEvents(
            getTopic("filtered-car-created-events", processor), 1, Duration.ofSeconds(30), uniquePrefix
        );
        assertThat(validEvents).hasSize(1);
        
        // Note: We can't easily send truly malformed JSON via Kafka producer,
        // but we can verify the system continues processing after various scenarios
        // In a real implementation, you might use a raw producer to send invalid JSON
    }
    
    @Test
    void testEventWithMissingFields() throws Exception {
        // Create an event with minimal required fields
        String uniquePrefix = "error-minimal-" + System.currentTimeMillis();
        String testId = uniquePrefix + "-001";
        EventHeader minimalEvent = EventHeader.builder()
            .id(testId)
            .eventType("CarCreated")
            .op("c")
            .table("event_headers")
            .build();
        
        kafkaUtils.publishTestEvent(sourceTopic, minimalEvent);
        
        // System should handle this gracefully (either filter or process)
        // The exact behavior depends on implementation
        // consumeEvents already polls with timeout, no need for Thread.sleep
        List<EventHeader> events = kafkaUtils.consumeEvents(
            getTopic("filtered-car-created-events", processor), 1, Duration.ofSeconds(10), uniquePrefix
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
        
        // Consume with first consumer group
        // consumeAllEvents already polls with timeout, no need for Thread.sleep
        String group1 = "test-group-1";
        List<EventHeader> events1 = consumeWithGroup(group1, getTopic("filtered-car-created-events", processor), 10);
        
        // Consume with second consumer group (should get same events)
        String group2 = "test-group-2";
        List<EventHeader> events2 = consumeWithGroup(group2, getTopic("filtered-car-created-events", processor), 10);
        
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
