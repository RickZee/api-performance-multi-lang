package com.loadtest.dsql;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;

/**
 * Repository for inserting events into DSQL database.
 */
public class EventRepository {
    private static final Logger LOGGER = LoggerFactory.getLogger(EventRepository.class);
    private static final ObjectMapper mapper = new ObjectMapper();
    
    private static final String INDIVIDUAL_INSERT_SQL = 
        "INSERT INTO car_entities_schema.business_events " +
        "(id, event_name, event_type, created_date, saved_date, event_data) " +
        "VALUES (?, ?, ?, ?, ?, ?) " +
        "ON CONFLICT (id) DO NOTHING";
    
    private static final String BATCH_INSERT_SQL_PREFIX = 
        "INSERT INTO car_entities_schema.business_events " +
        "(id, event_name, event_type, created_date, saved_date, event_data) " +
        "VALUES ";
    
    /**
     * Insert a single event.
     */
    public static int insertIndividual(Connection conn, String eventId, ObjectNode event) throws SQLException {
        try (PreparedStatement stmt = conn.prepareStatement(INDIVIDUAL_INSERT_SQL)) {
            ObjectNode eventHeader = (ObjectNode) event.get("eventHeader");
            
            stmt.setString(1, eventId);
            stmt.setString(2, eventHeader.get("eventName").asText());
            stmt.setString(3, eventHeader.get("eventType").asText());
            stmt.setTimestamp(4, Timestamp.from(Instant.parse(eventHeader.get("createdDate").asText())));
            stmt.setTimestamp(5, Timestamp.from(Instant.parse(eventHeader.get("savedDate").asText())));
            stmt.setString(6, event.toString()); // Full event as JSON string
            
            return stmt.executeUpdate();
        }
    }
    
    // PostgreSQL parameter limit: 65,535 parameters per statement
    // Each row has 6 parameters (id, event_name, event_type, created_date, saved_date, event_data)
    // Max safe batch size: 65,535 / 6 = ~10,925 rows. We cap at 10,000 for safety.
    private static final int MAX_BATCH_SIZE = 10000;
    
    /**
     * Insert a batch of events in a single statement.
     * Supports up to 10,000 rows per batch (PostgreSQL parameter limit).
     */
    public static int insertBatch(Connection conn, String[] eventIds, ObjectNode[] events) throws SQLException {
        if (events.length == 0) {
            return 0;
        }
        
        // Validate batch size
        if (events.length > MAX_BATCH_SIZE) {
            throw new IllegalArgumentException(
                String.format("Batch size %d exceeds maximum of %d rows (PostgreSQL parameter limit)", 
                             events.length, MAX_BATCH_SIZE));
        }
        
        // Optimize SQL string building for large batches
        int totalParams = events.length * 6;
        StringBuilder sql = new StringBuilder(BATCH_INSERT_SQL_PREFIX);
        sql.ensureCapacity(BATCH_INSERT_SQL_PREFIX.length() + (events.length * 30)); // Pre-allocate capacity
        
        for (int i = 0; i < events.length; i++) {
            if (i > 0) {
                sql.append(", ");
            }
            sql.append("(?, ?, ?, ?, ?, ?)");
        }
        sql.append(" ON CONFLICT (id) DO NOTHING");
        
        try (PreparedStatement stmt = conn.prepareStatement(sql.toString())) {
            int paramIndex = 1;
            for (int i = 0; i < events.length; i++) {
                ObjectNode event = events[i];
                ObjectNode eventHeader = (ObjectNode) event.get("eventHeader");
                
                stmt.setString(paramIndex++, eventIds[i]);
                stmt.setString(paramIndex++, eventHeader.get("eventName").asText());
                stmt.setString(paramIndex++, eventHeader.get("eventType").asText());
                stmt.setTimestamp(paramIndex++, Timestamp.from(Instant.parse(eventHeader.get("createdDate").asText())));
                stmt.setTimestamp(paramIndex++, Timestamp.from(Instant.parse(eventHeader.get("savedDate").asText())));
                stmt.setString(paramIndex++, event.toString());
            }
            
            return stmt.executeUpdate();
        }
    }
}

