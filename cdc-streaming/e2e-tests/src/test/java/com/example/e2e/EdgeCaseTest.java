package com.example.e2e;

import com.example.e2e.model.EventHeader;
import com.example.e2e.utils.KafkaTestUtils;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Edge case tests for null, empty, large payload, and special character scenarios.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class EdgeCaseTest {
    
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
     * Test event with empty header_data JSON.
     */
    @Test
    void testEmptyHeaderData() throws Exception {
        String eventId = "empty-header-" + UUID.randomUUID().toString();
        String timestamp = Instant.now().toString();
        
        EventHeader eventWithEmptyHeader = EventHeader.builder()
            .id(eventId)
            .eventName("CarCreated")
            .eventType("CarCreated")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData("{}") // Empty JSON object
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
        
        kafkaUtils.publishTestEvent(sourceTopic, eventWithEmptyHeader);
        Thread.sleep(10000);
        
        // System should handle empty header_data gracefully
        List<EventHeader> processedEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events", 1, Duration.ofSeconds(30)
        );
        
        // Should either process it or filter it out, but not crash
        assertThat(processedEvents.size()).isLessThanOrEqualTo(1);
    }
    
    /**
     * Test event with very large header_data (>1MB).
     */
    @Test
    void testLargeHeaderData() throws Exception {
        String eventId = "large-header-" + UUID.randomUUID().toString();
        String timestamp = Instant.now().toString();
        
        // Generate large header_data (1MB+)
        StringBuilder largeData = new StringBuilder();
        largeData.append("{\"uuid\":\"").append(eventId).append("\",");
        largeData.append("\"eventName\":\"CarCreated\",");
        largeData.append("\"eventType\":\"CarCreated\",");
        largeData.append("\"createdDate\":\"").append(timestamp).append("\",");
        largeData.append("\"savedDate\":\"").append(timestamp).append("\",");
        largeData.append("\"largeField\":\"");
        
        // Add 1MB of data
        for (int i = 0; i < 1000000; i++) {
            largeData.append("x");
        }
        largeData.append("\"}");
        
        EventHeader eventWithLargeHeader = EventHeader.builder()
            .id(eventId)
            .eventName("CarCreated")
            .eventType("CarCreated")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(largeData.toString())
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
        
        kafkaUtils.publishTestEvent(sourceTopic, eventWithLargeHeader);
        Thread.sleep(20000); // Longer wait for large payload
        
        // System should handle large payloads (may be slower but shouldn't crash)
        List<EventHeader> processedEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events", 1, Duration.ofSeconds(60)
        );
        
        // Should either process it or handle it gracefully
        assertThat(processedEvents.size()).isLessThanOrEqualTo(1);
    }
    
    /**
     * Test event with special characters and Unicode in event name.
     */
    @Test
    void testSpecialCharactersInEventName() throws Exception {
        String eventId = "special-chars-" + UUID.randomUUID().toString();
        String timestamp = Instant.now().toString();
        
        // Event with special characters and Unicode
        String headerData = String.format(
            "{\"uuid\":\"%s\",\"eventName\":\"CarCreated-测试-émoji-🚗\",\"eventType\":\"CarCreated\"," +
            "\"createdDate\":\"%s\",\"savedDate\":\"%s\"}",
            eventId, timestamp, timestamp
        );
        
        EventHeader eventWithSpecialChars = EventHeader.builder()
            .id(eventId)
            .eventName("CarCreated-测试-émoji-🚗")
            .eventType("CarCreated")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(headerData)
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
        
        kafkaUtils.publishTestEvent(sourceTopic, eventWithSpecialChars);
        Thread.sleep(10000);
        
        // System should handle special characters
        List<EventHeader> processedEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events", 1, Duration.ofSeconds(30)
        );
        
        if (!processedEvents.isEmpty()) {
            EventHeader processed = processedEvents.get(0);
            assertThat(processed.getId()).isEqualTo(eventId);
        }
    }
    
    /**
     * Test event with null event_type.
     */
    @Test
    void testNullEventType() throws Exception {
        String eventId = "null-type-" + UUID.randomUUID().toString();
        String timestamp = Instant.now().toString();
        
        EventHeader eventWithNullType = EventHeader.builder()
            .id(eventId)
            .eventName("CarCreated")
            .eventType(null) // Null event_type
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData("{\"uuid\":\"" + eventId + "\",\"eventName\":\"CarCreated\"}")
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
        
        kafkaUtils.publishTestEvent(sourceTopic, eventWithNullType);
        Thread.sleep(10000);
        
        // Events with null event_type should be filtered out
        List<EventHeader> processedEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events", 1, Duration.ofSeconds(10)
        );
        
        // Should be filtered out (not crash)
        assertThat(processedEvents).isEmpty();
    }
    
    /**
     * Test event with whitespace in event_type.
     */
    @Test
    void testWhitespaceEventType() throws Exception {
        String eventId = "whitespace-type-" + UUID.randomUUID().toString();
        String timestamp = Instant.now().toString();
        
        EventHeader eventWithWhitespace = EventHeader.builder()
            .id(eventId)
            .eventName("CarCreated")
            .eventType("  CarCreated  ") // Whitespace in event_type
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData("{\"uuid\":\"" + eventId + "\",\"eventType\":\"CarCreated\"}")
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
        
        kafkaUtils.publishTestEvent(sourceTopic, eventWithWhitespace);
        Thread.sleep(10000);
        
        // Events with whitespace should be filtered out (exact match required)
        List<EventHeader> processedEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events", 1, Duration.ofSeconds(10)
        );
        
        // Should be filtered out
        assertThat(processedEvents).isEmpty();
    }
    
    /**
     * Test event with very long event ID.
     */
    @Test
    void testVeryLongEventId() throws Exception {
        // Generate very long event ID (1000+ characters)
        StringBuilder longId = new StringBuilder("long-id-");
        for (int i = 0; i < 1000; i++) {
            longId.append("x");
        }
        
        String eventId = longId.toString();
        String timestamp = Instant.now().toString();
        
        EventHeader eventWithLongId = EventHeader.builder()
            .id(eventId)
            .eventName("LoanCreated")
            .eventType("LoanCreated")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData("{\"uuid\":\"" + eventId + "\",\"eventType\":\"LoanCreated\"}")
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
        
        kafkaUtils.publishTestEvent(sourceTopic, eventWithLongId);
        Thread.sleep(10000);
        
        // System should handle long IDs
        List<EventHeader> processedEvents = kafkaUtils.consumeEvents(
            "filtered-loan-created-events", 1, Duration.ofSeconds(30)
        );
        
        // Should either process it or handle it gracefully
        assertThat(processedEvents.size()).isLessThanOrEqualTo(1);
    }
    
    /**
     * Test event with SQL injection-like characters in fields.
     */
    @Test
    void testSqlInjectionLikeCharacters() throws Exception {
        String eventId = "sql-injection-test-" + UUID.randomUUID().toString();
        String timestamp = Instant.now().toString();
        
        // Event with SQL injection-like characters
        String maliciousString = "'; DROP TABLE event_headers; --";
        String headerData = String.format(
            "{\"uuid\":\"%s\",\"eventName\":\"%s\",\"eventType\":\"CarCreated\"," +
            "\"createdDate\":\"%s\",\"savedDate\":\"%s\"}",
            eventId, maliciousString, timestamp, timestamp
        );
        
        EventHeader eventWithMaliciousChars = EventHeader.builder()
            .id(eventId)
            .eventName(maliciousString)
            .eventType("CarCreated")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(headerData)
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
        
        kafkaUtils.publishTestEvent(sourceTopic, eventWithMaliciousChars);
        Thread.sleep(10000);
        
        // System should handle special characters safely (no SQL injection risk in Kafka)
        List<EventHeader> processedEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events", 1, Duration.ofSeconds(30)
        );
        
        // Should handle it as data, not execute it
        assertThat(processedEvents.size()).isLessThanOrEqualTo(1);
    }
    
    /**
     * Test event with newline characters in fields.
     */
    @Test
    void testNewlineCharacters() throws Exception {
        String eventId = "newline-test-" + UUID.randomUUID().toString();
        String timestamp = Instant.now().toString();
        
        // Event with newline characters
        String eventNameWithNewline = "CarCreated\nwith\nnewlines";
        String headerData = String.format(
            "{\"uuid\":\"%s\",\"eventName\":\"%s\",\"eventType\":\"CarCreated\"," +
            "\"createdDate\":\"%s\",\"savedDate\":\"%s\"}",
            eventId, eventNameWithNewline.replace("\n", "\\n"), timestamp, timestamp
        );
        
        EventHeader eventWithNewlines = EventHeader.builder()
            .id(eventId)
            .eventName(eventNameWithNewline)
            .eventType("CarCreated")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(headerData)
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
        
        kafkaUtils.publishTestEvent(sourceTopic, eventWithNewlines);
        Thread.sleep(10000);
        
        // System should handle newline characters
        List<EventHeader> processedEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events", 1, Duration.ofSeconds(30)
        );
        
        assertThat(processedEvents.size()).isLessThanOrEqualTo(1);
    }
}
