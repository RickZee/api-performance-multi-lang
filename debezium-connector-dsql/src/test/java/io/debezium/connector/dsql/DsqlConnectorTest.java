package io.debezium.connector.dsql;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class DsqlConnectorTest {
    
    private DsqlConnector connector;
    private Map<String, String> configProps;
    
    @BeforeEach
    void setUp() {
        connector = new DsqlConnector();
        configProps = createValidConfig();
    }
    
    @Test
    void testConnectorStart() {
        connector.start(configProps);
        assertThat(connector.version()).isEqualTo("1.0.0");
    }
    
    @Test
    void testTaskClass() {
        assertThat(connector.taskClass()).isEqualTo(DsqlSourceTask.class);
    }
    
    @Test
    void testTaskConfigs() {
        connector.start(configProps);
        List<Map<String, String>> taskConfigs = connector.taskConfigs(1);
        
        assertThat(taskConfigs).hasSize(1);
        assertThat(taskConfigs.get(0)).containsKey("task.id");
    }
    
    @Test
    void testTaskDistributionAcrossMultipleTables() {
        // Test task distribution when multiple tables are configured
        Map<String, String> multiTableConfig = createValidConfig();
        multiTableConfig.put(DsqlConnectorConfig.DSQL_TABLES, "table1,table2,table3");
        
        connector.start(multiTableConfig);
        
        // Request 3 tasks for 3 tables
        List<Map<String, String>> taskConfigs = connector.taskConfigs(3);
        
        assertThat(taskConfigs).hasSize(3);
        
        // Each task should be assigned a specific table
        for (int i = 0; i < 3; i++) {
            Map<String, String> taskConfig = taskConfigs.get(i);
            assertThat(taskConfig).containsKey("task.id");
            assertThat(taskConfig).containsKey(DsqlConnectorConfig.TASK_TABLE);
            assertThat(taskConfig.get(DsqlConnectorConfig.TASK_TABLE))
                    .isIn("table1", "table2", "table3");
        }
    }
    
    @Test
    void testTaskDistributionWithMoreTasksThanTables() {
        // Test when maxTasks > number of tables
        // Note: Connector creates min(maxTasks, tables.length) tasks
        // So with 2 tables and maxTasks=5, it creates 2 tasks (one per table)
        Map<String, String> config = createValidConfig();
        config.put(DsqlConnectorConfig.DSQL_TABLES, "table1,table2");
        
        connector.start(config);
        
        // Request 5 tasks for 2 tables
        // Actual: Creates 2 tasks (min(5, 2) = 2)
        List<Map<String, String>> taskConfigs = connector.taskConfigs(5);
        
        assertThat(taskConfigs).hasSize(2); // min(5, 2) = 2
        
        // Each task should be assigned a different table
        assertThat(taskConfigs.get(0).get(DsqlConnectorConfig.TASK_TABLE)).isEqualTo("table1");
        assertThat(taskConfigs.get(1).get(DsqlConnectorConfig.TASK_TABLE)).isEqualTo("table2");
    }
    
    @Test
    void testTaskDistributionWithMoreTablesThanTasks() {
        // Test when number of tables > maxTasks
        Map<String, String> config = createValidConfig();
        config.put(DsqlConnectorConfig.DSQL_TABLES, "table1,table2,table3,table4,table5");
        
        connector.start(config);
        
        // Request only 2 tasks for 5 tables
        List<Map<String, String>> taskConfigs = connector.taskConfigs(2);
        
        assertThat(taskConfigs).hasSize(2);
        
        // Each task should be assigned a table
        for (Map<String, String> taskConfig : taskConfigs) {
            assertThat(taskConfig.get(DsqlConnectorConfig.TASK_TABLE))
                    .isIn("table1", "table2", "table3", "table4", "table5");
        }
    }
    
    @Test
    void testTaskIsolation() {
        // Test that each task has its own configuration
        Map<String, String> config = createValidConfig();
        config.put(DsqlConnectorConfig.DSQL_TABLES, "table1,table2");
        
        connector.start(config);
        List<Map<String, String>> taskConfigs = connector.taskConfigs(2);
        
        // Each task should have unique task.id and table assignment
        assertThat(taskConfigs.get(0).get("task.id")).isNotEqualTo(taskConfigs.get(1).get("task.id"));
        assertThat(taskConfigs.get(0).get(DsqlConnectorConfig.TASK_TABLE))
                .isNotEqualTo(taskConfigs.get(1).get(DsqlConnectorConfig.TASK_TABLE));
    }
    
    @Test
    void testTaskConfigsWithSingleTable() {
        // Test task configs with single table
        connector.start(configProps);
        
        // Request multiple tasks for single table
        // Note: Connector creates min(maxTasks, tables.length) tasks
        // So with 1 table and maxTasks=3, it creates 1 task
        List<Map<String, String>> taskConfigs = connector.taskConfigs(3);
        
        assertThat(taskConfigs).hasSize(1); // Only 1 table, so only 1 task
        
        // Task should be assigned the table
        String tableName = configProps.get(DsqlConnectorConfig.DSQL_TABLES);
        assertThat(taskConfigs.get(0).get(DsqlConnectorConfig.TASK_TABLE)).isEqualTo(tableName);
    }
    
    @Test
    void testConfigDef() {
        assertThat(connector.config()).isNotNull();
    }
    
    @Test
    void testStop() {
        connector.start(configProps);
        connector.stop();
        // Should not throw exception
    }
    
    private Map<String, String> createValidConfig() {
        Map<String, String> props = new HashMap<>();
        props.put(DsqlConnectorConfig.DSQL_ENDPOINT_PRIMARY, "dsql-primary.cluster-xyz.us-east-1.rds.amazonaws.com");
        props.put(DsqlConnectorConfig.DSQL_ENDPOINT_SECONDARY, "dsql-secondary.cluster-xyz.us-west-2.rds.amazonaws.com");
        props.put(DsqlConnectorConfig.DSQL_PORT, "5432");
        props.put(DsqlConnectorConfig.DSQL_DATABASE_NAME, "mortgage_db");
        props.put(DsqlConnectorConfig.DSQL_REGION, "us-east-1");
        props.put(DsqlConnectorConfig.DSQL_IAM_USERNAME, "admin");
        props.put(DsqlConnectorConfig.DSQL_TABLES, "event_headers");
        props.put(DsqlConnectorConfig.DSQL_POLL_INTERVAL_MS, "1000");
        props.put(DsqlConnectorConfig.DSQL_BATCH_SIZE, "1000");
        props.put(DsqlConnectorConfig.TOPIC_PREFIX, "dsql-cdc");
        return props;
    }
}
