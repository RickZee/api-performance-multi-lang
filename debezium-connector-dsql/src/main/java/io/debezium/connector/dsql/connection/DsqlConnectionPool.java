package io.debezium.connector.dsql.connection;

import io.debezium.connector.dsql.auth.IamTokenGenerator;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

import java.sql.Connection;
import java.sql.Driver;
import java.sql.DriverManager;
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
    private final String region;
    private final int maxPoolSize;
    private final int minIdle;
    private final long connectionTimeoutMs;
    
    private volatile HikariDataSource dataSource;
    private final ReentrantLock poolLock = new ReentrantLock();
    private static final int MAX_RETRY_ATTEMPTS = 3;
    
    /**
     * Get a connection from the pool.
     * 
     * @return SQL Connection
     * @throws SQLException if connection fails
     */
    public Connection getConnection() throws SQLException {
        return getConnectionWithRetry(MAX_RETRY_ATTEMPTS);
    }
    
    /**
     * Get a connection with retry logic to avoid stack overflow from recursive calls.
     * 
     * @param maxAttempts Maximum number of retry attempts
     * @return SQL Connection
     * @throws SQLException if connection fails after all retries
     */
    private Connection getConnectionWithRetry(int maxAttempts) throws SQLException {
        for (int attempt = 0; attempt < maxAttempts; attempt++) {
            try {
                HikariDataSource current = dataSource;
                if (current != null && !current.isClosed()) {
                    try {
                        return current.getConnection();
                    } catch (SQLException e) {
                        if (isRetryableError(e) && attempt < maxAttempts - 1) {
                            LOGGER.warn("Connection error (attempt {}/{}), attempting failover: {}", 
                                       attempt + 1, maxAttempts, e.getMessage());
                            handleConnectionError();
                            continue; // Retry with new connection
                        }
                        throw e;
                    }
                }
                
                // Need to create pool
                return createPoolAndGetConnection();
                
            } catch (SQLException e) {
                if (isRetryableError(e) && attempt < maxAttempts - 1) {
                    LOGGER.warn("Connection error (attempt {}/{}), attempting failover: {}", 
                               attempt + 1, maxAttempts, e.getMessage());
                    handleConnectionError();
                    continue;
                }
                throw e;
            }
        }
        
        throw new SQLException("Failed to get connection after " + maxAttempts + " attempts");
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
            
            LOGGER.info("About to enter driver registration try block");
            try {
                LOGGER.info("Inside driver registration try block - starting driver load");
                // Explicitly load the DSQL connector driver class using the plugin's classloader
                // Kafka Connect's plugin isolation prevents ServiceLoader from finding drivers
                // in the plugin's classpath, so we need to load it explicitly
                LOGGER.info("Attempting to load AWS DSQL JDBC connector driver class using plugin classloader...");
                try {
                    // Use the current thread's context classloader (which should be the plugin classloader)
                    ClassLoader pluginClassLoader = Thread.currentThread().getContextClassLoader();
                    if (pluginClassLoader == null) {
                        pluginClassLoader = this.getClass().getClassLoader();
                    }
                    LOGGER.info("Using classloader: {}", pluginClassLoader.getClass().getName());
                    
                    Class<?> driverClass = Class.forName("software.amazon.dsql.jdbc.DSQLConnector", true, pluginClassLoader);
                    LOGGER.info("DSQL connector driver class loaded successfully: {}", driverClass.getName());
                    
                    java.sql.Driver driver = (java.sql.Driver) driverClass.getDeclaredConstructor().newInstance();
                    LOGGER.info("DSQL connector driver instance created successfully");
                    
                    java.sql.DriverManager.registerDriver(new DriverShim(driver));
                    LOGGER.info("Successfully registered AWS DSQL JDBC connector driver with DriverManager");
                } catch (ClassNotFoundException e) {
                    LOGGER.error("DSQL connector driver class not found: software.amazon.dsql.jdbc.DSQLConnector. " +
                               "Make sure aurora-dsql-jdbc-connector dependency is included in the JAR. Error: {}", e.getMessage(), e);
                    throw new SQLException("DSQL connector driver class not found", e);
                } catch (Exception e) {
                    LOGGER.error("Failed to explicitly register DSQL driver: {}", e.getMessage(), e);
                    throw new SQLException("Failed to register DSQL connector driver", e);
                }
                
                HikariConfig config = new HikariConfig();
                
                // Use AWS DSQL-specific JDBC URL format
                // The connector automatically handles IAM token generation
                config.setJdbcUrl(connectionString);
                
                // Explicitly set driver class to ensure HikariCP uses the DSQL connector
                // This is necessary because Kafka Connect plugin isolation prevents ServiceLoader
                // from finding drivers in the plugin classpath
                config.setDriverClassName("software.amazon.dsql.jdbc.DSQLConnector");
                
                // Set username explicitly (connector uses this for IAM authentication)
                config.setUsername(iamUsername);
                
                config.setMaximumPoolSize(maxPoolSize);
                config.setMinimumIdle(minIdle);
                config.setConnectionTimeout(connectionTimeoutMs);
                config.setIdleTimeout(600000); // 10 minutes
                config.setMaxLifetime(1800000); // 30 minutes (less than token expiration)
                config.setLeakDetectionThreshold(60000); // 1 minute
                config.setPoolName("DSQL-ConnectionPool");
                
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
                              String databaseName, int port, String iamUsername, String region,
                              int maxPoolSize, int minIdle, long connectionTimeoutMs) {
        this.endpoint = endpoint;
        this.tokenGenerator = tokenGenerator;
        this.databaseName = databaseName;
        this.port = port;
        this.iamUsername = iamUsername;
        this.region = region;
        this.maxPoolSize = maxPoolSize;
        this.minIdle = minIdle;
        this.connectionTimeoutMs = connectionTimeoutMs;
    }
    
    /**
     * Build JDBC connection string using AWS DSQL-specific format.
     * 
     * Uses jdbc:aws-dsql:postgresql:// format with IAM username.
     * The AWS DSQL JDBC connector automatically handles IAM token generation.
     * 
     * Matches the approach used in load-test/dsql-load-test-java/DSQLConnection.java
     * Note: No password/token needed - the connector handles IAM auth automatically
     */
    private String buildConnectionString() {
        String currentEndpoint = endpoint.getCurrentEndpoint();
        // AWS DSQL JDBC URL format - connector automatically handles IAM auth
        // token-duration-secs=900 matches 15-minute token validity
        // Matches exactly: load-test/dsql-load-test-java/src/main/java/com/loadtest/dsql/DSQLConnection.java:69
        return String.format("jdbc:aws-dsql:postgresql://%s:%d/%s?user=%s&sslmode=require&token-duration-secs=900",
                           currentEndpoint, port, databaseName, iamUsername);
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
     * Check if error is retryable (connection/timeout/authentication errors).
     */
    private boolean isRetryableError(SQLException e) {
        String errorMessage = e.getMessage().toLowerCase();
        return errorMessage.contains("connection") ||
               errorMessage.contains("timeout") ||
               errorMessage.contains("network") ||
               errorMessage.contains("unable to connect") ||
               errorMessage.contains("connection refused") ||
               errorMessage.contains("connection reset") ||
               errorMessage.contains("authentication") ||
               errorMessage.contains("password");
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
    
    /**
     * Wrapper class to register a JDBC driver that doesn't implement DriverManager registration.
     * This is needed for Kafka Connect plugin isolation where ServiceLoader doesn't work.
     */
    private static class DriverShim implements Driver {
        private final Driver driver;
        
        DriverShim(Driver driver) {
            this.driver = driver;
        }
        
        @Override
        public Connection connect(String url, java.util.Properties info) throws SQLException {
            return driver.connect(url, info);
        }
        
        @Override
        public boolean acceptsURL(String url) throws SQLException {
            return driver.acceptsURL(url);
        }
        
        @Override
        public java.sql.DriverPropertyInfo[] getPropertyInfo(String url, java.util.Properties info) throws SQLException {
            return driver.getPropertyInfo(url, info);
        }
        
        @Override
        public int getMajorVersion() {
            return driver.getMajorVersion();
        }
        
        @Override
        public int getMinorVersion() {
            return driver.getMinorVersion();
        }
        
        @Override
        public boolean jdbcCompliant() {
            return driver.jdbcCompliant();
        }
        
        @Override
        public java.util.logging.Logger getParentLogger() throws java.sql.SQLFeatureNotSupportedException {
            return driver.getParentLogger();
        }
    }
}
