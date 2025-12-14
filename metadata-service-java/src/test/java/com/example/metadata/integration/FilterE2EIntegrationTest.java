package com.example.metadata.integration;

import com.example.metadata.config.AppConfig;
import com.example.metadata.model.*;
import com.example.metadata.service.*;
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
    "spring.main.allow-bean-definition-overriding=true"
})
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
public class FilterE2EIntegrationTest {
    
    @LocalServerPort
    private int port;
    
    @Autowired
    private FilterStorageService filterStorageService;
    
    @Autowired
    private FilterGeneratorService filterGeneratorService;
    
    @Autowired
    private GitSyncService gitSyncService;
    
    private WebTestClient webTestClient;
    private ObjectMapper objectMapper = new ObjectMapper();
    private static String testRepoDir;
    private static String testCacheDir;
    private static String filterId;
    
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
    @Order(1)
    void testCreateFilter() {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Service Events for Dealer 001")
            .description("Routes service events from Tesla Service Center SF to dedicated topic")
            .consumerId("dealer-001-service-consumer")
            .outputTopic("filtered-service-events-dealer-001")
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarServiceDone")
                    .valueType("string")
                    .logicalOperator("AND")
                    .build(),
                FilterCondition.builder()
                    .field("header_data.dealerId")
                    .operator("equals")
                    .value("DEALER-001")
                    .valueType("string")
                    .logicalOperator("AND")
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
                Assertions.assertEquals("pending_approval", filter.getStatus());
                filterId = filter.getId();
            });
    }
    
    @Test
    @Order(2)
    void testGenerateSQL() {
        webTestClient.post()
            .uri("/api/v1/filters/{id}/generate?version=v1", filterId)
            .exchange()
            .expectStatus().isOk()
            .expectBody(GenerateSQLResponse.class)
            .value(response -> {
                Assertions.assertTrue(response.isValid());
                Assertions.assertNotNull(response.getSql());
                Assertions.assertEquals(2, response.getStatements().size());
                Assertions.assertTrue(response.getSql().contains("CREATE TABLE"));
                Assertions.assertTrue(response.getSql().contains("INSERT INTO"));
                Assertions.assertTrue(response.getSql().contains("DEALER-001"));
            });
    }
    
    @Test
    @Order(3)
    void testValidateSQL() throws IOException {
        Filter filter = filterStorageService.get("v1", filterId);
        GenerateSQLResponse sqlResponse = filterGeneratorService.generateSQL(filter);
        
        ValidateSQLRequest request = ValidateSQLRequest.builder()
            .sql(sqlResponse.getSql())
            .build();
        
        webTestClient.post()
            .uri("/api/v1/filters/{id}/validate?version=v1", filterId)
            .bodyValue(request)
            .exchange()
            .expectStatus().isOk()
            .expectBody(ValidateSQLResponse.class)
            .value(response -> {
                Assertions.assertTrue(response.isValid());
            });
    }
    
    @Test
    @Order(4)
    void testApproveFilter() {
        ApproveFilterRequest request = ApproveFilterRequest.builder()
            .approvedBy("test-user")
            .build();
        
        webTestClient.post()
            .uri("/api/v1/filters/{id}/approve?version=v1", filterId)
            .bodyValue(request)
            .exchange()
            .expectStatus().isOk()
            .expectBody(Filter.class)
            .value(filter -> {
                Assertions.assertEquals("approved", filter.getStatus());
                Assertions.assertEquals("test-user", filter.getApprovedBy());
                Assertions.assertNotNull(filter.getApprovedAt());
            });
    }
    
    @Test
    @Order(5)
    void testGetFilterStatus() {
        webTestClient.get()
            .uri("/api/v1/filters/{id}/status?version=v1", filterId)
            .exchange()
            .expectStatus().isOk()
            .expectBody(FilterStatusResponse.class)
            .value(response -> {
                Assertions.assertEquals(filterId, response.getFilterId());
                Assertions.assertEquals("approved", response.getStatus());
            });
    }
    
    @Test
    @Order(6)
    void testListFilters() {
        webTestClient.get()
            .uri("/api/v1/filters?version=v1")
            .exchange()
            .expectStatus().isOk()
            .expectBodyList(Filter.class)
            .value(filters -> {
                Assertions.assertTrue(filters.size() > 0);
                boolean found = filters.stream()
                    .anyMatch(f -> f.getId().equals(filterId));
                Assertions.assertTrue(found);
            });
    }
    
    @Test
    @Order(7)
    void testUpdateFilter() {
        UpdateFilterRequest request = UpdateFilterRequest.builder()
            .name("Updated Service Events for Dealer 001")
            .description("Updated description")
            .build();
        
        webTestClient.put()
            .uri("/api/v1/filters/{id}?version=v1", filterId)
            .bodyValue(request)
            .exchange()
            .expectStatus().isOk()
            .expectBody(Filter.class)
            .value(filter -> {
                Assertions.assertEquals("Updated Service Events for Dealer 001", filter.getName());
            });
    }
    
    @Test
    @Order(8)
    void testDeleteFilter() {
        webTestClient.delete()
            .uri("/api/v1/filters/{id}?version=v1", filterId)
            .exchange()
            .expectStatus().isNoContent();
        
        // Verify deletion
        webTestClient.get()
            .uri("/api/v1/filters/{id}?version=v1", filterId)
            .exchange()
            .expectStatus().isNotFound();
    }
}
