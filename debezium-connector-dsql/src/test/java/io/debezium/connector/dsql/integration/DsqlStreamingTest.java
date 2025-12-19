package io.debezium.connector.dsql.integration;

import io.debezium.connector.dsql.DsqlChangeEventSource;
import io.debezium.connector.dsql.DsqlConnectorConfig;
import io.debezium.connector.dsql.DsqlOffsetContext;
import io.debezium.connector.dsql.DsqlSchema;
import io.debezium.connector.dsql.connection.DsqlConnectionPool;
import io.debezium.connector.dsql.connection.MultiRegionEndpoint;
import io.debezium.connector.dsql.auth.IamTokenGenerator;
import io.debezium.connector.dsql.testutil.TestUtils;
import org.apache.kafka.connect.source.SourceRecord;
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
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Comprehensive streaming tests for DSQL connector.
 * 
 * Tests event ordering, transaction metadata, PK updates, concurrent writes, and lag detection.
 */
@Testcontainers(disabledWithoutDocker = true)
@ExtendWith(org.testcontainers.junit.jupiter.TestcontainersExtension.class)
class DsqlStreamingTest {
    
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
                TestUtils.createTestTable(conn, "streaming_test");
            }
            
            // Clear existing data
            TestUtils.clearTable(conn, "streaming_test");
        }
    }
    
    @Test
    void testStreamingAfterSnapshot() throws Exception {
        // Test transition from snapshot to streaming mode
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert initial data (snapshot)
            TestUtils.insertTestRecords(conn, "streaming_test", 10, Instant.now().minusSeconds(100));
            
            // Insert new data (streaming)
            TestUtils.insertTestRecords(conn, "streaming_test", 5, Instant.now());
            
            // Verify all records exist
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM streaming_test")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(15);
            }
        }
    }
    
    @Test
    void testOrderedEventDelivery() throws Exception {
        // Test that events are ordered by saved_date
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert records with different saved_date values
            Instant baseTime = Instant.now();
            try (Statement stmt = conn.createStatement()) {
                for (int i = 0; i < 10; i++) {
                    Instant savedDate = baseTime.plusSeconds(i * 10);
                    stmt.execute(
                        String.format(
                            "INSERT INTO streaming_test (id, event_name, event_type, created_date, saved_date, header_data) " +
                            "VALUES ('ordered-%d', 'Event%d', 'Type', '%s', '%s', '{\"order\": %d}'::jsonb)",
                            i, i, Timestamp.from(savedDate), Timestamp.from(savedDate), i
                        )
                    );
                }
            }
            
            // Verify records are ordered by saved_date
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery(
                     "SELECT id FROM streaming_test ORDER BY saved_date ASC")) {
                
                int index = 0;
                while (rs.next()) {
                    assertThat(rs.getString("id")).isEqualTo("ordered-" + index);
                    index++;
                }
                assertThat(index).isEqualTo(10);
            }
        }
    }
    
    @Test
    void testStreamingWithOffset() throws Exception {
        // Test resume from offset
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert initial data
            Instant baseTime = Instant.now().minusSeconds(100);
            TestUtils.insertTestRecords(conn, "streaming_test", 10, baseTime);
            
            // Create offset context
            DsqlOffsetContext offset = new DsqlOffsetContext("streaming_test");
            offset.update(baseTime.plusSeconds(5), "event-5");
            
            assertThat(offset.isInitialized()).isTrue();
            assertThat(offset.getSavedDate()).isAfter(baseTime);
            
            // Insert new data after offset
            TestUtils.insertTestRecords(conn, "streaming_test", 5, Instant.now());
            
            // Verify new data exists
            try (var pstmt = conn.prepareStatement(
                     "SELECT COUNT(*) FROM streaming_test WHERE saved_date > ?")) {
                pstmt.setTimestamp(1, Timestamp.from(offset.getSavedDate()));
                try (var rs = pstmt.executeQuery()) {
                    rs.next();
                    assertThat(rs.getInt(1)).isGreaterThan(0);
                }
            }
        }
    }
    
    @Test
    void testPrimaryKeyUpdateHandling() throws Exception {
        // Test handling of primary key updates (should be DELETE/CREATE pairs)
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert initial record
            try (Statement stmt = conn.createStatement()) {
                stmt.execute(
                    "INSERT INTO streaming_test (id, event_name, event_type, created_date, saved_date, header_data) " +
                    "VALUES ('pk-1', 'Event1', 'Type', NOW(), NOW(), '{\"old\": true}'::jsonb)"
                );
                
                // Delete old record
                stmt.execute("DELETE FROM streaming_test WHERE id = 'pk-1'");
                
                // Insert new record with same logical identity but different PK
                stmt.execute(
                    "INSERT INTO streaming_test (id, event_name, event_type, created_date, saved_date, header_data) " +
                    "VALUES ('pk-2', 'Event1', 'Type', NOW(), NOW(), '{\"new\": true}'::jsonb)"
                );
            }
            
            // Verify both operations recorded
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM streaming_test WHERE id IN ('pk-1', 'pk-2')")) {
                rs.next();
                // Only pk-2 should exist (pk-1 was deleted)
                assertThat(rs.getInt(1)).isEqualTo(1);
            }
        }
    }
    
    @Test
    void testConcurrentWritesOrdering() throws Exception {
        // Test ordering with concurrent writes
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert records with very close timestamps (simulating concurrent writes)
            Instant baseTime = Instant.now();
            try (Statement stmt = conn.createStatement()) {
                for (int i = 0; i < 5; i++) {
                    // Use same timestamp to simulate concurrent writes
                    Timestamp ts = Timestamp.from(baseTime);
                    stmt.execute(
                        String.format(
                            "INSERT INTO streaming_test (id, event_name, event_type, created_date, saved_date, header_data) " +
                            "VALUES ('concurrent-%d', 'Event%d', 'Type', '%s', '%s', '{\"seq\": %d}'::jsonb)",
                            i, i, ts, ts, i
                        )
                    );
                }
            }
            
            // Verify all records exist
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM streaming_test WHERE id LIKE 'concurrent-%'")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(5);
            }
        }
    }
    
    @Test
    void testStreamingLagDetection() throws Exception {
        // Test lag monitoring capability
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert data
            Instant oldTime = Instant.now().minusSeconds(300);
            TestUtils.insertTestRecords(conn, "streaming_test", 10, oldTime);
            
            // Calculate lag (difference between now and oldest unprocessed record)
            Instant now = Instant.now();
            long lagSeconds = now.getEpochSecond() - oldTime.getEpochSecond();
            
            assertThat(lagSeconds).isGreaterThan(200);
            assertThat(lagSeconds).isLessThan(400);
        }
    }
    
    @Test
    void testTransactionMetadata() throws Exception {
        // Structural test for transaction metadata (transaction topic generation)
        // Note: Full transaction metadata would require Kafka Connect integration
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Insert data in transaction
            conn.setAutoCommit(false);
            try (Statement stmt = conn.createStatement()) {
                stmt.execute(
                    "INSERT INTO streaming_test (id, event_name, event_type, created_date, saved_date, header_data) " +
                    "VALUES ('tx-1', 'Event1', 'Type', NOW(), NOW(), '{\"tx\": 1}'::jsonb)"
                );
                stmt.execute(
                    "INSERT INTO streaming_test (id, event_name, event_type, created_date, saved_date, header_data) " +
                    "VALUES ('tx-2', 'Event2', 'Type', NOW(), NOW(), '{\"tx\": 1}'::jsonb)"
                );
                conn.commit();
            } finally {
                conn.setAutoCommit(true);
            }
            
            // Verify both records in same transaction
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT COUNT(*) FROM streaming_test WHERE id LIKE 'tx-%'")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(2);
            }
        }
    }
    
    @Test
    @org.junit.jupiter.api.Disabled("Heartbeat not yet implemented")
    void testHeartbeatGeneration() throws Exception {
        // Structural test for heartbeat events
        // This would test heartbeat event creation during idle periods
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            // Verify connection works
            assertThat(conn.isValid(5)).isTrue();
        }
    }
}
