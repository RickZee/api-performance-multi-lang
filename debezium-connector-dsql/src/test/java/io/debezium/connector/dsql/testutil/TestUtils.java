package io.debezium.connector.dsql.testutil;

import java.sql.Connection;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.HashMap;

/**
 * Test utilities for DSQL connector tests.
 */
public class TestUtils {
    
    /**
     * Create a test table with standard CDC columns.
     */
    public static void createTestTable(Connection conn, String tableName) throws Exception {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute(
                "CREATE TABLE IF NOT EXISTS " + tableName + " (" +
                "    id VARCHAR(255) PRIMARY KEY," +
                "    event_name VARCHAR(255) NOT NULL," +
                "    event_type VARCHAR(255)," +
                "    created_date TIMESTAMP WITH TIME ZONE," +
                "    saved_date TIMESTAMP WITH TIME ZONE," +
                "    header_data JSONB NOT NULL" +
                ")"
            );
        }
    }
    
    /**
     * Create a test table with UPDATE/DELETE support columns.
     */
    public static void createTestTableWithUpdateDelete(Connection conn, String tableName) throws Exception {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute(
                "CREATE TABLE IF NOT EXISTS " + tableName + " (" +
                "    id VARCHAR(255) PRIMARY KEY," +
                "    event_name VARCHAR(255) NOT NULL," +
                "    created_date TIMESTAMP WITH TIME ZONE," +
                "    saved_date TIMESTAMP WITH TIME ZONE," +
                "    updated_date TIMESTAMP WITH TIME ZONE," +
                "    deleted_date TIMESTAMP WITH TIME ZONE," +
                "    header_data JSONB" +
                ")"
            );
        }
    }
    
    /**
     * Insert test records into a table.
     */
    public static void insertTestRecords(Connection conn, String tableName, int count) throws Exception {
        insertTestRecords(conn, tableName, count, Instant.now());
    }
    
    /**
     * Insert test records with specific saved_date.
     */
    public static void insertTestRecords(Connection conn, String tableName, int count, Instant baseTime) throws Exception {
        try (Statement stmt = conn.createStatement()) {
            List<String> values = new ArrayList<>();
            for (int i = 0; i < count; i++) {
                Instant savedDate = baseTime.plusSeconds(i);
                values.add(String.format(
                    "('event-%d', 'Event%d', 'EventType%d', '%s', '%s', '{\"id\": %d}'::jsonb)",
                    i, i, i, Timestamp.from(savedDate), Timestamp.from(savedDate), i
                ));
            }
            String sql = "INSERT INTO " + tableName + 
                        " (id, event_name, event_type, created_date, saved_date, header_data) VALUES " +
                        String.join(", ", values);
            stmt.execute(sql);
        }
    }
    
    /**
     * Clear all records from a table.
     */
    public static void clearTable(Connection conn, String tableName) throws Exception {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("DELETE FROM " + tableName);
        }
    }
    
    /**
     * Drop a table.
     */
    public static void dropTable(Connection conn, String tableName) throws Exception {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("DROP TABLE IF EXISTS " + tableName);
        }
    }
    
    /**
     * Create a valid connector configuration map.
     */
    public static Map<String, String> createConnectorConfig(String endpoint, int port, 
                                                             String database, String tables) {
        Map<String, String> config = new HashMap<>();
        config.put("dsql.endpoint.primary", endpoint);
        config.put("dsql.port", String.valueOf(port));
        config.put("dsql.database.name", database);
        config.put("dsql.region", "us-east-1");
        config.put("dsql.iam.username", "testuser");
        config.put("dsql.tables", tables);
        config.put("dsql.poll.interval.ms", "1000");
        config.put("dsql.batch.size", "1000");
        config.put("topic.prefix", "dsql-cdc");
        return config;
    }
    
    /**
     * Wait for a condition to become true.
     */
    public static void waitForCondition(java.util.function.Supplier<Boolean> condition, 
                                       long timeoutMs, long intervalMs) throws InterruptedException {
        long startTime = System.currentTimeMillis();
        while (!condition.get() && (System.currentTimeMillis() - startTime) < timeoutMs) {
            Thread.sleep(intervalMs);
        }
        if (!condition.get()) {
            throw new AssertionError("Condition not met within " + timeoutMs + "ms");
        }
    }
    
    /**
     * Sleep for a duration, handling InterruptedException.
     */
    public static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException(e);
        }
    }
    
    /**
     * Generate a large transaction with specified size and row count.
     * 
     * @param conn Database connection
     * @param tableName Table name
     * @param sizeBytes Approximate size in bytes
     * @param rowCount Number of rows
     */
    public static void generateLargeTransaction(Connection conn, String tableName, 
                                               int sizeBytes, int rowCount) throws Exception {
        int rowSize = sizeBytes / rowCount;
        try (Statement stmt = conn.createStatement()) {
            List<String> values = new ArrayList<>();
            for (int i = 0; i < rowCount; i++) {
                String largeData = "x".repeat(Math.max(1, rowSize - 200)); // Reserve space for other columns
                values.add(String.format(
                    "('tx-%d', 'Event%d', 'Type', NOW(), NOW(), '%s'::jsonb)",
                    i, i, largeData.replace("'", "''")
                ));
            }
            String sql = "INSERT INTO " + tableName + 
                        " (id, event_name, event_type, created_date, saved_date, header_data) VALUES " +
                        String.join(", ", values);
            stmt.execute(sql);
        }
    }
    
    /**
     * Create a table with many columns (up to specified count).
     * 
     * @param conn Database connection
     * @param tableName Table name
     * @param columnCount Number of columns to create
     */
    public static void createTableWithManyColumns(Connection conn, String tableName, int columnCount) throws Exception {
        try (Statement stmt = conn.createStatement()) {
            StringBuilder createTable = new StringBuilder(
                "CREATE TABLE IF NOT EXISTS " + tableName + " (" +
                "id VARCHAR(255) PRIMARY KEY, " +
                "saved_date TIMESTAMP WITH TIME ZONE"
            );
            
            for (int i = 1; i <= columnCount; i++) {
                createTable.append(", col_").append(i).append(" VARCHAR(255)");
            }
            createTable.append(")");
            
            stmt.execute(createTable.toString());
        }
    }
    
    /**
     * Create a signaling table for incremental snapshots.
     * 
     * @param conn Database connection
     */
    public static void createSignalingTable(Connection conn) throws Exception {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute(
                "CREATE TABLE IF NOT EXISTS debezium_signal (" +
                "    id VARCHAR(255) PRIMARY KEY," +
                "    type VARCHAR(32) NOT NULL," +
                "    data VARCHAR(2048)" +
                ")"
            );
        }
    }
    
    /**
     * Generate test data with various PostgreSQL types.
     * 
     * @param conn Database connection
     * @param tableName Table name
     */
    public static void generateTestDataWithTypes(Connection conn, String tableName) throws Exception {
        try (Statement stmt = conn.createStatement()) {
            // Create table with various types
            stmt.execute(
                "CREATE TABLE IF NOT EXISTS " + tableName + " (" +
                "    id VARCHAR(255) PRIMARY KEY," +
                "    saved_date TIMESTAMP WITH TIME ZONE," +
                "    decimal_col DECIMAL(10,2)," +
                "    jsonb_col JSONB," +
                "    array_col INTEGER[]," +
                "    text_col TEXT" +
                ")"
            );
            
            // Insert test data
            stmt.execute(
                "INSERT INTO " + tableName + 
                " (id, saved_date, decimal_col, jsonb_col, array_col, text_col) " +
                "VALUES " +
                "('type-1', NOW(), 123.45, '{\"key\": \"value\"}'::jsonb, ARRAY[1,2,3], 'test text')"
            );
        }
    }
    
    /**
     * Simulate OCC conflict scenario.
     * Note: This is a structural helper - actual OCC conflicts depend on DSQL implementation.
     * 
     * @param conn Database connection
     * @param tableName Table name
     */
    public static void simulateOccConflict(Connection conn, String tableName) throws Exception {
        // Simulate concurrent writes that might cause conflicts
        try (Statement stmt = conn.createStatement()) {
            // Insert records that might conflict
            for (int i = 0; i < 10; i++) {
                stmt.execute(
                    String.format(
                        "INSERT INTO " + tableName + 
                        " (id, event_name, event_type, created_date, saved_date, header_data) " +
                        "VALUES ('occ-%d', 'Event%d', 'Type', NOW(), NOW(), '{\"conflict\": true}'::jsonb)",
                        i, i
                    )
                );
            }
        }
    }
    
    /**
     * Create multi-region test setup.
     * Note: This creates tables in multiple connections to simulate regions.
     * 
     * @param primaryConn Primary region connection
     * @param secondaryConn Secondary region connection (can be null)
     * @param tableName Table name
     */
    public static void createMultiRegionSetup(Connection primaryConn, Connection secondaryConn, 
                                             String tableName) throws Exception {
        // Create table in primary region
        createTestTable(primaryConn, tableName);
        
        // Create table in secondary region if provided
        if (secondaryConn != null) {
            createTestTable(secondaryConn, tableName);
        }
    }
    
    /**
     * Generate load test data with specified TPS and duration.
     * 
     * @param conn Database connection
     * @param tableName Table name
     * @param tps Transactions per second
     * @param durationSeconds Duration in seconds
     */
    public static void generateLoadData(Connection conn, String tableName, 
                                       int tps, int durationSeconds) throws Exception {
        int totalRecords = tps * durationSeconds;
        int batchSize = Math.min(1000, totalRecords); // Batch size for efficiency
        
        try (Statement stmt = conn.createStatement()) {
            for (int batch = 0; batch < totalRecords; batch += batchSize) {
                List<String> values = new ArrayList<>();
                int currentBatch = Math.min(batchSize, totalRecords - batch);
                
                for (int i = 0; i < currentBatch; i++) {
                    int recordId = batch + i;
                    values.add(String.format(
                        "('load-%d', 'Event%d', 'Type', NOW(), NOW(), '{\"load\": true}'::jsonb)",
                        recordId, recordId
                    ));
                }
                
                String sql = "INSERT INTO " + tableName + 
                            " (id, event_name, event_type, created_date, saved_date, header_data) VALUES " +
                            String.join(", ", values);
                stmt.execute(sql);
            }
        }
    }
}
