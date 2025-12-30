package com.example.metadata.controller;

import com.example.metadata.model.*;
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
    private String filterId;
    
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
        if (testRepoDir != null) {
            TestRepoSetup.cleanupTestRepo(testRepoDir);
        }
    }
    
    @Test
    void testCreateFilter() {
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
        
        webTestClient.post()
            .uri("/api/v1/filters?version=v1")
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Filter.class)
            .value(filter -> {
                Assertions.assertNotNull(filter.getId());
                filterId = filter.getId();
            });
    }
    
    @Test
    void testCreateFilter_InvalidRequest() {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("") // Empty name should fail validation
            .consumerId("test-consumer")
            .outputTopic("test-topic")
            .conditions(List.of())
            .build();
        
        webTestClient.post()
            .uri("/api/v1/filters?version=v1")
            .bodyValue(request)
            .exchange()
            .expectStatus().isBadRequest();
    }
    
    @Test
    void testGetFilter_NotFound() {
        webTestClient.get()
            .uri("/api/v1/filters/non-existent-id?version=v1")
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
        
        Filter created = webTestClient.post()
            .uri("/api/v1/filters?version=v1")
            .bodyValue(createRequest)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Filter.class)
            .returnResult()
            .getResponseBody();
        
        // Then validate SQL
        webTestClient.post()
            .uri("/api/v1/filters/{id}/validate?version=v1", created.getId())
            .bodyValue(request)
            .exchange()
            .expectStatus().isOk()
            .expectBody(ValidateSQLResponse.class)
            .value(response -> {
                Assertions.assertTrue(response.isValid());
            });
    }
}
