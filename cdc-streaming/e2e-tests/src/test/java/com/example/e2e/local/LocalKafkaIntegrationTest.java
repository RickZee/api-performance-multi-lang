package com.example.e2e.local;

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
 * Local Kafka integration test using Docker Compose with Confluent Kafka.
 * Tests the full pipeline: event publish -> filter -> consume
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class LocalKafkaIntegrationTest {
    
    private KafkaTestUtils kafkaUtils;
    private String sourceTopic = "raw-event-headers";
    private String bootstrapServers = "localhost:9092";
    
    @BeforeAll
    void setUp() {
        // Local Kafka doesn't require authentication
        kafkaUtils = new KafkaTestUtils(bootstrapServers, null, null);
    }
    
    @Test
    void testCarCreatedEventRouting() throws Exception {
        String uniquePrefix = "local-car-" + System.currentTimeMillis();
        String testId = uniquePrefix + "-001";
        EventHeader testEvent = TestEventGenerator.generateCarCreatedEvent(testId);
        
        kafkaUtils.publishTestEvent(sourceTopic, testEvent);
        
        List<EventHeader> carEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events-spring", 1, Duration.ofSeconds(30), uniquePrefix
        );
        
        assertThat(carEvents).hasSize(1);
        assertThat(carEvents.get(0).getEventType()).isEqualTo("CarCreated");
        assertThat(carEvents.get(0).getId()).startsWith(uniquePrefix);
    }
    
    @Test
    void testLoanCreatedEventRouting() throws Exception {
        String uniquePrefix = "local-loan-" + System.currentTimeMillis();
        String testId = uniquePrefix + "-001";
        EventHeader testEvent = TestEventGenerator.generateLoanCreatedEvent(testId);
        
        kafkaUtils.publishTestEvent(sourceTopic, testEvent);
        
        List<EventHeader> loanEvents = kafkaUtils.consumeEvents(
            "filtered-loan-created-events-spring", 1, Duration.ofSeconds(30), uniquePrefix
        );
        
        assertThat(loanEvents).hasSize(1);
        assertThat(loanEvents.get(0).getEventType()).isEqualTo("LoanCreated");
        assertThat(loanEvents.get(0).getId()).startsWith(uniquePrefix);
    }
    
    @Test
    void testLoanPaymentEventRouting() throws Exception {
        String uniquePrefix = "local-payment-" + System.currentTimeMillis();
        String testId = uniquePrefix + "-001";
        EventHeader testEvent = TestEventGenerator.generateLoanPaymentEvent(testId);
        
        kafkaUtils.publishTestEvent(sourceTopic, testEvent);
        
        List<EventHeader> paymentEvents = kafkaUtils.consumeEvents(
            "filtered-loan-payment-submitted-events-spring", 1, Duration.ofSeconds(30), uniquePrefix
        );
        
        assertThat(paymentEvents).hasSize(1);
        assertThat(paymentEvents.get(0).getEventType()).isEqualTo("LoanPaymentSubmitted");
        assertThat(paymentEvents.get(0).getId()).startsWith(uniquePrefix);
    }
    
    @Test
    void testServiceEventRouting() throws Exception {
        String uniquePrefix = "local-service-" + System.currentTimeMillis();
        String testId = uniquePrefix + "-001";
        EventHeader testEvent = TestEventGenerator.generateServiceEvent(testId);
        
        kafkaUtils.publishTestEvent(sourceTopic, testEvent);
        
        List<EventHeader> serviceEvents = kafkaUtils.consumeEvents(
            "filtered-service-events-spring", 1, Duration.ofSeconds(60), uniquePrefix
        );
        
        assertThat(serviceEvents).hasSize(1);
        assertThat(serviceEvents.get(0).getEventName()).isEqualTo("CarServiceDone");
        assertThat(serviceEvents.get(0).getId()).startsWith(uniquePrefix);
    }
    
    @Test
    void testMultipleEventTypesBatch() throws Exception {
        List<EventHeader> testEvents = TestEventGenerator.generateMixedEventBatch(20);
        
        kafkaUtils.publishTestEvents(sourceTopic, testEvents);
        
        // Wait for processing
        Thread.sleep(5000);
        
        // Verify events are distributed across filtered topics
        List<EventHeader> carEvents = kafkaUtils.consumeAllEvents(
            "filtered-car-created-events-spring", 20, Duration.ofSeconds(30)
        );
        List<EventHeader> loanEvents = kafkaUtils.consumeAllEvents(
            "filtered-loan-created-events-spring", 20, Duration.ofSeconds(30)
        );
        List<EventHeader> paymentEvents = kafkaUtils.consumeAllEvents(
            "filtered-loan-payment-submitted-events-spring", 20, Duration.ofSeconds(30)
        );
        List<EventHeader> serviceEvents = kafkaUtils.consumeAllEvents(
            "filtered-service-events-spring", 20, Duration.ofSeconds(30)
        );
        
        int totalProcessed = carEvents.size() + loanEvents.size() + paymentEvents.size() + serviceEvents.size();
        assertThat(totalProcessed).isGreaterThanOrEqualTo(15); // Allow some margin for timing
    }
}

