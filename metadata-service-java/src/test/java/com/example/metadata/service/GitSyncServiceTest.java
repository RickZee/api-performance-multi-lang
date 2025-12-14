package com.example.metadata.service;

import com.example.metadata.config.AppConfig;
import com.example.metadata.testutil.TestRepoSetup;
import org.junit.jupiter.api.*;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

import static org.junit.jupiter.api.Assertions.*;

class GitSyncServiceTest {
    
    private static String testRepoDir;
    private static String testCacheDir;
    private GitSyncService gitSyncService;
    
    @BeforeAll
    static void setupTestRepo() throws IOException {
        String tempDir = Files.createTempDirectory("metadata-service-test-").toString();
        testRepoDir = TestRepoSetup.setupTestRepo(tempDir);
        testCacheDir = tempDir + "/cache";
    }
    
    @AfterAll
    static void tearDown() throws IOException {
        if (testRepoDir != null) {
            TestRepoSetup.cleanupTestRepo(testRepoDir);
        }
    }
    
    @BeforeEach
    void setUp() {
        AppConfig appConfig = new AppConfig();
        AppConfig.GitConfig gitConfig = new AppConfig.GitConfig();
        gitConfig.setRepository("file://" + testRepoDir);
        gitConfig.setBranch("main");
        gitConfig.setPullInterval("PT5M");
        gitConfig.setLocalCacheDir(testCacheDir);
        appConfig.setGit(gitConfig);
        
        gitSyncService = new GitSyncService(appConfig);
    }
    
    @AfterEach
    void tearDownService() {
        if (gitSyncService != null) {
            gitSyncService.stop();
        }
    }
    
    @Test
    void testStart() {
        assertDoesNotThrow(() -> {
            gitSyncService.start();
        });
        
        String localDir = gitSyncService.getLocalDir();
        assertNotNull(localDir);
        assertTrue(Files.exists(Paths.get(localDir)));
    }
    
    @Test
    void testSync_LocalRepository() throws IOException {
        gitSyncService.start();
        
        String localDir = gitSyncService.getLocalDir();
        Path schemasDir = Paths.get(localDir, "schemas", "v1");
        
        assertTrue(Files.exists(schemasDir), "Schemas should be synced");
        assertTrue(Files.exists(schemasDir.resolve("event")), "Event directory should exist");
    }
    
    @Test
    void testGetLocalDir() {
        gitSyncService.start();
        
        String localDir = gitSyncService.getLocalDir();
        assertNotNull(localDir);
        assertEquals(testCacheDir, localDir);
    }
    
    @Test
    void testStop() {
        gitSyncService.start();
        
        assertDoesNotThrow(() -> {
            gitSyncService.stop();
        });
    }
    
    @Test
    void testSync_RepositoryWithExistingFiles() throws IOException {
        // First sync
        gitSyncService.start();
        String localDir = gitSyncService.getLocalDir();
        
        // Verify files exist
        Path eventSchema = Paths.get(localDir, "schemas", "v1", "event", "event.json");
        assertTrue(Files.exists(eventSchema), "Event schema should exist after sync");
        
        // Stop and restart
        gitSyncService.stop();
        gitSyncService.start();
        
        // Verify files still exist (should use existing files for local repo)
        assertTrue(Files.exists(eventSchema), "Event schema should still exist after restart");
    }
    
    @Test
    void testSync_NonExistentRepository() {
        // Clear test.mode to ensure exception is thrown
        String originalTestMode = System.getProperty("test.mode");
        try {
            System.clearProperty("test.mode");
            
            AppConfig appConfig = new AppConfig();
            AppConfig.GitConfig gitConfig = new AppConfig.GitConfig();
            gitConfig.setRepository("file:///non/existent/path");
            gitConfig.setBranch("main");
            gitConfig.setPullInterval("PT5M");
            gitConfig.setLocalCacheDir(testCacheDir);
            appConfig.setGit(gitConfig);
            
            GitSyncService service = new GitSyncService(appConfig);
            
            assertThrows(Exception.class, () -> {
                service.start();
            });
        } finally {
            // Restore original test.mode
            if (originalTestMode != null) {
                System.setProperty("test.mode", originalTestMode);
            }
        }
    }
    
    @Test
    void testSync_EmptyRepository() throws IOException {
        // Create empty repository
        String emptyRepoDir = Files.createTempDirectory("empty-repo-").toString();
        
        AppConfig appConfig = new AppConfig();
        AppConfig.GitConfig gitConfig = new AppConfig.GitConfig();
        gitConfig.setRepository("file://" + emptyRepoDir);
        gitConfig.setBranch("main");
        gitConfig.setPullInterval("PT5M");
        gitConfig.setLocalCacheDir(testCacheDir);
        appConfig.setGit(gitConfig);
        
        GitSyncService service = new GitSyncService(appConfig);
        
        // Should handle empty repository gracefully
        assertDoesNotThrow(() -> {
            service.start();
        });
        
        service.stop();
        
        // Cleanup
        Files.deleteIfExists(Paths.get(emptyRepoDir));
    }
}
