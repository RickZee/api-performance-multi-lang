package com.loadtest.dsql;

import com.loadtest.dsql.auth.IamTokenGenerator;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;

public class TestConnection {
    private static final Logger LOGGER = LoggerFactory.getLogger(TestConnection.class);
    
    public static void main(String[] args) {
        String dsqlHost = System.getenv("DSQL_HOST");
        String portStr = System.getenv("DSQL_PORT");
        String databaseName = System.getenv("DATABASE_NAME");
        String iamUsername = System.getenv("IAM_USERNAME");
        String region = System.getenv("AWS_REGION");
        
        if (dsqlHost == null || portStr == null || databaseName == null || iamUsername == null || region == null) {
            LOGGER.error("Missing required environment variables");
            System.exit(1);
        }
        
        int port = Integer.parseInt(portStr);
        
        LOGGER.info("Testing DSQL connection...");
        LOGGER.info("Host: {}", dsqlHost);
        LOGGER.info("Port: {}", port);
        LOGGER.info("Database: {}", databaseName);
        LOGGER.info("IAM Username: {}", iamUsername);
        LOGGER.info("Region: {}", region);
        
        IamTokenGenerator tokenGenerator = new IamTokenGenerator(dsqlHost, port, iamUsername, region);
        
        try {
            String token = tokenGenerator.getToken();
            LOGGER.info("Token generated successfully (length: {})", token.length());
            LOGGER.info("Token preview: {}", token.length() > 200 ? token.substring(0, 200) + "..." : token);
            
            // Build JDBC URL exactly like debezium connector
            String jdbcUrl = String.format("jdbc:postgresql://%s:%d/%s?user=%s&password=%s&sslmode=require",
                    dsqlHost, port, databaseName, iamUsername, token);
            
            LOGGER.info("Attempting connection...");
            LOGGER.debug("JDBC URL (password hidden): jdbc:postgresql://{}:{}/{}/?user={}&password=***&sslmode=require",
                    dsqlHost, port, databaseName, iamUsername);
            
            try (Connection conn = DriverManager.getConnection(jdbcUrl)) {
                LOGGER.info("✅ Connection successful!");
                
                try (Statement stmt = conn.createStatement();
                     ResultSet rs = stmt.executeQuery("SELECT version()")) {
                    if (rs.next()) {
                        String version = rs.getString(1);
                        LOGGER.info("Database version: {}", version);
                    }
                }
                
                LOGGER.info("✅ Test completed successfully!");
            } catch (Exception e) {
                LOGGER.error("❌ Connection failed: {}", e.getMessage(), e);
                System.exit(1);
            }
        } catch (Exception e) {
            LOGGER.error("❌ Failed to generate token: {}", e.getMessage(), e);
            System.exit(1);
        } finally {
            tokenGenerator.close();
        }
    }
}

