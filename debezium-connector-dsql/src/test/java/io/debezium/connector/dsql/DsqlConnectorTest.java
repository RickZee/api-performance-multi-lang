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

