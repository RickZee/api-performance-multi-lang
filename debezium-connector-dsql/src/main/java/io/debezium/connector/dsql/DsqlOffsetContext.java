package io.debezium.connector.dsql;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.data.SchemaBuilder;
import org.apache.kafka.connect.data.Struct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Map;

/**
 * Manages offset tracking for DSQL CDC.
 * 
 * Stores offset information including table name, last processed timestamp,
 * and last processed record ID for resumability.
 */
public class DsqlOffsetContext {
    private static final Logger LOGGER = LoggerFactory.getLogger(DsqlOffsetContext.class);
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
    private static final DateTimeFormatter ISO_FORMATTER = DateTimeFormatter.ISO_INSTANT;
    
    private static final String OFFSET_TABLE = "table";
    private static final String OFFSET_SAVED_DATE = "saved_date";
    private static final String OFFSET_LAST_ID = "last_id";
    
    private final String table;
    private Instant savedDate;
    private String lastId;
    
    public DsqlOffsetContext(String table) {
        this.table = table;
        this.savedDate = null;
        this.lastId = null;
    }
    
    /**
     * Load offset from Kafka Connect offset storage.
     */
    public static DsqlOffsetContext load(Map<String, Object> offset, String table) {
        DsqlOffsetContext context = new DsqlOffsetContext(table);
        
        if (offset != null && !offset.isEmpty()) {
            String savedDateStr = (String) offset.get(OFFSET_SAVED_DATE);
            if (savedDateStr != null) {
                try {
                    context.savedDate = Instant.parse(savedDateStr);
                } catch (Exception e) {
                    LOGGER.warn("Failed to parse saved_date from offset: {}", savedDateStr, e);
                }
            }
            
            context.lastId = (String) offset.get(OFFSET_LAST_ID);
        }
        
        LOGGER.debug("Loaded offset for table {}: saved_date={}, last_id={}", 
                    table, context.savedDate, context.lastId);
        return context;
    }
    
    /**
     * Update offset with new values.
     */
    public void update(Instant newSavedDate, String newLastId) {
        this.savedDate = newSavedDate;
        this.lastId = newLastId;
        LOGGER.debug("Updated offset for table {}: saved_date={}, last_id={}", 
                    table, savedDate, lastId);
    }
    
    /**
     * Get offset as Map for Kafka Connect offset storage.
     */
    public Map<String, Object> toOffsetMap() {
        Map<String, Object> offset = new java.util.HashMap<>();
        offset.put(OFFSET_TABLE, table);
        
        if (savedDate != null) {
            offset.put(OFFSET_SAVED_DATE, ISO_FORMATTER.format(savedDate));
        }
        
        if (lastId != null) {
            offset.put(OFFSET_LAST_ID, lastId);
        }
        
        return offset;
    }
    
    /**
     * Get offset partition for Kafka Connect.
     */
    public Map<String, String> getPartition() {
        Map<String, String> partition = new java.util.HashMap<>();
        partition.put(OFFSET_TABLE, table);
        return partition;
    }
    
    // Getters
    public String getTable() { return table; }
    public Instant getSavedDate() { return savedDate; }
    public String getLastId() { return lastId; }
    
    /**
     * Check if offset has been initialized.
     */
    public boolean isInitialized() {
        return savedDate != null;
    }
}
