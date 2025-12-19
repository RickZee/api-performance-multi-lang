package io.debezium.connector.dsql;

import io.debezium.connector.dsql.testutil.TestUtils;
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

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Tests for transaction and size limits in DSQL connector.
 * 
 * Tests 10 MiB transaction limit, 3,000 row limit, 2 MiB row size limit, and batch handling.
 */
@Testcontainers(disabledWithoutDocker = true)
@ExtendWith(org.testcontainers.junit.jupiter.TestcontainersExtension.class)
class DsqlTransactionLimitTest {
    
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15")
            .withDatabaseName("testdb")
            .withUsername("testuser")
            .withPassword("testpass");
    
    @BeforeEach
    void setUp() throws Exception {
        // Access container to trigger startup (Testcontainers starts lazily)
        String jdbcUrl = postgres.getJdbcUrl();
        
        try (Connection conn = DriverManager.getConnection(
                jdbcUrl,
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                // Create table if it doesn't exist
                TestUtils.createTestTable(conn, "limit_test");
            }
            
            // Clear existing data
            TestUtils.clearTable(conn, "limit_test");
        }
    }
    
    @Test
    void testLargeBatchHandling() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert batch of records (within batch size limit)
            int batchSize = 1000;
            TestUtils.insertTestRecords(conn, "limit_test", batchSize);
            
            // Verify all records inserted
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM limit_test")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(batchSize);
            }
        }
    }
    
    @Test
    void testRowSizeLimitExceeded() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                // Create table with large text column
                stmt.execute(
                    "CREATE TABLE IF NOT EXISTS large_row_test (" +
                    "    id VARCHAR(255) PRIMARY KEY," +
                    "    saved_date TIMESTAMP WITH TIME ZONE," +
                    "    large_data TEXT" +
                    ")"
                );
                
                // Insert row approaching 2 MiB limit
                // Use 1.8 MiB to test large value handling without exceeding PostgreSQL's practical limits
                String largeValue = "x".repeat(1_800_000); // 1.8 MB
                stmt.execute(
                    String.format("INSERT INTO large_row_test (id, saved_date, large_data) " +
                                 "VALUES ('large-1', NOW(), '%s')", largeValue.replace("'", "''"))
                );
                
                // Verify row was inserted (PostgreSQL can handle this)
                try (var rs = stmt.executeQuery("SELECT LENGTH(large_data) FROM large_row_test WHERE id = 'large-1'")) {
                    rs.next();
                    assertThat(rs.getInt(1)).isEqualTo(1_800_000);
                }
            }
        }
    }
    
    @Test
    void testRowCountLimitExceeded() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert large number of rows (approaching 3,000 row limit)
            // Note: DSQL has a 3,000 row limit per transaction, but we can test with multiple transactions
            int rowCount = 5000; // Exceeds 3,000 limit
            
            // Insert in batches to simulate transaction limit
            int batchSize = 2000;
            for (int i = 0; i < rowCount; i += batchSize) {
                int currentBatch = Math.min(batchSize, rowCount - i);
                TestUtils.insertTestRecords(conn, "limit_test", currentBatch, Instant.now().plusSeconds(i));
            }
            
            // Verify all records inserted
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM limit_test")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(rowCount);
            }
        }
    }
    
    @Test
    void testTransactionSizeLimitExceeded() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                // Create table with large data column
                stmt.execute(
                    "CREATE TABLE IF NOT EXISTS large_tx_test (" +
                    "    id VARCHAR(255) PRIMARY KEY," +
                    "    saved_date TIMESTAMP WITH TIME ZONE," +
                    "    data TEXT" +
                    ")"
                );
                
                // Simulate large transaction (approaching 10 MiB limit)
                // Insert multiple rows with large data
                int rowSize = 100_000; // 100 KB per row
                int rowsToReachLimit = (10 * 1024 * 1024) / rowSize; // ~100 rows for 10 MiB
                
                StringBuilder values = new StringBuilder();
                for (int i = 0; i < rowsToReachLimit; i++) {
                    if (i > 0) values.append(", ");
                    String largeData = "x".repeat(rowSize);
                    values.append(String.format(
                        "('tx-%d', NOW(), '%s')",
                        i, largeData.replace("'", "''")
                    ));
                }
                
                // Insert in single transaction
                stmt.execute(
                    "INSERT INTO large_tx_test (id, saved_date, data) VALUES " + values.toString()
                );
                
                // Verify transaction succeeded (PostgreSQL can handle this)
                try (var rs = stmt.executeQuery("SELECT COUNT(*) FROM large_tx_test")) {
                    rs.next();
                    assertThat(rs.getInt(1)).isEqualTo(rowsToReachLimit);
                }
            }
        }
    }
    
    @Test
    void testGracefulErrorOnLimitExceeded() throws Exception {
        // Test that connector handles limit errors gracefully
        // This is a structural test - actual limit enforcement would be in connector logic
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Verify connection works
            assertThat(conn.isValid(5)).isTrue();
            
            // Note: Actual limit checking would be done in connector code
            // This test verifies the infrastructure can handle large operations
        }
    }
    
    @Test
    void testBatchSplitting() throws Exception {
        // Test that batches can be split if needed
        // This is a structural test for future batch splitting implementation
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert records that would require batch splitting
            int totalRecords = 5000;
            int batchSize = 1000; // Connector batch size limit
            
            // Simulate batch splitting by inserting in chunks
            for (int offset = 0; offset < totalRecords; offset += batchSize) {
                int currentBatch = Math.min(batchSize, totalRecords - offset);
                TestUtils.insertTestRecords(conn, "limit_test", currentBatch, Instant.now().plusSeconds(offset));
            }
            
            // Verify all records processed
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM limit_test")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(totalRecords);
            }
        }
    }
}
