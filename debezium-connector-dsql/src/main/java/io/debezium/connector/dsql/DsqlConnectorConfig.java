package io.debezium.connector.dsql;

import org.apache.kafka.common.config.AbstractConfig;
import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.common.config.ConfigException;
import org.apache.kafka.common.config.ConfigDef.Importance;
import org.apache.kafka.common.config.ConfigDef.Type;
import org.apache.kafka.common.config.ConfigDef.Width;

import java.util.Map;

/**
 * Configuration properties for DSQL connector.
 */
public class DsqlConnectorConfig extends AbstractConfig {
    
    // Configuration groups
    public static final String CONNECTION_GROUP = "Connection";
    public static final String AUTH_GROUP = "Authentication";
    public static final String CDC_GROUP = "Change Data Capture";
    public static final String POOL_GROUP = "Connection Pool";
    
    // Connection configuration
    public static final String DSQL_ENDPOINT_PRIMARY = "dsql.endpoint.primary";
    public static final String DSQL_ENDPOINT_SECONDARY = "dsql.endpoint.secondary";
    public static final String DSQL_PORT = "dsql.port";
    public static final String DSQL_DATABASE_NAME = "dsql.database.name";
    public static final String DSQL_REGION = "dsql.region";
    
    // Authentication configuration
    public static final String DSQL_IAM_USERNAME = "dsql.iam.username";
    
    // CDC configuration
    public static final String DSQL_TABLES = "dsql.tables";
    public static final String DSQL_POLL_INTERVAL_MS = "dsql.poll.interval.ms";
    public static final String DSQL_BATCH_SIZE = "dsql.batch.size";
    
    // Connection pool configuration
    public static final String DSQL_POOL_MAX_SIZE = "dsql.pool.max.size";
    public static final String DSQL_POOL_MIN_IDLE = "dsql.pool.min.idle";
    public static final String DSQL_POOL_CONNECTION_TIMEOUT_MS = "dsql.pool.connection.timeout.ms";
    
    // Topic configuration
    public static final String TOPIC_PREFIX = "topic.prefix";
    
    // Task-specific configuration (not in CONFIG_DEF, set by connector)
    public static final String TASK_TABLE = "task.table";
    
    // Default values
    private static final int DEFAULT_PORT = 5432;
    private static final int DEFAULT_POLL_INTERVAL_MS = 1000;
    private static final int DEFAULT_BATCH_SIZE = 1000;
    private static final int DEFAULT_POOL_MAX_SIZE = 10;
    private static final int DEFAULT_POOL_MIN_IDLE = 1;
    private static final long DEFAULT_POOL_CONNECTION_TIMEOUT_MS = 30000;
    private static final long DEFAULT_HEALTH_CHECK_INTERVAL_MS = 60000;

    private static final ConfigDef.Validator NON_EMPTY_STRING = new ConfigDef.Validator() {
        @Override
        public void ensureValid(String name, Object value) {
            if (value == null) {
                throw new ConfigException(name, null, "must be non-null and non-empty");
            }
            String s = value.toString().trim();
            if (s.isEmpty()) {
                throw new ConfigException(name, value, "must be non-empty");
            }
        }

        @Override
        public String toString() {
            return "non-empty string";
        }
    };
    
    public static final ConfigDef CONFIG_DEF = new ConfigDef()
            // Connection group
            .define(DSQL_ENDPOINT_PRIMARY, Type.STRING, ConfigDef.NO_DEFAULT_VALUE,
                    NON_EMPTY_STRING,
                    Importance.HIGH, "Primary DSQL endpoint (hostname)",
                    CONNECTION_GROUP, 1, Width.LONG, "Primary Endpoint")
            
            .define(DSQL_ENDPOINT_SECONDARY, Type.STRING, null,
                    null,
                    Importance.MEDIUM, "Secondary DSQL endpoint for failover (optional)",
                    CONNECTION_GROUP, 2, Width.LONG, "Secondary Endpoint")
            
            .define(DSQL_PORT, Type.INT, DEFAULT_PORT,
                    ConfigDef.Range.between(1, 65535),
                    Importance.MEDIUM, "DSQL database port",
                    CONNECTION_GROUP, 3, Width.SHORT, "Port")
            
            .define(DSQL_DATABASE_NAME, Type.STRING, ConfigDef.NO_DEFAULT_VALUE,
                    NON_EMPTY_STRING,
                    Importance.HIGH, "Database name",
                    CONNECTION_GROUP, 4, Width.MEDIUM, "Database Name")
            
            .define(DSQL_REGION, Type.STRING, ConfigDef.NO_DEFAULT_VALUE,
                    NON_EMPTY_STRING,
                    Importance.HIGH, "AWS region for IAM token generation",
                    CONNECTION_GROUP, 5, Width.MEDIUM, "AWS Region")
            
            // Authentication group
            .define(DSQL_IAM_USERNAME, Type.STRING, ConfigDef.NO_DEFAULT_VALUE,
                    NON_EMPTY_STRING,
                    Importance.HIGH, "IAM database username",
                    AUTH_GROUP, 1, Width.MEDIUM, "IAM Username")
            
            // CDC group
            .define(DSQL_TABLES, Type.STRING, ConfigDef.NO_DEFAULT_VALUE,
                    NON_EMPTY_STRING,
                    Importance.HIGH, "Comma-separated list of tables to monitor (e.g., 'event_headers,business_events')",
                    CDC_GROUP, 1, Width.LONG, "Tables")
            
            .define(DSQL_POLL_INTERVAL_MS, Type.INT, DEFAULT_POLL_INTERVAL_MS,
                    ConfigDef.Range.between(100, 60000),
                    Importance.MEDIUM, "Polling interval in milliseconds",
                    CDC_GROUP, 2, Width.SHORT, "Poll Interval (ms)")
            
            .define(DSQL_BATCH_SIZE, Type.INT, DEFAULT_BATCH_SIZE,
                    ConfigDef.Range.between(1, 10000),
                    Importance.MEDIUM, "Maximum number of records per poll",
                    CDC_GROUP, 3, Width.SHORT, "Batch Size")
            
            // Connection pool group
            .define(DSQL_POOL_MAX_SIZE, Type.INT, DEFAULT_POOL_MAX_SIZE,
                    ConfigDef.Range.between(1, 100),
                    Importance.LOW, "Maximum connection pool size",
                    POOL_GROUP, 1, Width.SHORT, "Max Pool Size")
            
            .define(DSQL_POOL_MIN_IDLE, Type.INT, DEFAULT_POOL_MIN_IDLE,
                    ConfigDef.Range.between(0, 100),
                    Importance.LOW, "Minimum idle connections in pool",
                    POOL_GROUP, 2, Width.SHORT, "Min Idle")
            
            .define(DSQL_POOL_CONNECTION_TIMEOUT_MS, Type.LONG, DEFAULT_POOL_CONNECTION_TIMEOUT_MS,
                    ConfigDef.Range.between(1000, 300000),
                    Importance.LOW, "Connection timeout in milliseconds",
                    POOL_GROUP, 3, Width.SHORT, "Connection Timeout (ms)")
            
            // Topic configuration
            .define(TOPIC_PREFIX, Type.STRING, "dsql-cdc",
                    NON_EMPTY_STRING,
                    Importance.MEDIUM, "Prefix for Kafka topic names",
                    CDC_GROUP, 4, Width.MEDIUM, "Topic Prefix");
    
    // Configuration values
    private final String primaryEndpoint;
    private final String secondaryEndpoint;
    private final int port;
    private final String databaseName;
    private final String region;
    private final String iamUsername;
    private final String tables;
    private final int pollIntervalMs;
    private final int batchSize;
    private final int poolMaxSize;
    private final int poolMinIdle;
    private final long poolConnectionTimeoutMs;
    private final String topicPrefix;
    private final Map<String, String> originalProps;
    
    public DsqlConnectorConfig(Map<String, String> props) {
        super(CONFIG_DEF, props);
        this.originalProps = props;
        
        this.primaryEndpoint = getString(DSQL_ENDPOINT_PRIMARY);
        this.secondaryEndpoint = getString(DSQL_ENDPOINT_SECONDARY);
        this.port = getInt(DSQL_PORT);
        this.databaseName = getString(DSQL_DATABASE_NAME);
        this.region = getString(DSQL_REGION);
        this.iamUsername = getString(DSQL_IAM_USERNAME);
        this.tables = getString(DSQL_TABLES);
        this.pollIntervalMs = getInt(DSQL_POLL_INTERVAL_MS);
        this.batchSize = getInt(DSQL_BATCH_SIZE);
        this.poolMaxSize = getInt(DSQL_POOL_MAX_SIZE);
        this.poolMinIdle = getInt(DSQL_POOL_MIN_IDLE);
        this.poolConnectionTimeoutMs = getLong(DSQL_POOL_CONNECTION_TIMEOUT_MS);
        this.topicPrefix = getString(TOPIC_PREFIX);
    }
    
    // Getters
    public String getPrimaryEndpoint() { return primaryEndpoint; }
    public String getSecondaryEndpoint() { return secondaryEndpoint; }
    public int getPort() { return port; }
    public String getDatabaseName() { return databaseName; }
    public String getRegion() { return region; }
    public String getIamUsername() { return iamUsername; }
    public String getTables() { return tables; }
    public int getPollIntervalMs() { return pollIntervalMs; }
    public int getBatchSize() { return batchSize; }
    public int getPoolMaxSize() { return poolMaxSize; }
    public int getPoolMinIdle() { return poolMinIdle; }
    public long getPoolConnectionTimeoutMs() { return poolConnectionTimeoutMs; }
    public String getTopicPrefix() { return topicPrefix; }
    
    /**
     * Get list of tables as array.
     */
    public String[] getTablesArray() {
        return tables.split(",");
    }
    
    /**
     * Get the table assigned to this task (if set).
     * Returns null if not set (for backward compatibility).
     */
    public String getTaskTable() {
        return originalProps != null ? originalProps.get(TASK_TABLE) : null;
    }
}
