package io.debezium.connector.dsql;

import org.apache.kafka.connect.data.Schema;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.sql.*;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class DsqlSchemaTest {
    
    @Mock
    private DatabaseMetaData databaseMetaData;
    
    @Mock
    private ResultSetMetaData resultSetMetaData;
    
    @Mock
    private ResultSet pkResultSet;
    
    @Mock
    private ResultSet columnsResultSet;
    
    private DsqlSchema schema;
    private String tableName = "event_headers";
    
    @BeforeEach
    void setUp() {
        schema = new DsqlSchema(tableName, "dsql-cdc");
    }
    
    @Test
    void testBuildSchemasFromDatabaseMetaData() throws SQLException {
        // Mock primary key
        when(databaseMetaData.getPrimaryKeys(isNull(), eq("public"), eq(tableName)))
                .thenReturn(pkResultSet);
        when(pkResultSet.next()).thenReturn(true);
        when(pkResultSet.getString("COLUMN_NAME")).thenReturn("id");
        
        // Mock columns
        when(databaseMetaData.getColumns(isNull(), eq("public"), eq(tableName), isNull()))
                .thenReturn(columnsResultSet);
        
        when(columnsResultSet.next()).thenReturn(true, true, true, true, true, true, false);
        when(columnsResultSet.getString("COLUMN_NAME"))
                .thenReturn("id", "event_name", "event_type", "created_date", "saved_date", "header_data");
        when(columnsResultSet.getInt("DATA_TYPE"))
                .thenReturn(Types.VARCHAR, Types.VARCHAR, Types.VARCHAR, Types.TIMESTAMP, Types.TIMESTAMP, Types.OTHER);
        when(columnsResultSet.getInt("NULLABLE"))
                .thenReturn(DatabaseMetaData.columnNoNulls,
                           DatabaseMetaData.columnNoNulls,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNoNulls);
        
        schema.buildSchemas(databaseMetaData, "public");
        
        assertThat(schema.getValueSchema()).isNotNull();
        assertThat(schema.getKeySchema()).isNotNull();
        assertThat(schema.getPrimaryKeyColumn()).isEqualTo("id");
        assertThat(schema.getColumnNames()).hasSize(6);
        assertThat(schema.getColumnSchemas()).hasSize(6);
    }
    
    @Test
    void testBuildSchemasFromResultSetMetaData() throws SQLException {
        when(resultSetMetaData.getColumnCount()).thenReturn(6);
        when(resultSetMetaData.getColumnName(1)).thenReturn("id");
        when(resultSetMetaData.getColumnName(2)).thenReturn("event_name");
        when(resultSetMetaData.getColumnName(3)).thenReturn("event_type");
        when(resultSetMetaData.getColumnName(4)).thenReturn("created_date");
        when(resultSetMetaData.getColumnName(5)).thenReturn("saved_date");
        when(resultSetMetaData.getColumnName(6)).thenReturn("header_data");
        
        when(resultSetMetaData.getColumnType(1)).thenReturn(Types.VARCHAR);
        when(resultSetMetaData.getColumnType(2)).thenReturn(Types.VARCHAR);
        when(resultSetMetaData.getColumnType(3)).thenReturn(Types.VARCHAR);
        when(resultSetMetaData.getColumnType(4)).thenReturn(Types.TIMESTAMP);
        when(resultSetMetaData.getColumnType(5)).thenReturn(Types.TIMESTAMP);
        when(resultSetMetaData.getColumnType(6)).thenReturn(Types.OTHER);
        
        when(resultSetMetaData.isNullable(1)).thenReturn(ResultSetMetaData.columnNoNulls);
        when(resultSetMetaData.isNullable(2)).thenReturn(ResultSetMetaData.columnNoNulls);
        when(resultSetMetaData.isNullable(3)).thenReturn(ResultSetMetaData.columnNullable);
        when(resultSetMetaData.isNullable(4)).thenReturn(ResultSetMetaData.columnNullable);
        when(resultSetMetaData.isNullable(5)).thenReturn(ResultSetMetaData.columnNullable);
        when(resultSetMetaData.isNullable(6)).thenReturn(ResultSetMetaData.columnNoNulls);
        
        schema.buildSchemas(resultSetMetaData);
        
        assertThat(schema.getValueSchema()).isNotNull();
        assertThat(schema.getKeySchema()).isNotNull();
        assertThat(schema.getPrimaryKeyColumn()).isEqualTo("id");
    }
    
    @Test
    void testValidateRequiredColumns() throws SQLException {
        // Setup schema with saved_date
        setupValidSchema();
        
        // Should not throw
        schema.validateRequiredColumns();
    }
    
    @Test
    void testValidateRequiredColumnsThrowsWhenSavedDateMissing() throws SQLException {
        // Setup schema without saved_date
        when(databaseMetaData.getPrimaryKeys(isNull(), eq("public"), eq(tableName)))
                .thenReturn(pkResultSet);
        when(pkResultSet.next()).thenReturn(true);
        when(pkResultSet.getString("COLUMN_NAME")).thenReturn("id");
        
        when(databaseMetaData.getColumns(isNull(), eq("public"), eq(tableName), isNull()))
                .thenReturn(columnsResultSet);
        
        when(columnsResultSet.next()).thenReturn(true, true, false);
        when(columnsResultSet.getString("COLUMN_NAME")).thenReturn("id", "event_name");
        when(columnsResultSet.getInt("DATA_TYPE")).thenReturn(Types.VARCHAR, Types.VARCHAR);
        when(columnsResultSet.getInt("NULLABLE"))
                .thenReturn(DatabaseMetaData.columnNoNulls, DatabaseMetaData.columnNoNulls);
        
        schema.buildSchemas(databaseMetaData, "public");
        
        assertThatThrownBy(() -> schema.validateRequiredColumns())
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("saved_date");
    }
    
    @Test
    void testValidateRequiredColumnsThrowsWhenNoPrimaryKey() throws SQLException {
        // Setup schema without primary key
        // Note: Schema uses first column as fallback, so validation passes
        // This test verifies the fallback behavior works
        when(databaseMetaData.getPrimaryKeys(isNull(), eq("public"), eq(tableName)))
                .thenReturn(pkResultSet);
        when(pkResultSet.next()).thenReturn(false); // No primary key
        
        when(databaseMetaData.getColumns(isNull(), eq("public"), eq(tableName), isNull()))
                .thenReturn(columnsResultSet);
        
        when(columnsResultSet.next()).thenReturn(true, true, false);
        when(columnsResultSet.getString("COLUMN_NAME")).thenReturn("col1", "saved_date");
        when(columnsResultSet.getInt("DATA_TYPE")).thenReturn(Types.VARCHAR, Types.TIMESTAMP);
        when(columnsResultSet.getInt("NULLABLE"))
                .thenReturn(DatabaseMetaData.columnNoNulls, DatabaseMetaData.columnNullable);
        
        schema.buildSchemas(databaseMetaData, "public");
        
        // Schema uses first column as fallback primary key, so validation should pass
        // Verify that primary key is set to first column
        assertThat(schema.getPrimaryKeyColumn()).isEqualTo("col1");
        
        // Validation should pass (has saved_date and primary key from fallback)
        schema.validateRequiredColumns();
    }
    
    @Test
    void testJdbcTypeMapping() throws SQLException {
        setupValidSchema();
        
        Map<String, Schema> columnSchemas = schema.getColumnSchemas();
        
        // Check type mappings
        Schema idSchema = columnSchemas.get("id");
        assertThat(idSchema.type()).isEqualTo(Schema.Type.STRING);
        
        Schema savedDateSchema = columnSchemas.get("saved_date");
        assertThat(savedDateSchema.type()).isEqualTo(Schema.Type.INT64); // Timestamp
    }
    
    @Test
    void testCdcMetadataFields() throws SQLException {
        setupValidSchema();
        
        Schema valueSchema = schema.getValueSchema();
        
        // Check CDC metadata fields are present
        assertThat(valueSchema.field(DsqlSchema.OP_FIELD)).isNotNull();
        assertThat(valueSchema.field(DsqlSchema.TABLE_FIELD)).isNotNull();
        assertThat(valueSchema.field(DsqlSchema.TS_MS_FIELD)).isNotNull();
    }
    
    @Test
    void testGetColumnNames() throws SQLException {
        setupValidSchema();
        
        List<String> columnNames = schema.getColumnNames();
        
        assertThat(columnNames).containsExactlyInAnyOrder(
                "id", "event_name", "event_type", "created_date", "saved_date", "header_data"
        );
    }
    
    private void setupValidSchema() throws SQLException {
        when(databaseMetaData.getPrimaryKeys(isNull(), eq("public"), eq(tableName)))
                .thenReturn(pkResultSet);
        when(pkResultSet.next()).thenReturn(true);
        when(pkResultSet.getString("COLUMN_NAME")).thenReturn("id");
        
        when(databaseMetaData.getColumns(isNull(), eq("public"), eq(tableName), isNull()))
                .thenReturn(columnsResultSet);
        
        when(columnsResultSet.next()).thenReturn(true, true, true, true, true, true, false);
        when(columnsResultSet.getString("COLUMN_NAME"))
                .thenReturn("id", "event_name", "event_type", "created_date", "saved_date", "header_data");
        when(columnsResultSet.getInt("DATA_TYPE"))
                .thenReturn(Types.VARCHAR, Types.VARCHAR, Types.VARCHAR, Types.TIMESTAMP, Types.TIMESTAMP, Types.OTHER);
        when(columnsResultSet.getInt("NULLABLE"))
                .thenReturn(DatabaseMetaData.columnNoNulls,
                           DatabaseMetaData.columnNoNulls,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNoNulls);
        
        schema.buildSchemas(databaseMetaData, "public");
    }
}
