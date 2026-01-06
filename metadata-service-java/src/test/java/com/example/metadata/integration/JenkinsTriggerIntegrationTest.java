package com.example.metadata.integration;

import com.example.metadata.config.AppConfig;
import com.example.metadata.model.*;
import com.example.metadata.service.JenkinsTriggerService;
import com.example.metadata.testutil.MockJenkinsServer;
import com.example.metadata.testutil.TestRepoSetup;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
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

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Integration tests for Jenkins CI/CD triggering when filters are changed via API.
 * 
 * These tests verify that:
 * - Jenkins builds are triggered on filter create/update/delete/approve/deploy
 * - Build parameters are correctly passed to Jenkins
 * - Jenkins triggering is configurable and can be disabled
 * - Errors in Jenkins triggering don't fail filter operations
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "spring.main.lazy-initialization=true"
})
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class JenkinsTriggerIntegrationTest {

    @Autowired
    private WebTestClient webTestClient;

    @Autowired
    private JenkinsTriggerService jenkinsTriggerService;

    @Autowired
    private AppConfig appConfig;

    private static String testRepoDir;
    private static String testCacheDir;
    private static String filterId;
    private static MockJenkinsServer mockJenkins;
    private static int jenkinsPort;

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) throws IOException {
        String tempDir = Files.createTempDirectory("metadata-service-test-").toString();
        testRepoDir = TestRepoSetup.setupTestRepo(tempDir);
        testCacheDir = tempDir + "/cache";
        
        // Start mock Jenkins server
        mockJenkins = new MockJenkinsServer();
        jenkinsPort = mockJenkins.start();
        
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
        
        // Enable Jenkins triggering for tests - use mock server URL
        registry.add("jenkins.enabled", () -> "true");
        registry.add("jenkins.base-url", () -> "http://localhost:" + jenkinsPort);
        registry.add("jenkins.job-name", () -> "test-filter-integration-tests");
        registry.add("jenkins.trigger-on-create", () -> "true");
        registry.add("jenkins.trigger-on-update", () -> "true");
        registry.add("jenkins.trigger-on-delete", () -> "true");
        registry.add("jenkins.trigger-on-approve", () -> "true");
        registry.add("jenkins.trigger-on-deploy", () -> "true");
    }
    
    @Sql(scripts = "/schema-test.sql", executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)

    @BeforeEach
    void setUp() throws IOException {
        // Reset mock Jenkins captured requests before each test
        if (mockJenkins != null) {
            mockJenkins.reset();
        }
        
        // Manually sync the repository in test mode
        Path srcPath = Paths.get(testRepoDir);
        Path dstPath = Paths.get(testCacheDir);
        if (Files.exists(srcPath) && !Files.exists(dstPath.resolve("schemas"))) {
            Files.createDirectories(dstPath);
            copyDirectory(srcPath, dstPath);
        }
    }

    private static void copyDirectory(Path source, Path target) throws IOException {
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
        // Stop mock Jenkins server
        if (mockJenkins != null) {
            mockJenkins.stop();
        }
        
        if (testRepoDir != null) {
            TestRepoSetup.cleanupTestRepo(testRepoDir);
        }
    }

    @Test
    @Order(1)
    @DisplayName("Jenkins triggering should be enabled when configured")
    void testJenkinsTriggeringIsEnabled() {
        assertThat(jenkinsTriggerService.isEnabled()).isTrue();
    }

    @Test
    @Order(2)
    @DisplayName("Creating a filter should trigger Jenkins build")
    void testCreateFilterTriggersJenkins() throws InterruptedException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Test Filter for Jenkins")
            .description("Test filter to verify Jenkins triggering")
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

        Filter created = webTestClient.post()
            .uri("/api/v1/filters?version=v1")
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Filter.class)
            .returnResult()
            .getResponseBody();

        assertThat(created).isNotNull();
        assertThat(created.getId()).isNotNull();
        filterId = created.getId();
        
        // Wait a bit for async Jenkins call to complete
        Thread.sleep(500);
        
        // Verify Jenkins was actually called
        assertThat(mockJenkins.wasTriggered("create")).isTrue();
        assertThat(mockJenkins.wasTriggeredWith("create", created.getId(), "v1")).isTrue();
        
        // Verify build parameters
        List<MockJenkinsServer.BuildRequest> requests = mockJenkins.getCapturedRequests("create");
        assertThat(requests).hasSize(1);
        MockJenkinsServer.BuildRequest buildRequest = requests.get(0);
        assertThat(buildRequest.getJobName()).isEqualTo("test-filter-integration-tests");
        assertThat(buildRequest.getFilterEventType()).isEqualTo("create");
        assertThat(buildRequest.getFilterId()).isEqualTo(created.getId());
        assertThat(buildRequest.getFilterVersion()).isEqualTo("v1");
    }

    @Test
    @Order(3)
    @DisplayName("Updating a filter should trigger Jenkins build")
    void testUpdateFilterTriggersJenkins() throws InterruptedException {
        UpdateFilterRequest request = UpdateFilterRequest.builder()
            .name("Updated Test Filter")
            .description("Updated description")
            .enabled(true)
            .build();

        webTestClient.put()
            .uri("/api/v1/filters/{id}?version=v1", filterId)
            .bodyValue(request)
            .exchange()
            .expectStatus().isOk()
            .expectBody(Filter.class)
            .value(filter -> {
                assertThat(filter.getName()).isEqualTo("Updated Test Filter");
            });
        
        // Wait for async Jenkins call
        Thread.sleep(500);
        
        // Verify Jenkins was called for update
        assertThat(mockJenkins.wasTriggered("update")).isTrue();
        assertThat(mockJenkins.wasTriggeredWith("update", filterId, "v1")).isTrue();
    }

    @Test
    @Order(4)
    @DisplayName("Approving a filter should trigger Jenkins build with approver info")
    void testApproveFilterTriggersJenkins() throws InterruptedException {
        UpdateFilterStatusRequest request = UpdateFilterStatusRequest.builder()
            .status("approved")
            .approvedBy("test-reviewer@example.com")
            .build();

        webTestClient.patch()
            .uri("/api/v1/filters/{id}?version=v1", filterId)
            .bodyValue(request)
            .exchange()
            .expectStatus().isOk()
            .expectBody(Filter.class)
            .value(filter -> {
                assertThat(filter.getStatus()).isEqualTo("approved");
                assertThat(filter.getApprovedBy()).isEqualTo("test-reviewer@example.com");
            });
        
        // Wait for async Jenkins call
        Thread.sleep(500);
        
        // Verify Jenkins was called for approve
        assertThat(mockJenkins.wasTriggered("approve")).isTrue();
        assertThat(mockJenkins.wasTriggeredWith("approve", filterId, "v1")).isTrue();
    }

    @Test
    @Order(5)
    @DisplayName("Deleting a filter should trigger Jenkins build")
    void testDeleteFilterTriggersJenkins() throws InterruptedException {
        // First create a filter to delete
        CreateFilterRequest createRequest = CreateFilterRequest.builder()
            .name("Filter to Delete")
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
            .build();

        Filter toDelete = webTestClient.post()
            .uri("/api/v1/filters?version=v1")
            .bodyValue(createRequest)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(Filter.class)
            .returnResult()
            .getResponseBody();

        // Wait for create trigger
        Thread.sleep(500);
        mockJenkins.reset(); // Clear create trigger

        // Now delete it
        webTestClient.delete()
            .uri("/api/v1/filters/{id}?version=v1", toDelete.getId())
            .exchange()
            .expectStatus().isNoContent();

        // Wait for async Jenkins call
        Thread.sleep(500);

        // Verify it's deleted
        webTestClient.get()
            .uri("/api/v1/filters/{id}?version=v1", toDelete.getId())
            .exchange()
            .expectStatus().isNotFound();
        
        // Verify Jenkins was called for delete
        assertThat(mockJenkins.wasTriggered("delete")).isTrue();
        assertThat(mockJenkins.wasTriggeredWith("delete", toDelete.getId(), "v1")).isTrue();
    }

    @Test
    @DisplayName("Jenkins triggering should be disabled when configuration is disabled")
    void testJenkinsTriggeringCanBeDisabled() {
        // Temporarily disable Jenkins
        appConfig.getJenkins().setEnabled(false);
        
        try {
            assertThat(jenkinsTriggerService.isEnabled()).isFalse();
        } finally {
            // Re-enable for other tests
            appConfig.getJenkins().setEnabled(true);
        }
    }

    @Test
    @DisplayName("Filter operations should succeed even if Jenkins triggering fails")
    void testFilterOperationsSucceedWhenJenkinsFails() {
        // Configure mock Jenkins to simulate failure
        mockJenkins.setSimulateFailure(true, 500);
        
        try {
            CreateFilterRequest request = CreateFilterRequest.builder()
                .name("Filter with Jenkins Failure")
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
                .build();

            // Filter creation should still succeed even if Jenkins fails
            Filter created = webTestClient.post()
                .uri("/api/v1/filters?version=v1")
                .bodyValue(request)
                .exchange()
                .expectStatus().isCreated()
                .expectBody(Filter.class)
                .returnResult()
                .getResponseBody();

            assertThat(created).isNotNull();
            assertThat(created.getId()).isNotNull();
            
            // Clean up
            webTestClient.delete()
                .uri("/api/v1/filters/{id}?version=v1", created.getId())
                .exchange()
                .expectStatus().isNoContent();
        } finally {
            // Restore normal operation
            mockJenkins.setSimulateFailure(false, 200);
        }
    }

    @Test
    @DisplayName("Event-specific triggering can be disabled")
    void testEventSpecificTriggeringCanBeDisabled() {
        // Disable triggering for create events
        boolean originalValue = appConfig.getJenkins().isTriggerOnCreate();
        appConfig.getJenkins().setTriggerOnCreate(false);
        
        try {
            CreateFilterRequest request = CreateFilterRequest.builder()
                .name("Filter without Create Trigger")
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
                .build();

            // Filter should still be created
            Filter created = webTestClient.post()
                .uri("/api/v1/filters?version=v1")
                .bodyValue(request)
                .exchange()
                .expectStatus().isCreated()
                .expectBody(Filter.class)
                .returnResult()
                .getResponseBody();

            assertThat(created).isNotNull();
            
            // Clean up
            webTestClient.delete()
                .uri("/api/v1/filters/{id}?version=v1", created.getId())
                .exchange()
                .expectStatus().isNoContent();
        } finally {
            // Restore original value
            appConfig.getJenkins().setTriggerOnCreate(originalValue);
        }
    }
}

