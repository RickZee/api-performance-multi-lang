package com.loadtest.dsql;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;
import java.sql.SQLException;

/**
 * DSQL connection manager using HikariCP connection pool with AWS DSQL JDBC connector.
 * 
 * Uses the AWS DSQL JDBC connector which automatically handles IAM token generation,
 * eliminating the need for manual SigV4 signing.
 */
public class DSQLConnection {
    private static final Logger LOGGER = LoggerFactory.getLogger(DSQLConnection.class);
    
    private final String dsqlHost;
    private final int port;
    private final String databaseName;
    private final String iamUsername;
    private final String region;
    private HikariDataSource dataSource;
    
    public DSQLConnection(String dsqlHost, int port, String databaseName, 
                         String iamUsername, String region) {
        this.dsqlHost = dsqlHost;
        this.port = port;
        this.databaseName = databaseName;
        this.iamUsername = iamUsername;
        this.region = region;
    }
    
    /**
     * Get a connection from the pool.
     */
    public Connection getConnection() throws SQLException {
        if (dataSource == null || dataSource.isClosed()) {
            createConnectionPool();
        }
        
        try {
            return dataSource.getConnection();
        } catch (SQLException e) {
            // If connection fails, try recreating pool
            LOGGER.warn("Connection failed, recreating pool: {}", e.getMessage());
            createConnectionPool();
            return dataSource.getConnection();
        }
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
            
            // Pool settings
            config.setMaximumPoolSize(5);
            config.setMinimumIdle(1);
            config.setConnectionTimeout(30000); // 30 seconds
            config.setIdleTimeout(600000); // 10 minutes
            config.setMaxLifetime(1800000); // 30 minutes
            config.setLeakDetectionThreshold(60000); // 1 minute
            config.setPoolName("DSQL-LoadTest-Pool");
            
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
            LOGGER.info("Created DSQL connection pool using AWS DSQL JDBC connector for {}", dsqlHost);
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
}

