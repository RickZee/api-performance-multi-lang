package com.example.metadata.service;

import com.example.metadata.testutil.TestRepoSetup;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import java.io.IOException;
import java.nio.file.Files;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(properties = {
    "spring.main.allow-bean-definition-overriding=true",
    "spring.main.lazy-initialization=true"
})
public class SchemaCacheServiceTest {
    
    @Autowired
    private SchemaCacheService schemaCacheService;
    
    private static String testRepoDir;
    private static String testCacheDir;
    
    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) throws IOException {
        String tempDir = Files.createTempDirectory("metadata-service-test-").toString();
        testRepoDir = TestRepoSetup.setupTestRepo(tempDir);
        testCacheDir = tempDir + "/cache";
        
        // Set test mode to skip GitSync startup
        System.setProperty("test.mode", "true");
        
        registry.add("git.repository", () -> "file://" + testRepoDir);
        registry.add("git.branch", () -> "main");
        registry.add("git.local-cache-dir", () -> testCacheDir);
        registry.add("test.mode", () -> "true");
    }
    
    @AfterAll
    static void tearDown() throws IOException {
        if (testRepoDir != null) {
            TestRepoSetup.cleanupTestRepo(testRepoDir);
        }
    }
    
    @Test
    void testLoadVersion() throws IOException {
        // SchemaCacheService expects the base directory (it will look for schemas subdirectory)
        // Pass testRepoDir directly, as it contains the "schemas" subdirectory
        SchemaCacheService.CachedSchema schema = schemaCacheService.loadVersion("v1", testRepoDir);
        
        assertNotNull(schema);
        assertEquals("v1", schema.getVersion());
        assertNotNull(schema.getEventSchema());
        assertFalse(schema.getEntitySchemas().isEmpty());
        assertTrue(schema.getEntitySchemas().containsKey("car"));
    }
    
    @Test
    void testGetVersions() throws IOException {
        // SchemaCacheService expects the base directory
        List<String> versions = schemaCacheService.getVersions(testRepoDir);
        
        assertNotNull(versions);
        assertTrue(versions.contains("v1"));
    }
    
    @Test
    void testInvalidate() throws IOException {
        schemaCacheService.loadVersion("v1", testRepoDir);
        schemaCacheService.invalidate("v1");
        
        // Cache should be cleared, but loading should still work
        SchemaCacheService.CachedSchema schema = schemaCacheService.loadVersion("v1", testRepoDir);
        assertNotNull(schema);
    }
    
    @Test
    void testInvalidateAll() throws IOException {
        schemaCacheService.loadVersion("v1", testRepoDir);
        schemaCacheService.invalidateAll();
        
        // Cache should be cleared, but loading should still work
        SchemaCacheService.CachedSchema schema = schemaCacheService.loadVersion("v1", testRepoDir);
        assertNotNull(schema);
    }
}
