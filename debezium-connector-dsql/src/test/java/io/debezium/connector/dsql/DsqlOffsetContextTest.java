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
}
