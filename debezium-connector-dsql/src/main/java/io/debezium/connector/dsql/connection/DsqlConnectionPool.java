package io.debezium.connector.dsql.connection;

import io.debezium.connector.dsql.auth.IamTokenGenerator;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

import java.sql.Connection;
import java.sql.SQLException;
import java.util.concurrent.locks.ReentrantLock;

/**
 * Connection pool manager for DSQL using HikariCP.
 * 
 * Integrates with IAM token generation and multi-region endpoint management
 * for automatic failover and token refresh.
 */
public class DsqlConnectionPool {
    private static final Logger LOGGER = LoggerFactory.getLogger(DsqlConnectionPool.class);
    
    private final MultiRegionEndpoint endpoint;
    private final IamTokenGenerator tokenGenerator;
    private final String databaseName;
    private final int port;
    private final String iamUsername;
    private final int maxPoolSize;
    private final int minIdle;
    private final long connectionTimeoutMs;
    
    private volatile HikariDataSource dataSource;
    private final ReentrantLock poolLock = new ReentrantLock();
    
    /**
     * Get a connection from the pool.
     * 
     * @return SQL Connection
     * @throws SQLException if connection fails
     */
    public Connection getConnection() throws SQLException {
        HikariDataSource current = dataSource;
        if (current != null && !current.isClosed()) {
            try {
                return current.getConnection();
            } catch (SQLException e) {
                if (isRetryableError(e)) {
                    LOGGER.warn("Connection error, attempting failover: {}", e.getMessage());
                    handleConnectionError();
                    // Retry with new connection
                    return getConnection();
                }
                throw e;
            }
        }
        
        // Need to create pool
        return createPoolAndGetConnection();
    }
    
    /**
     * Create the connection pool and get a connection.
     */
    private Connection createPoolAndGetConnection() throws SQLException {
        poolLock.lock();
        try {
            // Double-check after acquiring lock
            if (dataSource != null && !dataSource.isClosed()) {
                return dataSource.getConnection();
            }
            
            String connectionString = buildConnectionString();
            LOGGER.info("Creating HikariCP connection pool for DSQL endpoint: {}", endpoint.getCurrentEndpoint());
            
            // For DSQL VPC endpoints, we need to disable SSL hostname verification
            // because the SNI must match the cluster identifier format, not the VPC endpoint DNS
            // Save current system properties and set SSL properties
            String originalHostnameVerifier = System.getProperty("com.sun.net.ssl.checkRevocation");
            System.setProperty("jdk.tls.client.protocols", "TLSv1.2");
            
            try {
                HikariConfig config = new HikariConfig();
                config.setJdbcUrl(connectionString);
                config.setMaximumPoolSize(maxPoolSize);
                config.setMinimumIdle(minIdle);
                config.setConnectionTimeout(connectionTimeoutMs);
                config.setIdleTimeout(600000); // 10 minutes
                config.setMaxLifetime(1800000); // 30 minutes
                config.setLeakDetectionThreshold(60000); // 1 minute
                config.setPoolName("DSQL-ConnectionPool");
                
                // PostgreSQL-specific settings
                config.addDataSourceProperty("cachePrepStmts", "true");
                config.addDataSourceProperty("prepStmtCacheSize", "250");
                config.addDataSourceProperty("prepStmtCacheSqlLimit", "2048");
                
                // DSQL SSL settings - require SSL but allow any hostname for VPC endpoints
                config.addDataSourceProperty("ssl", "true");
                config.addDataSourceProperty("sslmode", "require");
                // Disable hostname verification for VPC endpoint SNI compatibility
                config.addDataSourceProperty("sslfactory", "org.postgresql.ssl.DefaultJavaSSLFactory");
                
                dataSource = new HikariDataSource(config);
                
                LOGGER.info("HikariCP connection pool created successfully");
                return dataSource.getConnection();
            } finally {
                // Restore original system properties if needed
                if (originalHostnameVerifier != null) {
                    System.setProperty("com.sun.net.ssl.checkRevocation", originalHostnameVerifier);
                }
            }
        } finally {
            poolLock.unlock();
        }
    }
    
    public DsqlConnectionPool(MultiRegionEndpoint endpoint, IamTokenGenerator tokenGenerator,
                              String databaseName, int port, String iamUsername, int maxPoolSize, int minIdle,
                              long connectionTimeoutMs) {
        this.endpoint = endpoint;
        this.tokenGenerator = tokenGenerator;
        this.databaseName = databaseName;
        this.port = port;
        this.iamUsername = iamUsername;
        this.maxPoolSize = maxPoolSize;
        this.minIdle = minIdle;
        this.connectionTimeoutMs = connectionTimeoutMs;
    }
    
    /**
     * Build JDBC connection string with IAM token.
     * 
     * For DSQL VPC endpoints, we connect to the VPC endpoint hostname
     * but the SNI (Server Name Indication) in SSL handshake must match
     * what DSQL expects. SSL parameters are configured via HikariCP properties.
     */
    private String buildConnectionString() {
        String token = tokenGenerator.getToken();
        String currentEndpoint = endpoint.getCurrentEndpoint();
        // Basic connection string - SSL is configured via HikariCP data source properties
        // The connection will use SSL but hostname verification is handled separately
        return String.format("jdbc:postgresql://%s:%d/%s?user=%s&password=%s&sslmode=require",
                           currentEndpoint, port, databaseName, iamUsername, token);
    }
    
    /**
     * Handle connection errors with failover logic.
     */
    private void handleConnectionError() {
        poolLock.lock();
        try {
            // Close existing pool
            if (dataSource != null) {
                try {
                    dataSource.close();
                } catch (Exception e) {
                    LOGGER.warn("Error closing connection pool: {}", e.getMessage());
                }
                dataSource = null;
            }
            
            // Attempt failover
            if (endpoint.isUsingPrimary()) {
                endpoint.failover();
            } else {
                // Already on secondary, try to failback
                String connectionString = buildConnectionString();
                endpoint.attemptFailback(connectionString);
            }
        } finally {
            poolLock.unlock();
        }
    }
    
    /**
     * Check if error is retryable (connection/timeout errors).
     */
    private boolean isRetryableError(SQLException e) {
        String errorMessage = e.getMessage().toLowerCase();
        return errorMessage.contains("connection") ||
               errorMessage.contains("timeout") ||
               errorMessage.contains("network") ||
               errorMessage.contains("unable to connect") ||
               errorMessage.contains("connection refused") ||
               errorMessage.contains("connection reset");
    }
    
    /**
     * Invalidate and recreate the connection pool.
     */
    public void invalidate() {
        poolLock.lock();
        try {
            LOGGER.warn("Invalidating connection pool");
            if (dataSource != null) {
                try {
                    dataSource.close();
                } catch (Exception e) {
                    LOGGER.warn("Error closing connection pool during invalidation: {}", e.getMessage());
                }
                dataSource = null;
            }
        } finally {
            poolLock.unlock();
        }
    }
    
    /**
     * Close the connection pool.
     */
    public void close() {
        poolLock.lock();
        try {
            LOGGER.info("Closing connection pool");
            if (dataSource != null) {
                try {
                    dataSource.close();
                } catch (Exception e) {
                    LOGGER.warn("Error closing connection pool: {}", e.getMessage());
                }
                dataSource = null;
            }
        } finally {
            poolLock.unlock();
        }
    }
}
