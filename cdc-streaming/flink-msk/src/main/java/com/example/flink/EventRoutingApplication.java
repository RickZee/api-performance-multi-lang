package com.example.flink;

import org.apache.flink.api.common.restartstrategy.RestartStrategies;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.configuration.GlobalConfiguration;
import org.apache.flink.configuration.RestOptions;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.TableEnvironment;
import org.apache.flink.table.api.bridge.java.StreamTableEnvironment;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.stream.Collectors;

/**
 * Flink Application for Event Routing
 * 
 * This application reads SQL statements from business-events-routing-msk.sql
 * and executes them to filter and route events from MSK topics.
 */
public class EventRoutingApplication {
    
    private static final Logger LOG = LoggerFactory.getLogger(EventRoutingApplication.class);
    private static final String SQL_FILE = "/business-events-routing-msk.sql";
    
    public static void main(String[] args) throws Exception {
        // Get bootstrap servers from multiple sources (priority order):
        // 1. System property
        // 2. Environment variable
        // 3. Command line argument
        // 4. Flink configuration (from property groups)
        String bootstrapServers = System.getProperty("bootstrap.servers");
        if (bootstrapServers == null || bootstrapServers.isEmpty()) {
            bootstrapServers = System.getenv("BOOTSTRAP_SERVERS");
        }
        if ((bootstrapServers == null || bootstrapServers.isEmpty()) && args.length > 0) {
            bootstrapServers = args[0];
        }
        // Try to read from properties file in resources
        if (bootstrapServers == null || bootstrapServers.isEmpty()) {
            try {
                java.util.Properties props = new java.util.Properties();
                try (InputStream is = EventRoutingApplication.class.getResourceAsStream("/application.properties")) {
                    if (is != null) {
                        props.load(is);
                        bootstrapServers = props.getProperty("bootstrap.servers");
                        if (bootstrapServers != null && !bootstrapServers.isEmpty()) {
                            LOG.info("Found bootstrap servers from properties file: {}", bootstrapServers);
                        }
                    }
                }
            } catch (Exception e) {
                LOG.warn("Could not read bootstrap servers from properties file: {}", e.getMessage());
            }
        }
        // Final check - throw error if still not found
        if (bootstrapServers == null || bootstrapServers.isEmpty()) {
            throw new IllegalArgumentException("BOOTSTRAP_SERVERS environment variable, bootstrap.servers system property, command line argument, or application.properties file is required");
        }
        
        LOG.info("Starting Flink Event Routing Application");
        LOG.info("Bootstrap Servers: {}", bootstrapServers);
        
        // Create Flink execution environment
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.setRestartStrategy(RestartStrategies.fixedDelayRestart(3, org.apache.flink.api.common.time.Time.seconds(10)));
        
        // Create Table Environment
        EnvironmentSettings settings = EnvironmentSettings.newInstance()
            .inStreamingMode()
            .build();
        StreamTableEnvironment tableEnv = StreamTableEnvironment.create(env, settings);
        
        // Try to get bootstrap servers from TableEnvironment configuration if not already set
        // (This is a fallback, but properties file should have already provided it)
        if (bootstrapServers == null || bootstrapServers.isEmpty()) {
            try {
                // Try reading from TableEnvironment's configuration
                // Property groups might be accessible via the table config
                Configuration tableConfig = tableEnv.getConfig().getConfiguration();
                String configValue = tableConfig.getString("kafka.source.bootstrap.servers", null);
                if (configValue == null || configValue.isEmpty()) {
                    configValue = tableConfig.getString("kafka.sink.bootstrap.servers", null);
                }
                if (configValue != null && !configValue.isEmpty()) {
                    bootstrapServers = configValue;
                    LOG.info("Found bootstrap servers from TableEnvironment config: {}", bootstrapServers);
                }
            } catch (Exception e) {
                LOG.warn("Could not read bootstrap servers from TableEnvironment: {}", e.getMessage());
            }
        }
        
        // Load and execute SQL statements
        String sqlContent = loadSQLFile();
        
        // Replace bootstrap.servers placeholder
        sqlContent = sqlContent.replace("${bootstrap.servers}", bootstrapServers);
        
        // Split SQL into individual statements and execute
        // Use a more robust splitting that handles semicolons in string literals
        java.util.List<String> statements = new java.util.ArrayList<>();
        StringBuilder currentStatement = new StringBuilder();
        boolean inSingleQuote = false;
        boolean inDoubleQuote = false;
        
        for (int i = 0; i < sqlContent.length(); i++) {
            char c = sqlContent.charAt(i);
            
            if (c == '\'' && (i == 0 || sqlContent.charAt(i - 1) != '\\')) {
                inSingleQuote = !inSingleQuote;
            } else if (c == '"' && (i == 0 || sqlContent.charAt(i - 1) != '\\')) {
                inDoubleQuote = !inDoubleQuote;
            } else if (c == ';' && !inSingleQuote && !inDoubleQuote) {
                String stmt = currentStatement.toString().trim();
                if (!stmt.isEmpty() && !stmt.startsWith("--")) {
                    statements.add(stmt);
                }
                currentStatement = new StringBuilder();
                continue;
            }
            
            currentStatement.append(c);
        }
        
        // Add the last statement if any
        String lastStmt = currentStatement.toString().trim();
        if (!lastStmt.isEmpty() && !lastStmt.startsWith("--")) {
            statements.add(lastStmt);
        }
        
        for (String statement : statements) {
            // Remove comments
            statement = removeComments(statement);
            if (statement.trim().isEmpty()) {
                continue;
            }
            
            LOG.info("Executing SQL statement: {}", statement.substring(0, Math.min(100, statement.length())) + "...");
            
            try {
                tableEnv.executeSql(statement);
                LOG.info("Successfully executed SQL statement");
            } catch (Exception e) {
                LOG.error("Error executing SQL statement: {}", statement, e);
                throw e;
            }
        }
        
        LOG.info("All SQL statements executed successfully. Starting Flink job...");
        
        // Execute the Flink job
        env.execute("Event Routing Application");
    }
    
    /**
     * Load SQL file from resources
     */
    private static String loadSQLFile() {
        try (InputStream inputStream = EventRoutingApplication.class.getResourceAsStream(SQL_FILE)) {
            if (inputStream == null) {
                throw new RuntimeException("SQL file not found: " + SQL_FILE);
            }
            
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(inputStream, StandardCharsets.UTF_8))) {
                return reader.lines().collect(Collectors.joining("\n"));
            }
        } catch (Exception e) {
            throw new RuntimeException("Failed to load SQL file: " + SQL_FILE, e);
        }
    }
    
    /**
     * Remove SQL comments from statement
     */
    private static String removeComments(String sql) {
        // Remove single-line comments
        sql = sql.replaceAll("--.*", "");
        // Remove multi-line comments
        sql = sql.replaceAll("/\\*[\\s\\S]*?\\*/", "");
        return sql.trim();
    }
}

