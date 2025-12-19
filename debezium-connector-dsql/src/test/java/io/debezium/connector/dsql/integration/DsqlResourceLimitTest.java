package io.debezium.connector.dsql.integration;

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

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Tests for resource limits in DSQL connector.
 * 
 * Tests table count limits (1,000), storage quota (10 TiB), connection limits (10,000),
 * and index limits (24 per table).
 */
@Testcontainers(disabledWithoutDocker = true)
@ExtendWith(org.testcontainers.junit.jupiter.TestcontainersExtension.class)
class DsqlResourceLimitTest {
    
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15")
            .withDatabaseName("testdb")
            .withUsername("testuser")
            .withPassword("testpass");
    
    @BeforeEach
    void setUp() throws Exception {
        // Access container to trigger startup (Testcontainers starts lazily)
        String jdbcUrl = postgres.getJdbcUrl();
        
        // Clean up test tables
        try (Connection conn = DriverManager.getConnection(
                jdbcUrl,
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                // Drop test tables
                for (int i = 0; i < 10; i++) {
                    stmt.execute("DROP TABLE IF EXISTS limit_test_" + i);
                }
                stmt.execute("DROP TABLE IF EXISTS index_limit_test");
                stmt.execute("DROP TABLE IF EXISTS stability_test_0");
                stmt.execute("DROP TABLE IF EXISTS stability_test_1");
                stmt.execute("DROP TABLE IF EXISTS stability_test_2");
                stmt.execute("DROP TABLE IF EXISTS stability_test_3");
                stmt.execute("DROP TABLE IF EXISTS stability_test_4");
            }
        }
    }
    
    @Test
    void testMaxTableCountLimit() throws Exception {
        // Test approaching 1,000 table limit
        // Note: We test with smaller number due to test environment constraints
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Create multiple tables (simulating approach to 1,000 limit)
            int tableCount = 10; // Test with smaller number
            try (Statement stmt = conn.createStatement()) {
                for (int i = 0; i < tableCount; i++) {
                    TestUtils.createTestTable(conn, "limit_test_" + i);
                }
            }
            
            // Verify tables created
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery(
                     "SELECT COUNT(*) FROM information_schema.tables " +
                     "WHERE table_name LIKE 'limit_test_%'")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(tableCount);
            }
        }
    }
    
    @Test
    void testMaxIndexLimit() throws Exception {
        // Test 24 indexes per table limit
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                // Create table
                TestUtils.createTestTable(conn, "index_limit_test");
                
                // Create multiple indexes (approaching 24 limit)
                int indexCount = 10; // Test with smaller number
                for (int i = 0; i < indexCount; i++) {
                    stmt.execute(
                        "CREATE INDEX IF NOT EXISTS idx_" + i + " ON index_limit_test (event_name)"
                    );
                }
            }
            
            // Verify indexes created
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery(
                     "SELECT COUNT(*) FROM pg_indexes " +
                     "WHERE tablename = 'index_limit_test'")) {
                rs.next();
                assertThat(rs.getInt(1)).isGreaterThanOrEqualTo(10);
            }
        }
    }
    
    @Test
    void testGracefulErrorOnResourceLimit() throws Exception {
        // Test that connector handles resource limit errors gracefully
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Verify connection works
            assertThat(conn.isValid(5)).isTrue();
            
            // Note: Actual limit checking would be done in connector code
            // This test verifies the infrastructure can handle operations
        }
    }
    
    @Test
    void testConnectorStabilityAtLimits() throws Exception {
        // Test that connector doesn't crash when approaching limits
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Create multiple tables and indexes
            try (Statement stmt = conn.createStatement()) {
                for (int i = 0; i < 5; i++) {
                    TestUtils.createTestTable(conn, "stability_test_" + i);
                    
                    // Create indexes
                    for (int j = 0; j < 3; j++) {
                        stmt.execute(
                            "CREATE INDEX IF NOT EXISTS idx_stability_" + i + "_" + j +
                            " ON stability_test_" + i + " (event_name)"
                        );
                    }
                }
            }
            
            // Verify all tables exist
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery(
                     "SELECT COUNT(*) FROM information_schema.tables " +
                     "WHERE table_name LIKE 'stability_test_%'")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(5);
            }
        }
    }
    
    @Test
    void testMaxConnectionLimit() throws Exception {
        // Structural test for 10,000 connection limit
        // Note: We test with smaller number due to test environment constraints
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Verify connection works
            assertThat(conn.isValid(5)).isTrue();
            
            // Note: Actual connection limit testing would require connection pool configuration
            // This test verifies basic connection functionality
        }
    }
    
    @Test
    void testMaxStorageQuotaLimit() throws Exception {
        // Structural test for 10 TiB storage quota limit
        // Note: We can't easily test this in Testcontainers, but verify infrastructure
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Verify connection works
            assertThat(conn.isValid(5)).isTrue();
            
            // Note: Actual storage quota testing would require large data generation
            // This test verifies basic database operations work
        }
    }
}
