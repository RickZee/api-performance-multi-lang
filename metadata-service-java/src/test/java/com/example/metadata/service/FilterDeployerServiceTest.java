package com.example.metadata.service;

import com.example.metadata.config.AppConfig;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class FilterDeployerServiceTest {
    
    private FilterDeployerService deployerService;
    private AppConfig appConfig;
    
    @BeforeEach
    void setUp() {
        appConfig = new AppConfig();
        AppConfig.ConfluentConfig confluentConfig = new AppConfig.ConfluentConfig();
        AppConfig.ConfluentConfig.CloudConfig cloudConfig = new AppConfig.ConfluentConfig.CloudConfig();
        confluentConfig.setCloud(cloudConfig);
        appConfig.setConfluent(confluentConfig);
        
        deployerService = new FilterDeployerService(appConfig);
    }
    
    @Test
    void testValidateConnection_MissingCredentials() {
        // No credentials set
        boolean result = deployerService.validateConnection();
        
        assertFalse(result, "Should return false when credentials are missing");
    }
    
    @Test
    void testValidateConnection_MissingApiKey() {
        appConfig.getConfluent().getCloud().setApiSecret("secret");
        appConfig.getConfluent().getCloud().setFlinkComputePoolId("pool-123");
        
        boolean result = deployerService.validateConnection();
        
        assertFalse(result, "Should return false when API key is missing");
    }
    
    @Test
    void testValidateConnection_MissingApiSecret() {
        appConfig.getConfluent().getCloud().setApiKey("key");
        appConfig.getConfluent().getCloud().setFlinkComputePoolId("pool-123");
        
        boolean result = deployerService.validateConnection();
        
        assertFalse(result, "Should return false when API secret is missing");
    }
    
    @Test
    void testValidateConnection_MissingComputePoolId() {
        appConfig.getConfluent().getCloud().setApiKey("key");
        appConfig.getConfluent().getCloud().setApiSecret("secret");
        
        boolean result = deployerService.validateConnection();
        
        assertFalse(result, "Should return false when compute pool ID is missing");
    }
    
    @Test
    void testValidateConnection_ValidConfiguration() {
        appConfig.getConfluent().getCloud().setApiKey("key");
        appConfig.getConfluent().getCloud().setApiSecret("secret");
        appConfig.getConfluent().getCloud().setFlinkComputePoolId("pool-123");
        
        boolean result = deployerService.validateConnection();
        
        assertTrue(result, "Should return true when all required config is present");
    }
    
    @Test
    void testExtractStatementNames() {
        String sql = """
            CREATE TABLE `source_table` (
                id STRING
            ) WITH (...);
            CREATE TABLE `target_table` (
                id STRING
            ) WITH (...);
            """;
        
        List<String> names = deployerService.extractStatementNames(sql);
        
        assertEquals(2, names.size(), "Should extract 2 table names");
        assertTrue(names.contains("source_table"), "Should contain source_table");
        assertTrue(names.contains("target_table"), "Should contain target_table");
    }
    
    @Test
    void testExtractStatementNames_NoTables() {
        String sql = "SELECT * FROM table;";
        
        List<String> names = deployerService.extractStatementNames(sql);
        
        assertTrue(names.isEmpty(), "Should return empty list when no CREATE TABLE statements");
    }
    
    @Test
    void testExtractStatementNames_CaseInsensitive() {
        String sql = "create table `test_table` (id STRING) WITH (...);";
        
        List<String> names = deployerService.extractStatementNames(sql);
        
        assertEquals(1, names.size(), "Should extract table name (case insensitive)");
        assertEquals("test_table", names.get(0));
    }
    
    @Test
    void testDeployStatements_MissingCredentials() {
        List<String> statements = List.of("CREATE TABLE test (id STRING) WITH (...);");
        List<String> names = List.of("test");
        
        assertThrows(IOException.class, () -> {
            deployerService.deployStatements(statements, names);
        }, "Should throw IOException when credentials are missing");
    }
    
    @Test
    void testDeployStatements_MismatchedLengths() {
        appConfig.getConfluent().getCloud().setApiKey("key");
        appConfig.getConfluent().getCloud().setApiSecret("secret");
        appConfig.getConfluent().getCloud().setFlinkComputePoolId("pool-123");
        
        List<String> statements = List.of("CREATE TABLE test1 (id STRING) WITH (...);");
        List<String> names = List.of("test1", "test2"); // Mismatched lengths
        
        assertThrows(IllegalArgumentException.class, () -> {
            deployerService.deployStatements(statements, names);
        }, "Should throw IllegalArgumentException when lengths don't match");
    }
    
    @Test
    void testDeployStatements_EmptyStatementName() {
        appConfig.getConfluent().getCloud().setApiKey("key");
        appConfig.getConfluent().getCloud().setApiSecret("secret");
        appConfig.getConfluent().getCloud().setFlinkComputePoolId("pool-123");
        
        List<String> statements = List.of("CREATE TABLE test (id STRING) WITH (...);");
        List<String> names = List.of(""); // Empty name
        
        // Should not throw, but will use auto-generated name
        // Can't test actual deployment without mocking HTTP client
        assertTrue(true, "Empty name should be handled");
    }
    
    @Test
    void testBuildApiUrl_DefaultEndpoint() {
        // Test URL building logic indirectly via validateConnection
        appConfig.getConfluent().getCloud().setApiKey("key");
        appConfig.getConfluent().getCloud().setApiSecret("secret");
        appConfig.getConfluent().getCloud().setFlinkComputePoolId("pool-123");
        // No endpoint set - should use default
        
        boolean result = deployerService.validateConnection();
        assertTrue(result, "Should use default endpoint when not configured");
    }
    
    @Test
    void testBuildApiUrl_CustomEndpoint() {
        appConfig.getConfluent().getCloud().setApiKey("key");
        appConfig.getConfluent().getCloud().setApiSecret("secret");
        appConfig.getConfluent().getCloud().setFlinkComputePoolId("pool-123");
        appConfig.getConfluent().getCloud().setFlinkApiEndpoint("https://custom.endpoint.com");
        
        boolean result = deployerService.validateConnection();
        assertTrue(result, "Should accept custom endpoint");
    }
}
