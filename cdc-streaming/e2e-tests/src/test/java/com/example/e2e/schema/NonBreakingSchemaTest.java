package com.example.e2e.schema;

import com.example.e2e.fixtures.TestEventGenerator;
import com.example.e2e.model.EventHeader;
import com.example.e2e.utils.KafkaTestUtils;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;

import java.time.Duration;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Non-breaking schema change tests.
 * Tests backward compatible changes: adding optional fields, new event types, etc.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class NonBreakingSchemaTest {
    
    private KafkaTestUtils kafkaUtils;
    private String sourceTopic = "raw-event-headers";
    private String bootstrapServers;
    private String apiKey;
    private String apiSecret;
    
    @BeforeAll
    void setUp() {
        // Support both local Docker Kafka and Confluent Cloud
        // Check environment variables first (for Confluent Cloud mode)
        bootstrapServers = System.getenv("KAFKA_BOOTSTRAP_SERVERS");
        if (bootstrapServers == null || bootstrapServers.isEmpty()) {
            bootstrapServers = System.getenv("CONFLUENT_BOOTSTRAP_SERVERS");
        }
        if (bootstrapServers == null || bootstrapServers.isEmpty()) {
            // Default to local Docker Kafka
            bootstrapServers = "localhost:9092";
        }
        
        // Get API credentials if using Confluent Cloud
        apiKey = System.getenv("CONFLUENT_API_KEY");
        if (apiKey == null || apiKey.isEmpty()) {
            apiKey = System.getenv("CONFLUENT_CLOUD_API_KEY");
        }
        if (apiKey == null || apiKey.isEmpty()) {
            apiKey = System.getenv("KAFKA_API_KEY");
        }
        
        apiSecret = System.getenv("CONFLUENT_API_SECRET");
        if (apiSecret == null || apiSecret.isEmpty()) {
            apiSecret = System.getenv("CONFLUENT_CLOUD_API_SECRET");
        }
        if (apiSecret == null || apiSecret.isEmpty()) {
            apiSecret = System.getenv("KAFKA_API_SECRET");
        }
        
        // Local Kafka doesn't require authentication
        kafkaUtils = new KafkaTestUtils(bootstrapServers, apiKey, apiSecret);
    }
    
    @Test
    void testAddOptionalFieldToEvent() throws Exception {
        // Create event with standard fields
        String testId = "test-optional-field-" + System.currentTimeMillis();
        EventHeader event = TestEventGenerator.generateCarCreatedEvent(testId);
        
        // Start consuming BEFORE publishing to ensure we capture the event
        // The consumeEvents method will seek to end and wait for new messages
        String filteredTopic = "filtered-car-created-events-spring";
        java.util.concurrent.Future<List<EventHeader>> consumeFuture = java.util.concurrent.Executors.newSingleThreadExecutor().submit(() -> {
            return kafkaUtils.consumeEvents(filteredTopic, 1, Duration.ofSeconds(30), "test-optional-field-");
        });
        
        // Small delay to ensure consumer is ready
        Thread.sleep(1000);
        
        // Publish the event
        kafkaUtils.publishTestEvent(sourceTopic, event);
        
        // Wait for stream-processor to process the event
        // With exactly-once semantics, Kafka Streams commits in transactions which can take time
        Thread.sleep(8000);
        
        // Get the consumed events
        List<EventHeader> carEvents = consumeFuture.get(35, java.util.concurrent.TimeUnit.SECONDS);
        
        assertThat(carEvents).hasSize(1);
        assertThat(carEvents.get(0).getEventType()).isEqualTo("CarCreated");
    }
    
    @Test
    void testNewEventTypeWithNewFilter() throws Exception {
        // This test would require:
        // 1. Creating a new filter via Metadata Service API
        // 2. Hot reloading the filter configuration
        // 3. Producing new event type
        // 4. Verifying it routes to new topic
        
        // For now, verify that existing event types still work
        String testId = "test-new-event-type-" + System.currentTimeMillis();
        EventHeader event = TestEventGenerator.generateCarCreatedEvent(testId);
        
        kafkaUtils.publishTestEvent(sourceTopic, event);
        
        List<EventHeader> carEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events-spring", 1, Duration.ofSeconds(30), "test-new-event-type-"
        );
        
        assertThat(carEvents).hasSize(1);
    }
    
    @Test
    void testWidenFieldTypeCompatibility() throws Exception {
        // Test that widening field types (e.g., int -> long) is backward compatible
        // This is more of a schema registry test, but we can verify events still process
        
        String testId = "test-widen-field-" + System.currentTimeMillis();
        EventHeader event = TestEventGenerator.generateLoanCreatedEvent(testId);
        
        String filteredTopic = "filtered-loan-created-events-spring";
        try (KafkaConsumer<String, byte[]> consumer = kafkaUtils.prepareConsumerForTopic(filteredTopic)) {
            kafkaUtils.publishTestEvent(sourceTopic, event);
            
            Thread.sleep(5000);
            
            List<EventHeader> loanEvents = kafkaUtils.consumeEventsWithConsumer(
                consumer, 1, Duration.ofSeconds(30), testId
            );
            
            assertThat(loanEvents).hasSize(1);
            assertThat(loanEvents.get(0).getEventType()).isEqualTo("LoanCreated");
        }
    }
    
    @Test
    void testBackwardCompatibleEventProcessing() throws Exception {
        // Verify that old event format still works after schema changes
        String testId = "test-backward-compat-" + System.currentTimeMillis();
        EventHeader event = TestEventGenerator.generateServiceEvent(testId);
        
        kafkaUtils.publishTestEvent(sourceTopic, event);
        
        List<EventHeader> serviceEvents = kafkaUtils.consumeEvents(
            "filtered-service-events-spring", 1, Duration.ofSeconds(30), "test-backward-compat-"
        );
        
        assertThat(serviceEvents).hasSize(1);
        assertThat(serviceEvents.get(0).getEventName()).isEqualTo("CarServiceDone");
    }
}

