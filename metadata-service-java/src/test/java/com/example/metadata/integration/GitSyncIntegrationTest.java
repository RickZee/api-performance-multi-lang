package com.example.metadata.integration;

import com.example.metadata.service.GitSyncService;
import com.example.metadata.testutil.TestRepoSetup;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(properties = {
    "spring.main.allow-bean-definition-overriding=true",
    "spring.main.lazy-initialization=true"
})
public class GitSyncIntegrationTest {
    
    @Autowired
    private GitSyncService gitSyncService;
    
    private static String testRepoDir;
    private static String testCacheDir;
    
    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) throws IOException {
        String tempDir = Files.createTempDirectory("metadata-service-test-").toString();
        testRepoDir = TestRepoSetup.setupTestRepo(tempDir);
        testCacheDir = tempDir + "/cache";
        
        // Set test mode to skip GitSync startup
        System.setProperty("test.mode", "true");
        
        // Configure H2 in-memory database for tests
        registry.add("spring.datasource.url", () -> "jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE");
        registry.add("spring.datasource.driver-class-name", () -> "org.h2.Driver");
        registry.add("spring.datasource.username", () -> "sa");
        registry.add("spring.datasource.password", () -> "");
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
        registry.add("spring.jpa.database-platform", () -> "org.hibernate.dialect.H2Dialect");
        registry.add("spring.flyway.enabled", () -> "false");
        
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
    void testGitSync_InitialSync() throws IOException {
        // Manually sync in test mode since start() is skipped
        gitSyncService.sync();
        
        String localDir = gitSyncService.getLocalDir();
        assertNotNull(localDir);
        
        // Verify schemas are available
        Path schemasDir = Paths.get(localDir, "schemas", "v1");
        assertTrue(Files.exists(schemasDir), "Schemas directory should exist");
        
        Path eventSchema = schemasDir.resolve("event").resolve("event.json");
        assertTrue(Files.exists(eventSchema), "Event schema should exist");
    }
    
    @Test
    void testGitSync_GetLocalDir() {
        String localDir = gitSyncService.getLocalDir();
        assertNotNull(localDir);
        assertFalse(localDir.isEmpty());
    }
    
    @Test
    void testGitSync_LocalRepository() throws IOException {
        // Manually sync in test mode since start() is skipped
        gitSyncService.sync();
        
        // Test that local file:// repository works
        String localDir = gitSyncService.getLocalDir();
        Path schemasDir = Paths.get(localDir, "schemas", "v1");
        
        assertTrue(Files.exists(schemasDir), "Local repository should be accessible");
        assertTrue(Files.exists(schemasDir.resolve("event")), "Event directory should exist");
        assertTrue(Files.exists(schemasDir.resolve("entity")), "Entity directory should exist");
    }
    
    @Test
    void testGitSync_Stop() {
        // Test that stop doesn't throw exceptions
        assertDoesNotThrow(() -> {
            // Service is managed by Spring, but we can verify stop method exists
            gitSyncService.stop();
        });
    }
}
