package io.debezium.connector.dsql;

import io.debezium.connector.dsql.connection.DsqlConnectionPool;
import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.data.Struct;
import org.apache.kafka.connect.source.SourceRecord;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.sql.*;
import java.time.Instant;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.*;
import static org.mockito.Mockito.lenient;

@ExtendWith(MockitoExtension.class)
class DsqlChangeEventSourceTest {
    
    @Mock
    private DsqlConnectionPool connectionPool;
    
    @Mock
    private DsqlConnectorConfig config;
    
    @Mock
    private Connection connection;
    
    @Mock
    private DatabaseMetaData databaseMetaData;
    
    @Mock
    private PreparedStatement preparedStatement;
    
    @Mock
    private ResultSet resultSet;
    
    @Mock
    private ResultSet pkResultSet;
    
    @Mock
    private ResultSet columnsResultSet;
    
    private DsqlChangeEventSource changeEventSource;
    private DsqlSchema schema;
    private DsqlOffsetContext offsetContext;
    private String tableName = "event_headers";
    
    @BeforeEach
    void setUp() throws SQLException {
        schema = new DsqlSchema(tableName, "dsql-cdc");
        offsetContext = new DsqlOffsetContext(tableName);
        
        lenient().when(config.getBatchSize()).thenReturn(1000);
        lenient().when(config.getTopicPrefix()).thenReturn("dsql-cdc");
        
        changeEventSource = new DsqlChangeEventSource(
                connectionPool,
                config,
                tableName,
                schema,
                offsetContext
        );
    }
    
    @Test
    void testInitializeSchema() throws SQLException {
        // Setup mocks for schema initialization
        lenient().when(connectionPool.getConnection()).thenReturn(connection);
        lenient().when(connection.getMetaData()).thenReturn(databaseMetaData);
        
        // Mock primary key result set
        when(databaseMetaData.getPrimaryKeys(isNull(), eq("public"), eq(tableName)))
                .thenReturn(pkResultSet);
        when(pkResultSet.next()).thenReturn(true);
        when(pkResultSet.getString("COLUMN_NAME")).thenReturn("id");
        
        // Mock columns result set
        when(databaseMetaData.getColumns(isNull(), eq("public"), eq(tableName), isNull()))
                .thenReturn(columnsResultSet);
        
        // First column: id (primary key)
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
        
        // Initialize schema
        changeEventSource.initializeSchema();
        
        // Verify schema was built
        assertThat(schema.getValueSchema()).isNotNull();
        assertThat(schema.getKeySchema()).isNotNull();
        assertThat(schema.getPrimaryKeyColumn()).isEqualTo("id");
        assertThat(schema.getColumnNames()).contains("id", "event_name", "saved_date");
    }
    
    @Test
    void testInitializeSchemaThrowsWhenSavedDateMissing() throws SQLException {
        lenient().when(connectionPool.getConnection()).thenReturn(connection);
        lenient().when(connection.getMetaData()).thenReturn(databaseMetaData);
        
        when(databaseMetaData.getPrimaryKeys(isNull(), eq("public"), eq(tableName)))
                .thenReturn(pkResultSet);
        when(pkResultSet.next()).thenReturn(true);
        when(pkResultSet.getString("COLUMN_NAME")).thenReturn("id");
        
        when(databaseMetaData.getColumns(isNull(), eq("public"), eq(tableName), isNull()))
                .thenReturn(columnsResultSet);
        
        // Columns without saved_date
        when(columnsResultSet.next()).thenReturn(true, true, false);
        when(columnsResultSet.getString("COLUMN_NAME")).thenReturn("id", "event_name");
        when(columnsResultSet.getInt("DATA_TYPE")).thenReturn(Types.VARCHAR, Types.VARCHAR);
        when(columnsResultSet.getInt("NULLABLE"))
                .thenReturn(DatabaseMetaData.columnNoNulls, DatabaseMetaData.columnNoNulls);
        
        assertThatThrownBy(() -> changeEventSource.initializeSchema())
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("saved_date");
    }
    
    @Test
    void testPollWithNoOffset() throws SQLException {
        // Setup schema first
        setupSchemaMocks();
        changeEventSource.initializeSchema();
        
        // Setup poll mocks
        lenient().when(connectionPool.getConnection()).thenReturn(connection);
        when(connection.prepareStatement(anyString())).thenReturn(preparedStatement);
        when(preparedStatement.executeQuery()).thenReturn(resultSet);
        
        // No records
        when(resultSet.next()).thenReturn(false);
        
        List<SourceRecord> records = changeEventSource.poll();
        
        assertThat(records).isEmpty();
        verify(preparedStatement).setInt(1, 1000); // LIMIT parameter
    }
    
    @Test
    void testPollWithOffset() throws SQLException {
        // Setup schema
        setupSchemaMocks();
        changeEventSource.initializeSchema();
        
        // Set offset
        offsetContext.update(Instant.now().minusSeconds(60), "event-1");
        
        // Setup poll mocks
        lenient().when(connectionPool.getConnection()).thenReturn(connection);
        when(connection.prepareStatement(anyString())).thenReturn(preparedStatement);
        when(preparedStatement.executeQuery()).thenReturn(resultSet);
        
        // One record
        when(resultSet.next()).thenReturn(true, false);
        when(resultSet.getTimestamp("saved_date")).thenReturn(Timestamp.from(Instant.now()));
        when(resultSet.getString("id")).thenReturn("event-2");
        // Return null for any other columns not explicitly set
        when(resultSet.getObject(anyString())).thenAnswer(invocation -> {
            String colName = invocation.getArgument(0);
            if (colName.equals("id")) return "event-123";
            if (colName.equals("event_name")) return "LoanCreated";
            if (colName.equals("event_type")) return "LoanCreated";
            if (colName.equals("created_date") || colName.equals("saved_date")) {
                return Timestamp.from(Instant.now());
            }
            if (colName.equals("header_data")) return "{\"test\": \"data\"}";
            return null;
        });
        
        List<SourceRecord> records = changeEventSource.poll();
        
        assertThat(records).hasSize(1);
        verify(preparedStatement).setTimestamp(eq(1), any(Timestamp.class)); // saved_date parameter
        verify(preparedStatement).setInt(eq(2), eq(1000)); // LIMIT parameter
    }
    
    @Test
    void testBuildSourceRecord() throws SQLException {
        // Setup schema
        setupSchemaMocks();
        changeEventSource.initializeSchema();
        
        // Setup result set - return proper types for each column
        when(resultSet.getObject("id")).thenReturn("event-123");
        when(resultSet.getObject("event_name")).thenReturn("LoanCreated");
        when(resultSet.getObject("event_type")).thenReturn("LoanCreated");
        when(resultSet.getObject("created_date")).thenReturn(Timestamp.from(Instant.now()));
        when(resultSet.getObject("saved_date")).thenReturn(Timestamp.from(Instant.now()));
        when(resultSet.getObject("header_data")).thenReturn("{\"test\": \"data\"}");
        
        // Use reflection or package-private access to test buildSourceRecord
        // For now, test through poll
        lenient().when(connectionPool.getConnection()).thenReturn(connection);
        when(connection.prepareStatement(anyString())).thenReturn(preparedStatement);
        when(preparedStatement.executeQuery()).thenReturn(resultSet);
        when(resultSet.next()).thenReturn(true, false);
        when(resultSet.getTimestamp("saved_date")).thenReturn(Timestamp.from(Instant.now()));
        when(resultSet.getString("id")).thenReturn("event-123");
        
        List<SourceRecord> records = changeEventSource.poll();
        
        assertThat(records).hasSize(1);
        SourceRecord record = records.get(0);
        
        assertThat(record.topic()).isEqualTo("dsql-cdc.public.event_headers");
        assertThat(record.keySchema()).isNotNull();
        assertThat(record.valueSchema()).isNotNull();
        
        Struct value = (Struct) record.value();
        assertThat(value.get("__op")).isEqualTo("c");
        assertThat(value.get("__table")).isEqualTo(tableName);
        assertThat(value.get("__ts_ms")).isNotNull();
    }
    
    @Test
    void testPollUpdatesOffset() throws SQLException {
        setupSchemaMocks();
        changeEventSource.initializeSchema();
        
        Instant savedDate = Instant.now();
        String recordId = "event-456";
        
        lenient().when(connectionPool.getConnection()).thenReturn(connection);
        when(connection.prepareStatement(anyString())).thenReturn(preparedStatement);
        when(preparedStatement.executeQuery()).thenReturn(resultSet);
        when(resultSet.next()).thenReturn(true, false);
        when(resultSet.getTimestamp("saved_date")).thenReturn(Timestamp.from(savedDate));
        when(resultSet.getString("id")).thenReturn(recordId);
        // Return null for any other columns not explicitly set
        when(resultSet.getObject(anyString())).thenAnswer(invocation -> {
            String colName = invocation.getArgument(0);
            if (colName.equals("id")) return "event-123";
            if (colName.equals("event_name")) return "LoanCreated";
            if (colName.equals("event_type")) return "LoanCreated";
            if (colName.equals("created_date") || colName.equals("saved_date")) {
                return Timestamp.from(Instant.now());
            }
            if (colName.equals("header_data")) return "{\"test\": \"data\"}";
            return null;
        });
        
        changeEventSource.poll();
        
        assertThat(offsetContext.getSavedDate()).isEqualTo(savedDate);
        assertThat(offsetContext.getLastId()).isEqualTo(recordId);
    }
    
    private void setupSchemaMocks() throws SQLException {
        lenient().when(connectionPool.getConnection()).thenReturn(connection);
        lenient().when(connection.getMetaData()).thenReturn(databaseMetaData);
        
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
    }
}
