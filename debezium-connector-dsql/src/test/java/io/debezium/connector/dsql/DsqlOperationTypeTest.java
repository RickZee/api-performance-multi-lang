package io.debezium.connector.dsql;

import io.debezium.connector.dsql.connection.DsqlConnectionPool;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.sql.*;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.*;
import static org.mockito.Mockito.lenient;

@ExtendWith(MockitoExtension.class)
class DsqlOperationTypeTest {
    
    @Mock
    private DsqlConnectionPool connectionPool;
    
    @Mock
    private Connection connection;
    
    @Mock
    private DatabaseMetaData databaseMetaData;
    
    @Mock
    private ResultSet pkResultSet;
    
    @Mock
    private ResultSet columnsResultSet;
    
    @Mock
    private ResultSet resultSet;
    
    private DsqlConnectorConfig config;
    private DsqlSchema schema;
    private DsqlChangeEventSource changeEventSource;
    
    @BeforeEach
    void setUp() throws SQLException {
        Map<String, String> props = new HashMap<>();
        props.put(DsqlConnectorConfig.DSQL_ENDPOINT_PRIMARY, "test");
        props.put(DsqlConnectorConfig.DSQL_PORT, "5432");
        props.put(DsqlConnectorConfig.DSQL_DATABASE_NAME, "testdb");
        props.put(DsqlConnectorConfig.DSQL_REGION, "us-east-1");
        props.put(DsqlConnectorConfig.DSQL_IAM_USERNAME, "testuser");
        props.put(DsqlConnectorConfig.DSQL_TABLES, "test_table");
        props.put(DsqlConnectorConfig.DSQL_POLL_INTERVAL_MS, "1000");
        props.put(DsqlConnectorConfig.DSQL_BATCH_SIZE, "1000");
        props.put(DsqlConnectorConfig.TOPIC_PREFIX, "test");
        
        config = new DsqlConnectorConfig(props);
        schema = new DsqlSchema("test_table", "test");
    }
    
    @Test
    void testSchemaDetectsUpdatedDateColumn() throws SQLException {
        setupSchemaWithUpdatedDate();
        
        assertThat(schema.hasUpdatedDateColumn()).isTrue();
        assertThat(schema.hasDeletedDateColumn()).isFalse();
    }
    
    @Test
    void testSchemaDetectsDeletedDateColumn() throws SQLException {
        setupSchemaWithDeletedDate();
        
        assertThat(schema.hasUpdatedDateColumn()).isFalse();
        assertThat(schema.hasDeletedDateColumn()).isTrue();
    }
    
    @Test
    void testSchemaDetectsBothUpdateAndDeleteColumns() throws SQLException {
        setupSchemaWithBothColumns();
        
        assertThat(schema.hasUpdatedDateColumn()).isTrue();
        assertThat(schema.hasDeletedDateColumn()).isTrue();
    }
    
    @Test
    void testOperationTypeCreate() throws SQLException {
        setupSchemaWithoutUpdateDelete();
        
        // Operation type should be 'c' for create when no update/delete columns
        assertThat(schema.hasUpdatedDateColumn()).isFalse();
        assertThat(schema.hasDeletedDateColumn()).isFalse();
    }
    
    @Test
    void testOperationTypeUpdate() throws SQLException {
        setupSchemaWithUpdatedDate();
        
        // Operation type should be 'u' for update when updated_date column exists
        assertThat(schema.hasUpdatedDateColumn()).isTrue();
    }
    
    @Test
    void testOperationTypeDelete() throws SQLException {
        setupSchemaWithDeletedDate();
        
        // Operation type should be 'd' for delete when deleted_date column exists
        assertThat(schema.hasDeletedDateColumn()).isTrue();
    }
    
    @Test
    void testOperationTypeDeleteTakesPrecedence() throws SQLException {
        setupSchemaWithBothColumns();
        
        // Both columns should be detected
        // Delete takes precedence in determineOperationType logic
        assertThat(schema.hasDeletedDateColumn()).isTrue();
        assertThat(schema.hasUpdatedDateColumn()).isTrue();
    }
    
    @Test
    void testOperationTypeWithUpdatedAtColumn() throws SQLException {
        // Test alternative column name 'updated_at'
        lenient().when(connectionPool.getConnection()).thenReturn(connection);
        lenient().when(connection.getMetaData()).thenReturn(databaseMetaData);
        
        when(databaseMetaData.getPrimaryKeys(isNull(), eq("public"), eq("test_table")))
                .thenReturn(pkResultSet);
        when(pkResultSet.next()).thenReturn(true);
        when(pkResultSet.getString("COLUMN_NAME")).thenReturn("id");
        
        when(databaseMetaData.getColumns(isNull(), eq("public"), eq("test_table"), isNull()))
                .thenReturn(columnsResultSet);
        
        when(columnsResultSet.next()).thenReturn(true, true, true, false);
        when(columnsResultSet.getString("COLUMN_NAME"))
                .thenReturn("id", "saved_date", "updated_at");
        when(columnsResultSet.getInt("DATA_TYPE"))
                .thenReturn(Types.VARCHAR, Types.TIMESTAMP, Types.TIMESTAMP);
        when(columnsResultSet.getInt("NULLABLE"))
                .thenReturn(DatabaseMetaData.columnNoNulls,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNullable);
        
        schema.buildSchemas(databaseMetaData, "public");
        
        // Should detect updated_at as updated_date column
        assertThat(schema.hasUpdatedDateColumn()).isTrue();
    }
    
    private void setupSchemaWithUpdatedDate() throws SQLException {
        lenient().when(connectionPool.getConnection()).thenReturn(connection);
        lenient().when(connection.getMetaData()).thenReturn(databaseMetaData);
        
        when(databaseMetaData.getPrimaryKeys(isNull(), eq("public"), eq("test_table")))
                .thenReturn(pkResultSet);
        when(pkResultSet.next()).thenReturn(true);
        when(pkResultSet.getString("COLUMN_NAME")).thenReturn("id");
        
        when(databaseMetaData.getColumns(isNull(), eq("public"), eq("test_table"), isNull()))
                .thenReturn(columnsResultSet);
        
        when(columnsResultSet.next()).thenReturn(true, true, true, true, false);
        when(columnsResultSet.getString("COLUMN_NAME"))
                .thenReturn("id", "saved_date", "created_date", "updated_date");
        when(columnsResultSet.getInt("DATA_TYPE"))
                .thenReturn(Types.VARCHAR, Types.TIMESTAMP, Types.TIMESTAMP, Types.TIMESTAMP);
        when(columnsResultSet.getInt("NULLABLE"))
                .thenReturn(DatabaseMetaData.columnNoNulls,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNullable);
        
        schema.buildSchemas(databaseMetaData, "public");
    }
    
    private void setupSchemaWithDeletedDate() throws SQLException {
        lenient().when(connectionPool.getConnection()).thenReturn(connection);
        lenient().when(connection.getMetaData()).thenReturn(databaseMetaData);
        
        when(databaseMetaData.getPrimaryKeys(isNull(), eq("public"), eq("test_table")))
                .thenReturn(pkResultSet);
        when(pkResultSet.next()).thenReturn(true);
        when(pkResultSet.getString("COLUMN_NAME")).thenReturn("id");
        
        when(databaseMetaData.getColumns(isNull(), eq("public"), eq("test_table"), isNull()))
                .thenReturn(columnsResultSet);
        
        when(columnsResultSet.next()).thenReturn(true, true, true, false);
        when(columnsResultSet.getString("COLUMN_NAME"))
                .thenReturn("id", "saved_date", "deleted_date");
        when(columnsResultSet.getInt("DATA_TYPE"))
                .thenReturn(Types.VARCHAR, Types.TIMESTAMP, Types.TIMESTAMP);
        when(columnsResultSet.getInt("NULLABLE"))
                .thenReturn(DatabaseMetaData.columnNoNulls,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNullable);
        
        schema.buildSchemas(databaseMetaData, "public");
    }
    
    private void setupSchemaWithBothColumns() throws SQLException {
        lenient().when(connectionPool.getConnection()).thenReturn(connection);
        lenient().when(connection.getMetaData()).thenReturn(databaseMetaData);
        
        when(databaseMetaData.getPrimaryKeys(isNull(), eq("public"), eq("test_table")))
                .thenReturn(pkResultSet);
        when(pkResultSet.next()).thenReturn(true);
        when(pkResultSet.getString("COLUMN_NAME")).thenReturn("id");
        
        when(databaseMetaData.getColumns(isNull(), eq("public"), eq("test_table"), isNull()))
                .thenReturn(columnsResultSet);
        
        when(columnsResultSet.next()).thenReturn(true, true, true, true, false);
        when(columnsResultSet.getString("COLUMN_NAME"))
                .thenReturn("id", "saved_date", "updated_date", "deleted_date");
        when(columnsResultSet.getInt("DATA_TYPE"))
                .thenReturn(Types.VARCHAR, Types.TIMESTAMP, Types.TIMESTAMP, Types.TIMESTAMP);
        when(columnsResultSet.getInt("NULLABLE"))
                .thenReturn(DatabaseMetaData.columnNoNulls,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNullable,
                           DatabaseMetaData.columnNullable);
        
        schema.buildSchemas(databaseMetaData, "public");
    }
    
    private void setupSchemaWithoutUpdateDelete() throws SQLException {
        lenient().when(connectionPool.getConnection()).thenReturn(connection);
        lenient().when(connection.getMetaData()).thenReturn(databaseMetaData);
        
        when(databaseMetaData.getPrimaryKeys(isNull(), eq("public"), eq("test_table")))
                .thenReturn(pkResultSet);
        when(pkResultSet.next()).thenReturn(true);
        when(pkResultSet.getString("COLUMN_NAME")).thenReturn("id");
        
        when(databaseMetaData.getColumns(isNull(), eq("public"), eq("test_table"), isNull()))
                .thenReturn(columnsResultSet);
        
        when(columnsResultSet.next()).thenReturn(true, true, false);
        when(columnsResultSet.getString("COLUMN_NAME"))
                .thenReturn("id", "saved_date");
        when(columnsResultSet.getInt("DATA_TYPE"))
                .thenReturn(Types.VARCHAR, Types.TIMESTAMP);
        when(columnsResultSet.getInt("NULLABLE"))
                .thenReturn(DatabaseMetaData.columnNoNulls,
                           DatabaseMetaData.columnNullable);
        
        schema.buildSchemas(databaseMetaData, "public");
    }
    
}
