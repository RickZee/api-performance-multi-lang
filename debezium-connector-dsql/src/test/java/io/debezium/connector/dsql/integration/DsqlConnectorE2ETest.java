package io.debezium.connector.dsql.integration;

import io.debezium.connector.dsql.DsqlConnector;
import io.debezium.connector.dsql.DsqlConnectorConfig;
import io.debezium.connector.dsql.DsqlSourceTask;
import org.apache.kafka.connect.source.SourceRecord;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.testcontainers.containers.KafkaContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * End-to-end tests for DSQL connector.
 * 
 * Note: Full E2E tests with Kafka Connect would require:
 * - Kafka Connect container setup
 * - Connector registration
 * - Kafka consumer to verify records
 * 
 * This test provides the structure and basic validation.
 */
@Testcontainers(disabledWithoutDocker = true)
@ExtendWith(org.testcontainers.junit.jupiter.TestcontainersExtension.class)
class DsqlConnectorE2ETest {
    
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15")
            .withDatabaseName("testdb")
            .withUsername("testuser")
            .withPassword("testpass");
    
    @Container
    static KafkaContainer kafka = new KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.4.0"));
    
    @BeforeAll
    static void setUpDatabase() throws Exception {
        // Access containers to trigger Testcontainers to start them
        // The @Testcontainers annotation will skip tests if Docker is not available
        postgres.start();
        kafka.start();
        
        // Create test table
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                stmt.execute(
                    "CREATE TABLE IF NOT EXISTS event_headers (" +
                    "    id VARCHAR(255) PRIMARY KEY," +
                    "    event_name VARCHAR(255) NOT NULL," +
                    "    event_type VARCHAR(255)," +
                    "    created_date TIMESTAMP WITH TIME ZONE," +
                    "    saved_date TIMESTAMP WITH TIME ZONE," +
                    "    header_data JSONB NOT NULL" +
                    ")"
                );
            }
        }
    }
    
    @Test
    void testConnectorConfigurationForE2E() {
        // Test that connector can be configured for E2E scenario
        Map<String, String> config = createE2EConfig();
        DsqlConnectorConfig connectorConfig = new DsqlConnectorConfig(config);
        
        assertThat(connectorConfig.getDatabaseName()).isEqualTo(postgres.getDatabaseName());
        assertThat(connectorConfig.getTablesArray()).contains("event_headers");
    }
    
    @Test
    void testConnectorStartup() {
        // Test connector startup with E2E configuration
        DsqlConnector connector = new DsqlConnector();
        Map<String, String> config = createE2EConfig();
        
        connector.start(config);
        
        assertThat(connector.version()).isEqualTo("1.0.0");
        assertThat(connector.taskClass()).isEqualTo(DsqlSourceTask.class);
        
        connector.stop();
    }
    
    @Test
    void testTaskConfigurationForE2E() {
        // Test task configuration generation for E2E
        DsqlConnector connector = new DsqlConnector();
        Map<String, String> config = createE2EConfig();
        
        connector.start(config);
        List<Map<String, String>> taskConfigs = connector.taskConfigs(1);
        
        assertThat(taskConfigs).hasSize(1);
        assertThat(taskConfigs.get(0)).containsKey("task.id");
        assertThat(taskConfigs.get(0)).containsKey(DsqlConnectorConfig.TASK_TABLE);
        
        connector.stop();
    }
    
    @Test
    void testKafkaContainerRunning() {
        // Verify Kafka container is available for E2E tests
        // Container is started in @BeforeAll, @Testcontainers will skip if Docker unavailable
        String bootstrapServers = kafka.getBootstrapServers();
        assertThat(bootstrapServers).isNotNull();
        assertThat(bootstrapServers).isNotEmpty();
    }
    
    @Test
    void testDatabaseAndKafkaBothRunning() {
        // Verify both database and Kafka are available
        // Containers are started in @BeforeAll, @Testcontainers will skip if Docker unavailable
        assertThat(postgres.getJdbcUrl()).isNotNull();
        assertThat(kafka.getBootstrapServers()).isNotNull();
    }
    
    /**
     * Note: Full E2E test would:
     * 1. Set up Kafka Connect container
     * 2. Register the DSQL connector
     * 3. Insert test data into database
     * 4. Wait for connector to poll and produce records
     * 5. Consume records from Kafka topic
     * 6. Verify record format and content
     * 
     * This requires additional setup with Kafka Connect container
     * and connector JAR deployment, which is beyond basic test structure.
     */
    
    private Map<String, String> createE2EConfig() {
        Map<String, String> config = new HashMap<>();
        config.put("dsql.endpoint.primary", postgres.getHost());
        config.put("dsql.port", String.valueOf(postgres.getFirstMappedPort()));
        config.put("dsql.database.name", postgres.getDatabaseName());
        config.put("dsql.region", "us-east-1");
        config.put("dsql.iam.username", postgres.getUsername());
        config.put("dsql.tables", "event_headers");
        config.put("dsql.poll.interval.ms", "1000");
        config.put("dsql.batch.size", "1000");
        config.put("topic.prefix", "dsql-cdc");
        return config;
    }
}
