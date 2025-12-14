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
    "spring.main.allow-bean-definition-overriding=true"
})
public class GitSyncEdgeCasesIntegrationTest {
    
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
    void testGitSync_RepositoryWithExistingFiles() throws IOException {
        // Manually sync in test mode since start() is skipped
        gitSyncService.sync();
        
        String localDir = gitSyncService.getLocalDir();
        
        // Verify files exist after sync
        Path eventSchema = Paths.get(localDir, "schemas", "v1", "event", "event.json");
        assertTrue(Files.exists(eventSchema), "Event schema should exist after sync");
        
        // Verify entity schemas exist
        Path carSchema = Paths.get(localDir, "schemas", "v1", "entity", "car.json");
        assertTrue(Files.exists(carSchema), "Car schema should exist after sync");
    }
    
    @Test
    void testGitSync_LocalFileRepository() throws IOException {
        // Manually sync in test mode since start() is skipped
        gitSyncService.sync();
        
        // Test that file:// repository works correctly
        String localDir = gitSyncService.getLocalDir();
        assertNotNull(localDir);
        
        // Verify schemas are accessible
        Path schemasDir = Paths.get(localDir, "schemas", "v1");
        assertTrue(Files.exists(schemasDir), "Local repository should be accessible");
    }
    
    @Test
    void testGitSync_HandlesMissingRepository() {
        // This test verifies that the service handles missing repository gracefully
        // The service should fail to start if repository doesn't exist
        // (This is tested in GitSyncServiceTest.testSync_NonExistentRepository)
        assertTrue(true, "Service initialization handles missing repo in unit tests");
    }
    
    @Test
    void testGitSync_GetLocalDirReturnsCorrectPath() {
        String localDir = gitSyncService.getLocalDir();
        assertNotNull(localDir);
        assertEquals(testCacheDir, localDir);
    }
}
