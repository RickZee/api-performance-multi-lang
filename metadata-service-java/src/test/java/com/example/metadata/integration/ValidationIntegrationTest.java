package com.example.metadata.integration;

import com.example.metadata.service.GitSyncService;
import com.example.metadata.testutil.TestEventGenerator;
import com.example.metadata.testutil.TestRepoSetup;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.reactive.server.WebTestClient;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.List;
import java.util.Map;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "spring.main.allow-bean-definition-overriding=true",
    "spring.main.lazy-initialization=true"
})
public class ValidationIntegrationTest {
    
    @LocalServerPort
    private int port;
    
    private WebTestClient webTestClient;
    private ObjectMapper objectMapper = new ObjectMapper();
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
        // This ensures the cache directory has the schema files
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
    void testValidateEvent_Valid() {
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        Map<String, Object> request = Map.of("event", event);
        
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(request)
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.valid").isEqualTo(true)
            .jsonPath("$.version").exists();
    }
    
    @Test
    void testValidateEvent_Invalid() {
        Map<String, Object> event = TestEventGenerator.invalidEventMissingRequired();
        Map<String, Object> request = Map.of("event", event);
        
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(request)
            .exchange()
            .expectStatus().isEqualTo(422) // Unprocessable Entity
            .expectBody()
            .jsonPath("$.valid").isEqualTo(false)
            .jsonPath("$.errors").isArray()
            .jsonPath("$.errors").isArray()
            .jsonPath("$.errors.length()").value(org.hamcrest.Matchers.greaterThan(0));
    }
    
    @Test
    void testValidateBulkEvents() {
        Map<String, Object> validEvent = TestEventGenerator.validCarCreatedEvent();
        Map<String, Object> invalidEvent = TestEventGenerator.invalidEventMissingRequired();
        
        Map<String, Object> request = Map.of(
            "events", List.of(validEvent, invalidEvent)
        );
        
        webTestClient.post()
            .uri("/api/v1/validate/bulk")
            .bodyValue(request)
            .exchange()
            .expectStatus().isEqualTo(422) // Unprocessable Entity (strict mode)
            .expectBody()
            .jsonPath("$.summary.total").isEqualTo(2)
            .jsonPath("$.summary.valid").isEqualTo(1)
            .jsonPath("$.summary.invalid").isEqualTo(1)
            .jsonPath("$.results.length()").isEqualTo(2)
            .jsonPath("$.results[0].valid").isEqualTo(true)
            .jsonPath("$.results[1].valid").isEqualTo(false);
    }
    
    @Test
    void testGetVersions() {
        webTestClient.get()
            .uri("/api/v1/schemas/versions")
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.versions").isArray()
            .jsonPath("$.versions[0]").isEqualTo("v1");
    }
    
    @Test
    void testGetSchema() {
        webTestClient.get()
            .uri("/api/v1/schemas/v1?type=event")
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.version").isEqualTo("v1")
            .jsonPath("$.schema").exists();
    }
    
    @Test
    void testGetSchema_Entity() {
        webTestClient.get()
            .uri("/api/v1/schemas/v1?type=car")
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.version").isEqualTo("v1")
            .jsonPath("$.schema").exists();
    }
    
    @Test
    void testHealth() {
        webTestClient.get()
            .uri("/api/v1/health")
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.status").isEqualTo("healthy");
    }
}
