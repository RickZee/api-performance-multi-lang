package com.example.metadata.integration;

import com.example.metadata.config.AppConfig;
import com.example.metadata.model.CreateFilterRequest;
import com.example.metadata.model.Filter;
import com.example.metadata.model.FilterCondition;
import com.example.metadata.model.UpdateFilterRequest;
import com.example.metadata.service.FilterStorageService;
import com.example.metadata.service.SpringYamlGeneratorService;
import com.example.metadata.service.SpringYamlWriterService;
import com.example.metadata.testutil.TestRepoSetup;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.jdbc.Sql;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(properties = {
    "spring.main.lazy-initialization=true"
})
class SpringYamlUpdateIntegrationTest {

    @TempDir
    Path tempDir;

    @Autowired
    private FilterStorageService filterStorageService;

    @Autowired
    private SpringYamlGeneratorService springYamlGeneratorService;

    @Autowired
    private SpringYamlWriterService springYamlWriterService;

    @Autowired
    private AppConfig appConfig;

    private Path yamlFile;
    private static String testRepoDir;
    private static String testCacheDir;

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) throws IOException {
        String tempDirPath = Files.createTempDirectory("metadata-service-yaml-test-").toString();
        testRepoDir = TestRepoSetup.setupTestRepo(tempDirPath);
        testCacheDir = tempDirPath + "/cache";
        
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
    }
    
    @Sql(scripts = "/schema-test.sql", executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)

    @BeforeEach
    void setUp() throws IOException {
        // Set up cache directory structure (required for FilterStorageService)
        Path cachePath = Path.of(testCacheDir);
        Path v1Path = cachePath.resolve("v1");
        Path schemasPath = v1Path.resolve("schemas");
        Files.createDirectories(schemasPath);
        
        // Copy schemas from test repo to cache if they exist
        Path repoSchemasPath = Path.of(testRepoDir).resolve("schemas");
        if (Files.exists(repoSchemasPath)) {
            Files.walk(repoSchemasPath).forEach(source -> {
                try {
                    Path dest = schemasPath.resolve(repoSchemasPath.relativize(source));
                    if (Files.isDirectory(source)) {
                        Files.createDirectories(dest);
                    } else {
                        Files.copy(source, dest, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                    }
                } catch (IOException e) {
                    throw new RuntimeException(e);
                }
            });
        }
        
        // Set YAML file path in config
        yamlFile = tempDir.resolve("filters.yml");
        appConfig.getSpringBoot().setFiltersYamlPath(yamlFile.toString());
        appConfig.getSpringBoot().setBackupEnabled(true);
        appConfig.getSpringBoot().setBackupDir(tempDir.resolve("backups").toString());
        
        // Refresh the writer service config to pick up changes
        springYamlWriterService.refreshConfig();
    }

    @Test
    void testCreateFilterUpdatesYaml() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Test Filter")
            .description("Test description")
            .consumerId("test-consumer")
            .outputTopic("filtered-test-events")
            .enabled(true)
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("TestEvent")
                    .valueType("string")
                    .build()
            ))
            .conditionLogic("AND")
            .build();

        Filter filter = filterStorageService.create("v1", request);
        
        // Manually trigger YAML update (simulating what FilterController does)
        List<Filter> filters = filterStorageService.list("v1");
        String yaml = springYamlGeneratorService.generateYaml(filters);
        springYamlWriterService.writeFiltersYaml(yaml);

        assertThat(Files.exists(yamlFile)).isTrue();
        String yamlContent = Files.readString(yamlFile);
        assertThat(yamlContent).contains("id: " + filter.getId());
        assertThat(yamlContent).contains("name: Test Filter");
        assertThat(yamlContent).contains("outputTopic: filtered-test-events-spring");
    }

    @Test
    void testUpdateFilterUpdatesYaml() throws IOException {
        // Create initial filter
        CreateFilterRequest createRequest = CreateFilterRequest.builder()
            .name("Original Filter")
            .consumerId("test-consumer")
            .outputTopic("filtered-original")
            .enabled(true)
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("OriginalEvent")
                    .valueType("string")
                    .build()
            ))
            .build();

        Filter filter = filterStorageService.create("v1", createRequest);
        
        // Update filter
        UpdateFilterRequest updateRequest = UpdateFilterRequest.builder()
            .name("Updated Filter")
            .description("Updated description")
            .build();

        filterStorageService.update("v1", filter.getId(), updateRequest);
        
        // Manually trigger YAML update
        List<Filter> filters = filterStorageService.list("v1");
        String yaml = springYamlGeneratorService.generateYaml(filters);
        springYamlWriterService.writeFiltersYaml(yaml);

        String yamlContent = Files.readString(yamlFile);
        assertThat(yamlContent).contains("name: Updated Filter");
        assertThat(yamlContent).contains("description: Updated description");
    }

    @Test
    void testDeleteFilterUpdatesYaml() throws IOException {
        // Create two filters
        CreateFilterRequest request1 = CreateFilterRequest.builder()
            .name("Filter 1")
            .consumerId("consumer-1")
            .outputTopic("filtered-1")
            .enabled(true)
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("Event1")
                    .valueType("string")
                    .build()
            ))
            .build();

        CreateFilterRequest request2 = CreateFilterRequest.builder()
            .name("Filter 2")
            .consumerId("consumer-2")
            .outputTopic("filtered-2")
            .enabled(true)
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("Event2")
                    .valueType("string")
                    .build()
            ))
            .build();

        Filter filter1 = filterStorageService.create("v1", request1);
        Filter filter2 = filterStorageService.create("v1", request2);
        
        // Generate initial YAML
        List<Filter> filters = filterStorageService.list("v1");
        String yaml = springYamlGeneratorService.generateYaml(filters);
        springYamlWriterService.writeFiltersYaml(yaml);
        
        String initialYaml = Files.readString(yamlFile);
        assertThat(initialYaml).contains("id: " + filter1.getId());
        assertThat(initialYaml).contains("id: " + filter2.getId());
        
        // Delete one filter
        filterStorageService.delete("v1", filter1.getId());
        
        // Regenerate YAML
        filters = filterStorageService.list("v1");
        yaml = springYamlGeneratorService.generateYaml(filters);
        springYamlWriterService.writeFiltersYaml(yaml);
        
        String updatedYaml = Files.readString(yamlFile);
        assertThat(updatedYaml).doesNotContain("id: " + filter1.getId());
        assertThat(updatedYaml).contains("id: " + filter2.getId());
    }

    @Test
    void testYamlFormatMatchesExpectedStructure() throws IOException {
        CreateFilterRequest request = CreateFilterRequest.builder()
            .name("Format Test Filter")
            .description("Testing YAML format")
            .consumerId("test-consumer")
            .outputTopic("filtered-format-test")
            .enabled(true)
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("FormatTest")
                    .valueType("string")
                    .build()
            ))
            .conditionLogic("AND")
            .build();

        // Create filter (result not used, but operation is verified via YAML)
        filterStorageService.create("v1", request);
        
        List<Filter> filters = filterStorageService.list("v1");
        String yaml = springYamlGeneratorService.generateYaml(filters);
        springYamlWriterService.writeFiltersYaml(yaml);

        String yamlContent = Files.readString(yamlFile);
        
        // Verify YAML structure
        assertThat(yamlContent).contains("# Generated Spring Boot Filter Configuration");
        assertThat(yamlContent).contains("filters:");
        assertThat(yamlContent).contains("  - id:");
        assertThat(yamlContent).contains("    name:");
        assertThat(yamlContent).contains("    outputTopic:");
        assertThat(yamlContent).contains("    conditionLogic:");
        assertThat(yamlContent).contains("    enabled:");
        assertThat(yamlContent).contains("    conditions:");
        assertThat(yamlContent).contains("      - field:");
        assertThat(yamlContent).contains("        operator:");
        assertThat(yamlContent).contains("        value:");
    }

    @Test
    void testMultipleFiltersInYaml() throws IOException {
        // Create multiple filters
        for (int i = 1; i <= 3; i++) {
            CreateFilterRequest request = CreateFilterRequest.builder()
                .name("Filter " + i)
                .consumerId("consumer-" + i)
                .outputTopic("filtered-" + i)
                .enabled(true)
                .conditions(List.of(
                    FilterCondition.builder()
                        .field("event_type")
                        .operator("equals")
                        .value("Event" + i)
                        .valueType("string")
                        .build()
                ))
                .build();
            // Create filter (result not used, but operation is verified via YAML)
            filterStorageService.create("v1", request);
        }
        
        List<Filter> filters = filterStorageService.list("v1");
        String yaml = springYamlGeneratorService.generateYaml(filters);
        springYamlWriterService.writeFiltersYaml(yaml);

        String yamlContent = Files.readString(yamlFile);
        
        // Verify all filters are present
        assertThat(yamlContent).contains("Filter 1");
        assertThat(yamlContent).contains("Filter 2");
        assertThat(yamlContent).contains("Filter 3");
    }
}

