package com.example.flink;

import org.apache.flink.api.common.restartstrategy.RestartStrategies;
import org.apache.flink.configuration.Configuration;
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
        // Get bootstrap servers from environment variable or use default
        String bootstrapServers = System.getenv("BOOTSTRAP_SERVERS");
        if (bootstrapServers == null || bootstrapServers.isEmpty()) {
            throw new IllegalArgumentException("BOOTSTRAP_SERVERS environment variable is required");
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
        
        // Load and execute SQL statements
        String sqlContent = loadSQLFile();
        
        // Replace bootstrap.servers placeholder
        sqlContent = sqlContent.replace("${bootstrap.servers}", bootstrapServers);
        
        // Split SQL into individual statements and execute
        String[] statements = sqlContent.split(";");
        
        for (String statement : statements) {
            statement = statement.trim();
            if (statement.isEmpty() || statement.startsWith("--")) {
                continue;
            }
            
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

