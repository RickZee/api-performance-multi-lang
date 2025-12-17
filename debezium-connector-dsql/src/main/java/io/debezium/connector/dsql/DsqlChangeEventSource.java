package io.debezium.connector.dsql;

import io.debezium.connector.dsql.connection.DsqlConnectionPool;
import org.apache.kafka.connect.source.SourceRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.*;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Change detection logic for DSQL CDC.
 * 
 * Uses timestamp-based polling to detect changes since last offset.
 * Queries table for records with saved_date > last_offset_timestamp.
 */
public class DsqlChangeEventSource {
    private static final Logger LOGGER = LoggerFactory.getLogger(DsqlChangeEventSource.class);
    
    private final DsqlConnectionPool connectionPool;
    private final DsqlConnectorConfig config;
    private final String tableName;
    private final DsqlSchema schema;
    private final DsqlOffsetContext offsetContext;
    
    public DsqlChangeEventSource(DsqlConnectionPool connectionPool,
                                 DsqlConnectorConfig config,
                                 String tableName,
                                 DsqlSchema schema,
                                 DsqlOffsetContext offsetContext) {
        this.connectionPool = connectionPool;
        this.config = config;
        this.tableName = tableName;
        this.schema = schema;
        this.offsetContext = offsetContext;
    }
    
    /**
     * Poll for changes and return SourceRecords.
     */
    public List<SourceRecord> poll() throws SQLException {
        List<SourceRecord> records = new ArrayList<>();
        
        try (Connection conn = connectionPool.getConnection()) {
            String query = buildQuery();
            LOGGER.debug("Executing query: {}", query);
            
            try (PreparedStatement stmt = conn.prepareStatement(query)) {
                setQueryParameters(stmt);
                
                try (ResultSet rs = stmt.executeQuery()) {
                    // Build schema if not already built
                    // We need to build schema from metadata before processing rows
                    if (schema.getValueSchema() == null) {
                        // Create a separate query to get metadata without executing
                        try (PreparedStatement metaStmt = conn.prepareStatement(
                                "SELECT id, event_name, event_type, created_date, saved_date, header_data FROM " + tableName + " WHERE 1=0")) {
                            try (ResultSet metaRs = metaStmt.executeQuery()) {
                                schema.buildSchemas(metaRs.getMetaData());
                            }
                        }
                    }
                    
                    int recordCount = 0;
                    Instant latestSavedDate = null;
                    String latestId = null;
                    
                    while (rs.next() && recordCount < config.getBatchSize()) {
                        SourceRecord record = buildSourceRecord(rs);
                        records.add(record);
                        
                        // Track latest values for offset update
                        Timestamp savedDate = rs.getTimestamp("saved_date");
                        if (savedDate != null) {
                            latestSavedDate = savedDate.toInstant();
                        }
                        latestId = rs.getString("id");
                        
                        recordCount++;
                    }
                    
                    // Update offset if we processed records
                    if (recordCount > 0 && latestSavedDate != null) {
                        offsetContext.update(latestSavedDate, latestId);
                    }
                    
                    LOGGER.debug("Polled {} records from table {}", recordCount, tableName);
                }
            }
        }
        
        return records;
    }
    
    /**
     * Build query for change detection.
     */
    private String buildQuery() {
        StringBuilder query = new StringBuilder();
        query.append("SELECT id, event_name, event_type, created_date, saved_date, header_data ");
        query.append("FROM ").append(tableName);
        
        if (offsetContext.isInitialized()) {
            query.append(" WHERE saved_date > ? ");
        }
        
        query.append(" ORDER BY saved_date ASC ");
        query.append(" LIMIT ? ");
        
        return query.toString();
    }
    
    /**
     * Set query parameters.
     */
    private void setQueryParameters(PreparedStatement stmt) throws SQLException {
        int paramIndex = 1;
        
        if (offsetContext.isInitialized()) {
            Timestamp lastSavedDate = Timestamp.from(offsetContext.getSavedDate());
            stmt.setTimestamp(paramIndex++, lastSavedDate);
        }
        
        stmt.setInt(paramIndex, config.getBatchSize());
    }
    
    /**
     * Build SourceRecord from ResultSet row.
     */
    private SourceRecord buildSourceRecord(ResultSet rs) throws SQLException {
        // Build key struct
        org.apache.kafka.connect.data.Struct keyStruct = new org.apache.kafka.connect.data.Struct(schema.getKeySchema());
        keyStruct.put("id", rs.getString("id"));
        
        // Build value struct
        org.apache.kafka.connect.data.Struct valueStruct = new org.apache.kafka.connect.data.Struct(schema.getValueSchema());
        
        // Add table columns
        for (Map.Entry<String, org.apache.kafka.connect.data.Schema> entry : schema.getColumnSchemas().entrySet()) {
            String columnName = entry.getKey();
            Object value = rs.getObject(columnName);
            if (value != null) {
                // Handle JSONB/JSON types
                if (value instanceof java.sql.Clob) {
                    value = ((java.sql.Clob) value).getSubString(1, (int) ((java.sql.Clob) value).length());
                } else if (value instanceof java.sql.Blob) {
                    value = new String(((java.sql.Blob) value).getBytes(1, (int) ((java.sql.Blob) value).length()));
                }
                valueStruct.put(columnName, value);
            }
        }
        
        // Add CDC metadata
        valueStruct.put(DsqlSchema.OP_FIELD, "c"); // 'c' for create/insert
        valueStruct.put(DsqlSchema.TABLE_FIELD, tableName);
        valueStruct.put(DsqlSchema.TS_MS_FIELD, System.currentTimeMillis());
        
        // Build topic name
        String topicName = config.getTopicPrefix() + ".public." + tableName;
        
        return new SourceRecord(
                offsetContext.getPartition(),
                offsetContext.toOffsetMap(),
                topicName,
                schema.getKeySchema(),
                keyStruct,
                schema.getValueSchema(),
                valueStruct
        );
    }
}
