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

