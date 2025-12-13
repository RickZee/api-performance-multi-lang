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
    
    @Override
    public String version() {
        return "1.0.0";
    }
    
    @Override
    public void start(Map<String, String> props) {
        LOGGER.info("Starting DSQL source task");
        
        try {
            this.config = new DsqlConnectorConfig(props);
            
            // Get table name (for now, use first table)
            String[] tables = config.getTablesArray();
            if (tables.length == 0) {
                throw new ConnectException("No tables configured");
            }
            this.tableName = tables[0].trim();
            
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
            
            LOGGER.info("DSQL source task started successfully for table: {}", tableName);
            
        } catch (Exception e) {
            LOGGER.error("Failed to start DSQL source task", e);
            throw new ConnectException("Failed to start DSQL source task", e);
        }
    }
    
    @Override
    public List<SourceRecord> poll() throws InterruptedException {
        try {
            List<SourceRecord> records = changeEventSource.poll();
            
            if (records.isEmpty()) {
                // No records, sleep for poll interval
                Thread.sleep(config.getPollIntervalMs());
            }
            
            return records;
            
        } catch (SQLException e) {
            LOGGER.error("SQL error during poll: {}", e.getMessage(), e);
            
            // Attempt connection pool invalidation and retry
            connectionPool.invalidate();
            
            // Try failover if using primary
            if (endpoint.isUsingPrimary() && config.getSecondaryEndpoint() != null) {
                endpoint.failover();
            }
            
            // Sleep before retry
            Thread.sleep(config.getPollIntervalMs());
            return new ArrayList<>();
            
        } catch (Exception e) {
            LOGGER.error("Unexpected error during poll: {}", e.getMessage(), e);
            Thread.sleep(config.getPollIntervalMs());
            return new ArrayList<>();
        }
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
}

