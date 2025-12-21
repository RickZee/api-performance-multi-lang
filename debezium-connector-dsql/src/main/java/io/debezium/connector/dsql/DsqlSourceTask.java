package io.debezium.connector.dsql;

import io.debezium.connector.dsql.auth.IamTokenGenerator;
import io.debezium.connector.dsql.auth.TokenRefreshScheduler;
import io.debezium.connector.dsql.connection.DsqlConnectionPool;
import io.debezium.connector.dsql.connection.MultiRegionEndpoint;
import org.apache.kafka.connect.errors.ConnectException;
import org.apache.kafka.connect.source.SourceRecord;
import org.apache.kafka.connect.source.SourceTask;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Source task implementation for DSQL CDC.
 * 
 * Connects to DSQL using IAM-generated tokens, polls for changes,
 * and converts rows to Kafka Connect SourceRecord objects.
 */
public class DsqlSourceTask extends SourceTask {
    private static final Logger LOGGER = LoggerFactory.getLogger(DsqlSourceTask.class);
    
    private DsqlConnectorConfig config;
    private DsqlConnectionPool connectionPool;
    private IamTokenGenerator tokenGenerator;
    private TokenRefreshScheduler tokenScheduler;
    private MultiRegionEndpoint endpoint;
    private DsqlChangeEventSource changeEventSource;
    private DsqlSchema schema;
    private DsqlOffsetContext offsetContext;
    private String tableName;
    
    // Metrics
    private long recordsPolled = 0;
    private long errorsCount = 0;
    private long lastPollTime = 0;
    
    @Override
    public String version() {
        return "1.0.0";
    }
    
    @Override
    public void start(Map<String, String> props) {
        LOGGER.info("Starting DSQL source task");
        
        try {
            this.config = new DsqlConnectorConfig(props);
            
            // Get table name assigned to this task
            String assignedTable = config.getTaskTable();
            if (assignedTable == null || assignedTable.isEmpty()) {
                // Fallback to first table for backward compatibility
                String[] tables = config.getTablesArray();
                if (tables.length == 0) {
                    throw new ConnectException("No tables configured");
                }
                this.tableName = tables[0].trim();
                LOGGER.warn("No table assigned to task, using first table: {}", this.tableName);
            } else {
                this.tableName = assignedTable.trim();
            }
            
            // Initialize IAM token generator
            this.tokenGenerator = new IamTokenGenerator(
                    config.getPrimaryEndpoint(),
                    config.getPort(),
                    config.getIamUsername(),
                    config.getRegion()
            );
            
            // Start token refresh scheduler
            this.tokenScheduler = new TokenRefreshScheduler(tokenGenerator);
            tokenScheduler.start();
            
            // Initialize multi-region endpoint
            String secondaryEndpoint = config.getSecondaryEndpoint();
            if (secondaryEndpoint == null || secondaryEndpoint.isEmpty()) {
                secondaryEndpoint = config.getPrimaryEndpoint(); // Use primary as fallback
            }
            
            this.endpoint = new MultiRegionEndpoint(
                    config.getPrimaryEndpoint(),
                    secondaryEndpoint,
                    config.getPort(),
                    config.getDatabaseName(),
                    60000L // 1 minute health check interval
            );
            
            // Initialize connection pool
            this.connectionPool = new DsqlConnectionPool(
                    endpoint,
                    tokenGenerator,
                    config.getDatabaseName(),
                    config.getPort(),
                    config.getIamUsername(),
                    config.getRegion(),
                    config.getPoolMaxSize(),
                    config.getPoolMinIdle(),
                    config.getPoolConnectionTimeoutMs()
            );
            
            // Initialize schema
            this.schema = new DsqlSchema(tableName, config.getTopicPrefix());
            
            // Load offset
            Map<String, Object> offset = context.offsetStorageReader().offset(
                    Map.of("table", tableName)
            );
            this.offsetContext = DsqlOffsetContext.load(offset, tableName);
            
            // Initialize change event source
            this.changeEventSource = new DsqlChangeEventSource(
                    connectionPool,
                    config,
                    tableName,
                    schema,
                    offsetContext
            );
            
            // Initialize schema before first poll
            changeEventSource.initializeSchema();
            
            // Validate table exists and has required columns
            validateTable();
            
            LOGGER.info("DSQL source task started successfully for table: {}", tableName);
            LOGGER.info("Metrics: recordsPolled={}, errorsCount={}", recordsPolled, errorsCount);
            
        } catch (Exception e) {
            LOGGER.error("Failed to start DSQL source task", e);
            throw new ConnectException("Failed to start DSQL source task", e);
        }
    }
    
    @Override
    public List<SourceRecord> poll() throws InterruptedException {
        // Validate required components are initialized
        if (config == null) {
            LOGGER.error("Configuration is null, cannot poll");
            throw new ConnectException("DSQL source task not properly initialized: configuration is null");
        }
        if (changeEventSource == null) {
            LOGGER.error("Change event source is null, cannot poll");
            throw new ConnectException("DSQL source task not properly initialized: change event source is null");
        }
        if (connectionPool == null) {
            LOGGER.error("Connection pool is null, cannot poll");
            throw new ConnectException("DSQL source task not properly initialized: connection pool is null");
        }
        
        int maxRetries = 3;
        int retryCount = 0;
        long retryDelayMs = config.getPollIntervalMs();
        
        while (retryCount < maxRetries) {
            try {
                List<SourceRecord> records = changeEventSource.poll();
                
                // Update metrics
                recordsPolled += records.size();
                lastPollTime = System.currentTimeMillis();
                
                if (records.isEmpty()) {
                    // No records, sleep for poll interval
                    Thread.sleep(config.getPollIntervalMs());
                }
                
                // Reset retry count on success
                retryCount = 0;
                return records;
                
            } catch (SQLException e) {
                errorsCount++;
                retryCount++;
                
                String errorContext = String.format("table=%s, sqlState=%s, attempt=%d/%d", 
                    tableName, e.getSQLState(), retryCount, maxRetries);
                
                if (isTransientError(e) && retryCount < maxRetries) {
                    LOGGER.warn("Transient SQL error during poll ({}): {} - {}", 
                               errorContext, e.getClass().getSimpleName(), e.getMessage());
                    
                    // Attempt connection pool invalidation and failover
                    if (connectionPool != null) {
                        connectionPool.invalidate();
                    }
                    
                    // Try failover if using primary
                    if (endpoint != null && endpoint.isUsingPrimary() && 
                        config != null && config.getSecondaryEndpoint() != null) {
                        endpoint.failover();
                    }
                    
                    // Exponential backoff
                    long delay = retryDelayMs * (long) Math.pow(2, retryCount - 1);
                    Thread.sleep(Math.min(delay, config.getPollIntervalMs() * 10)); // Cap at 10x poll interval
                } else {
                    LOGGER.error("SQL error during poll (non-retryable or max retries reached) ({}): {} - {}", 
                               errorContext, e.getClass().getSimpleName(), e.getMessage(), e);
                    
                    // Attempt connection pool invalidation and failover even on non-retryable errors
                    if (connectionPool != null) {
                        connectionPool.invalidate();
                    }
                    if (endpoint != null && endpoint.isUsingPrimary() && 
                        config != null && config.getSecondaryEndpoint() != null) {
                        endpoint.failover();
                    }
                    
                    Thread.sleep(config.getPollIntervalMs());
                    return new ArrayList<>();
                }
                
            } catch (Exception e) {
                errorsCount++;
                String errorContext = String.format("table=%s, errorType=%s", 
                    tableName, e.getClass().getSimpleName());
                LOGGER.error("Unexpected error during poll ({}): {} - {}", 
                           errorContext, e.getClass().getSimpleName(), e.getMessage(), e);
                if (config != null) {
                    Thread.sleep(config.getPollIntervalMs());
                }
                return new ArrayList<>();
            }
        }
        
        return new ArrayList<>();
    }
    
    /**
     * Check if SQL error is transient and retryable.
     */
    private boolean isTransientError(SQLException e) {
        String errorMessage = e.getMessage().toLowerCase();
        String sqlState = e.getSQLState();
        
        // Check for transient error SQL states
        if (sqlState != null) {
            // PostgreSQL transient error states
            if (sqlState.startsWith("08") || // Connection exceptions
                sqlState.startsWith("40") || // Transaction rollback
                sqlState.equals("40001") ||  // Serialization failure
                sqlState.equals("40P01")) {  // Deadlock detected
                return true;
            }
        }
        
        // Check error message for transient conditions
        return errorMessage.contains("connection") ||
               errorMessage.contains("timeout") ||
               errorMessage.contains("network") ||
               errorMessage.contains("unable to connect") ||
               errorMessage.contains("connection refused") ||
               errorMessage.contains("connection reset") ||
               errorMessage.contains("temporary") ||
               errorMessage.contains("retry") ||
               errorMessage.contains("authentication") ||
               errorMessage.contains("password");
    }
    
    @Override
    public void stop() {
        LOGGER.info("Stopping DSQL source task");
        
        try {
            if (tokenScheduler != null) {
                tokenScheduler.stop();
            }
            
            if (connectionPool != null) {
                connectionPool.close();
            }
            
            if (tokenGenerator != null) {
                tokenGenerator.close();
            }
            
            LOGGER.info("DSQL source task stopped");
            
        } catch (Exception e) {
            LOGGER.error("Error stopping DSQL source task", e);
        }
    }
    
    /**
     * Validate that the table exists and has required columns.
     */
    private void validateTable() throws SQLException {
        if (connectionPool == null) {
            throw new ConnectException("Cannot validate table: connection pool is null");
        }
        if (tableName == null || tableName.isEmpty()) {
            throw new ConnectException("Cannot validate table: table name is null or empty");
        }
        
        try (java.sql.Connection conn = connectionPool.getConnection()) {
            if (conn == null) {
                throw new ConnectException("Cannot validate table: failed to get database connection");
            }
            
            java.sql.DatabaseMetaData metadata = conn.getMetaData();
            if (metadata == null) {
                throw new ConnectException("Cannot validate table: failed to get database metadata");
            }
            
            // Check if table exists
            try (java.sql.ResultSet tables = metadata.getTables(null, "public", tableName, null)) {
                if (tables == null) {
                    throw new ConnectException("Cannot validate table: failed to query table metadata");
                }
                if (!tables.next()) {
                    throw new ConnectException(String.format(
                        "Table '%s' does not exist in schema 'public'. Please verify the table name and schema.", 
                        tableName));
                }
            }
            
            // Schema validation already checks for saved_date and primary key
            // This is done in initializeSchema()
            
            LOGGER.debug("Table validation passed for: {}", tableName);
        } catch (SQLException e) {
            LOGGER.error("Failed to validate table '{}': {} - {}", tableName, e.getClass().getSimpleName(), e.getMessage(), e);
            throw new ConnectException(String.format(
                "Failed to validate table '%s': %s", tableName, e.getMessage()), e);
        }
    }
    
    /**
     * Get metrics for monitoring.
     */
    public long getRecordsPolled() {
        return recordsPolled;
    }
    
    public long getErrorsCount() {
        return errorsCount;
    }
    
    public long getLastPollTime() {
        return lastPollTime;
    }
}
