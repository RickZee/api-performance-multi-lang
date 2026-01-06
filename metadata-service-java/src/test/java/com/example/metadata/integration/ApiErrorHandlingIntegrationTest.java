package com.example.metadata.integration;

import com.example.metadata.service.GitSyncService;
import com.example.metadata.testutil.TestEventGenerator;
import com.example.metadata.testutil.TestRepoSetup;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.jdbc.Sql;
import org.springframework.test.web.reactive.server.WebTestClient;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.Map;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "spring.main.allow-bean-definition-overriding=true",
    "spring.main.lazy-initialization=true"
})
@Sql(scripts = "/schema-test.sql", executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)
public class ApiErrorHandlingIntegrationTest {
    
    @LocalServerPort
    private int port;
    
    private WebTestClient webTestClient;
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
        registry.add("validation.default-version", () -> "v1");
        registry.add("validation.accepted-versions", () -> "v1");
        registry.add("validation.strict-mode", () -> "true");
        registry.add("test.mode", () -> "true");
    }
    
    @Autowired
    private GitSyncService gitSyncService;
    
    @BeforeEach
    void setUp() throws IOException {
        // Manually sync the repository in test mode since start() is skipped
        try {
            gitSyncService.sync();
        } catch (Exception e) {
            // If sync fails, try to copy files manually
            Path srcPath = Paths.get(testRepoDir);
            Path dstPath = Paths.get(testCacheDir);
            if (Files.exists(srcPath) && !Files.exists(dstPath.resolve("schemas"))) {
                Files.createDirectories(dstPath);
                copyDirectory(srcPath, dstPath);
            }
        }
        
        webTestClient = WebTestClient.bindToServer()
            .baseUrl("http://localhost:" + port)
            .build();
    }
    
    private void copyDirectory(Path source, Path target) throws IOException {
        Files.walk(source).forEach(src -> {
            try {
                Path dest = target.resolve(source.relativize(src));
                if (Files.isDirectory(src)) {
                    if (!Files.exists(dest)) {
                        Files.createDirectories(dest);
                    }
                } else {
                    Files.copy(src, dest, StandardCopyOption.REPLACE_EXISTING);
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
    void testValidateEvent_InvalidJSON() {
        webTestClient.post()
            .uri("/api/v1/validate")
            .header("Content-Type", "application/json")
            .bodyValue("{ invalid json }")
            .exchange()
            .expectStatus().isBadRequest();
    }
    
    @Test
    void testValidateEvent_MissingEventField() {
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue("{}")
            .exchange()
            .expectStatus().isBadRequest();
    }
    
    @Test
    void testValidateEvent_WrongContentType() {
        webTestClient.post()
            .uri("/api/v1/validate")
            .header("Content-Type", "text/plain")
            .bodyValue("{\"event\": {}}")
            .exchange()
            .expectStatus().isBadRequest();
    }
    
    @Test
    void testValidateEvent_WrongHTTPMethod() {
        // GET on POST endpoint
        webTestClient.get()
            .uri("/api/v1/validate")
            .exchange()
            .expectStatus().isEqualTo(405); // Method Not Allowed
        
        // PUT on POST endpoint
        webTestClient.put()
            .uri("/api/v1/validate")
            .bodyValue("{}")
            .exchange()
            .expectStatus().isEqualTo(405);
        
        // DELETE on POST endpoint
        webTestClient.delete()
            .uri("/api/v1/validate")
            .exchange()
            .expectStatus().isEqualTo(405);
    }
    
    @Test
    void testValidateBulkEvents_EmptyArray() {
        webTestClient.post()
            .uri("/api/v1/validate/bulk")
            .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
            .bodyValue("{\"events\": []}")
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.summary.total").isEqualTo(0)
            .jsonPath("$.summary.valid").isEqualTo(0)
            .jsonPath("$.summary.invalid").isEqualTo(0);
    }
    
    @Test
    void testValidateBulkEvents_InvalidJSON() {
        webTestClient.post()
            .uri("/api/v1/validate/bulk")
            .header("Content-Type", "application/json")
            .bodyValue("{ invalid json }")
            .exchange()
            .expectStatus().isBadRequest();
    }
    
    @Test
    void testGetSchema_InvalidVersionFormat() {
        webTestClient.get()
            .uri("/api/v1/schemas/invalid-version")
            .exchange()
            .expectStatus().isNotFound();
    }
    
    @Test
    void testGetSchema_MissingTypeParameter() {
        // Should default to "event" type
        webTestClient.get()
            .uri("/api/v1/schemas/v1")
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.version").isEqualTo("v1")
            .jsonPath("$.schema").exists();
    }
    
    @Test
    void testGetSchema_NonExistentVersion() {
        webTestClient.get()
            .uri("/api/v1/schemas/v999")
            .exchange()
            .expectStatus().isNotFound();
    }
    
    @Test
    void testCreateFilter_InvalidRequest() {
        // Missing required fields
        webTestClient.post()
            .uri("/api/v1/filters?version=v1")
            .bodyValue("{}")
            .exchange()
            .expectStatus().isBadRequest();
        
        // Empty name
        webTestClient.post()
            .uri("/api/v1/filters?version=v1")
            .bodyValue("{\"name\": \"\", \"consumerId\": \"test\", \"outputTopic\": \"test\", \"conditions\": []}")
            .exchange()
            .expectStatus().isBadRequest();
        
        // Missing consumerId
        webTestClient.post()
            .uri("/api/v1/filters?version=v1")
            .bodyValue("{\"name\": \"Test\", \"outputTopic\": \"test\", \"conditions\": []}")
            .exchange()
            .expectStatus().isBadRequest();
        
        // Empty conditions array
        webTestClient.post()
            .uri("/api/v1/filters?version=v1")
            .bodyValue("{\"name\": \"Test\", \"consumerId\": \"test\", \"outputTopic\": \"test\", \"conditions\": []}")
            .exchange()
            .expectStatus().isBadRequest();
    }
    
    @Test
    void testGetFilter_InvalidId() {
        webTestClient.get()
            .uri("/api/v1/filters/../etc/passwd?version=v1")
            .exchange()
            .expectStatus().isNotFound();
    }
    
    @Test
    void testUpdateFilter_NotFound() {
        webTestClient.put()
            .uri("/api/v1/filters/non-existent-id?version=v1")
            .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
            .bodyValue("{\"name\": \"Updated\"}")
            .exchange()
            .expectStatus().isNotFound();
    }
    
    @Test
    void testDeleteFilter_NotFound() {
        webTestClient.delete()
            .uri("/api/v1/filters/non-existent-id?version=v1")
            .exchange()
            .expectStatus().isNotFound();
    }
    
    @Test
    void testGenerateSQL_NotFound() {
        webTestClient.get()
            .uri("/api/v1/filters/non-existent-id/sql?version=v1")
            .exchange()
            .expectStatus().isNotFound();
    }
    
    @Test
    void testApproveFilter_NotFound() {
        webTestClient.patch()
            .uri("/api/v1/filters/non-existent-id?version=v1")
            .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
            .bodyValue("{\"status\": \"approved\", \"approvedBy\": \"user\"}")
            .exchange()
            .expectStatus().isNotFound();
    }
    
    @Test
    void testValidateEvent_ExplicitVersion() {
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        Map<String, Object> request = Map.of(
            "event", event,
            "version", "v1"
        );
        
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(request)
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.valid").isEqualTo(true)
            .jsonPath("$.version").isEqualTo("v1");
    }
    
    @Test
    void testValidateEvent_InvalidVersion() {
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        Map<String, Object> request = Map.of(
            "event", event,
            "version", "v999"
        );
        
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(request)
            .exchange()
            .expectStatus().isEqualTo(500); // Internal server error - version not found
    }
    
    @Test
    void testValidateBulkEvents_MissingEventsField() {
        webTestClient.post()
            .uri("/api/v1/validate/bulk")
            .bodyValue("{}")
            .exchange()
            .expectStatus().isBadRequest();
    }
}
