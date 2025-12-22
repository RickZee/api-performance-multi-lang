package com.loadtest.dsql;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import com.zaxxer.hikari.HikariPoolMXBean;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;
import java.sql.SQLException;

/**
 * DSQL connection manager using HikariCP connection pool with AWS DSQL JDBC connector.
 * 
 * Uses the AWS DSQL JDBC connector which automatically handles IAM token generation,
 * eliminating the need for manual SigV4 signing.
 * 
 * Optimized for extreme scaling tests with up to 5000+ concurrent threads.
 */
public class DSQLConnection {
    private static final Logger LOGGER = LoggerFactory.getLogger(DSQLConnection.class);
    
    // DSQL connection limits - increase for extreme scaling
    // Note: DSQL supports up to 5000 connections per cluster endpoint
    private static final int ABSOLUTE_MAX_POOL_SIZE = 2000;
    private static final int DEFAULT_MAX_RETRIES = 3;
    private static final long DEFAULT_RETRY_DELAY_MS = 500;
    
    private final String dsqlHost;
    private final int port;
    private final String databaseName;
    private final String iamUsername;
    private final String region;
    private final int maxPoolSize;
    private final int maxRetries;
    private final long retryDelayMs;
    private HikariDataSource dataSource;
    
    public DSQLConnection(String dsqlHost, int port, String databaseName, 
                         String iamUsername, String region) {
        this(dsqlHost, port, databaseName, iamUsername, region, 5);
    }
    
    public DSQLConnection(String dsqlHost, int port, String databaseName, 
                         String iamUsername, String region, int threadCount) {
        this.dsqlHost = dsqlHost;
        this.port = port;
        this.databaseName = databaseName;
        this.iamUsername = iamUsername;
        this.region = region;
        
        // Parse retry configuration from environment
        this.maxRetries = parseEnvInt("CONNECTION_MAX_RETRIES", DEFAULT_MAX_RETRIES);
        this.retryDelayMs = parseEnvLong("CONNECTION_RETRY_DELAY_MS", DEFAULT_RETRY_DELAY_MS);
        
        // Enhanced pool sizing for extreme scaling
        // Support up to ABSOLUTE_MAX_POOL_SIZE connections
        String maxPoolSizeEnv = System.getenv("MAX_POOL_SIZE");
        int calculatedPoolSize;
        if (maxPoolSizeEnv != null && !maxPoolSizeEnv.isEmpty()) {
            try {
                calculatedPoolSize = Math.min(Integer.parseInt(maxPoolSizeEnv), ABSOLUTE_MAX_POOL_SIZE);
            } catch (NumberFormatException e) {
                LOGGER.warn("Invalid MAX_POOL_SIZE environment variable: {}, using calculated value", maxPoolSizeEnv);
                calculatedPoolSize = calculatePoolSize(threadCount);
            }
        } else {
            calculatedPoolSize = calculatePoolSize(threadCount);
        }
        this.maxPoolSize = calculatedPoolSize;
        LOGGER.info("Pool size configured: {} (threads: {}, max: {})", maxPoolSize, threadCount, ABSOLUTE_MAX_POOL_SIZE);
    }
    
    private int calculatePoolSize(int threadCount) {
        // For extreme scaling (1000+ threads), use aggressive pool sizing
        // Each connection can handle multiple requests sequentially
        // Goal: minimize connection wait time while not exceeding DSQL limits
        if (threadCount >= 2000) {
            // Extreme scaling: pool size = threads / 3, capped at ABSOLUTE_MAX_POOL_SIZE
            return Math.min(threadCount / 3, ABSOLUTE_MAX_POOL_SIZE);
        } else if (threadCount >= 500) {
            // High concurrency: pool size = threads / 2
            return Math.min(threadCount / 2, ABSOLUTE_MAX_POOL_SIZE);
        } else {
            // Normal: match thread count up to 200, then grow slower
            return Math.min(Math.max(threadCount, 10), 200);
        }
    }
    
    private int parseEnvInt(String name, int defaultValue) {
        String value = System.getenv(name);
        if (value != null && !value.isEmpty()) {
            try {
                return Integer.parseInt(value);
            } catch (NumberFormatException e) {
                LOGGER.warn("Invalid {} environment variable: {}", name, value);
            }
        }
        return defaultValue;
    }
    
    private long parseEnvLong(String name, long defaultValue) {
        String value = System.getenv(name);
        if (value != null && !value.isEmpty()) {
            try {
                return Long.parseLong(value);
            } catch (NumberFormatException e) {
                LOGGER.warn("Invalid {} environment variable: {}", name, value);
            }
        }
        return defaultValue;
    }
    
    /**
     * Get a connection from the pool with retry logic for high concurrency scenarios.
     * Uses exponential backoff to handle connection pool contention.
     */
    public Connection getConnection() throws SQLException {
        if (dataSource == null || dataSource.isClosed()) {
            synchronized (this) {
                if (dataSource == null || dataSource.isClosed()) {
                    createConnectionPool();
                }
            }
        }
        
        SQLException lastException = null;
        for (int attempt = 0; attempt <= maxRetries; attempt++) {
            try {
                return dataSource.getConnection();
            } catch (SQLException e) {
                lastException = e;
                if (attempt < maxRetries) {
                    // Exponential backoff with jitter
                    long delay = retryDelayMs * (1L << attempt) + (long)(Math.random() * 100);
                    LOGGER.debug("Connection attempt {} failed, retrying in {}ms: {}", 
                                attempt + 1, delay, e.getMessage());
                    try {
                        Thread.sleep(delay);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        throw e;
                    }
                }
            }
        }
        
        LOGGER.warn("All {} connection attempts failed: {}", maxRetries + 1, 
                   lastException != null ? lastException.getMessage() : "unknown error");
        throw lastException != null ? lastException : new SQLException("Failed to get connection");
    }
    
    /**
     * Get a connection with a custom timeout (useful for extreme scaling scenarios).
     * @param timeoutMs Maximum time to wait for a connection
     */
    public Connection getConnection(long timeoutMs) throws SQLException {
        if (dataSource == null || dataSource.isClosed()) {
            synchronized (this) {
                if (dataSource == null || dataSource.isClosed()) {
                    createConnectionPool();
                }
            }
        }
        
        long startTime = System.currentTimeMillis();
        SQLException lastException = null;
        int attempt = 0;
        
        while (System.currentTimeMillis() - startTime < timeoutMs) {
            try {
                return dataSource.getConnection();
            } catch (SQLException e) {
                lastException = e;
                attempt++;
                // Exponential backoff with jitter, capped at 2 seconds
                long delay = Math.min(retryDelayMs * (1L << Math.min(attempt, 4)) + (long)(Math.random() * 100), 2000);
                LOGGER.debug("Connection attempt {} failed, retrying in {}ms", attempt, delay);
                try {
                    Thread.sleep(delay);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw e;
                }
            }
        }
        
        LOGGER.warn("Connection timeout after {}ms ({} attempts): {}", 
                   System.currentTimeMillis() - startTime, attempt,
                   lastException != null ? lastException.getMessage() : "unknown error");
        throw lastException != null ? lastException : new SQLException("Connection timeout");
    }
    
    private void createConnectionPool() throws SQLException {
        if (dataSource != null && !dataSource.isClosed()) {
            dataSource.close();
        }
        
        // Set TLS protocol
        String originalHostnameVerifier = System.getProperty("com.sun.net.ssl.checkRevocation");
        System.setProperty("jdk.tls.client.protocols", "TLSv1.2");
        
        try {
            HikariConfig config = new HikariConfig();
            
            // Use AWS DSQL JDBC connector - automatically handles IAM token generation
            // Key: Use DSQL wrapper prefix (jdbc:aws-dsql:postgresql://) to trigger IAM auto-auth
            // The connector wraps PostgreSQL driver and handles SigV4 token generation automatically
            String jdbcUrl = String.format("jdbc:aws-dsql:postgresql://%s:%d/%s?user=%s&sslmode=require&token-duration-secs=900",
                                           dsqlHost, port, databaseName, iamUsername);
            config.setJdbcUrl(jdbcUrl);
            
            // Don't set driver class - let ServiceLoader mechanism find the connector driver
            // The connector registers itself via META-INF/services/java.sql.Driver
            config.setUsername(iamUsername); // Explicit for clarity
            
            // Pool settings - optimized for extreme scaling (up to 5000+ threads)
            config.setMaximumPoolSize(maxPoolSize);
            
            // Pre-warm connections: use a fraction of max to avoid overwhelming DSQL on startup
            int minIdle = maxPoolSize >= 500 ? Math.min(maxPoolSize / 4, 200) : 
                          maxPoolSize >= 100 ? Math.min(maxPoolSize / 2, 50) : 
                          Math.min(maxPoolSize / 2, 5);
            config.setMinimumIdle(minIdle);
            
            // Extended timeout for extreme concurrency - threads may wait longer
            // Use 120 seconds to give threads more chances to get connections
            config.setConnectionTimeout(120000); // 120 seconds for extreme concurrency
            config.setIdleTimeout(600000); // 10 minutes
            config.setMaxLifetime(1800000); // 30 minutes - IAM tokens valid for 15 mins
            config.setLeakDetectionThreshold(120000); // 2 minutes for extreme tests
            config.setPoolName("DSQL-LoadTest-Pool");
            
            // Enable keepalive to maintain connections during high-latency periods
            config.setKeepaliveTime(60000); // 1 minute keepalive
            
            // Connection validation
            config.setConnectionTestQuery("SELECT 1");
            config.setValidationTimeout(5000); // 5 seconds
            config.setRegisterMbeans(true); // Enable monitoring via JMX
            
            // AWS DSQL connector configuration
            // Connector automatically uses DefaultCredentialsProvider from EC2 instance profile
            config.addDataSourceProperty("region", region);
            
            // PostgreSQL-specific settings
            config.addDataSourceProperty("cachePrepStmts", "true");
            config.addDataSourceProperty("prepStmtCacheSize", "250");
            config.addDataSourceProperty("prepStmtCacheSqlLimit", "2048");
            
            // DSQL SSL settings (required for DSQL)
            config.addDataSourceProperty("ssl", "true");
            config.addDataSourceProperty("sslfactory", "org.postgresql.ssl.DefaultJavaSSLFactory");
            
            // Set search path
            config.setConnectionInitSql("SET search_path TO car_entities_schema");
            
            dataSource = new HikariDataSource(config);
            LOGGER.info("Created DSQL connection pool using AWS DSQL JDBC connector for {} (pool size: {})", 
                       dsqlHost, maxPoolSize);
        } finally {
            // Restore original system properties
            if (originalHostnameVerifier != null) {
                System.setProperty("com.sun.net.ssl.checkRevocation", originalHostnameVerifier);
            }
        }
    }
    
    public void close() {
        if (dataSource != null && !dataSource.isClosed()) {
            dataSource.close();
        }
    }
    
    /**
     * Get connection pool metrics for monitoring.
     */
    public PoolMetrics getPoolMetrics() {
        if (dataSource == null || dataSource.isClosed()) {
            return new PoolMetrics(0, 0, 0, 0, 0);
        }
        
        HikariPoolMXBean poolBean = dataSource.getHikariPoolMXBean();
        if (poolBean == null) {
            return new PoolMetrics(0, 0, 0, 0, 0);
        }
        
        return new PoolMetrics(
            poolBean.getActiveConnections(),
            poolBean.getIdleConnections(),
            poolBean.getThreadsAwaitingConnection(),
            poolBean.getTotalConnections(),
            maxPoolSize
        );
    }
    
    /**
     * Connection pool metrics.
     */
    public static class PoolMetrics {
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

