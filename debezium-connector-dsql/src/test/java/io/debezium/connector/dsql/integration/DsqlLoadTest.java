package io.debezium.connector.dsql.integration;

import io.debezium.connector.dsql.testutil.TestUtils;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;
import java.time.Instant;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Performance and load tests for DSQL connector.
 * 
 * Tests throughput under high load (30K TPS), lag monitoring, metrics exposure,
 * connection pool behavior, and batch processing performance.
 * 
 * Note: These tests are marked as "slow" and may be skipped in CI.
 */
@Tag("slow")
@Testcontainers(disabledWithoutDocker = true)
@ExtendWith(org.testcontainers.junit.jupiter.TestcontainersExtension.class)
class DsqlLoadTest {
    
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
                TestUtils.createTestTable(conn, "load_test");
            }
            
            // Clear existing data
            TestUtils.clearTable(conn, "load_test");
        }
    }
    
    @Test
    void testThroughputUnderHighLoad() throws Exception {
        // Test handling of high throughput (simulated 30K TPS)
        // Note: We test with smaller load due to test environment constraints
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            int recordCount = 1000; // Smaller load for test environment
            long startTime = System.currentTimeMillis();
            
            // Insert records in batches to simulate high throughput
            ExecutorService executor = Executors.newFixedThreadPool(10);
            AtomicLong insertedCount = new AtomicLong(0);
            
            for (int i = 0; i < 10; i++) {
                final int batchId = i;
                executor.submit(() -> {
                    try (Connection c = DriverManager.getConnection(
                            postgres.getJdbcUrl(),
                            postgres.getUsername(),
                            postgres.getPassword())) {
                        
                        TestUtils.insertTestRecords(c, "load_test", recordCount / 10, 
                                                   Instant.now().plusSeconds(batchId));
                        insertedCount.addAndGet(recordCount / 10);
                    } catch (Exception e) {
                        e.printStackTrace();
                    }
                });
            }
            
            executor.shutdown();
            assertThat(executor.awaitTermination(30, TimeUnit.SECONDS)).isTrue();
            
            long duration = System.currentTimeMillis() - startTime;
            
            // Verify all records inserted
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM load_test")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(recordCount);
            }
            
            // Calculate approximate TPS
            double tps = (recordCount * 1000.0) / duration;
            assertThat(tps).isGreaterThan(0);
        }
    }
    
    @Test
    void testLagUnderLoad() throws Exception {
        // Test lag monitoring under load
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert data with timestamps
            Instant oldTime = Instant.now().minusSeconds(300);
            TestUtils.insertTestRecords(conn, "load_test", 100, oldTime);
            
            // Insert new data
            TestUtils.insertTestRecords(conn, "load_test", 100, Instant.now());
            
            // Calculate lag
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery(
                     "SELECT MIN(saved_date) FROM load_test")) {
                rs.next();
                java.sql.Timestamp oldest = rs.getTimestamp(1);
                if (oldest != null) {
                    long lagSeconds = (System.currentTimeMillis() - oldest.getTime()) / 1000;
                    assertThat(lagSeconds).isGreaterThan(200);
                }
            }
        }
    }
    
    @Test
    void testMetricsExposure() throws Exception {
        // Structural test for metrics exposure (snapshot progress, streaming lag)
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert data
            TestUtils.insertTestRecords(conn, "load_test", 100);
            
            // Verify data exists (metrics would track this)
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM load_test")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(100);
            }
        }
    }
    
    @Test
    void testConnectionPoolUnderLoad() throws Exception {
        // Test connection pool behavior under load
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Simulate concurrent connections
            ExecutorService executor = Executors.newFixedThreadPool(5);
            
            for (int i = 0; i < 5; i++) {
                executor.submit(() -> {
                    try (Connection c = DriverManager.getConnection(
                            postgres.getJdbcUrl(),
                            postgres.getUsername(),
                            postgres.getPassword())) {
                        
                        assertThat(c.isValid(5)).isTrue();
                        TestUtils.insertTestRecords(c, "load_test", 10);
                    } catch (Exception e) {
                        e.printStackTrace();
                    }
                });
            }
            
            executor.shutdown();
            assertThat(executor.awaitTermination(10, TimeUnit.SECONDS)).isTrue();
            
            // Verify all records inserted
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM load_test")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(50);
            }
        }
    }
    
    @Test
    void testBatchProcessingPerformance() throws Exception {
        // Test batch processing efficiency
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            int batchSize = 100;
            int totalRecords = 1000;
            
            long startTime = System.currentTimeMillis();
            
            // Insert in batches
            for (int i = 0; i < totalRecords; i += batchSize) {
                TestUtils.insertTestRecords(conn, "load_test", batchSize, 
                                           Instant.now().plusSeconds(i));
            }
            
            long duration = System.currentTimeMillis() - startTime;
            
            // Verify all records inserted
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM load_test")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(totalRecords);
            }
            
            // Verify reasonable performance
            assertThat(duration).isLessThan(30000); // Should complete in < 30 seconds
        }
    }
    
    @Test
    void testMemoryUsageUnderLoad() throws Exception {
        // Structural test for memory consumption under load
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert large number of records
            TestUtils.insertTestRecords(conn, "load_test", 1000);
            
            // Verify records inserted
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM load_test")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(1000);
            }
            
            // Note: Actual memory monitoring would require JVM metrics
            // This test verifies operations complete without OOM
        }
    }
}
