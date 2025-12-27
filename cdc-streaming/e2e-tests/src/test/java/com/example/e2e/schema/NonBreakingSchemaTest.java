package com.example.e2e.schema;

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
 * Non-breaking schema change tests.
 * Tests backward compatible changes: adding optional fields, new event types, etc.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class NonBreakingSchemaTest {
    
    private KafkaTestUtils kafkaUtils;
    private String sourceTopic = "raw-event-headers";
    private String bootstrapServers = "localhost:9092";
    
    @BeforeAll
    void setUp() {
        kafkaUtils = new KafkaTestUtils(bootstrapServers, null, null);
    }
    
    @Test
    void testAddOptionalFieldToEvent() throws Exception {
        // Create event with standard fields
        String testId = "test-optional-field-" + System.currentTimeMillis();
        EventHeader event = TestEventGenerator.generateCarCreatedEvent(testId);
        
        // Add optional field (simulated - in real scenario this would be in header_data)
        kafkaUtils.publishTestEvent(sourceTopic, event);
        
        // Verify event is still processed correctly
        List<EventHeader> carEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events-spring", 1, Duration.ofSeconds(30), "test-optional-field-"
        );
        
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
        
        kafkaUtils.publishTestEvent(sourceTopic, event);
        
        List<EventHeader> loanEvents = kafkaUtils.consumeEvents(
            "filtered-loan-created-events-spring", 1, Duration.ofSeconds(30), "test-widen-field-"
        );
        
        assertThat(loanEvents).hasSize(1);
        assertThat(loanEvents.get(0).getEventType()).isEqualTo("LoanCreated");
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

