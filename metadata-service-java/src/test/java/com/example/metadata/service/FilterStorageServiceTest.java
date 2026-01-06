package com.example.metadata.service;

import com.example.metadata.exception.FilterNotFoundException;
import com.example.metadata.model.*;
import com.example.metadata.model.FilterConditions;
import com.example.metadata.testutil.TestRepoSetup;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.jdbc.Sql;

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
@Sql(scripts = "/schema-test.sql", executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)
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
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .conditions(FilterConditions.builder()
                .logic("AND")
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarCreated")
                    .valueType("string")
                    .build()
            ))
                .build())
            .enabled(true)
            .build();
        
        Filter filter = filterStorageService.create("test-schema-id", "v1", request);
        
        assertNotNull(filter.getId());
        assertEquals("Test Filter", filter.getName());
        assertEquals("pending_approval", filter.getStatus());
        assertEquals(1, filter.getVersion());
        assertNotNull(filter.getCreatedAt());
        assertNotNull(filter.getUpdatedAt());
        // Default targets should be ["flink", "spring"]
        assertNotNull(filter.getTargets());
        assertTrue(filter.getTargets().contains("flink"));
        assertTrue(filter.getTargets().contains("spring"));
        assertFalse(filter.getApprovedForFlink());
        assertFalse(filter.getApprovedForSpring());
        assertFalse(filter.getDeployedToFlink());
        assertFalse(filter.getDeployedToSpring());
    }
    
    @Test
    void testGetFilter() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Get Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .conditions(FilterConditions.builder()
                .logic("AND")
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarCreated")
                    .build()
            ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", request);
        Filter retrieved = filterStorageService.get("test-schema-id", "v1", created.getId());
        
        assertEquals(created.getId(), retrieved.getId());
        assertEquals(created.getName(), retrieved.getName());
    }
    
    @Test
    void testGetFilter_NotFound() {
        assertThrows(FilterNotFoundException.class, () -> {
            filterStorageService.get("test-schema-id", "v1", "non-existent-id");
        });
    }
    
    @Test
    void testListFilters() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("List Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .conditions(FilterConditions.builder()
                .logic("AND")
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarCreated")
                    .build()
            ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", request);
        List<Filter> filters = filterStorageService.list("test-schema-id", "v1");
        
        assertTrue(filters.size() > 0);
        boolean found = filters.stream()
            .anyMatch(f -> f.getId().equals(created.getId()));
        assertTrue(found);
    }
    
    @Test
    void testUpdateFilter() throws IOException {
        CreateFilterRequest createRequest = CreateFilterRequest.builder()
            .name("Update Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .conditions(FilterConditions.builder()
                .logic("AND")
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarCreated")
                    .build()
            ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", createRequest);
        
        UpdateFilterRequest updateRequest = UpdateFilterRequest.builder()
            .name("Updated Filter Name")
            .description("Updated Description")
            .build();
        
        Filter updated = filterStorageService.update("test-schema-id", "v1", created.getId(), updateRequest);
        
        assertEquals("Updated Filter Name", updated.getName());
        assertEquals("Updated Description", updated.getDescription());
        // Version is automatically incremented by Hibernate @Version on save
        // After save, version should be incremented, but we need to reload to see it
        Filter reloaded = filterStorageService.get("test-schema-id", "v1", updated.getId());
        assertTrue(reloaded.getVersion() >= updated.getVersion()); // Version should increment
    }
    
    @Test
    void testApproveFilterForAllTargets() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Approve All Targets Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .targets(List.of("flink", "spring"))
            .conditions(FilterConditions.builder()
                .logic("AND")
                .conditions(List.of(
                    FilterCondition.builder()
                        .field("event_type")
                        .operator("equals")
                        .value("CarCreated")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", request);
        Filter approvedFlink = filterStorageService.approveForTarget("test-schema-id", "v1", created.getId(), "flink", "test-user");
        Filter approvedBoth = filterStorageService.approveForTarget("test-schema-id", "v1", created.getId(), "spring", "test-user");
        
        assertEquals("approved", approvedBoth.getStatus());
        assertTrue(approvedBoth.getApprovedForFlink());
        assertTrue(approvedBoth.getApprovedForSpring());
        assertEquals("test-user", approvedBoth.getApprovedForFlinkBy());
        assertEquals("test-user", approvedBoth.getApprovedForSpringBy());
    }
    
    @Test
    void testCreateFilter_WithTargets() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Single Target Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .targets(List.of("flink"))
            .conditions(FilterConditions.builder()
                .logic("AND")
                .conditions(List.of(
                    FilterCondition.builder()
                        .field("event_type")
                        .operator("equals")
                        .value("CarCreated")
                        .build()
                ))
                .build())
            .build();
        
        Filter filter = filterStorageService.create("test-schema-id", "v1", request);
        
        assertNotNull(filter.getTargets());
        assertEquals(1, filter.getTargets().size());
        assertTrue(filter.getTargets().contains("flink"));
        assertFalse(filter.getTargets().contains("spring"));
    }
    
    @Test
    void testApproveForTarget_Flink() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Approve Target Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .targets(List.of("flink", "spring"))
            .conditions(FilterConditions.builder()
                .logic("AND")
                .conditions(List.of(
                    FilterCondition.builder()
                        .field("event_type")
                        .operator("equals")
                        .value("CarCreated")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", request);
        Filter approved = filterStorageService.approveForTarget("test-schema-id", "v1", created.getId(), "flink", "test-user");
        
        assertTrue(approved.getApprovedForFlink());
        assertFalse(approved.getApprovedForSpring());
        assertNotNull(approved.getApprovedForFlinkAt());
        assertEquals("test-user", approved.getApprovedForFlinkBy());
        // Status should still be pending_approval since spring is not approved
        assertEquals("pending_approval", approved.getStatus());
    }
    
    @Test
    void testApproveForTarget_Spring() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Approve Spring Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .targets(List.of("flink", "spring"))
            .conditions(FilterConditions.builder()
                .logic("AND")
                .conditions(List.of(
                    FilterCondition.builder()
                        .field("event_type")
                        .operator("equals")
                        .value("CarCreated")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", request);
        Filter approved = filterStorageService.approveForTarget("test-schema-id", "v1", created.getId(), "spring", "test-user");
        
        assertFalse(approved.getApprovedForFlink());
        assertTrue(approved.getApprovedForSpring());
        assertNotNull(approved.getApprovedForSpringAt());
        assertEquals("test-user", approved.getApprovedForSpringBy());
    }
    
    @Test
    void testApproveForTarget_Both() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Approve Both Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .targets(List.of("flink", "spring"))
            .conditions(FilterConditions.builder()
                .logic("AND")
                .conditions(List.of(
                    FilterCondition.builder()
                        .field("event_type")
                        .operator("equals")
                        .value("CarCreated")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", request);
        Filter approvedFlink = filterStorageService.approveForTarget("test-schema-id", "v1", created.getId(), "flink", "test-user");
        Filter approvedBoth = filterStorageService.approveForTarget("test-schema-id", "v1", created.getId(), "spring", "test-user");
        
        assertTrue(approvedBoth.getApprovedForFlink());
        assertTrue(approvedBoth.getApprovedForSpring());
        assertEquals("approved", approvedBoth.getStatus());
    }
    
    @Test
    void testApproveForTarget_InvalidTarget() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Invalid Target Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .targets(List.of("flink"))
            .conditions(FilterConditions.builder()
                .logic("AND")
                .conditions(List.of(
                    FilterCondition.builder()
                        .field("event_type")
                        .operator("equals")
                        .value("CarCreated")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", request);
        
        assertThrows(IllegalArgumentException.class, () -> {
            filterStorageService.approveForTarget("test-schema-id", "v1", created.getId(), "invalid", "test-user");
        });
    }
    
    @Test
    void testApproveForTarget_TargetNotInFilter() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Single Target Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .targets(List.of("flink"))
            .conditions(FilterConditions.builder()
                .logic("AND")
                .conditions(List.of(
                    FilterCondition.builder()
                        .field("event_type")
                        .operator("equals")
                        .value("CarCreated")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", request);
        
        assertThrows(IOException.class, () -> {
            filterStorageService.approveForTarget("test-schema-id", "v1", created.getId(), "spring", "test-user");
        });
    }
    
    @Test
    void testUpdateDeploymentForTarget_Flink() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Deploy Flink Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .targets(List.of("flink", "spring"))
            .conditions(FilterConditions.builder()
                .logic("AND")
                .conditions(List.of(
                    FilterCondition.builder()
                        .field("event_type")
                        .operator("equals")
                        .value("CarCreated")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", request);
        filterStorageService.approveForTarget("test-schema-id", "v1", created.getId(), "flink", "test-user");
        
        List<String> statementIds = List.of("stmt-123", "stmt-456");
        Filter deployed = filterStorageService.updateDeploymentForTarget("test-schema-id", "v1", created.getId(), "flink", "deployed", statementIds, null);
        
        assertTrue(deployed.getDeployedToFlink());
        assertFalse(deployed.getDeployedToSpring());
        assertNotNull(deployed.getDeployedToFlinkAt());
        assertEquals(statementIds, deployed.getFlinkStatementIds());
    }
    
    @Test
    void testUpdateDeploymentForTarget_Spring() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Deploy Spring Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .targets(List.of("flink", "spring"))
            .conditions(FilterConditions.builder()
                .logic("AND")
                .conditions(List.of(
                    FilterCondition.builder()
                        .field("event_type")
                        .operator("equals")
                        .value("CarCreated")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", request);
        Filter approved = filterStorageService.approveForTarget("test-schema-id", "v1", created.getId(), "spring", "test-user");
        
        Filter deployed = filterStorageService.updateDeploymentForTarget("test-schema-id", "v1", approved.getId(), "spring", "deployed", null, null);
        
        assertFalse(deployed.getDeployedToFlink());
        assertTrue(deployed.getDeployedToSpring());
        assertNotNull(deployed.getDeployedToSpringAt());
    }
    
    @Test
    void testUpdateDeploymentForTarget_Both() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Deploy Both Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .targets(List.of("flink", "spring"))
            .conditions(FilterConditions.builder()
                .logic("AND")
                .conditions(List.of(
                    FilterCondition.builder()
                        .field("event_type")
                        .operator("equals")
                        .value("CarCreated")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", request);
        Filter approvedFlink = filterStorageService.approveForTarget("test-schema-id", "v1", created.getId(), "flink", "test-user");
        Filter approvedBoth = filterStorageService.approveForTarget("test-schema-id", "v1", created.getId(), "spring", "test-user");
        
        List<String> statementIds = List.of("stmt-123");
        Filter deployedFlink = filterStorageService.updateDeploymentForTarget("test-schema-id", "v1", approvedBoth.getId(), "flink", "deployed", statementIds, null);
        Filter deployedBoth = filterStorageService.updateDeploymentForTarget("test-schema-id", "v1", deployedFlink.getId(), "spring", "deployed", null, null);
        
        assertTrue(deployedBoth.getDeployedToFlink());
        assertTrue(deployedBoth.getDeployedToSpring());
        assertEquals("deployed", deployedBoth.getStatus());
    }
    
    @Test
    void testUpdateDeploymentForTarget_Failed() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Failed Deployment Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .targets(List.of("flink"))
            .conditions(FilterConditions.builder()
                .logic("AND")
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarCreated")
                    .build()
            ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", request);
        Filter approved = filterStorageService.approveForTarget("test-schema-id", "v1", created.getId(), "flink", "test-user");
        
        Filter failed = filterStorageService.updateDeploymentForTarget("test-schema-id", "v1", approved.getId(), "flink", "failed", null, "Deployment error");
        
        assertFalse(failed.getDeployedToFlink());
        assertEquals("failed", failed.getStatus());
        assertEquals("Deployment error", failed.getFlinkDeploymentError());
    }
    
    @Test
    void testDeleteFilter() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Delete Test Filter")
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .conditions(FilterConditions.builder()
                .logic("AND")
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarCreated")
                    .build()
            ))
                .build())
            .build();
        
        Filter created = filterStorageService.create("test-schema-id", "v1", request);
        filterStorageService.delete("test-schema-id", "v1", created.getId());
        
        assertThrows(FilterNotFoundException.class, () -> {
            filterStorageService.get("test-schema-id", "v1", created.getId());
        });
    }
}
