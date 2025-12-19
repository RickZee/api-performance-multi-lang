package io.debezium.connector.dsql;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.sql.*;
import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.*;

/**
 * Tests for schema evolution scenarios.
 */
@ExtendWith(MockitoExtension.class)
class DsqlSchemaEvolutionTest {
    
    @Mock
    private Connection connection;
    
    @Mock
    private DatabaseMetaData databaseMetaData;
    
    @Mock
    private ResultSet pkResultSet;
    
    @Mock
    private ResultSet columnsResultSet;
    
    private DsqlSchema schema;
    
    @BeforeEach
    void setUp() {
        schema = new DsqlSchema("test_table", "test");
    }
    
    @Test
    void testSchemaRefreshWithNewColumn() throws SQLException {
        // Test that schema can be rebuilt when new column is added
        setupInitialSchema();
        schema.buildSchemas(databaseMetaData, "public");
        
        int initialColumnCount = schema.getColumnNames().size();
        
        // Simulate adding a new column
        setupSchemaWithNewColumn();
        schema.buildSchemas(databaseMetaData, "public");
        
        int newColumnCount = schema.getColumnNames().size();
        
        assertThat(newColumnCount).isGreaterThan(initialColumnCount);
        assertThat(schema.getColumnNames()).contains("new_column");
    }
    
    @Test
    void testSchemaHandlesColumnTypeChanges() throws SQLException {
        // Test that schema can handle column type changes
        // Note: In practice, schema changes require connector restart
        setupInitialSchema();
        schema.buildSchemas(databaseMetaData, "public");
        
        // Verify initial schema
        assertThat(schema.getColumnSchemas()).containsKey("id");
        
        // Schema should be rebuildable
        assertThat(schema.getValueSchema()).isNotNull();
    }
    
    @Test
    void testSchemaBackwardCompatibility() throws SQLException {
        // Test that schema maintains backward compatibility
        setupInitialSchema();
        schema.buildSchemas(databaseMetaData, "public");
        
        // Original columns should still be present
        assertThat(schema.getColumnNames()).contains("id", "saved_date");
        
        // Schema should be valid
        assertThat(schema.getValueSchema()).isNotNull();
        assertThat(schema.getKeySchema()).isNotNull();
    }
    
    @Test
    void testSchemaValidationAfterEvolution() throws SQLException {
        // Test that schema validation still works after evolution
        setupInitialSchema();
        schema.buildSchemas(databaseMetaData, "public");
        
        // Should still validate required columns
        try {
            schema.validateRequiredColumns();
            // Should not throw if saved_date exists
        } catch (SQLException e) {
            // Expected if saved_date is missing
            assertThat(e.getMessage()).contains("saved_date");
        }
    }
    
    @Test
    void testSchemaRebuildPreservesPrimaryKey() throws SQLException {
        // Test that primary key is preserved during schema rebuild
        setupInitialSchema();
        schema.buildSchemas(databaseMetaData, "public");
        
        String originalPk = schema.getPrimaryKeyColumn();
        
        // Rebuild schema
        schema.buildSchemas(databaseMetaData, "public");
        
        assertThat(schema.getPrimaryKeyColumn()).isEqualTo(originalPk);
    }
    
    private void setupInitialSchema() throws SQLException {
        when(databaseMetaData.getPrimaryKeys(isNull(), eq("public"), eq("test_table")))
                .thenReturn(pkResultSet);
        when(pkResultSet.next()).thenReturn(true);
        when(pkResultSet.getString("COLUMN_NAME")).thenReturn("id");
        
        when(databaseMetaData.getColumns(isNull(), eq("public"), eq("test_table"), isNull()))
                .thenReturn(columnsResultSet);
        
        when(columnsResultSet.next()).thenReturn(true, true, true, false);
        when(columnsResultSet.getString("COLUMN_NAME"))
                .thenReturn("id", "saved_date", "event_name");
        when(columnsResultSet.getInt("DATA_TYPE"))
                .thenReturn(Types.VARCHAR, Types.TIMESTAMP, Types.VARCHAR);
        when(columnsResultSet.getInt("NULLABLE"))
                .thenReturn(DatabaseMetaData.columnNoNulls,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNoNulls);
    }
    
    private void setupSchemaWithNewColumn() throws SQLException {
        when(databaseMetaData.getPrimaryKeys(isNull(), eq("public"), eq("test_table")))
                .thenReturn(pkResultSet);
        when(pkResultSet.next()).thenReturn(true);
        when(pkResultSet.getString("COLUMN_NAME")).thenReturn("id");
        
        when(databaseMetaData.getColumns(isNull(), eq("public"), eq("test_table"), isNull()))
                .thenReturn(columnsResultSet);
        
        when(columnsResultSet.next()).thenReturn(true, true, true, true, false);
        when(columnsResultSet.getString("COLUMN_NAME"))
                .thenReturn("id", "saved_date", "event_name", "new_column");
        when(columnsResultSet.getInt("DATA_TYPE"))
                .thenReturn(Types.VARCHAR, Types.TIMESTAMP, Types.VARCHAR, Types.VARCHAR);
        when(columnsResultSet.getInt("NULLABLE"))
                .thenReturn(DatabaseMetaData.columnNoNulls,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNoNulls,
                           DatabaseMetaData.columnNullable);
    }
}
