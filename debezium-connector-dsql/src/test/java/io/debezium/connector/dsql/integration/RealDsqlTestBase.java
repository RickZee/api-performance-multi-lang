package io.debezium.connector.dsql.integration;

import io.debezium.connector.dsql.auth.IamTokenGenerator;
import io.debezium.connector.dsql.connection.DsqlConnectionPool;
import io.debezium.connector.dsql.connection.MultiRegionEndpoint;
import org.junit.jupiter.api.Assumptions;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;

import java.sql.Connection;
import java.sql.SQLException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Base class for real DSQL integration tests.
 * 
 * Loads configuration from environment variables and provides
 * setup/teardown for connection pool and token generator.
 * Tests will be skipped if required environment variables are not set.
 */
public abstract class RealDsqlTestBase {
    
    protected String primaryEndpoint;
    protected String secondaryEndpoint;
    protected int port;
    protected String databaseName;
    protected String region;
    protected String iamUsername;
    protected String[] tables;
    protected String topicPrefix;
    
    protected MultiRegionEndpoint endpoint;
    protected IamTokenGenerator tokenGenerator;
    protected DsqlConnectionPool connectionPool;
    
    /**
     * Load configuration from environment variables and validate.
     * Skips tests if required variables are not set.
     */
    protected void loadConfiguration() {
        primaryEndpoint = System.getenv("DSQL_ENDPOINT_PRIMARY");
        secondaryEndpoint = System.getenv("DSQL_ENDPOINT_SECONDARY");
        String portStr = System.getenv("DSQL_PORT");
        databaseName = System.getenv("DSQL_DATABASE_NAME");
        region = System.getenv("DSQL_REGION");
        iamUsername = System.getenv("DSQL_IAM_USERNAME");
        String tablesStr = System.getenv("DSQL_TABLES");
        topicPrefix = System.getenv("DSQL_TOPIC_PREFIX");
        
        if (topicPrefix == null || topicPrefix.isEmpty()) {
            topicPrefix = "dsql-cdc";
        }
        
        // Check required variables
        if (primaryEndpoint == null || primaryEndpoint.isEmpty()) {
            Assumptions.assumeTrue(false, "DSQL_ENDPOINT_PRIMARY environment variable not set");
        }
        if (databaseName == null || databaseName.isEmpty()) {
            Assumptions.assumeTrue(false, "DSQL_DATABASE_NAME environment variable not set");
        }
        if (region == null || region.isEmpty()) {
            Assumptions.assumeTrue(false, "DSQL_REGION environment variable not set");
        }
        if (iamUsername == null || iamUsername.isEmpty()) {
            Assumptions.assumeTrue(false, "DSQL_IAM_USERNAME environment variable not set");
        }
        if (tablesStr == null || tablesStr.isEmpty()) {
            Assumptions.assumeTrue(false, "DSQL_TABLES environment variable not set");
        }
        
        port = 5432;
        if (portStr != null && !portStr.isEmpty()) {
            try {
                port = Integer.parseInt(portStr);
            } catch (NumberFormatException e) {
                // Use default
            }
        }
        
        tables = tablesStr.split(",");
        for (int i = 0; i < tables.length; i++) {
            tables[i] = tables[i].trim();
        }
        
        // Validate AWS credentials are available
        try {
            DefaultCredentialsProvider.create().resolveCredentials();
        } catch (Exception e) {
            Assumptions.assumeTrue(false, 
                "AWS credentials not available: " + e.getMessage() + 
                ". Please configure AWS credentials via environment variables, ~/.aws/credentials, or IAM role.");
        }
    }
    
    /**
     * Set up connection pool and token generator.
     * Called by test classes in @BeforeEach or @BeforeAll.
     */
    protected void setUpConnections() {
        loadConfiguration();
        
        // Set up multi-region endpoint
        String secondary = (secondaryEndpoint != null && !secondaryEndpoint.isEmpty()) 
            ? secondaryEndpoint 
            : primaryEndpoint; // Use primary as fallback
        
        endpoint = new MultiRegionEndpoint(
            primaryEndpoint,
            secondary,
            port,
            databaseName,
            60000L // Health check interval
        );
        
        // Set up token generator
        tokenGenerator = new IamTokenGenerator(
            primaryEndpoint,
            port,
            iamUsername,
            region
        );
        
        // Set up connection pool
        connectionPool = new DsqlConnectionPool(
            endpoint,
            tokenGenerator,
            databaseName,
            port,
            iamUsername,
            10, // maxPoolSize
            1,  // minIdle
            30000L // connectionTimeoutMs
        );
    }
    
    /**
     * Clean up connections.
     * Called by test classes in @AfterEach or @AfterAll.
     */
    protected void tearDownConnections() {
        if (connectionPool != null) {
            try {
                connectionPool.close();
            } catch (Exception e) {
                // Ignore cleanup errors
            }
        }
        
        if (tokenGenerator != null) {
            try {
                tokenGenerator.close();
            } catch (Exception e) {
                // Ignore cleanup errors
            }
        }
    }
    
    /**
     * Get a connection from the pool for testing.
     */
    protected Connection getConnection() throws SQLException {
        return connectionPool.getConnection();
    }
    
    /**
     * Create connector configuration map from environment variables.
     */
    protected Map<String, String> createConnectorConfig() {
        Map<String, String> config = new ConcurrentHashMap<>();
        config.put("dsql.endpoint.primary", primaryEndpoint);
        if (secondaryEndpoint != null && !secondaryEndpoint.isEmpty()) {
            config.put("dsql.endpoint.secondary", secondaryEndpoint);
        }
        config.put("dsql.port", String.valueOf(port));
        config.put("dsql.database.name", databaseName);
        config.put("dsql.region", region);
        config.put("dsql.iam.username", iamUsername);
        config.put("dsql.tables", String.join(",", tables));
        config.put("topic.prefix", topicPrefix);
        config.put("dsql.poll.interval.ms", "1000");
        config.put("dsql.batch.size", "1000");
        config.put("dsql.pool.max.size", "10");
        config.put("dsql.pool.min.idle", "1");
        config.put("dsql.pool.connection.timeout.ms", "30000");
        return config;
    }
}
