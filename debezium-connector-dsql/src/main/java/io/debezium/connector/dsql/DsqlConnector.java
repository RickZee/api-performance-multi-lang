package io.debezium.connector.dsql;

import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.connect.connector.Task;
import org.apache.kafka.connect.source.SourceConnector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Main connector class for DSQL CDC.
 * 
 * Extends SourceConnector to integrate with Kafka Connect framework.
 * Validates configuration and creates task configurations for parallel processing.
 */
public class DsqlConnector extends SourceConnector {
    private static final Logger LOGGER = LoggerFactory.getLogger(DsqlConnector.class);
    
    private Map<String, String> configProps;
    
    @Override
    public void start(Map<String, String> props) {
        LOGGER.info("Starting DSQL connector");
        this.configProps = props;
        
        // Validate configuration
        DsqlConnectorConfig config = new DsqlConnectorConfig(props);
        LOGGER.info("DSQL connector configuration validated successfully");
        LOGGER.info("Primary endpoint: {}", config.getPrimaryEndpoint());
        LOGGER.info("Database: {}", config.getDatabaseName());
        LOGGER.info("Tables: {}", config.getTables());
    }
    
    @Override
    public void stop() {
        LOGGER.info("Stopping DSQL connector");
        configProps = null;
    }
    
    @Override
    public Class<? extends Task> taskClass() {
        return DsqlSourceTask.class;
    }
    
    @Override
    public List<Map<String, String>> taskConfigs(int maxTasks) {
        LOGGER.info("Creating task configurations for {} tasks", maxTasks);
        
        List<Map<String, String>> taskConfigs = new ArrayList<>();
        
        // For now, we'll use a single task per table
        // In the future, we could partition tables across tasks for parallelism
        String[] tables = new DsqlConnectorConfig(configProps).getTablesArray();
        
        int tasksToCreate = Math.min(maxTasks, tables.length);
        if (tasksToCreate == 0) {
            tasksToCreate = 1; // At least one task
        }
        
        for (int i = 0; i < tasksToCreate; i++) {
            Map<String, String> taskConfig = new HashMap<>(configProps);
            taskConfig.put("task.id", String.valueOf(i));
            taskConfigs.add(taskConfig);
        }
        
        LOGGER.info("Created {} task configuration(s)", taskConfigs.size());
        return taskConfigs;
    }
    
    @Override
    public ConfigDef config() {
        return DsqlConnectorConfig.CONFIG_DEF;
    }
    
    @Override
    public String version() {
        return "1.0.0";
    }
}
