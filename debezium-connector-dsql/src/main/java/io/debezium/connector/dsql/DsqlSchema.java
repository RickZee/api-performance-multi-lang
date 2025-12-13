package io.debezium.connector.dsql;

import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.data.SchemaBuilder;
import org.apache.kafka.connect.data.Timestamp;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Types;
import java.util.HashMap;
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
    
    public DsqlSchema(String tableName, String topicPrefix) {
        this.tableName = tableName;
        this.topicPrefix = topicPrefix;
    }
    
    /**
     * Build schemas from ResultSet metadata.
     */
    public void buildSchemas(ResultSetMetaData metadata) throws SQLException {
        LOGGER.debug("Building schemas for table: {}", tableName);
        
        SchemaBuilder valueSchemaBuilder = SchemaBuilder.struct()
                .name(topicPrefix + "." + tableName + ".Value")
                .version(1)
                .doc("Schema for " + tableName + " table");
        
        SchemaBuilder keySchemaBuilder = SchemaBuilder.struct()
                .name(topicPrefix + "." + tableName + ".Key")
                .version(1)
                .doc("Key schema for " + tableName + " table");
        
        int columnCount = metadata.getColumnCount();
        for (int i = 1; i <= columnCount; i++) {
            String columnName = metadata.getColumnName(i);
            int columnType = metadata.getColumnType(i);
            boolean nullable = metadata.isNullable(i) == ResultSetMetaData.columnNullable;
            
            Schema columnSchema = mapJdbcTypeToSchema(columnType, nullable);
            columnSchemas.put(columnName, columnSchema);
            valueSchemaBuilder.field(columnName, columnSchema);
            
            // Use first column as key (typically ID)
            if (i == 1) {
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
    
    // Getters
    public Schema getKeySchema() { return keySchema; }
    public Schema getValueSchema() { return valueSchema; }
    public Map<String, Schema> getColumnSchemas() { return columnSchemas; }
    public String getTableName() { return tableName; }
}

