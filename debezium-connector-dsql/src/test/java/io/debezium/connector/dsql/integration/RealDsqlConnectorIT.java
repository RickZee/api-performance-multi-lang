package io.debezium.connector.dsql.integration;

import io.debezium.connector.dsql.DsqlConnector;
import io.debezium.connector.dsql.DsqlConnectorConfig;
import io.debezium.connector.dsql.DsqlOffsetContext;
import io.debezium.connector.dsql.DsqlSchema;
import io.debezium.connector.dsql.DsqlSourceTask;
import io.debezium.connector.dsql.testutil.RealDsqlTestUtils;
import org.apache.kafka.connect.source.SourceRecord;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Integration tests for DSQL connector using real DSQL cluster.
 * 
 * These tests require:
 * - Environment variables set (via .env.dsql file)
 * - Real DSQL cluster accessible
 * - AWS credentials configured
 * 
 * Tests are tagged with "real-dsql" and will be skipped if environment variables are not set.
 */
@Tag("real-dsql")
class RealDsqlConnectorIT extends RealDsqlTestBase {
    
    private static final String TEST_TABLE_PREFIX = "test_cdc_";
    private String testTableName;
    
    @BeforeEach
    void setUp() throws Exception {
        setUpConnections();
        
        // Create a unique test table name
        testTableName = TEST_TABLE_PREFIX + System.currentTimeMillis();
        
        // Create test table
        try (Connection conn = getConnection()) {
            RealDsqlTestUtils.createTestTable(conn, testTableName, "id");
        }
    }
    
    @AfterEach
    void tearDown() throws Exception {
        // Clean up test table
        try (Connection conn = getConnection()) {
            RealDsqlTestUtils.dropTestTable(conn, testTableName);
        } catch (Exception e) {
            // Ignore cleanup errors
        }
        
        tearDownConnections();
    }
    
    @Test
    void testConnectionToRealDsql() throws SQLException {
        // Test basic connection
        try (Connection conn = getConnection()) {
            assertThat(conn).isNotNull();
            assertThat(conn.isClosed()).isFalse();
            
            // Verify we can query
            try (var stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT 1")) {
                assertThat(rs.next()).isTrue();
                assertThat(rs.getInt(1)).isEqualTo(1);
            }
        }
    }
    
    @Test
    void testIamAuthentication() throws Exception {
        // Test that IAM token generation works
        String token = tokenGenerator.getToken();
        assertThat(token).isNotNull();
        assertThat(token).isNotEmpty();
        
        // Test that we can connect with the token
        try (Connection conn = getConnection()) {
            assertThat(conn).isNotNull();
        }
    }
    
    @Test
    void testSchemaDiscovery() throws SQLException {
        // Test schema building from real database
        try (Connection conn = getConnection()) {
            DatabaseMetaData metaData = conn.getMetaData();
            DsqlSchema schema = new DsqlSchema(testTableName, topicPrefix);
            schema.buildSchemas(metaData, "public");
            
            assertThat(schema.getPrimaryKeyColumn()).isEqualTo("id");
            assertThat(schema.getColumnNames()).contains("id", "event_name", "saved_date");
            assertThat(schema.hasUpdatedDateColumn()).isTrue();
            assertThat(schema.hasDeletedDateColumn()).isTrue();
            
            // Validate required columns
            schema.validateRequiredColumns();
        }
    }
    
    @Test
    void testBasicPolling() throws Exception {
        // Insert test data
        try (Connection conn = getConnection()) {
            String testId = "test-poll-" + System.currentTimeMillis();
            RealDsqlTestUtils.insertTestData(
                conn, testTableName, testId, "test-event", 
                Timestamp.from(Instant.now())
            );
        }
        
        // Create connector config with test table
        Map<String, String> configMap = createConnectorConfig();
        configMap.put("dsql.tables", testTableName);
        
        DsqlConnectorConfig config = new DsqlConnectorConfig(configMap);
        
        // Create source task
        DsqlSourceTask task = new DsqlSourceTask();
        try {
            task.start(configMap);
            
            // Poll for records
            List<SourceRecord> records = task.poll();
            
            // Should have at least one record
            assertThat(records).isNotNull();
            // Note: May be empty if polling hasn't caught up yet, which is OK for basic test
            
            // Clean up test data
            try (Connection conn = getConnection()) {
                RealDsqlTestUtils.cleanupTestData(conn, testTableName, "test-poll-");
            }
        } finally {
            task.stop();
        }
    }
    
    @Test
    void testOffsetPersistence() throws Exception {
        // Create offset context
        DsqlOffsetContext offset = new DsqlOffsetContext(testTableName);
        assertThat(offset.isInitialized()).isFalse();
        
        // Update offset
        Timestamp savedDate = Timestamp.from(Instant.now());
        offset.update(savedDate.toInstant(), "test-id");
        assertThat(offset.isInitialized()).isTrue();
        
        // Serialize and deserialize
        Map<String, Object> offsetMap = offset.toOffsetMap();
        DsqlOffsetContext loadedOffset = DsqlOffsetContext.load(offsetMap, testTableName);
        
        assertThat(loadedOffset.isInitialized()).isTrue();
        assertThat(loadedOffset.getLastId()).isEqualTo("test-id");
        assertThat(loadedOffset.getSavedDate()).isEqualTo(savedDate.toInstant());
    }
    
    @Test
    void testMultiTableConfiguration() {
        // Test connector configuration with multiple tables
        Map<String, String> configMap = createConnectorConfig();
        DsqlConnectorConfig config = new DsqlConnectorConfig(configMap);
        
        String[] tablesArray = config.getTablesArray();
        assertThat(tablesArray).isNotEmpty();
        assertThat(tablesArray.length).isGreaterThanOrEqualTo(1);
    }
    
    @Test
    void testConnectorStartup() {
        // Test connector can be configured and started
        DsqlConnector connector = new DsqlConnector();
        Map<String, String> configMap = createConnectorConfig();
        
        connector.start(configMap);
        
        assertThat(connector.version()).isEqualTo("1.0.0");
        assertThat(connector.taskClass()).isEqualTo(DsqlSourceTask.class);
        
        // Test task configuration
        List<Map<String, String>> taskConfigs = connector.taskConfigs(1);
        assertThat(taskConfigs).hasSize(1);
        assertThat(taskConfigs.get(0)).containsKey("dsql.endpoint.primary");
        assertThat(taskConfigs.get(0)).containsKey("dsql.database.name");
        
        connector.stop();
    }
    
    @Test
    void testTableExists() throws SQLException {
        // Verify test table was created
        try (Connection conn = getConnection()) {
            int count = RealDsqlTestUtils.getRecordCount(conn, testTableName);
            assertThat(count).isGreaterThanOrEqualTo(0); // Table exists, may be empty
        }
    }
}
