package io.debezium.connector.dsql;

import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class DsqlConnectorConfigTest {
    
    @Test
    void testValidConfiguration() {
        Map<String, String> props = createValidConfig();
        DsqlConnectorConfig config = new DsqlConnectorConfig(props);
        
        assertThat(config.getPrimaryEndpoint()).isEqualTo("dsql-primary.cluster-xyz.us-east-1.rds.amazonaws.com");
        assertThat(config.getSecondaryEndpoint()).isEqualTo("dsql-secondary.cluster-xyz.us-west-2.rds.amazonaws.com");
        assertThat(config.getPort()).isEqualTo(5432);
        assertThat(config.getDatabaseName()).isEqualTo("mortgage_db");
        assertThat(config.getRegion()).isEqualTo("us-east-1");
        assertThat(config.getIamUsername()).isEqualTo("admin");
        assertThat(config.getTables()).isEqualTo("event_headers");
        assertThat(config.getPollIntervalMs()).isEqualTo(1000);
        assertThat(config.getBatchSize()).isEqualTo(1000);
        assertThat(config.getTopicPrefix()).isEqualTo("dsql-cdc");
    }
    
    @Test
    void testDefaultValues() {
        Map<String, String> props = createValidConfig();
        props.remove(DsqlConnectorConfig.DSQL_POLL_INTERVAL_MS);
        props.remove(DsqlConnectorConfig.DSQL_BATCH_SIZE);
        
        DsqlConnectorConfig config = new DsqlConnectorConfig(props);
        
        assertThat(config.getPollIntervalMs()).isEqualTo(1000); // Default
        assertThat(config.getBatchSize()).isEqualTo(1000); // Default
    }
    
    @Test
    void testMissingRequiredFields() {
        Map<String, String> props = new HashMap<>();
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testTablesArray() {
        Map<String, String> props = createValidConfig();
        props.put(DsqlConnectorConfig.DSQL_TABLES, "event_headers,business_events");
        
        DsqlConnectorConfig config = new DsqlConnectorConfig(props);
        String[] tables = config.getTablesArray();
        
        assertThat(tables).hasSize(2);
        assertThat(tables[0]).isEqualTo("event_headers");
        assertThat(tables[1]).isEqualTo("business_events");
    }
    
    @Test
    void testInvalidPortNumber() {
        Map<String, String> props = createValidConfig();
        props.put(DsqlConnectorConfig.DSQL_PORT, "99999"); // Out of range
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testNegativePortNumber() {
        Map<String, String> props = createValidConfig();
        props.put(DsqlConnectorConfig.DSQL_PORT, "-1");
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testInvalidPollInterval() {
        Map<String, String> props = createValidConfig();
        props.put(DsqlConnectorConfig.DSQL_POLL_INTERVAL_MS, "50"); // Below minimum (100)
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testInvalidBatchSize() {
        Map<String, String> props = createValidConfig();
        props.put(DsqlConnectorConfig.DSQL_BATCH_SIZE, "0"); // Below minimum (1)
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testExcessiveBatchSize() {
        Map<String, String> props = createValidConfig();
        props.put(DsqlConnectorConfig.DSQL_BATCH_SIZE, "20000"); // Above maximum (10000)
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testEmptyEndpoint() {
        Map<String, String> props = createValidConfig();
        props.put(DsqlConnectorConfig.DSQL_ENDPOINT_PRIMARY, "");
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testEmptyDatabaseName() {
        Map<String, String> props = createValidConfig();
        props.put(DsqlConnectorConfig.DSQL_DATABASE_NAME, "");
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testEmptyTables() {
        Map<String, String> props = createValidConfig();
        props.put(DsqlConnectorConfig.DSQL_TABLES, "");
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testConfigurationWithSpecialCharacters() {
        // Test that special characters in configuration are handled
        Map<String, String> props = createValidConfig();
        props.put(DsqlConnectorConfig.DSQL_TABLES, "table_with_underscores,table-with-dashes");
        props.put(DsqlConnectorConfig.TOPIC_PREFIX, "prefix-with-special-chars_123");
        
        DsqlConnectorConfig config = new DsqlConnectorConfig(props);
        
        assertThat(config.getTablesArray()).hasSize(2);
        assertThat(config.getTopicPrefix()).isEqualTo("prefix-with-special-chars_123");
    }
    
    @Test
    void testVeryLongTableName() {
        // Test configuration with very long table name
        Map<String, String> props = createValidConfig();
        String longTableName = "a".repeat(1000);
        props.put(DsqlConnectorConfig.DSQL_TABLES, longTableName);
        
        DsqlConnectorConfig config = new DsqlConnectorConfig(props);
        String[] tables = config.getTablesArray();
        
        assertThat(tables[0]).isEqualTo(longTableName);
    }
    
    @Test
    void testMissingPrimaryEndpoint() {
        Map<String, String> props = createValidConfig();
        props.remove(DsqlConnectorConfig.DSQL_ENDPOINT_PRIMARY);
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testMissingDatabaseName() {
        Map<String, String> props = createValidConfig();
        props.remove(DsqlConnectorConfig.DSQL_DATABASE_NAME);
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testMissingRegion() {
        Map<String, String> props = createValidConfig();
        props.remove(DsqlConnectorConfig.DSQL_REGION);
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testMissingIamUsername() {
        Map<String, String> props = createValidConfig();
        props.remove(DsqlConnectorConfig.DSQL_IAM_USERNAME);
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testConnectionPoolConfigValidation() {
        Map<String, String> props = createValidConfig();
        props.put(DsqlConnectorConfig.DSQL_POOL_MAX_SIZE, "0"); // Invalid (minimum 1)
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testConnectionPoolMaxSizeTooLarge() {
        Map<String, String> props = createValidConfig();
        props.put(DsqlConnectorConfig.DSQL_POOL_MAX_SIZE, "200"); // Above maximum (100)
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
    }
    
    @Test
    void testConnectionTimeoutTooSmall() {
        Map<String, String> props = createValidConfig();
        props.put(DsqlConnectorConfig.DSQL_POOL_CONNECTION_TIMEOUT_MS, "500"); // Below minimum (1000)
        
        assertThatThrownBy(() -> new DsqlConnectorConfig(props))
                .isInstanceOf(Exception.class);
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
