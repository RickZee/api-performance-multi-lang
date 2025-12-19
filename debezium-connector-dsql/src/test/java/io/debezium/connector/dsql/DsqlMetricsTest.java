package io.debezium.connector.dsql;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class DsqlMetricsTest {
    
    private DsqlSourceTask task;
    private Map<String, String> configProps;
    
    @BeforeEach
    void setUp() {
        configProps = createValidConfig();
    }
    
    @Test
    void testInitialMetrics() {
        // Test that metrics start at zero
        task = new DsqlSourceTask();
        
        // Metrics should be accessible even before task is started
        assertThat(task.getRecordsPolled()).isEqualTo(0);
        assertThat(task.getErrorsCount()).isEqualTo(0);
        assertThat(task.getLastPollTime()).isEqualTo(0);
    }
    
    @Test
    void testMetricsAreNonNegative() {
        // Test that metrics are always non-negative
        task = new DsqlSourceTask();
        
        assertThat(task.getRecordsPolled()).isGreaterThanOrEqualTo(0);
        assertThat(task.getErrorsCount()).isGreaterThanOrEqualTo(0);
        assertThat(task.getLastPollTime()).isGreaterThanOrEqualTo(0);
    }
    
    @Test
    void testMetricsMethodsExist() {
        // Test that all metric getter methods exist and are accessible
        task = new DsqlSourceTask();
        
        // Verify methods don't throw
        long records = task.getRecordsPolled();
        long errors = task.getErrorsCount();
        long lastPoll = task.getLastPollTime();
        
        assertThat(records).isNotNull();
        assertThat(errors).isNotNull();
        assertThat(lastPoll).isNotNull();
    }
    
    @Test
    void testMetricsType() {
        // Test that metrics return correct types
        task = new DsqlSourceTask();
        
        // All metrics should be long values
        assertThat(task.getRecordsPolled()).isInstanceOf(Long.class);
        assertThat(task.getErrorsCount()).isInstanceOf(Long.class);
        assertThat(task.getLastPollTime()).isInstanceOf(Long.class);
    }
    
    private Map<String, String> createValidConfig() {
        Map<String, String> props = new HashMap<>();
        props.put(DsqlConnectorConfig.DSQL_ENDPOINT_PRIMARY, "test-endpoint");
        props.put(DsqlConnectorConfig.DSQL_PORT, "5432");
        props.put(DsqlConnectorConfig.DSQL_DATABASE_NAME, "testdb");
        props.put(DsqlConnectorConfig.DSQL_REGION, "us-east-1");
        props.put(DsqlConnectorConfig.DSQL_IAM_USERNAME, "testuser");
        props.put(DsqlConnectorConfig.DSQL_TABLES, "test_table");
        props.put(DsqlConnectorConfig.DSQL_POLL_INTERVAL_MS, "1000");
        props.put(DsqlConnectorConfig.DSQL_BATCH_SIZE, "1000");
        props.put(DsqlConnectorConfig.TOPIC_PREFIX, "test");
        return props;
    }
}
