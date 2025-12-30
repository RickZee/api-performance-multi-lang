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
public class MultiVersionValidationIntegrationTest {
    
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
    void testValidateEvent_DefaultVersion() {
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        Map<String, Object> request = Map.of("event", event);
        // No version specified - should use default
        
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
            .expectStatus().is5xxServerError(); // Version not found
    }
    
    @Test
    void testValidateEvent_LatestVersion() {
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        Map<String, Object> request = Map.of(
            "event", event,
            "version", "latest"
        );
        
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(request)
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.valid").isEqualTo(true)
            .jsonPath("$.version").exists();
    }
}
