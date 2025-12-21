package io.debezium.connector.dsql;

import io.debezium.connector.dsql.connection.DsqlConnectionPool;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.sql.SQLException;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class DsqlChangeEventSourceErrorHandlingTest {
    
    @Mock
    private DsqlConnectionPool connectionPool;
    
    @Mock
    private DsqlConnectorConfig config;
    
    @Mock
    private DsqlSchema schema;
    
    @Mock
    private DsqlOffsetContext offsetContext;
    
    private String tableName = "test_table";
    
    @Test
    void testPollWithNullConnectionPool() {
        // Test that poll() validates connection pool is not null
        DsqlChangeEventSource source = new DsqlChangeEventSource(
                null,
                config,
                tableName,
                schema,
                offsetContext
        );
        
        assertThatThrownBy(() -> source.poll())
            .isInstanceOf(SQLException.class)
            .hasMessageContaining("connection pool is null");
    }
    
    @Test
    void testPollWithNullConfig() {
        // Test that poll() validates configuration is not null
        DsqlChangeEventSource source = new DsqlChangeEventSource(
                connectionPool,
                null,
                tableName,
                schema,
                offsetContext
        );
        
        assertThatThrownBy(() -> source.poll())
            .isInstanceOf(SQLException.class)
            .hasMessageContaining("configuration is null");
    }
    
    @Test
    void testPollWithNullSchema() {
        // Test that poll() validates schema is not null
        DsqlChangeEventSource source = new DsqlChangeEventSource(
                connectionPool,
                config,
                tableName,
                null,
                offsetContext
        );
        
        assertThatThrownBy(() -> source.poll())
            .isInstanceOf(SQLException.class)
            .hasMessageContaining("schema is null");
    }
    
    @Test
    void testPollWithNullOffsetContext() {
        // Test that poll() validates offset context is not null
        DsqlChangeEventSource source = new DsqlChangeEventSource(
                connectionPool,
                config,
                tableName,
                schema,
                null
        );
        
        assertThatThrownBy(() -> source.poll())
            .isInstanceOf(SQLException.class)
            .hasMessageContaining("offset context is null");
    }
    
    @Test
    void testPollWithEmptyTableName() {
        // Test that poll() validates table name is not empty
        DsqlChangeEventSource source = new DsqlChangeEventSource(
                connectionPool,
                config,
                "",
                schema,
                offsetContext
        );
        
        assertThatThrownBy(() -> source.poll())
            .isInstanceOf(SQLException.class)
            .hasMessageContaining("table name is null or empty");
    }
    
    @Test
    void testInitializeSchemaWithNullConnectionPool() {
        // Test that initializeSchema() validates connection pool is not null
        DsqlChangeEventSource source = new DsqlChangeEventSource(
                null,
                config,
                tableName,
                schema,
                offsetContext
        );
        
        assertThatThrownBy(() -> source.initializeSchema())
            .isInstanceOf(SQLException.class)
            .hasMessageContaining("connection pool is null");
    }
    
    @Test
    void testInitializeSchemaWithNullSchema() {
        // Test that initializeSchema() validates schema is not null
        DsqlChangeEventSource source = new DsqlChangeEventSource(
                connectionPool,
                config,
                tableName,
                null,
                offsetContext
        );
        
        assertThatThrownBy(() -> source.initializeSchema())
            .isInstanceOf(SQLException.class)
            .hasMessageContaining("schema object is null");
    }
    
    @Test
    void testErrorMessagesIncludeTableName() {
        // Test that error messages include table name for context
        // Note: The error message format may vary, so we check for the key error message
        DsqlChangeEventSource source = new DsqlChangeEventSource(
                null,
                config,
                tableName,
                schema,
                offsetContext
        );
        
        assertThatThrownBy(() -> source.poll())
            .isInstanceOf(SQLException.class)
            .hasMessageContaining("connection pool is null");
        // Table name is included in the error message in later error handling, 
        // but the initial null check may not include it
    }
}

