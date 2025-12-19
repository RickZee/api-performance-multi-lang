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
    private boolean schemaBuilt = false;
    
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
     * Initialize schema from database metadata.
     * Should be called before first poll.
     */
    public void initializeSchema() throws SQLException {
        if (schemaBuilt) {
            return;
        }
        
        try (Connection conn = connectionPool.getConnection()) {
            DatabaseMetaData metadata = conn.getMetaData();
            // Use 'public' schema by default (PostgreSQL convention)
            schema.buildSchemas(metadata, "public");
            schema.validateRequiredColumns();
            schemaBuilt = true;
            LOGGER.info("Schema initialized for table: {}", tableName);
        }
    }
    
    /**
     * Poll for changes and return SourceRecords.
     */
    public List<SourceRecord> poll() throws SQLException {
        // Initialize schema if not already done
        if (!schemaBuilt) {
            initializeSchema();
        }
        
        List<SourceRecord> records = new ArrayList<>();
        
        try (Connection conn = connectionPool.getConnection()) {
            String query = buildQuery();
            LOGGER.debug("Executing query: {}", query);
            
            try (PreparedStatement stmt = conn.prepareStatement(query)) {
                setQueryParameters(stmt);
                
                try (ResultSet rs = stmt.executeQuery()) {
                    
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
                        // Use primary key column from schema
                        String pkColumn = schema.getPrimaryKeyColumn();
                        if (pkColumn != null) {
                            latestId = rs.getString(pkColumn);
                        }
                        
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
     * Dynamically builds SELECT query with all columns from schema.
     */
    private String buildQuery() {
        StringBuilder query = new StringBuilder();
        query.append("SELECT ");
        
        // Build column list from schema
        List<String> columnNames = schema.getColumnNames();
        if (columnNames.isEmpty()) {
            // Fallback to SELECT * if schema not built yet
            query.append("*");
        } else {
            // Quote column names to handle reserved words and special characters
            for (int i = 0; i < columnNames.size(); i++) {
                if (i > 0) {
                    query.append(", ");
                }
                query.append("\"").append(columnNames.get(i)).append("\"");
            }
        }
        
        query.append(" FROM \"").append(tableName).append("\"");
        
        if (offsetContext.isInitialized()) {
            query.append(" WHERE \"saved_date\" > ? ");
        }
        
        query.append(" ORDER BY \"saved_date\" ASC ");
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
        // Build key struct using primary key column
        org.apache.kafka.connect.data.Struct keyStruct = new org.apache.kafka.connect.data.Struct(schema.getKeySchema());
        String pkColumn = schema.getPrimaryKeyColumn();
        if (pkColumn != null) {
            Object pkValue = rs.getObject(pkColumn);
            keyStruct.put(pkColumn, pkValue);
        }
        
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
                } else if (value instanceof java.sql.Timestamp) {
                    // Convert Timestamp to java.util.Date for Kafka Connect Timestamp schema
                    value = new java.util.Date(((java.sql.Timestamp) value).getTime());
                } else if (value instanceof java.sql.Date) {
                    // Convert Date to java.util.Date
                    value = new java.util.Date(((java.sql.Date) value).getTime());
                } else if (value instanceof java.sql.Time) {
                    // Convert Time to java.util.Date
                    value = new java.util.Date(((java.sql.Time) value).getTime());
                }
                valueStruct.put(columnName, value);
            }
        }
        
        // Determine operation type based on column values
        String op = determineOperationType(rs);
        
        // Add CDC metadata
        valueStruct.put(DsqlSchema.OP_FIELD, op);
        valueStruct.put(DsqlSchema.TABLE_FIELD, tableName);
        // Timestamp schema expects java.util.Date
        valueStruct.put(DsqlSchema.TS_MS_FIELD, new java.util.Date(System.currentTimeMillis()));
        
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
    
    /**
     * Determine the operation type (create, update, delete) based on column values.
     */
    private String determineOperationType(ResultSet rs) throws SQLException {
        // Check for deleted_date column first (highest priority)
        if (schema.hasDeletedDateColumn()) {
            try {
                Timestamp deletedDate = rs.getTimestamp("deleted_date");
                if (deletedDate != null) {
                    return "d"; // delete
                }
            } catch (SQLException e) {
                // Column might have different name, try alternative
                try {
                    Timestamp deletedDate = rs.getTimestamp("deleted_at");
                    if (deletedDate != null) {
                        return "d"; // delete
                    }
                } catch (SQLException ignored) {
                    // Column doesn't exist or is null
                }
            }
        }
        
        // Check for updated_date column
        if (schema.hasUpdatedDateColumn()) {
            try {
                Timestamp updatedDate = rs.getTimestamp("updated_date");
                Timestamp createdDate = null;
                try {
                    createdDate = rs.getTimestamp("created_date");
                } catch (SQLException ignored) {
                    // created_date might not exist
                }
                
                if (updatedDate != null && createdDate != null) {
                    // If updated_date is significantly after created_date, it's an update
                    if (updatedDate.after(new Timestamp(createdDate.getTime() + 1000))) { // 1 second threshold
                        return "u"; // update
                    }
                } else if (updatedDate != null) {
                    // If we have updated_date but no created_date, assume update
                    return "u"; // update
                }
            } catch (SQLException e) {
                // Column might have different name, try alternative
                try {
                    Timestamp updatedDate = rs.getTimestamp("updated_at");
                    if (updatedDate != null) {
                        return "u"; // update
                    }
                } catch (SQLException ignored) {
                    // Column doesn't exist or is null
                }
            }
        }
        
        // Default to create/insert
        return "c"; // create
    }
}
