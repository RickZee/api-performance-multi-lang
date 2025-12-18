package com.example.e2e;

import com.example.e2e.fixtures.TestEventGenerator;
import com.example.e2e.model.EventHeader;
import com.example.e2e.utils.KafkaTestUtils;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Schema evolution tests for backward and forward compatibility.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class SchemaEvolutionTest {
    
    private KafkaTestUtils kafkaUtils;
    private static final ObjectMapper objectMapper = new ObjectMapper()
            .registerModule(new JavaTimeModule());
    
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
     * Test backward compatible schema change: add new optional field.
     * Processors should handle events with new fields gracefully.
     */
    @Test
    void testBackwardCompatibleSchemaChange() throws Exception {
        // Create event with additional optional field (simulating schema evolution)
        String eventId = "schema-evolution-" + UUID.randomUUID().toString();
        String timestamp = Instant.now().toString();
        
        // Create event with extra field in header_data
        String headerDataWithExtraField = String.format(
            "{\"uuid\":\"%s\",\"eventName\":\"CarCreated\",\"eventType\":\"CarCreated\"," +
            "\"createdDate\":\"%s\",\"savedDate\":\"%s\",\"newOptionalField\":\"newValue\"}",
            eventId, timestamp, timestamp
        );
        
        EventHeader eventWithNewField = EventHeader.builder()
            .id(eventId)
            .eventName("CarCreated")
            .eventType("CarCreated")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(headerDataWithExtraField)
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
        
        // Publish event with new field
        kafkaUtils.publishTestEvent(sourceTopic, eventWithNewField);
        Thread.sleep(10000);
        
        // Verify event is processed correctly despite new field
        List<EventHeader> processedEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events", 1, Duration.ofSeconds(30)
        );
        
        assertThat(processedEvents).as("Should process event with new optional field")
            .hasSize(1);
        
        EventHeader processed = processedEvents.get(0);
        assertThat(processed.getId()).isEqualTo(eventId);
        assertThat(processed.getEventType()).isEqualTo("CarCreated");
        // New field should be preserved in header_data
        assertThat(processed.getHeaderData()).contains("newOptionalField");
    }
    
    /**
     * Test forward compatible schema change: verify consumers can read older messages.
     * This tests that removing optional fields doesn't break processing.
     */
    @Test
    void testForwardCompatibleSchemaChange() throws Exception {
        // Create event with minimal required fields (simulating older schema)
        String eventId = "forward-compat-" + UUID.randomUUID().toString();
        String timestamp = Instant.now().toString();
        
        // Minimal header_data without optional fields
        String minimalHeaderData = String.format(
            "{\"uuid\":\"%s\",\"eventName\":\"LoanCreated\",\"eventType\":\"LoanCreated\"," +
            "\"createdDate\":\"%s\",\"savedDate\":\"%s\"}",
            eventId, timestamp, timestamp
        );
        
        EventHeader minimalEvent = EventHeader.builder()
            .id(eventId)
            .eventName("LoanCreated")
            .eventType("LoanCreated")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(minimalHeaderData)
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
        
        // Publish minimal event
        kafkaUtils.publishTestEvent(sourceTopic, minimalEvent);
        Thread.sleep(10000);
        
        // Verify event is processed correctly
        List<EventHeader> processedEvents = kafkaUtils.consumeEvents(
            "filtered-loan-created-events", 1, Duration.ofSeconds(30)
        );
        
        assertThat(processedEvents).as("Should process minimal event (forward compatible)")
            .hasSize(1);
        
        EventHeader processed = processedEvents.get(0);
        assertThat(processed.getId()).isEqualTo(eventId);
        assertThat(processed.getEventType()).isEqualTo("LoanCreated");
    }
    
    /**
     * Test that unknown fields are ignored gracefully.
     */
    @Test
    void testUnknownFieldIgnored() throws Exception {
        String eventId = "unknown-field-" + UUID.randomUUID().toString();
        String timestamp = Instant.now().toString();
        
        // Create event with multiple unknown fields
        String headerDataWithUnknownFields = String.format(
            "{\"uuid\":\"%s\",\"eventName\":\"LoanPaymentSubmitted\",\"eventType\":\"LoanPaymentSubmitted\"," +
            "\"createdDate\":\"%s\",\"savedDate\":\"%s\"," +
            "\"unknownField1\":\"value1\",\"unknownField2\":123,\"unknownField3\":{\"nested\":\"data\"}}",
            eventId, timestamp, timestamp
        );
        
        EventHeader eventWithUnknownFields = EventHeader.builder()
            .id(eventId)
            .eventName("LoanPaymentSubmitted")
            .eventType("LoanPaymentSubmitted")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(headerDataWithUnknownFields)
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
        
        // Publish event with unknown fields
        kafkaUtils.publishTestEvent(sourceTopic, eventWithUnknownFields);
        Thread.sleep(10000);
        
        // Verify event is processed correctly
        List<EventHeader> processedEvents = kafkaUtils.consumeEvents(
            "filtered-loan-payment-submitted-events", 1, Duration.ofSeconds(30)
        );
        
        assertThat(processedEvents).as("Should process event with unknown fields")
            .hasSize(1);
        
        EventHeader processed = processedEvents.get(0);
        assertThat(processed.getId()).isEqualTo(eventId);
        // Unknown fields should be preserved in header_data JSON string
        assertThat(processed.getHeaderData()).contains("unknownField1");
    }
    
    /**
     * Test schema compatibility with null values in optional fields.
     */
    @Test
    void testNullValuesInOptionalFields() throws Exception {
        String eventId = "null-fields-" + UUID.randomUUID().toString();
        String timestamp = Instant.now().toString();
        
        // Create event with null values in header_data
        String headerDataWithNulls = String.format(
            "{\"uuid\":\"%s\",\"eventName\":\"CarServiceDone\",\"eventType\":\"CarServiceDone\"," +
            "\"createdDate\":\"%s\",\"savedDate\":\"%s\",\"optionalField\":null}",
            eventId, timestamp, timestamp
        );
        
        EventHeader eventWithNulls = EventHeader.builder()
            .id(eventId)
            .eventName("CarServiceDone")
            .eventType("CarServiceDone")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(headerDataWithNulls)
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
        
        // Publish event with null values
        kafkaUtils.publishTestEvent(sourceTopic, eventWithNulls);
        Thread.sleep(10000);
        
        // Verify event is processed correctly
        List<EventHeader> processedEvents = kafkaUtils.consumeEvents(
            "filtered-service-events", 1, Duration.ofSeconds(30)
        );
        
        assertThat(processedEvents).as("Should process event with null optional fields")
            .hasSize(1);
        
        EventHeader processed = processedEvents.get(0);
        assertThat(processed.getId()).isEqualTo(eventId);
    }
    
    /**
     * Test that field type changes are handled (if schema allows).
     * Note: This tests that processors don't crash on type mismatches.
     */
    @Test
    void testFieldTypeTolerance() throws Exception {
        String eventId = "type-tolerance-" + UUID.randomUUID().toString();
        String timestamp = Instant.now().toString();
        
        // Create event with different field types (string vs number)
        String headerDataWithTypeVariation = String.format(
            "{\"uuid\":\"%s\",\"eventName\":\"CarCreated\",\"eventType\":\"CarCreated\"," +
            "\"createdDate\":\"%s\",\"savedDate\":\"%s\",\"numericField\":\"123\"}",
            eventId, timestamp, timestamp
        );
        
        EventHeader eventWithTypeVariation = EventHeader.builder()
            .id(eventId)
            .eventName("CarCreated")
            .eventType("CarCreated")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(headerDataWithTypeVariation)
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
        
        // Publish event
        kafkaUtils.publishTestEvent(sourceTopic, eventWithTypeVariation);
        Thread.sleep(10000);
        
        // Verify event is processed (should not crash on type variations)
        List<EventHeader> processedEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events", 1, Duration.ofSeconds(30)
        );
        
        assertThat(processedEvents).as("Should handle type variations gracefully")
            .hasSize(1);
    }
}
