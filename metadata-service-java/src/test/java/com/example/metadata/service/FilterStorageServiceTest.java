package com.example.metadata.service;

import com.example.metadata.exception.FilterNotFoundException;
import com.example.metadata.model.*;
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
import java.nio.file.StandardCopyOption;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(properties = {
    "spring.main.allow-bean-definition-overriding=true",
    "spring.main.lazy-initialization=true"
})
public class FilterStorageServiceTest {
    
    @Autowired
    private FilterStorageService filterStorageService;
    
    private static String testRepoDir;
    private static String testCacheDir;
    
    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) throws IOException {
        String tempDir = Files.createTempDirectory("metadata-service-test-").toString();
        testRepoDir = TestRepoSetup.setupTestRepo(tempDir);
        testCacheDir = tempDir + "/cache";
        
        // Copy schemas to cache directory for tests (simulating GitSync behavior)
        Path repoSchemasDir = Paths.get(testRepoDir, "schemas");
        Path cacheSchemasDir = Paths.get(testCacheDir, "schemas");
        if (Files.exists(repoSchemasDir)) {
            Files.createDirectories(cacheSchemasDir);
            copyDirectory(repoSchemasDir, cacheSchemasDir);
        }
        
        // Set test mode to skip GitSync startup
        System.setProperty("test.mode", "true");
        
        registry.add("git.repository", () -> "file://" + testRepoDir);
        registry.add("git.branch", () -> "main");
        registry.add("git.local-cache-dir", () -> testCacheDir);
        registry.add("test.mode", () -> "true");
    }
    
    private static void copyDirectory(Path source, Path target) throws IOException {
        Files.walk(source).forEach(sourcePath -> {
            try {
                Path targetPath = target.resolve(source.relativize(sourcePath));
                if (Files.isDirectory(sourcePath)) {
                    Files.createDirectories(targetPath);
                } else {
                    Files.copy(sourcePath, targetPath, StandardCopyOption.REPLACE_EXISTING);
                }
            } catch (IOException e) {
                throw new RuntimeException(e);
            }
        });
    }
    
    @AfterAll
    static void tearDown() throws IOException {
        if (testRepoDir != null) {
            TestRepoSetup.cleanupTestRepo(testRepoDir);
        }
    }
    
    @Test
    void testCreateFilter() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Test Filter")
            .description("Test Description")
            .consumerId("test-consumer")
            .outputTopic("test-topic")
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarCreated")
                    .valueType("string")
                    .build()
            ))
            .enabled(true)
            .conditionLogic("AND")
            .build();
        
        Filter filter = filterStorageService.create("v1", request);
        
        assertNotNull(filter.getId());
        assertEquals("Test Filter", filter.getName());
        assertEquals("pending_approval", filter.getStatus());
        assertEquals(1, filter.getVersion());
        assertNotNull(filter.getCreatedAt());
        assertNotNull(filter.getUpdatedAt());
    }
    
    @Test
    void testGetFilter() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Get Test Filter")
            .consumerId("test-consumer")
            .outputTopic("test-topic")
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarCreated")
                    .build()
            ))
            .build();
        
        Filter created = filterStorageService.create("v1", request);
        Filter retrieved = filterStorageService.get("v1", created.getId());
        
        assertEquals(created.getId(), retrieved.getId());
        assertEquals(created.getName(), retrieved.getName());
    }
    
    @Test
    void testGetFilter_NotFound() {
        assertThrows(FilterNotFoundException.class, () -> {
            filterStorageService.get("v1", "non-existent-id");
        });
    }
    
    @Test
    void testListFilters() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("List Test Filter")
            .consumerId("test-consumer")
            .outputTopic("test-topic")
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarCreated")
                    .build()
            ))
            .build();
        
        Filter created = filterStorageService.create("v1", request);
        List<Filter> filters = filterStorageService.list("v1");
        
        assertTrue(filters.size() > 0);
        boolean found = filters.stream()
            .anyMatch(f -> f.getId().equals(created.getId()));
        assertTrue(found);
    }
    
    @Test
    void testUpdateFilter() throws IOException {
        CreateFilterRequest createRequest = CreateFilterRequest.builder()
            .name("Update Test Filter")
            .consumerId("test-consumer")
            .outputTopic("test-topic")
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarCreated")
                    .build()
            ))
            .build();
        
        Filter created = filterStorageService.create("v1", createRequest);
        
        UpdateFilterRequest updateRequest = UpdateFilterRequest.builder()
            .name("Updated Filter Name")
            .description("Updated Description")
            .build();
        
        Filter updated = filterStorageService.update("v1", created.getId(), updateRequest);
        
        assertEquals("Updated Filter Name", updated.getName());
        assertEquals("Updated Description", updated.getDescription());
        assertEquals(2, updated.getVersion()); // Version should increment
    }
    
    @Test
    void testApproveFilter() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Approve Test Filter")
            .consumerId("test-consumer")
            .outputTopic("test-topic")
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarCreated")
                    .build()
            ))
            .build();
        
        Filter created = filterStorageService.create("v1", request);
        Filter approved = filterStorageService.approve("v1", created.getId(), "test-user");
        
        assertEquals("approved", approved.getStatus());
        assertEquals("test-user", approved.getApprovedBy());
        assertNotNull(approved.getApprovedAt());
    }
    
    @Test
    void testDeleteFilter() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Delete Test Filter")
            .consumerId("test-consumer")
            .outputTopic("test-topic")
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarCreated")
                    .build()
            ))
            .build();
        
        Filter created = filterStorageService.create("v1", request);
        filterStorageService.delete("v1", created.getId());
        
        assertThrows(FilterNotFoundException.class, () -> {
            filterStorageService.get("v1", created.getId());
        });
    }
}
