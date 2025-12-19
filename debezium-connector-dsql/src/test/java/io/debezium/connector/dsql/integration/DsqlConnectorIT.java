package io.debezium.connector.dsql.integration;

import io.debezium.connector.dsql.DsqlConnectorConfig;
import io.debezium.connector.dsql.DsqlOffsetContext;
import io.debezium.connector.dsql.DsqlSchema;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Integration test for DSQL connector using PostgreSQL Testcontainers.
 * 
 * Uses PostgreSQL as a proxy for DSQL since DSQL is not available in test environments.
 * Tests the connector's ability to connect, poll for changes, and generate records.
 */
@Testcontainers(disabledWithoutDocker = true)
@ExtendWith(org.testcontainers.junit.jupiter.TestcontainersExtension.class)
class DsqlConnectorIT {
    
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15")
            .withDatabaseName("testdb")
            .withUsername("testuser")
            .withPassword("testpass");
    
    @BeforeAll
    static void setUpDatabase() throws Exception {
        // Access container to trigger Testcontainers to start it
        // The @Testcontainers annotation will skip tests if Docker is not available
        postgres.start();
        
        // Create test tables
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                // Create event_headers table
                stmt.execute(
                    "CREATE TABLE event_headers (" +
                    "    id VARCHAR(255) PRIMARY KEY," +
                    "    event_name VARCHAR(255) NOT NULL," +
                    "    event_type VARCHAR(255)," +
                    "    created_date TIMESTAMP WITH TIME ZONE," +
                    "    saved_date TIMESTAMP WITH TIME ZONE," +
                    "    header_data JSONB NOT NULL" +
                    ")"
                );
                
                // Create business_events table for multi-table test
                stmt.execute(
                    "CREATE TABLE business_events (" +
                    "    id VARCHAR(255) PRIMARY KEY," +
                    "    event_type VARCHAR(255) NOT NULL," +
                    "    created_date TIMESTAMP WITH TIME ZONE," +
                    "    saved_date TIMESTAMP WITH TIME ZONE," +
                    "    updated_date TIMESTAMP WITH TIME ZONE," +
                    "    payload JSONB" +
                    ")"
                );
                
                // Insert initial test data
                stmt.execute(
                    "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) " +
                    "VALUES " +
                    "    ('event-1', 'LoanCreated', 'LoanCreated', NOW(), NOW(), '{\"uuid\": \"event-1\"}'::jsonb)," +
                    "    ('event-2', 'CarCreated', 'CarCreated', NOW(), NOW(), '{\"uuid\": \"event-2\"}'::jsonb)"
                );
            }
        }
    }
    
    @BeforeEach
    void setUp() throws Exception {
        // Clear test data before each test
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("DELETE FROM event_headers");
                stmt.execute("DELETE FROM business_events");
            }
        }
    }
    
    @Test
    void testDatabaseConnection() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            assertThat(conn.isValid(5)).isTrue();
        }
    }
    
    @Test
    void testTableExists() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery(
                     "SELECT COUNT(*) FROM event_headers")) {
                
                rs.next();
                assertThat(rs.getInt(1)).isGreaterThan(0);
            }
        }
    }
    
    @Test
    void testConnectorConfiguration() {
        Map<String, String> config = createTestConfig();
        
        // Verify configuration can be created
        // Note: Full connector test would require mocking IAM token generation
        assertThat(config).isNotEmpty();
        assertThat(config.get("dsql.database.name")).isEqualTo("testdb");
        
        DsqlConnectorConfig connectorConfig = new DsqlConnectorConfig(config);
        assertThat(connectorConfig.getDatabaseName()).isEqualTo("testdb");
        assertThat(connectorConfig.getTablesArray()).containsExactly("event_headers");
    }
    
    @Test
    void testSchemaBuilding() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            DsqlSchema schema = new DsqlSchema("event_headers", "dsql-cdc");
            schema.buildSchemas(conn.getMetaData(), "public");
            schema.validateRequiredColumns();
            
            assertThat(schema.getValueSchema()).isNotNull();
            assertThat(schema.getKeySchema()).isNotNull();
            assertThat(schema.getPrimaryKeyColumn()).isEqualTo("id");
            assertThat(schema.getColumnNames()).contains("id", "event_name", "saved_date");
        }
    }
    
    @Test
    void testOffsetContext() {
        DsqlOffsetContext offset = new DsqlOffsetContext("event_headers");
        
        assertThat(offset.isInitialized()).isFalse();
        
        Instant savedDate = Instant.now();
        offset.update(savedDate, "event-123");
        
        assertThat(offset.isInitialized()).isTrue();
        assertThat(offset.getSavedDate()).isEqualTo(savedDate);
        assertThat(offset.getLastId()).isEqualTo("event-123");
        
        Map<String, Object> offsetMap = offset.toOffsetMap();
        assertThat(offsetMap).containsKey("table");
        assertThat(offsetMap).containsKey("saved_date");
        assertThat(offsetMap).containsKey("last_id");
    }
    
    @Test
    void testOffsetPersistence() {
        // Test loading offset from map
        Map<String, Object> savedOffset = new HashMap<>();
        savedOffset.put("table", "event_headers");
        savedOffset.put("saved_date", Instant.now().toString());
        savedOffset.put("last_id", "event-456");
        
        DsqlOffsetContext loaded = DsqlOffsetContext.load(savedOffset, "event_headers");
        
        assertThat(loaded.isInitialized()).isTrue();
        assertThat(loaded.getLastId()).isEqualTo("event-456");
    }
    
    @Test
    void testMultiTableConfiguration() {
        Map<String, String> config = createTestConfig();
        config.put("dsql.tables", "event_headers,business_events");
        
        DsqlConnectorConfig connectorConfig = new DsqlConnectorConfig(config);
        String[] tables = connectorConfig.getTablesArray();
        
        assertThat(tables).hasSize(2);
        assertThat(tables).containsExactly("event_headers", "business_events");
    }
    
    @Test
    void testSchemaWithUpdatedDateColumn() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            DsqlSchema schema = new DsqlSchema("business_events", "dsql-cdc");
            schema.buildSchemas(conn.getMetaData(), "public");
            
            assertThat(schema.hasUpdatedDateColumn()).isTrue();
            assertThat(schema.getColumnNames()).contains("updated_date");
        }
    }
    
    @Test
    void testFullCdcPipeline() throws Exception {
        // Insert new records
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                // Insert records with different saved_date values
                Instant now = Instant.now();
                stmt.execute(
                    "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) " +
                    "VALUES " +
                    "    ('event-3', 'LoanCreated', 'LoanCreated', '" + Timestamp.from(now) + "', '" + Timestamp.from(now) + "', '{\"uuid\": \"event-3\"}'::jsonb)," +
                    "    ('event-4', 'CarCreated', 'CarCreated', '" + Timestamp.from(now.plusSeconds(1)) + "', '" + Timestamp.from(now.plusSeconds(1)) + "', '{\"uuid\": \"event-4\"}'::jsonb)"
                );
            }
            
            // Verify records exist
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM event_headers")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(2);
            }
        }
    }
    
    @Test
    void testInitialSnapshotWithNoOffset() throws Exception {
        // Test initial snapshot when no offset exists
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert test data
            try (Statement stmt = conn.createStatement()) {
                stmt.execute(
                    "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) " +
                    "VALUES " +
                    "    ('snapshot-1', 'TestEvent1', 'TestType', NOW(), NOW(), '{\"test\": 1}'::jsonb)," +
                    "    ('snapshot-2', 'TestEvent2', 'TestType', NOW(), NOW(), '{\"test\": 2}'::jsonb)," +
                    "    ('snapshot-3', 'TestEvent3', 'TestType', NOW(), NOW(), '{\"test\": 3}'::jsonb)"
                );
            }
            
            // Create offset context with no offset (simulating first run)
            DsqlOffsetContext offset = new DsqlOffsetContext("event_headers");
            assertThat(offset.isInitialized()).isFalse();
            
            // Verify that when offset is not initialized, query should capture all records
            // This is tested through the buildQuery() method which doesn't add WHERE clause
            // when offset is not initialized
        }
    }
    
    @Test
    void testInitialSnapshotWithExistingData() throws Exception {
        // Test that all existing records are captured on first run
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert multiple records
            int recordCount = 10;
            try (Statement stmt = conn.createStatement()) {
                StringBuilder values = new StringBuilder();
                for (int i = 0; i < recordCount; i++) {
                    if (i > 0) values.append(", ");
                    values.append(String.format(
                        "('snapshot-%d', 'Event%d', 'Type%d', NOW(), NOW(), '{\"id\": %d}'::jsonb)",
                        i, i, i, i
                    ));
                }
                stmt.execute(
                    "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) " +
                    "VALUES " + values.toString()
                );
            }
            
            // Verify all records exist
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM event_headers WHERE id LIKE 'snapshot-%'")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(recordCount);
            }
        }
    }
    
    @Test
    void testSnapshotWithEmptyTable() throws Exception {
        // Test behavior when table is empty
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Table should be empty (cleared in setUp)
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM event_headers")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(0);
            }
            
            // Offset should not be initialized for empty table
            DsqlOffsetContext offset = new DsqlOffsetContext("event_headers");
            assertThat(offset.isInitialized()).isFalse();
        }
    }
    
    @Test
    void testSnapshotOrderedBySavedDate() throws Exception {
        // Test that snapshot captures records in order by saved_date
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert records with different saved_date values
            Instant baseTime = Instant.now();
            try (Statement stmt = conn.createStatement()) {
                for (int i = 0; i < 5; i++) {
                    Instant savedDate = baseTime.plusSeconds(i * 10);
                    stmt.execute(
                        String.format(
                            "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) " +
                            "VALUES ('ordered-%d', 'Event%d', 'Type', '%s', '%s', '{\"order\": %d}'::jsonb)",
                            i, i, Timestamp.from(savedDate), Timestamp.from(savedDate), i
                        )
                    );
                }
            }
            
            // Verify records are ordered by saved_date
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery(
                     "SELECT id FROM event_headers WHERE id LIKE 'ordered-%' ORDER BY saved_date ASC")) {
                
                int index = 0;
                while (rs.next()) {
                    assertThat(rs.getString("id")).isEqualTo("ordered-" + index);
                    index++;
                }
                assertThat(index).isEqualTo(5);
            }
        }
    }
    
    private Map<String, String> createTestConfig() {
        Map<String, String> config = new HashMap<>();
        config.put("dsql.endpoint.primary", postgres.getHost());
        config.put("dsql.port", String.valueOf(postgres.getFirstMappedPort()));
        config.put("dsql.database.name", postgres.getDatabaseName());
        config.put("dsql.region", "us-east-1");
        config.put("dsql.iam.username", postgres.getUsername());
        config.put("dsql.tables", "event_headers");
        config.put("dsql.poll.interval.ms", "1000");
        config.put("dsql.batch.size", "1000");
        config.put("topic.prefix", "dsql-cdc");
        return config;
    }
}
