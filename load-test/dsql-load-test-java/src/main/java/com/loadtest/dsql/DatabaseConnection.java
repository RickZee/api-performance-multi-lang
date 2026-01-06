package com.loadtest.dsql;

import java.sql.Connection;
import java.sql.SQLException;

/**
 * Common interface for database connections (DSQL and Aurora).
 * Allows polymorphic handling of different database types.
 */
public interface DatabaseConnection {
    /**
     * Get a connection from the pool.
     * @return A database connection
     * @throws SQLException if connection fails
     */
    Connection getConnection() throws SQLException;
    
    /**
     * Get a connection with a custom timeout.
     * @param timeoutMs Maximum time to wait for a connection
     * @return A database connection
     * @throws SQLException if connection fails or times out
     */
    Connection getConnection(long timeoutMs) throws SQLException;
    
    /**
     * Close the connection pool and release resources.
     */
    void close();
    
    /**
     * Get connection pool metrics for monitoring.
     * @return Pool metrics
     */
    DatabaseConnection.PoolMetrics getPoolMetrics();
    
    /**
     * Connection pool metrics.
     */
    class PoolMetrics {
        public final int activeConnections;
        public final int idleConnections;
        public final int threadsAwaitingConnection;
        public final int totalConnections;
        public final int maxPoolSize;
        
        public PoolMetrics(int activeConnections, int idleConnections, 
                          int threadsAwaitingConnection, int totalConnections, int maxPoolSize) {
            this.activeConnections = activeConnections;
            this.idleConnections = idleConnections;
            this.threadsAwaitingConnection = threadsAwaitingConnection;
            this.totalConnections = totalConnections;
            this.maxPoolSize = maxPoolSize;
        }
        
        @Override
        public String toString() {
            return String.format("Pool[active=%d, idle=%d, waiting=%d, total=%d, max=%d]",
                               activeConnections, idleConnections, threadsAwaitingConnection,
                               totalConnections, maxPoolSize);
        }
    }
}

