package io.debezium.connector.dsql.testutil;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * Utilities for managing test data in real DSQL databases.
 */
public class RealDsqlTestUtils {
    
    /**
     * Create a test table with proper schema for CDC testing.
     * 
     * @param conn Database connection
     * @param tableName Name of the table to create
     * @param primaryKeyColumn Name of the primary key column
     * @throws SQLException if table creation fails
     */
    public static void createTestTable(Connection conn, String tableName, String primaryKeyColumn) throws SQLException {
        String sql = String.format(
            "CREATE TABLE IF NOT EXISTS %s (" +
            "    %s VARCHAR(255) PRIMARY KEY," +
            "    event_name VARCHAR(255) NOT NULL," +
            "    event_type VARCHAR(255)," +
            "    created_date TIMESTAMP WITH TIME ZONE," +
            "    saved_date TIMESTAMP WITH TIME ZONE NOT NULL," +
            "    updated_date TIMESTAMP WITH TIME ZONE," +
            "    deleted_date TIMESTAMP WITH TIME ZONE," +
            "    header_data JSONB" +
            ")",
            tableName, primaryKeyColumn
        );
        
        try (Statement stmt = conn.createStatement()) {
            stmt.execute(sql);
        }
    }
    
    /**
     * Insert test data into a table.
     * 
     * @param conn Database connection
     * @param tableName Name of the table
     * @param id Primary key value
     * @param eventName Event name
     * @param savedDate Saved date (if null, uses current timestamp)
     * @return Number of rows inserted
     * @throws SQLException if insert fails
     */
    public static int insertTestData(Connection conn, String tableName, String id, 
                                     String eventName, Timestamp savedDate) throws SQLException {
        if (savedDate == null) {
            savedDate = Timestamp.from(Instant.now());
        }
        
        String sql = String.format(
            "INSERT INTO %s (id, event_name, saved_date, created_date) VALUES (?, ?, ?, ?)",
            tableName
        );
        
        try (PreparedStatement pstmt = conn.prepareStatement(sql)) {
            pstmt.setString(1, id);
            pstmt.setString(2, eventName);
            pstmt.setTimestamp(3, savedDate);
            pstmt.setTimestamp(4, savedDate);
            return pstmt.executeUpdate();
        }
    }
    
    /**
     * Insert test data with multiple records.
     * 
     * @param conn Database connection
     * @param tableName Name of the table
     * @param count Number of records to insert
     * @param baseId Base ID prefix
     * @return List of inserted IDs
     * @throws SQLException if insert fails
     */
    public static List<String> insertTestData(Connection conn, String tableName, 
                                              int count, String baseId) throws SQLException {
        List<String> ids = new ArrayList<>();
        Timestamp now = Timestamp.from(Instant.now());
        
        for (int i = 0; i < count; i++) {
            String id = baseId + "-" + i;
            insertTestData(conn, tableName, id, "test-event-" + i, now);
            ids.add(id);
        }
        
        return ids;
    }
    
    /**
     * Update test data.
     * 
     * @param conn Database connection
     * @param tableName Name of the table
     * @param id Primary key value
     * @param newEventName New event name
     * @return Number of rows updated
     * @throws SQLException if update fails
     */
    public static int updateTestData(Connection conn, String tableName, String id, 
                                     String newEventName) throws SQLException {
        String sql = String.format(
            "UPDATE %s SET event_name = ?, updated_date = ? WHERE id = ?",
            tableName
        );
        
        try (PreparedStatement pstmt = conn.prepareStatement(sql)) {
            pstmt.setString(1, newEventName);
            pstmt.setTimestamp(2, Timestamp.from(Instant.now()));
            pstmt.setString(3, id);
            return pstmt.executeUpdate();
        }
    }
    
    /**
     * Delete test data (soft delete if deleted_date column exists, hard delete otherwise).
     * 
     * @param conn Database connection
     * @param tableName Name of the table
     * @param id Primary key value
     * @return Number of rows affected
     * @throws SQLException if delete fails
     */
    public static int deleteTestData(Connection conn, String tableName, String id) throws SQLException {
        // Check if deleted_date column exists
        boolean hasDeletedDate = false;
        try (ResultSet rs = conn.getMetaData().getColumns(null, "public", tableName, "deleted_date")) {
            hasDeletedDate = rs.next();
        }
        
        if (hasDeletedDate) {
            // Soft delete
            String sql = String.format(
                "UPDATE %s SET deleted_date = ? WHERE id = ?",
                tableName
            );
            try (PreparedStatement pstmt = conn.prepareStatement(sql)) {
                pstmt.setTimestamp(1, Timestamp.from(Instant.now()));
                pstmt.setString(2, id);
                return pstmt.executeUpdate();
            }
        } else {
            // Hard delete
            String sql = String.format("DELETE FROM %s WHERE id = ?", tableName);
            try (PreparedStatement pstmt = conn.prepareStatement(sql)) {
                pstmt.setString(1, id);
                return pstmt.executeUpdate();
            }
        }
    }
    
    /**
     * Clean up test data from a table.
     * 
     * @param conn Database connection
     * @param tableName Name of the table
     * @param idPrefix Prefix of IDs to delete (if null, deletes all)
     * @return Number of rows deleted
     * @throws SQLException if cleanup fails
     */
    public static int cleanupTestData(Connection conn, String tableName, String idPrefix) throws SQLException {
        if (idPrefix != null && !idPrefix.isEmpty()) {
            String sql = String.format("DELETE FROM %s WHERE id LIKE ?", tableName);
            try (PreparedStatement pstmt = conn.prepareStatement(sql)) {
                pstmt.setString(1, idPrefix + "%");
                return pstmt.executeUpdate();
            }
        } else {
            String sql = String.format("DELETE FROM %s", tableName);
            try (Statement stmt = conn.createStatement()) {
                return stmt.executeUpdate(sql);
            }
        }
    }
    
    /**
     * Drop a test table.
     * 
     * @param conn Database connection
     * @param tableName Name of the table to drop
     * @throws SQLException if drop fails
     */
    public static void dropTestTable(Connection conn, String tableName) throws SQLException {
        String sql = "DROP TABLE IF EXISTS " + tableName;
        try (Statement stmt = conn.createStatement()) {
            stmt.execute(sql);
        }
    }
    
    /**
     * Wait for data to be available in a table (useful for async scenarios).
     * 
     * @param conn Database connection
     * @param tableName Name of the table
     * @param expectedCount Expected number of records
     * @param timeoutMs Timeout in milliseconds
     * @return true if data is available within timeout
     * @throws SQLException if query fails
     * @throws InterruptedException if interrupted
     */
    public static boolean waitForData(Connection conn, String tableName, int expectedCount, 
                                     long timeoutMs) throws SQLException, InterruptedException {
        long startTime = System.currentTimeMillis();
        
        while (System.currentTimeMillis() - startTime < timeoutMs) {
            String sql = "SELECT COUNT(*) FROM " + tableName;
            try (Statement stmt = conn.createStatement();
                 ResultSet rs = stmt.executeQuery(sql)) {
                if (rs.next()) {
                    int count = rs.getInt(1);
                    if (count >= expectedCount) {
                        return true;
                    }
                }
            }
            
            Thread.sleep(100); // Wait 100ms before retry
        }
        
        return false;
    }
    
    /**
     * Get count of records in a table.
     * 
     * @param conn Database connection
     * @param tableName Name of the table
     * @return Record count
     * @throws SQLException if query fails
     */
    public static int getRecordCount(Connection conn, String tableName) throws SQLException {
        String sql = "SELECT COUNT(*) FROM " + tableName;
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            if (rs.next()) {
                return rs.getInt(1);
            }
        }
        return 0;
    }
}
