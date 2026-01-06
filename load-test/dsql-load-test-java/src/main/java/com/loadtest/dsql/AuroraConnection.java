package com.loadtest.dsql;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import com.zaxxer.hikari.HikariPoolMXBean;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;
import java.sql.SQLException;

/**
 * Aurora PostgreSQL connection manager using HikariCP connection pool with standard PostgreSQL JDBC driver.
 * 
 * Uses standard PostgreSQL JDBC driver with username/password authentication.
 * 
 * Optimized for load testing with configurable connection pool sizing.
 */
public class AuroraConnection implements DatabaseConnection {
    private static final Logger LOGGER = LoggerFactory.getLogger(AuroraConnection.class);
    
    // Aurora connection limits - typically lower than DSQL
    // Note: Aurora instance connection limits vary by instance class (e.g., db.t3.small ~40 connections)
    // For load testing, we'll use a more conservative limit
    private static final int ABSOLUTE_MAX_POOL_SIZE = 1000;
    // Aurora may need more retries than DSQL due to connection limits
    private static final int DEFAULT_MAX_RETRIES = 3;
    private static final long DEFAULT_RETRY_DELAY_MS = 100; // 100ms delay for Aurora
    
    private final String auroraHost;
    private final int port;
    private final String databaseName;
    private final String username;
    private final String password;
    private final boolean requireSsl;
    private final int maxPoolSize;
    private final int maxRetries;
    private final long retryDelayMs;
    private HikariDataSource dataSource;
    
    public AuroraConnection(String auroraHost, int port, String databaseName, 
                            String username, String password) {
        this(auroraHost, port, databaseName, username, password, true, 5);
    }
    
    public AuroraConnection(String auroraHost, int port, String databaseName,
                           String username, String password, int threadCount) {
        this(auroraHost, port, databaseName, username, password, true, threadCount);
    }
    
    public AuroraConnection(String auroraHost, int port, String databaseName,
                           String username, String password, boolean requireSsl, int threadCount) {
        this.auroraHost = auroraHost;
        this.port = port;
        this.databaseName = databaseName;
        this.username = username;
        this.password = password;
        this.requireSsl = requireSsl;
        
        // Parse retry configuration from environment
        this.maxRetries = parseEnvInt("CONNECTION_MAX_RETRIES", DEFAULT_MAX_RETRIES);
        this.retryDelayMs = parseEnvLong("CONNECTION_RETRY_DELAY_MS", DEFAULT_RETRY_DELAY_MS);
        
        // Enhanced pool sizing for Aurora
        // Aurora has lower connection limits, so be more conservative
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
        // Aurora has lower connection limits, so use more conservative pool sizing
        // Each connection can handle multiple requests sequentially
        if (threadCount >= 1000) {
            // High concurrency: pool size = threads / 5 (more conservative than DSQL)
            return Math.min(threadCount / 5, ABSOLUTE_MAX_POOL_SIZE);
        } else if (threadCount >= 500) {
            // Medium concurrency: pool size = threads / 3
            return Math.min(threadCount / 3, ABSOLUTE_MAX_POOL_SIZE);
        } else if (threadCount >= 100) {
            // Normal: pool size = threads / 2
            return Math.min(threadCount / 2, ABSOLUTE_MAX_POOL_SIZE);
        } else {
            // Low concurrency: match thread count up to 50
            return Math.min(Math.max(threadCount, 5), 50);
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
     */
    @Override
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
                    long delay = retryDelayMs * (attempt + 1); // Exponential backoff
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
    @Override
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
                long delay = retryDelayMs * (attempt + 1); // Exponential backoff
                LOGGER.debug("Connection attempt {} failed, retrying in {}ms", attempt, delay);
                try {
                    Thread.sleep(Math.min(delay, timeoutMs - (System.currentTimeMillis() - startTime)));
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
            
            // Use standard PostgreSQL JDBC driver with username/password authentication
            String sslMode = requireSsl ? "require" : "disable";
            String jdbcUrl = String.format("jdbc:postgresql://%s:%d/%s?sslmode=%s",
                                           auroraHost, port, databaseName, sslMode);
            config.setJdbcUrl(jdbcUrl);
            config.setDriverClassName("org.postgresql.Driver");
            config.setUsername(username);
            config.setPassword(password);
            
            // Pool settings - optimized for Aurora (more conservative than DSQL)
            config.setMaximumPoolSize(maxPoolSize);
            
            // Pre-warm connections: use a fraction of max to avoid overwhelming Aurora on startup
            int minIdle = maxPoolSize >= 100 ? Math.min(maxPoolSize / 4, 50) : 
                          maxPoolSize >= 50 ? Math.min(maxPoolSize / 2, 25) : 
                          Math.min(maxPoolSize / 2, 5);
            config.setMinimumIdle(minIdle);
            
            // Aurora connection timeouts - allow more time than DSQL
            int connectionTimeout = maxPoolSize >= 100 ? 15000 : 
                                   maxPoolSize >= 50 ? 10000 : 5000;
            config.setConnectionTimeout(connectionTimeout); // 5-15 seconds for Aurora
            config.setIdleTimeout(600000); // 10 minutes
            config.setMaxLifetime(1800000); // 30 minutes
            config.setLeakDetectionThreshold(120000); // 2 minutes
            config.setPoolName("Aurora-LoadTest-Pool");
            
            // Enable keepalive to maintain connections during high-latency periods
            config.setKeepaliveTime(60000); // 1 minute keepalive
            
            // Connection validation
            config.setConnectionTestQuery("SELECT 1");
            config.setValidationTimeout(5000); // 5 seconds
            config.setRegisterMbeans(true); // Enable monitoring via JMX
            
            // PostgreSQL-specific settings
            config.addDataSourceProperty("cachePrepStmts", "true");
            config.addDataSourceProperty("prepStmtCacheSize", "250");
            config.addDataSourceProperty("prepStmtCacheSqlLimit", "2048");
            
            // SSL settings (optional for local connections)
            if (requireSsl) {
                config.addDataSourceProperty("ssl", "true");
                config.addDataSourceProperty("sslfactory", "org.postgresql.ssl.DefaultJavaSSLFactory");
            }
            
            // Set search path
            config.setConnectionInitSql("SET search_path TO car_entities_schema");
            
            dataSource = new HikariDataSource(config);
            LOGGER.info("Created Aurora connection pool for {} (pool size: {})", 
                       auroraHost, maxPoolSize);
        } finally {
            // Restore original system properties
            if (originalHostnameVerifier != null) {
                System.setProperty("com.sun.net.ssl.checkRevocation", originalHostnameVerifier);
            }
        }
    }
    
    @Override
    public void close() {
        if (dataSource != null && !dataSource.isClosed()) {
            dataSource.close();
        }
    }
    
    /**
     * Get connection pool metrics for monitoring.
     */
    @Override
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
}

