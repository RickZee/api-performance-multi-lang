package io.debezium.connector.dsql;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class DsqlOffsetContextTest {
    
    @Test
    void testNewOffsetContext() {
        DsqlOffsetContext context = new DsqlOffsetContext("event_headers");
        
        assertThat(context.getTable()).isEqualTo("event_headers");
        assertThat(context.getSavedDate()).isNull();
        assertThat(context.getLastId()).isNull();
        assertThat(context.isInitialized()).isFalse();
    }
    
    @Test
    void testLoadOffsetFromMap() {
        Map<String, Object> offset = new HashMap<>();
        offset.put("saved_date", "2025-06-15T10:30:05.123Z");
        offset.put("last_id", "event-12345");
        
        DsqlOffsetContext context = DsqlOffsetContext.load(offset, "event_headers");
        
        assertThat(context.getTable()).isEqualTo("event_headers");
        assertThat(context.getSavedDate()).isNotNull();
        assertThat(context.getLastId()).isEqualTo("event-12345");
        assertThat(context.isInitialized()).isTrue();
    }
    
    @Test
    void testLoadEmptyOffset() {
        Map<String, Object> offset = new HashMap<>();
        DsqlOffsetContext context = DsqlOffsetContext.load(offset, "event_headers");
        
        assertThat(context.getTable()).isEqualTo("event_headers");
        assertThat(context.isInitialized()).isFalse();
    }
    
    @Test
    void testUpdateOffset() {
        DsqlOffsetContext context = new DsqlOffsetContext("event_headers");
        
        Instant savedDate = Instant.parse("2025-06-15T10:30:05.123Z");
        context.update(savedDate, "event-12345");
        
        assertThat(context.getSavedDate()).isEqualTo(savedDate);
        assertThat(context.getLastId()).isEqualTo("event-12345");
        assertThat(context.isInitialized()).isTrue();
    }
    
    @Test
    void testToOffsetMap() {
        DsqlOffsetContext context = new DsqlOffsetContext("event_headers");
        Instant savedDate = Instant.parse("2025-06-15T10:30:05.123Z");
        context.update(savedDate, "event-12345");
        
        Map<String, Object> offsetMap = context.toOffsetMap();
        
        assertThat(offsetMap).containsKey("table");
        assertThat(offsetMap).containsKey("saved_date");
        assertThat(offsetMap).containsKey("last_id");
        assertThat(offsetMap.get("table")).isEqualTo("event_headers");
    }
    
    @Test
    void testGetPartition() {
        DsqlOffsetContext context = new DsqlOffsetContext("event_headers");
        Map<String, String> partition = context.getPartition();
        
        assertThat(partition).containsKey("table");
        assertThat(partition.get("table")).isEqualTo("event_headers");
    }
    
    @Test
    void testOffsetRecoveryAfterRestart() {
        // Test that offset can be recovered after connector restart
        Instant savedDate = Instant.parse("2025-06-15T10:30:05.123Z");
        String lastId = "event-12345";
        
        // Simulate saving offset
        DsqlOffsetContext original = new DsqlOffsetContext("event_headers");
        original.update(savedDate, lastId);
        Map<String, Object> savedOffset = original.toOffsetMap();
        
        // Simulate loading offset after restart
        DsqlOffsetContext recovered = DsqlOffsetContext.load(savedOffset, "event_headers");
        
        assertThat(recovered.isInitialized()).isTrue();
        assertThat(recovered.getSavedDate()).isEqualTo(savedDate);
        assertThat(recovered.getLastId()).isEqualTo(lastId);
    }
    
    @Test
    void testOffsetWithDuplicateSavedDate() {
        // Test offset handling with duplicate saved_date values
        Instant savedDate = Instant.parse("2025-06-15T10:30:05.123Z");
        
        // Update with same saved_date but different ID
        DsqlOffsetContext context = new DsqlOffsetContext("event_headers");
        context.update(savedDate, "event-1");
        context.update(savedDate, "event-2"); // Same timestamp, different ID
        
        // Should use the latest ID
        assertThat(context.getSavedDate()).isEqualTo(savedDate);
        assertThat(context.getLastId()).isEqualTo("event-2");
    }
    
    @Test
    void testOffsetWithVeryOldTimestamp() {
        // Test offset with very old timestamp (edge case)
        Instant oldDate = Instant.parse("2000-01-01T00:00:00Z");
        
        DsqlOffsetContext context = new DsqlOffsetContext("event_headers");
        context.update(oldDate, "old-event");
        
        assertThat(context.getSavedDate()).isEqualTo(oldDate);
        assertThat(context.isInitialized()).isTrue();
    }
    
    @Test
    void testOffsetWithFutureTimestamp() {
        // Test offset with future timestamp (clock skew scenario)
        Instant futureDate = Instant.now().plusSeconds(3600); // 1 hour in future
        
        DsqlOffsetContext context = new DsqlOffsetContext("event_headers");
        context.update(futureDate, "future-event");
        
        // Should accept future timestamps (handled by query logic)
        assertThat(context.getSavedDate()).isEqualTo(futureDate);
        assertThat(context.isInitialized()).isTrue();
    }
    
    @Test
    void testOffsetLoadWithInvalidDate() {
        // Test loading offset with invalid date format
        Map<String, Object> offset = new HashMap<>();
        offset.put("saved_date", "invalid-date-format");
        offset.put("last_id", "event-123");
        
        // Should handle gracefully (logs warning, doesn't throw)
        DsqlOffsetContext context = DsqlOffsetContext.load(offset, "event_headers");
        
        // Should not be initialized if date parsing fails
        assertThat(context.isInitialized()).isFalse();
        assertThat(context.getLastId()).isEqualTo("event-123"); // ID should still be loaded
    }
    
    @Test
    void testOffsetLoadWithNullValues() {
        // Test loading offset with null values
        Map<String, Object> offset = new HashMap<>();
        offset.put("saved_date", null);
        offset.put("last_id", null);
        
        DsqlOffsetContext context = DsqlOffsetContext.load(offset, "event_headers");
        
        assertThat(context.isInitialized()).isFalse();
        assertThat(context.getSavedDate()).isNull();
        assertThat(context.getLastId()).isNull();
    }
    
    @Test
    void testOffsetUpdateWithNullId() {
        // Test updating offset with null ID
        Instant savedDate = Instant.now();
        DsqlOffsetContext context = new DsqlOffsetContext("event_headers");
        
        context.update(savedDate, null);
        
        assertThat(context.getSavedDate()).isEqualTo(savedDate);
        assertThat(context.getLastId()).isNull();
        assertThat(context.isInitialized()).isTrue(); // Initialized if savedDate is set
    }
    
    @Test
    void testOffsetSerializationRoundTrip() {
        // Test that offset can be serialized and deserialized correctly
        Instant savedDate = Instant.parse("2025-06-15T10:30:05.123Z");
        String lastId = "event-12345";
        
        DsqlOffsetContext original = new DsqlOffsetContext("event_headers");
        original.update(savedDate, lastId);
        
        // Serialize
        Map<String, Object> offsetMap = original.toOffsetMap();
        
        // Deserialize
        DsqlOffsetContext deserialized = DsqlOffsetContext.load(offsetMap, "event_headers");
        
        assertThat(deserialized.getSavedDate()).isEqualTo(savedDate);
        assertThat(deserialized.getLastId()).isEqualTo(lastId);
        assertThat(deserialized.getTable()).isEqualTo("event_headers");
    }
}
