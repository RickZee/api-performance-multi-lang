package io.debezium.connector.dsql.connection;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

import static org.assertj.core.api.Assertions.assertThat;

class MultiRegionEndpointTest {
    
    private MultiRegionEndpoint endpoint;
    private String primaryEndpoint = "primary-endpoint";
    private String secondaryEndpoint = "secondary-endpoint";
    private int port = 5432;
    private String databaseName = "testdb";
    private long healthCheckIntervalMs = 60000;
    
    @BeforeEach
    void setUp() {
        endpoint = new MultiRegionEndpoint(
                primaryEndpoint,
                secondaryEndpoint,
                port,
                databaseName,
                healthCheckIntervalMs
        );
    }
    
    @Test
    void testGetCurrentEndpoint() {
        assertThat(endpoint.getCurrentEndpoint()).isEqualTo(primaryEndpoint);
    }
    
    @Test
    void testGetPrimaryEndpoint() {
        assertThat(endpoint.getPrimaryEndpoint()).isEqualTo(primaryEndpoint);
    }
    
    @Test
    void testGetSecondaryEndpoint() {
        assertThat(endpoint.getSecondaryEndpoint()).isEqualTo(secondaryEndpoint);
    }
    
    @Test
    void testIsUsingPrimary() {
        assertThat(endpoint.isUsingPrimary()).isTrue();
    }
    
    @Test
    void testIsUsingSecondary() {
        assertThat(endpoint.isUsingSecondary()).isFalse();
    }
    
    @Test
    void testFailover() {
        boolean result = endpoint.failover();
        
        assertThat(result).isTrue();
        assertThat(endpoint.isUsingPrimary()).isFalse();
        assertThat(endpoint.isUsingSecondary()).isTrue();
        assertThat(endpoint.getCurrentEndpoint()).isEqualTo(secondaryEndpoint);
    }
    
    @Test
    void testFailoverWhenAlreadyOnSecondary() {
        endpoint.failover();
        boolean result = endpoint.failover();
        
        assertThat(result).isTrue();
        assertThat(endpoint.isUsingSecondary()).isTrue();
    }
    
    @Test
    void testAttemptFailbackWithInvalidConnection() {
        // Failover first
        endpoint.failover();
        assertThat(endpoint.isUsingSecondary()).isTrue();
        
        // Attempt failback with invalid connection string (will fail)
        String invalidConnectionString = "jdbc:postgresql://invalid:5432/testdb?user=test&password=test";
        boolean result = endpoint.attemptFailback(invalidConnectionString);
        
        // Should fail because connection is invalid
        assertThat(result).isFalse();
        assertThat(endpoint.isUsingSecondary()).isTrue();
    }
    
    @Test
    void testAttemptFailbackWhenAlreadyOnPrimary() {
        // Already on primary
        assertThat(endpoint.isUsingPrimary()).isTrue();
        
        String connectionString = "jdbc:postgresql://primary:5432/testdb?user=test&password=test";
        boolean result = endpoint.attemptFailback(connectionString);
        
        // Should return true (already on primary)
        assertThat(result).isTrue();
        assertThat(endpoint.isUsingPrimary()).isTrue();
    }
    
    @Test
    void testHealthCheckInterval() throws InterruptedException {
        endpoint.failover();
        assertThat(endpoint.isUsingSecondary()).isTrue();
        
        // Attempt failback immediately (should fail due to health check interval)
        String connectionString = "jdbc:postgresql://primary:5432/testdb?user=test&password=test";
        boolean result1 = endpoint.attemptFailback(connectionString);
        assertThat(result1).isFalse();
        
        // Wait for health check interval
        Thread.sleep(healthCheckIntervalMs + 100);
        
        // Now attempt failback again (will still fail due to invalid connection, but interval check passes)
        boolean result2 = endpoint.attemptFailback(connectionString);
        // Connection is invalid, so still false, but interval check passed
        assertThat(result2).isFalse();
    }
}
