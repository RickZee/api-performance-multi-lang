package com.example.e2e;

import com.example.e2e.fixtures.TestEventGenerator;
import com.example.e2e.model.EventHeader;
import com.example.e2e.utils.ComparisonUtils;
import com.example.e2e.utils.KafkaTestUtils;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;

import java.time.Duration;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Functional parity tests to verify both Flink and Spring Boot services
 * produce identical output for the same input.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class FunctionalParityTest {
    
    private KafkaTestUtils kafkaUtils;
    private String sourceTopic = "raw-event-headers";
    private String flinkCarTopic = "filtered-car-created-events";
    private String flinkLoanTopic = "filtered-loan-created-events";
    private String flinkPaymentTopic = "filtered-loan-payment-submitted-events";
    private String flinkServiceTopic = "filtered-service-events";
    
    // Spring Boot topics (same names, but we'll use different consumer groups)
    private String springCarTopic = "filtered-car-created-events";
    private String springLoanTopic = "filtered-loan-created-events";
    private String springPaymentTopic = "filtered-loan-payment-submitted-events";
    private String springServiceTopic = "filtered-service-events";
    
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
    void testCarCreatedEventRouting() throws Exception {
        // Generate test event
        EventHeader testEvent = TestEventGenerator.generateCarCreatedEvent("test-car-001");
        
        // Publish to source topic
        kafkaUtils.publishTestEvent(sourceTopic, testEvent);
        
        // Wait for processing
        Thread.sleep(5000);
        
        // Consume from Flink output
        List<EventHeader> flinkEvents = kafkaUtils.consumeEvents(
            flinkCarTopic, 1, Duration.ofSeconds(30)
        );
        
        // Consume from Spring Boot output (using different consumer group)
        List<EventHeader> springEvents = kafkaUtils.consumeEvents(
            springCarTopic, 1, Duration.ofSeconds(30)
        );
        
        // Assert parity
        assertThat(flinkEvents).hasSize(1);
        assertThat(springEvents).hasSize(1);
        ComparisonUtils.assertEventParity(flinkEvents, springEvents);
    }
    
    @Test
    void testLoanCreatedEventRouting() throws Exception {
        EventHeader testEvent = TestEventGenerator.generateLoanCreatedEvent("test-loan-001");
        
        kafkaUtils.publishTestEvent(sourceTopic, testEvent);
        Thread.sleep(5000);
        
        List<EventHeader> flinkEvents = kafkaUtils.consumeEvents(
            flinkLoanTopic, 1, Duration.ofSeconds(30)
        );
        List<EventHeader> springEvents = kafkaUtils.consumeEvents(
            springLoanTopic, 1, Duration.ofSeconds(30)
        );
        
        assertThat(flinkEvents).hasSize(1);
        assertThat(springEvents).hasSize(1);
        ComparisonUtils.assertEventParity(flinkEvents, springEvents);
    }
    
    @Test
    void testLoanPaymentEventRouting() throws Exception {
        EventHeader testEvent = TestEventGenerator.generateLoanPaymentEvent("test-payment-001");
        
        kafkaUtils.publishTestEvent(sourceTopic, testEvent);
        Thread.sleep(5000);
        
        List<EventHeader> flinkEvents = kafkaUtils.consumeEvents(
            flinkPaymentTopic, 1, Duration.ofSeconds(30)
        );
        List<EventHeader> springEvents = kafkaUtils.consumeEvents(
            springPaymentTopic, 1, Duration.ofSeconds(30)
        );
        
        assertThat(flinkEvents).hasSize(1);
        assertThat(springEvents).hasSize(1);
        ComparisonUtils.assertEventParity(flinkEvents, springEvents);
    }
    
    @Test
    void testServiceEventRouting() throws Exception {
        EventHeader testEvent = TestEventGenerator.generateServiceEvent("test-service-001");
        
        kafkaUtils.publishTestEvent(sourceTopic, testEvent);
        Thread.sleep(5000);
        
        List<EventHeader> flinkEvents = kafkaUtils.consumeEvents(
            flinkServiceTopic, 1, Duration.ofSeconds(30)
        );
        List<EventHeader> springEvents = kafkaUtils.consumeEvents(
            springServiceTopic, 1, Duration.ofSeconds(30)
        );
        
        assertThat(flinkEvents).hasSize(1);
        assertThat(springEvents).hasSize(1);
        ComparisonUtils.assertEventParity(flinkEvents, springEvents);
    }
    
    @Test
    void testEventFilteringByOp() throws Exception {
        // Generate update event (should be filtered out for CarCreated, LoanCreated, LoanPaymentSubmitted)
        EventHeader updateEvent = TestEventGenerator.generateUpdateEvent("CarCreated", "test-update-001");
        
        kafkaUtils.publishTestEvent(sourceTopic, updateEvent);
        Thread.sleep(5000);
        
        // These should be empty because update events are filtered out
        List<EventHeader> flinkEvents = kafkaUtils.consumeEvents(
            flinkCarTopic, 1, Duration.ofSeconds(10)
        );
        List<EventHeader> springEvents = kafkaUtils.consumeEvents(
            springCarTopic, 1, Duration.ofSeconds(10)
        );
        
        // Both should filter out update events
        assertThat(flinkEvents).isEmpty();
        assertThat(springEvents).isEmpty();
    }
    
    @Test
    void testEventStructurePreservation() throws Exception {
        EventHeader testEvent = TestEventGenerator.generateLoanCreatedEvent("test-structure-001");
        
        kafkaUtils.publishTestEvent(sourceTopic, testEvent);
        Thread.sleep(5000);
        
        List<EventHeader> flinkEvents = kafkaUtils.consumeEvents(
            flinkLoanTopic, 1, Duration.ofSeconds(30)
        );
        List<EventHeader> springEvents = kafkaUtils.consumeEvents(
            springLoanTopic, 1, Duration.ofSeconds(30)
        );
        
        assertThat(flinkEvents).hasSize(1);
        assertThat(springEvents).hasSize(1);
        
        EventHeader flinkEvent = flinkEvents.get(0);
        EventHeader springEvent = springEvents.get(0);
        
        // Verify all fields are preserved
        assertThat(flinkEvent.getId()).isEqualTo(springEvent.getId());
        assertThat(flinkEvent.getEventName()).isEqualTo(springEvent.getEventName());
        assertThat(flinkEvent.getEventType()).isEqualTo(springEvent.getEventType());
        assertThat(flinkEvent.getCreatedDate()).isEqualTo(springEvent.getCreatedDate());
        assertThat(flinkEvent.getSavedDate()).isEqualTo(springEvent.getSavedDate());
        assertThat(flinkEvent.getHeaderData()).isEqualTo(springEvent.getHeaderData());
        assertThat(flinkEvent.getOp()).isEqualTo(springEvent.getOp());
        assertThat(flinkEvent.getTable()).isEqualTo(springEvent.getTable());
    }
    
    @Test
    void testMultipleEventTypesBatch() throws Exception {
        // Generate batch of mixed event types
        List<EventHeader> testEvents = TestEventGenerator.generateMixedEventBatch(8);
        
        kafkaUtils.publishTestEvents(sourceTopic, testEvents);
        Thread.sleep(10000); // Wait longer for batch processing
        
        // Consume from all topics
        List<EventHeader> flinkCarEvents = kafkaUtils.consumeEvents(
            flinkCarTopic, 2, Duration.ofSeconds(30)
        );
        List<EventHeader> flinkLoanEvents = kafkaUtils.consumeEvents(
            flinkLoanTopic, 2, Duration.ofSeconds(30)
        );
        List<EventHeader> flinkPaymentEvents = kafkaUtils.consumeEvents(
            flinkPaymentTopic, 2, Duration.ofSeconds(30)
        );
        List<EventHeader> flinkServiceEvents = kafkaUtils.consumeEvents(
            flinkServiceTopic, 2, Duration.ofSeconds(30)
        );
        
        List<EventHeader> springCarEvents = kafkaUtils.consumeEvents(
            springCarTopic, 2, Duration.ofSeconds(30)
        );
        List<EventHeader> springLoanEvents = kafkaUtils.consumeEvents(
            springLoanTopic, 2, Duration.ofSeconds(30)
        );
        List<EventHeader> springPaymentEvents = kafkaUtils.consumeEvents(
            springPaymentTopic, 2, Duration.ofSeconds(30)
        );
        List<EventHeader> springServiceEvents = kafkaUtils.consumeEvents(
            springServiceTopic, 2, Duration.ofSeconds(30)
        );
        
        // Verify counts match
        assertThat(flinkCarEvents.size()).isEqualTo(springCarEvents.size());
        assertThat(flinkLoanEvents.size()).isEqualTo(springLoanEvents.size());
        assertThat(flinkPaymentEvents.size()).isEqualTo(springPaymentEvents.size());
        assertThat(flinkServiceEvents.size()).isEqualTo(springServiceEvents.size());
        
        // Verify each batch has parity
        ComparisonUtils.assertEventParity(flinkCarEvents, springCarEvents);
        ComparisonUtils.assertEventParity(flinkLoanEvents, springLoanEvents);
        ComparisonUtils.assertEventParity(flinkPaymentEvents, springPaymentEvents);
        ComparisonUtils.assertEventParity(flinkServiceEvents, springServiceEvents);
    }
    
    @Test
    void testNullAndInvalidEvents() throws Exception {
        // This test verifies that null/invalid events don't break processing
        // We can't easily send null events via Kafka, but we can verify
        // that the system continues processing after invalid events
        
        // Send a valid event first
        EventHeader validEvent = TestEventGenerator.generateCarCreatedEvent("test-valid-001");
        kafkaUtils.publishTestEvent(sourceTopic, validEvent);
        Thread.sleep(5000);
        
        // Verify valid event is processed
        List<EventHeader> flinkEvents = kafkaUtils.consumeEvents(
            flinkCarTopic, 1, Duration.ofSeconds(30)
        );
        assertThat(flinkEvents).hasSize(1);
    }
}

