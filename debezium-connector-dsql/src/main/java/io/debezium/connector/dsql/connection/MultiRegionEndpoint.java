package io.debezium.connector.dsql.connection;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.locks.ReentrantLock;

/**
 * Manages multi-region endpoint failover for DSQL connections.
 * 
 * Maintains primary and secondary endpoints with automatic failover
 * on connection errors. Implements health checks with configurable intervals.
 */
public class MultiRegionEndpoint {
    private static final Logger LOGGER = LoggerFactory.getLogger(MultiRegionEndpoint.class);
    
    private final String primaryEndpoint;
    private final String secondaryEndpoint;
    private final int port;
    private final String databaseName;
    private final long healthCheckIntervalMs;
    
    private final AtomicReference<EndpointState> currentEndpoint = new AtomicReference<>(EndpointState.PRIMARY);
    private final ReentrantLock failoverLock = new ReentrantLock();
    private volatile long lastHealthCheckTime = 0;
    
    private enum EndpointState {
        PRIMARY,
        SECONDARY
    }
    
    public MultiRegionEndpoint(String primaryEndpoint, String secondaryEndpoint, 
                               int port, String databaseName, long healthCheckIntervalMs) {
        this.primaryEndpoint = primaryEndpoint;
        this.secondaryEndpoint = secondaryEndpoint;
        this.port = port;
        this.databaseName = databaseName;
        this.healthCheckIntervalMs = healthCheckIntervalMs;
    }
    
    /**
     * Get the current active endpoint.
     */
    public String getCurrentEndpoint() {
        return currentEndpoint.get() == EndpointState.PRIMARY ? primaryEndpoint : secondaryEndpoint;
    }
    
    /**
     * Get the primary endpoint.
     */
    public String getPrimaryEndpoint() {
        return primaryEndpoint;
    }
    
    /**
     * Get the secondary endpoint.
     */
    public String getSecondaryEndpoint() {
        return secondaryEndpoint;
    }
    
    /**
     * Attempt to failover to the secondary endpoint.
     * 
     * @return true if failover was successful, false otherwise
     */
    public boolean failover() {
        failoverLock.lock();
        try {
            EndpointState current = currentEndpoint.get();
            if (current == EndpointState.SECONDARY) {
                LOGGER.debug("Already using secondary endpoint");
                return true;
            }
            
            LOGGER.warn("Failing over from primary endpoint {} to secondary endpoint {}", 
                       primaryEndpoint, secondaryEndpoint);
            
            currentEndpoint.set(EndpointState.SECONDARY);
            lastHealthCheckTime = System.currentTimeMillis();
            return true;
        } finally {
            failoverLock.unlock();
        }
    }
    
    /**
     * Attempt to failback to the primary endpoint if health check passes.
     * 
     * @param connectionString Connection string builder for testing connectivity
     * @return true if failback was successful, false otherwise
     */
    public boolean attemptFailback(String connectionString) {
        failoverLock.lock();
        try {
            EndpointState current = currentEndpoint.get();
            if (current == EndpointState.PRIMARY) {
                return true; // Already on primary
            }
            
            // Check if enough time has passed since last health check
            long now = System.currentTimeMillis();
            if (now - lastHealthCheckTime < healthCheckIntervalMs) {
                return false; // Too soon for health check
            }
            
            // Test primary endpoint connectivity
            try (Connection testConn = DriverManager.getConnection(connectionString)) {
                if (testConn.isValid(5)) { // 5 second timeout
                    LOGGER.info("Primary endpoint {} is healthy, failing back", primaryEndpoint);
                    currentEndpoint.set(EndpointState.PRIMARY);
                    lastHealthCheckTime = now;
                    return true;
                }
            } catch (SQLException e) {
                LOGGER.debug("Primary endpoint {} still unavailable: {}", primaryEndpoint, e.getMessage());
            }
            
            lastHealthCheckTime = now;
            return false;
        } finally {
            failoverLock.unlock();
        }
    }
    
    /**
     * Check if currently using primary endpoint.
     */
    public boolean isUsingPrimary() {
        return currentEndpoint.get() == EndpointState.PRIMARY;
    }
    
    /**
     * Check if currently using secondary endpoint.
     */
    public boolean isUsingSecondary() {
        return currentEndpoint.get() == EndpointState.SECONDARY;
    }
}
