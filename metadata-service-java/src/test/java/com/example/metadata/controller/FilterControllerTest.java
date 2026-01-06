package com.example.metadata.controller;

import com.example.metadata.model.*;
import com.example.metadata.model.FilterConditions;
import com.example.metadata.testutil.MockJenkinsServer;
import com.example.metadata.testutil.TestRepoSetup;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.jdbc.Sql;
import org.springframework.test.web.reactive.server.WebTestClient;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "spring.main.allow-bean-definition-overriding=true",
    "spring.main.lazy-initialization=true"
})
@AutoConfigureWebTestClient
public class FilterControllerTest {
    
    @Autowired
    private WebTestClient webTestClient;
    
    private ObjectMapper objectMapper = new ObjectMapper();
    private static String testRepoDir;
    private static String testCacheDir;
    private static MockJenkinsServer mockJenkins;
    private static int jenkinsPort;
    private static Path yamlFile;
    private String filterId;
    
    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) throws IOException {
        String tempDir = Files.createTempDirectory("metadata-service-test-").toString();
        testRepoDir = TestRepoSetup.setupTestRepo(tempDir);
        testCacheDir = tempDir + "/cache";
        
        // Start mock Jenkins server
        mockJenkins = new MockJenkinsServer();
        jenkinsPort = mockJenkins.start();
        
        // Set up YAML file path
        yamlFile = Paths.get(tempDir, "filters.yml");
        
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
        
        // Configure Spring YAML path for tests
        registry.add("spring-boot.filters-yaml-path", () -> yamlFile.toString());
        registry.add("spring-boot.backup-enabled", () -> "false");
        
        // Enable Jenkins triggering for tests - use mock server URL
        registry.add("jenkins.enabled", () -> "true");
        registry.add("jenkins.base-url", () -> "http://localhost:" + jenkinsPort);
        registry.add("jenkins.job-name", () -> "filter-integration-tests");
        registry.add("jenkins.trigger-on-create", () -> "true");
        registry.add("jenkins.trigger-on-update", () -> "true");
        registry.add("jenkins.trigger-on-delete", () -> "true");
        registry.add("jenkins.trigger-on-approve", () -> "true");
        registry.add("jenkins.trigger-on-deploy", () -> "true");
    }
    
    @Sql(scripts = "/schema-test.sql", executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)
    
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
        if (mockJenkins != null) {
            mockJenkins.stop();
        }
        if (testRepoDir != null) {
            TestRepoSetup.cleanupTestRepo(testRepoDir);
        }
    }
    
    @Test
    void testCreateFilter() {
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
        
        webTestClient.post()
            .uri("/api/v1/filters?schemaId=test-schema-id&version=v1")
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Filter.class)
            .value(filter -> {
                Assertions.assertNotNull(filter.getId());
                filterId = filter.getId();
                // Default targets should be ["flink", "spring"]
                assertNotNull(filter.getTargets());
                assertTrue(filter.getTargets().contains("flink"));
                assertTrue(filter.getTargets().contains("spring"));
            });
    }
    
    @Test
    void testCreateFilter_WithTargets() {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Single Target Filter")
            .description("Test Description")
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
                        .valueType("string")
                        .build()
                ))
                .build())
            .enabled(true)
            .build();
        
        webTestClient.post()
            .uri("/api/v1/filters?schemaId=test-schema-id&version=v1")
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Filter.class)
            .value(filter -> {
                assertNotNull(filter.getId());
                assertNotNull(filter.getTargets());
                assertEquals(1, filter.getTargets().size());
                assertTrue(filter.getTargets().contains("flink"));
            });
    }
    
    @Test
    void testApproveFilterForTarget_Flink() {
        // First create a filter
        CreateFilterRequest createRequest = CreateFilterRequest.builder()
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
                        .valueType("string")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = webTestClient.post()
            .uri("/api/v1/filters?schemaId=test-schema-id&version=v1")
            .bodyValue(createRequest)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Filter.class)
            .returnResult()
            .getResponseBody();
        
        // Then approve for Flink
        ApproveFilterRequest approveRequest = ApproveFilterRequest.builder()
            .approvedBy("test-user")
            .notes("Approved for Flink")
            .build();
        
        webTestClient.patch()
            .uri("/api/v1/filters/{id}/approvals/flink?schemaId=test-schema-id&version=v1", created.getId())
            .bodyValue(approveRequest)
            .exchange()
            .expectStatus().isOk()
            .expectBody(Filter.class)
            .value(filter -> {
                assertTrue(filter.getApprovedForFlink());
                assertFalse(filter.getApprovedForSpring());
                assertEquals("test-user", filter.getApprovedForFlinkBy());
            });
    }
    
    @Test
    void testApproveFilterForTarget_Spring() {
        // First create a filter
        CreateFilterRequest createRequest = CreateFilterRequest.builder()
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
                        .valueType("string")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = webTestClient.post()
            .uri("/api/v1/filters?schemaId=test-schema-id&version=v1")
            .bodyValue(createRequest)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Filter.class)
            .returnResult()
            .getResponseBody();
        
        // Then approve for Spring
        ApproveFilterRequest approveRequest = ApproveFilterRequest.builder()
            .approvedBy("test-user")
            .build();
        
        webTestClient.patch()
            .uri("/api/v1/filters/{id}/approvals/spring?schemaId=test-schema-id&version=v1", created.getId())
            .bodyValue(approveRequest)
            .exchange()
            .expectStatus().isOk()
            .expectBody(Filter.class)
            .value(filter -> {
                assertFalse(filter.getApprovedForFlink());
                assertTrue(filter.getApprovedForSpring());
            });
    }
    
    @Test
    void testGetFilterApprovals() {
        // First create and approve a filter
        CreateFilterRequest createRequest = CreateFilterRequest.builder()
            .name("Get Approvals Test Filter")
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
                        .valueType("string")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = webTestClient.post()
            .uri("/api/v1/filters?schemaId=test-schema-id&version=v1")
            .bodyValue(createRequest)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Filter.class)
            .returnResult()
            .getResponseBody();
        
        // Approve for Flink
        ApproveFilterRequest approveRequest = ApproveFilterRequest.builder()
            .approvedBy("test-user")
            .build();
        
        webTestClient.patch()
            .uri("/api/v1/filters/{id}/approvals/flink?schemaId=test-schema-id&version=v1", created.getId())
            .bodyValue(approveRequest)
            .exchange()
            .expectStatus().isOk();
        
        // Get approval status
        webTestClient.get()
            .uri("/api/v1/filters/{id}/approvals?schemaId=test-schema-id&version=v1", created.getId())
            .exchange()
            .expectStatus().isOk()
            .expectBody(FilterApprovalStatus.class)
            .value(status -> {
                assertTrue(status.getFlink().getApproved());
                assertFalse(status.getSpring().getApproved());
                assertEquals("test-user", status.getFlink().getApprovedBy());
            });
    }
    
    @Test
    void testApproveFilterForTarget_InvalidTarget() {
        CreateFilterRequest createRequest = CreateFilterRequest.builder()
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
                        .valueType("string")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = webTestClient.post()
            .uri("/api/v1/filters?schemaId=test-schema-id&version=v1")
            .bodyValue(createRequest)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Filter.class)
            .returnResult()
            .getResponseBody();
        
        ApproveFilterRequest approveRequest = ApproveFilterRequest.builder()
            .approvedBy("test-user")
            .build();
        
        // Try to approve for invalid target
        webTestClient.patch()
            .uri("/api/v1/filters/{id}/approvals/invalid?schemaId=test-schema-id&version=v1", created.getId())
            .bodyValue(approveRequest)
            .exchange()
            .expectStatus().isBadRequest();
    }
    
    @Test
    void testGetFilterDeployments() {
        // Create a filter
        CreateFilterRequest createRequest = CreateFilterRequest.builder()
            .name("Get Deployments Test Filter")
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
                        .valueType("string")
                        .build()
                ))
                .build())
            .build();
        
        Filter created = webTestClient.post()
            .uri("/api/v1/filters?schemaId=test-schema-id&version=v1")
            .bodyValue(createRequest)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Filter.class)
            .returnResult()
            .getResponseBody();
        
        // Get deployment status
        webTestClient.get()
            .uri("/api/v1/filters/{id}/deployments?schemaId=test-schema-id&version=v1", created.getId())
            .exchange()
            .expectStatus().isOk()
            .expectBody(FilterDeploymentStatus.class)
            .value(status -> {
                assertFalse(status.getFlink().getDeployed());
                assertFalse(status.getSpring().getDeployed());
            });
    }
    
    @Test
    void testCreateFilter_InvalidRequest() {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("") // Empty name should fail validation
            .consumerGroup("test-consumer")
            .outputTopic("test-topic")
            .conditions(FilterConditions.builder()
                .logic("AND")
                .conditions(List.of())
                .build())
            .build();
        
        webTestClient.post()
            .uri("/api/v1/filters?schemaId=test-schema-id&version=v1")
            .bodyValue(request)
            .exchange()
            .expectStatus().isBadRequest();
    }
    
    @Test
    void testGetFilter_NotFound() {
        webTestClient.get()
            .uri("/api/v1/filters/non-existent-id?schemaId=test-schema-id&version=v1")
            .exchange()
            .expectStatus().isNotFound();
    }
    
    @Test
    void testValidateSQL() {
        ValidateSQLRequest request = ValidateSQLRequest.builder()
            .sql("CREATE TABLE test (id STRING); INSERT INTO test SELECT * FROM source;")
            .build();
        
        // First create a filter
        CreateFilterRequest createRequest = CreateFilterRequest.builder()
            .name("SQL Test Filter")
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
        
        Filter created = webTestClient.post()
            .uri("/api/v1/filters?schemaId=test-schema-id&version=v1")
            .bodyValue(createRequest)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Filter.class)
            .returnResult()
            .getResponseBody();
        
        // Then validate SQL
        webTestClient.post()
            .uri("/api/v1/filters/{id}/validations?schemaId=test-schema-id&version=v1", created.getId())
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(ValidateSQLResponse.class)
            .value(response -> {
                Assertions.assertTrue(response.isValid());
            });
    }
}
