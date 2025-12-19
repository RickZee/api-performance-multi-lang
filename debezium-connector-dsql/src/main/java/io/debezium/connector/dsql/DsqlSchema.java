package io.debezium.connector.dsql;

import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.data.SchemaBuilder;
import org.apache.kafka.connect.data.Timestamp;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.DatabaseMetaData;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Types;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Builds Kafka Connect schemas for DSQL tables.
 * 
 * Generates schemas matching existing CDC format with CDC metadata fields:
 * __op, __table, __ts_ms. Compatible with existing Flink SQL jobs.
 */
public class DsqlSchema {
    private static final Logger LOGGER = LoggerFactory.getLogger(DsqlSchema.class);
    
    // CDC metadata field names
    public static final String OP_FIELD = "__op";
    public static final String TABLE_FIELD = "__table";
    public static final String TS_MS_FIELD = "__ts_ms";
    
    private final String tableName;
    private final String topicPrefix;
    private Schema keySchema;
    private Schema valueSchema;
    private final Map<String, Schema> columnSchemas = new HashMap<>();
    private String primaryKeyColumn;
    private List<String> columnNames = new ArrayList<>();
    private boolean hasUpdatedDateColumn = false;
    private boolean hasDeletedDateColumn = false;
    
    public DsqlSchema(String tableName, String topicPrefix) {
        this.tableName = tableName;
        this.topicPrefix = topicPrefix;
    }
    
    /**
     * Build schemas from DatabaseMetaData.
     * This is the preferred method as it provides complete column information.
     */
    public void buildSchemas(DatabaseMetaData metadata, String schemaName) throws SQLException {
        LOGGER.debug("Building schemas for table: {} in schema: {}", tableName, schemaName);
        
        // Get primary key column
        try (ResultSet pkRs = metadata.getPrimaryKeys(null, schemaName, tableName)) {
            if (pkRs.next()) {
                primaryKeyColumn = pkRs.getString("COLUMN_NAME");
                LOGGER.debug("Found primary key column: {}", primaryKeyColumn);
            }
        }
        
        // Get all columns
        SchemaBuilder valueSchemaBuilder = SchemaBuilder.struct()
                .name(topicPrefix + "." + tableName + ".Value")
                .version(1)
                .doc("Schema for " + tableName + " table");
        
        SchemaBuilder keySchemaBuilder = SchemaBuilder.struct()
                .name(topicPrefix + "." + tableName + ".Key")
                .version(1)
                .doc("Key schema for " + tableName + " table");
        
        columnNames.clear();
        columnSchemas.clear();
        
        try (ResultSet columnsRs = metadata.getColumns(null, schemaName, tableName, null)) {
            while (columnsRs.next()) {
                String columnName = columnsRs.getString("COLUMN_NAME");
                int columnType = columnsRs.getInt("DATA_TYPE");
                int nullable = columnsRs.getInt("NULLABLE");
                boolean isNullable = nullable == DatabaseMetaData.columnNullable;
                
                // Detect UPDATE/DELETE support columns
                if (columnName.equalsIgnoreCase("updated_date") || columnName.equalsIgnoreCase("updated_at")) {
                    hasUpdatedDateColumn = true;
                }
                if (columnName.equalsIgnoreCase("deleted_date") || columnName.equalsIgnoreCase("deleted_at")) {
                    hasDeletedDateColumn = true;
                }
                
                Schema columnSchema = mapJdbcTypeToSchema(columnType, isNullable);
                columnSchemas.put(columnName, columnSchema);
                columnNames.add(columnName);
                valueSchemaBuilder.field(columnName, columnSchema);
                
                // Use primary key column for key schema, or first column if no PK found
                if (primaryKeyColumn != null && columnName.equals(primaryKeyColumn)) {
                    keySchemaBuilder.field(columnName, columnSchema);
                } else if (primaryKeyColumn == null && columnNames.size() == 1) {
                    keySchemaBuilder.field(columnName, columnSchema);
                }
            }
        }
        
        // If no primary key was found, use first column
        if (primaryKeyColumn == null && !columnNames.isEmpty()) {
            primaryKeyColumn = columnNames.get(0);
            LOGGER.warn("No primary key found for table {}, using first column as key: {}", tableName, primaryKeyColumn);
        }
        
        // Add CDC metadata fields
        valueSchemaBuilder.field(OP_FIELD, Schema.OPTIONAL_STRING_SCHEMA)
                .field(TABLE_FIELD, Schema.STRING_SCHEMA)
                .field(TS_MS_FIELD, Timestamp.builder().optional().build());
        
        this.valueSchema = valueSchemaBuilder.build();
        this.keySchema = keySchemaBuilder.build();
        
        LOGGER.debug("Built schemas: {} columns + 3 CDC metadata fields", columnNames.size());
    }
    
    /**
     * Build schemas from ResultSet metadata.
     * Fallback method for compatibility.
     */
    public void buildSchemas(ResultSetMetaData metadata) throws SQLException {
        LOGGER.debug("Building schemas for table: {} from ResultSet metadata", tableName);
        
        SchemaBuilder valueSchemaBuilder = SchemaBuilder.struct()
                .name(topicPrefix + "." + tableName + ".Value")
                .version(1)
                .doc("Schema for " + tableName + " table");
        
        SchemaBuilder keySchemaBuilder = SchemaBuilder.struct()
                .name(topicPrefix + "." + tableName + ".Key")
                .version(1)
                .doc("Key schema for " + tableName + " table");
        
        columnNames.clear();
        columnSchemas.clear();
        
        int columnCount = metadata.getColumnCount();
        for (int i = 1; i <= columnCount; i++) {
            String columnName = metadata.getColumnName(i);
            int columnType = metadata.getColumnType(i);
            boolean nullable = metadata.isNullable(i) == ResultSetMetaData.columnNullable;
            
            // Detect UPDATE/DELETE support columns
            if (columnName.equalsIgnoreCase("updated_date") || columnName.equalsIgnoreCase("updated_at")) {
                hasUpdatedDateColumn = true;
            }
            if (columnName.equalsIgnoreCase("deleted_date") || columnName.equalsIgnoreCase("deleted_at")) {
                hasDeletedDateColumn = true;
            }
            
            Schema columnSchema = mapJdbcTypeToSchema(columnType, nullable);
            columnSchemas.put(columnName, columnSchema);
            columnNames.add(columnName);
            valueSchemaBuilder.field(columnName, columnSchema);
            
            // Use first column as key (typically ID)
            if (i == 1) {
                primaryKeyColumn = columnName;
                keySchemaBuilder.field(columnName, columnSchema);
            }
        }
        
        // Add CDC metadata fields
        valueSchemaBuilder.field(OP_FIELD, Schema.OPTIONAL_STRING_SCHEMA)
                .field(TABLE_FIELD, Schema.STRING_SCHEMA)
                .field(TS_MS_FIELD, Timestamp.builder().optional().build());
        
        this.valueSchema = valueSchemaBuilder.build();
        this.keySchema = keySchemaBuilder.build();
        
        LOGGER.debug("Built schemas: {} columns + 3 CDC metadata fields", columnCount);
    }
    
    /**
     * Map JDBC type to Kafka Connect schema.
     */
    private Schema mapJdbcTypeToSchema(int jdbcType, boolean nullable) {
        SchemaBuilder builder;
        
        switch (jdbcType) {
            case Types.BOOLEAN:
            case Types.BIT:
                builder = SchemaBuilder.bool();
                break;
            case Types.TINYINT:
            case Types.SMALLINT:
            case Types.INTEGER:
                builder = SchemaBuilder.int32();
                break;
            case Types.BIGINT:
                builder = SchemaBuilder.int64();
                break;
            case Types.REAL:
            case Types.FLOAT:
                builder = SchemaBuilder.float32();
                break;
            case Types.DOUBLE:
                builder = SchemaBuilder.float64();
                break;
            case Types.DECIMAL:
            case Types.NUMERIC:
                builder = SchemaBuilder.string(); // Decimal as string for precision
                break;
            case Types.CHAR:
            case Types.VARCHAR:
            case Types.LONGVARCHAR:
            case Types.NCHAR:
            case Types.NVARCHAR:
            case Types.LONGNVARCHAR:
                builder = SchemaBuilder.string();
                break;
            case Types.DATE:
                builder = Timestamp.builder();
                break;
            case Types.TIME:
                builder = Timestamp.builder();
                break;
            case Types.TIMESTAMP:
            case Types.TIMESTAMP_WITH_TIMEZONE:
                builder = Timestamp.builder();
                break;
            case Types.BINARY:
            case Types.VARBINARY:
            case Types.LONGVARBINARY:
            case Types.BLOB:
                builder = SchemaBuilder.bytes();
                break;
            case Types.CLOB:
            case Types.NCLOB:
                builder = SchemaBuilder.string();
                break;
            case Types.ARRAY:
                builder = SchemaBuilder.string(); // Arrays as JSON string
                break;
            case Types.OTHER: // JSONB, JSON, etc.
                builder = SchemaBuilder.string(); // JSON types as string
                break;
            default:
                LOGGER.warn("Unknown JDBC type: {}, mapping to string", jdbcType);
                builder = SchemaBuilder.string();
        }
        
        if (nullable) {
            builder.optional();
        }
        
        return builder.build();
    }
    
    /**
     * Validate that required columns exist.
     * @throws SQLException if required columns are missing
     */
    public void validateRequiredColumns() throws SQLException {
        if (!columnSchemas.containsKey("saved_date")) {
            throw new SQLException("Table " + tableName + " must have a 'saved_date' column for change detection");
        }
        if (primaryKeyColumn == null) {
            throw new SQLException("Table " + tableName + " must have a primary key column");
        }
    }
    
    /**
     * Get column names in order.
     */
    public List<String> getColumnNames() {
        return new ArrayList<>(columnNames);
    }
    
    // Getters
    public Schema getKeySchema() { return keySchema; }
    public Schema getValueSchema() { return valueSchema; }
    public Map<String, Schema> getColumnSchemas() { return columnSchemas; }
    public String getTableName() { return tableName; }
    public String getPrimaryKeyColumn() { return primaryKeyColumn; }
    public boolean hasUpdatedDateColumn() { return hasUpdatedDateColumn; }
    public boolean hasDeletedDateColumn() { return hasDeletedDateColumn; }
}
