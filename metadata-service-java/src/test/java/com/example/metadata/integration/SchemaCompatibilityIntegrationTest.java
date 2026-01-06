package com.example.metadata.integration;

import com.example.metadata.service.CompatibilityService;
import com.example.metadata.service.GitSyncService;
import com.example.metadata.service.SchemaCacheService;
import com.example.metadata.testutil.SchemaChangeHelper;
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
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Comprehensive integration tests for schema compatibility checking.
 * Tests breaking and non-breaking schema changes, Git sync integration,
 * and validation behavior during schema evolution.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "spring.main.allow-bean-definition-overriding=true",
    "spring.main.lazy-initialization=true"
})
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class SchemaCompatibilityIntegrationTest {
    
    @LocalServerPort
    private int port;
    
    @Autowired
    private WebTestClient webTestClient;
    
    @Autowired
    private GitSyncService gitSyncService;
    
    @Autowired
    private SchemaCacheService schemaCacheService;
    
    @Autowired
    private CompatibilityService compatibilityService;
    
    private static String testRepoDir;
    private static String testCacheDir;
    private static final ObjectMapper objectMapper = new ObjectMapper();
    
    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) throws IOException {
        String tempDir = Files.createTempDirectory("metadata-service-compatibility-test-").toString();
        testRepoDir = TestRepoSetup.setupTestRepo(tempDir);
        testCacheDir = tempDir + "/cache";
        
        System.setProperty("test.mode", "true");
        
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
    
    @BeforeEach
    void setUp() throws IOException {
        // Sync repository to ensure cache is up to date
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
        
        // Invalidate cache to ensure fresh schema load
        schemaCacheService.invalidateAll();
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
        if (testRepoDir != null) {
            TestRepoSetup.cleanupTestRepo(testRepoDir);
        }
    }
    
    // ========== Non-Breaking Changes ==========
    
    @Test
    @Order(1)
    @DisplayName("Non-Breaking: Add optional field - old events still validate")
    void testNonBreaking_AddOptionalField() throws IOException {
        // Get original event schema
        Path eventSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event.json");
        String originalContent = Files.readString(eventSchemaPath);
        
        // Add optional field to schema
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event.json", schema -> {
            SchemaChangeHelper.addOptionalField(schema, "metadata", "object");
        });
        
        // Sync to update cache
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Old event should still validate (doesn't have new field)
        Map<String, Object> oldEvent = TestEventGenerator.validCarCreatedEvent();
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", oldEvent))
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.valid").isEqualTo(true);
        
        // Restore original schema
        Files.writeString(eventSchemaPath, originalContent);
    }
    
    @Test
    @Order(2)
    @DisplayName("Non-Breaking: Remove optional field - events without field still validate")
    void testNonBreaking_RemoveOptionalField() throws IOException {
        // First add an optional field, then remove it
        Path eventSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event.json");
        String originalContent = Files.readString(eventSchemaPath);
        
        // Add optional field first
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event.json", schema -> {
            SchemaChangeHelper.addOptionalField(schema, "tempField", "string");
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Now remove it
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event.json", schema -> {
            SchemaChangeHelper.removeOptionalField(schema, "tempField");
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Event without the field should still validate
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", event))
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.valid").isEqualTo(true);
        
        // Restore original schema
        Files.writeString(eventSchemaPath, originalContent);
    }
    
    @Test
    @Order(3)
    @DisplayName("Non-Breaking: Make required field optional - events with/without field validate")
    void testNonBreaking_MakeRequiredFieldOptional() throws IOException {
        // Modify event-header.json to make a required field optional
        Path headerSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event-header.json");
        String originalContent = Files.readString(headerSchemaPath);
        
        // Make savedDate optional (it's currently required)
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event-header.json", schema -> {
            SchemaChangeHelper.makeRequiredFieldOptional(schema, "savedDate");
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Event with savedDate should validate
        Map<String, Object> eventWithField = TestEventGenerator.validCarCreatedEvent();
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", eventWithField))
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.valid").isEqualTo(true);
        
        // Event without savedDate should also validate (now optional)
        @SuppressWarnings("unchecked")
        Map<String, Object> eventHeader = (Map<String, Object>) eventWithField.get("eventHeader");
        eventHeader.remove("savedDate");
        
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", eventWithField))
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.valid").isEqualTo(true);
        
        // Restore original schema
        Files.writeString(headerSchemaPath, originalContent);
    }
    
    @Test
    @Order(4)
    @DisplayName("Non-Breaking: Add enum value - old enum values still validate")
    void testNonBreaking_AddEnumValue() throws IOException {
        Path headerSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event-header.json");
        String originalContent = Files.readString(headerSchemaPath);
        
        // Add new enum value
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event-header.json", schema -> {
            SchemaChangeHelper.addEnumValue(schema, "eventType", "NewEventType");
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Old enum value should still validate
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", event))
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.valid").isEqualTo(true);
        
        // Restore original schema
        Files.writeString(headerSchemaPath, originalContent);
    }
    
    @Test
    @Order(5)
    @DisplayName("Non-Breaking: Relax maximum constraint - old values still validate")
    void testNonBreaking_RelaxMaximumConstraint() throws IOException {
        Path carSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "entity", "car.json");
        String originalContent = Files.readString(carSchemaPath);
        
        // Relax maximum constraint on year (increase from 2030 to 2050)
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/entity/car.json", schema -> {
            SchemaChangeHelper.relaxMaximumConstraint(schema, "year", 2050);
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Old value (2024) should still validate
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", event))
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.valid").isEqualTo(true);
        
        // Restore original schema
        Files.writeString(carSchemaPath, originalContent);
    }
    
    @Test
    @Order(7)
    @DisplayName("Non-Breaking: Relax minimum constraint - old values still validate")
    void testNonBreaking_RelaxMinimumConstraint() throws IOException {
        Path carSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "entity", "car.json");
        String originalContent = Files.readString(carSchemaPath);
        
        // Relax minimum constraint on mileage (decrease from 0 to -100, effectively removing constraint)
        // Note: mileage currently has minimum: 0, so we'll decrease it
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/entity/car.json", schema -> {
            SchemaChangeHelper.relaxMinimumConstraint(schema, "mileage", -100);
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Old value (0) should still validate
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", event))
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.valid").isEqualTo(true);
        
        // Restore original schema
        Files.writeString(carSchemaPath, originalContent);
    }
    
    @Test
    @Order(8)
    @DisplayName("Non-Breaking: Change additionalProperties false to true - events with extra fields validate")
    void testNonBreaking_AllowAdditionalProperties() throws IOException {
        Path eventSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event.json");
        String originalContent = Files.readString(eventSchemaPath);
        
        // Change additionalProperties from false to true
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event.json", schema -> {
            SchemaChangeHelper.allowAdditionalProperties(schema);
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Event with extra field should now validate
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        event.put("extraField", "allowed");
        
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", event))
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.valid").isEqualTo(true);
        
        // Restore original schema
        Files.writeString(eventSchemaPath, originalContent);
    }
    
    // ========== Breaking Changes ==========
    
    @Test
    @Order(10)
    @DisplayName("Breaking: Remove required field - compatibility service detects breaking change")
    void testBreaking_RemoveRequiredField() throws IOException {
        Path headerSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event-header.json");
        String originalContent = Files.readString(headerSchemaPath);
        
        @SuppressWarnings("unchecked")
        Map<String, Object> oldSchema = objectMapper.readValue(originalContent, Map.class);
        
        // Remove required field (eventName) - removing from both required and properties
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event-header.json", schema -> {
            SchemaChangeHelper.removeRequiredField(schema, "eventName");
        });
        
        String newContent = Files.readString(headerSchemaPath);
        @SuppressWarnings("unchecked")
        Map<String, Object> newSchema = objectMapper.readValue(newContent, Map.class);
        
        // Compatibility service should detect this as breaking
        CompatibilityService.CompatibilityResult result = compatibilityService.checkCompatibility(oldSchema, newSchema);
        
        assertThat(result.isCompatible()).isFalse();
        assertThat(result.getBreakingChanges()).isNotEmpty();
        assertThat(result.getBreakingChanges()).anyMatch(change -> 
            change.contains("eventName") && change.contains("removed"));
        
        // Restore original schema
        Files.writeString(headerSchemaPath, originalContent);
    }
    
    @Test
    @Order(11)
    @DisplayName("Breaking: Add required field - old events fail validation")
    void testBreaking_AddRequiredField() throws IOException {
        Path headerSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event-header.json");
        String originalContent = Files.readString(headerSchemaPath);
        
        // Add new required field
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event-header.json", schema -> {
            SchemaChangeHelper.addRequiredField(schema, "newRequiredField", "string");
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Old event without new field should fail validation
        Map<String, Object> oldEvent = TestEventGenerator.validCarCreatedEvent();
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", oldEvent))
            .exchange()
            .expectStatus().isEqualTo(422)
            .expectBody()
            .jsonPath("$.valid").isEqualTo(false);
        
        // Restore original schema
        Files.writeString(headerSchemaPath, originalContent);
    }
    
    @Test
    @Order(12)
    @DisplayName("Breaking: Change field type - events with old type fail validation")
    void testBreaking_ChangeFieldType() throws IOException {
        Path carSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "entity", "car.json");
        String originalContent = Files.readString(carSchemaPath);
        
        // Change year from integer to string
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/entity/car.json", schema -> {
            SchemaChangeHelper.changeFieldType(schema, "year", "string");
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Event with integer year should fail validation
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", event))
            .exchange()
            .expectStatus().isEqualTo(422)
            .expectBody()
            .jsonPath("$.valid").isEqualTo(false);
        
        // Restore original schema
        Files.writeString(carSchemaPath, originalContent);
    }
    
    @Test
    @Order(13)
    @DisplayName("Breaking: Remove enum value - events with removed enum fail validation")
    void testBreaking_RemoveEnumValue() throws IOException {
        Path headerSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event-header.json");
        String originalContent = Files.readString(headerSchemaPath);
        
        // Remove CarCreated from enum
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event-header.json", schema -> {
            SchemaChangeHelper.removeEnumValue(schema, "eventType", "CarCreated");
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Event with CarCreated should fail validation
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", event))
            .exchange()
            .expectStatus().isEqualTo(422)
            .expectBody()
            .jsonPath("$.valid").isEqualTo(false);
        
        // Restore original schema
        Files.writeString(headerSchemaPath, originalContent);
    }
    
    @Test
    @Order(14)
    @DisplayName("Breaking: Tighten maximum constraint - out-of-range values fail validation")
    void testBreaking_TightenMaximumConstraint() throws IOException {
        Path carSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "entity", "car.json");
        String originalContent = Files.readString(carSchemaPath);
        
        // Tighten maximum constraint on year (decrease from 2030 to 2020)
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/entity/car.json", schema -> {
            SchemaChangeHelper.tightenMaximumConstraint(schema, "year", 2020);
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Event with year 2024 should fail validation (exceeds new max of 2020)
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", event))
            .exchange()
            .expectStatus().isEqualTo(422)
            .expectBody()
            .jsonPath("$.valid").isEqualTo(false);
        
        // Restore original schema
        Files.writeString(carSchemaPath, originalContent);
    }
    
    @Test
    @Order(16)
    @DisplayName("Breaking: Tighten minimum constraint - out-of-range values fail validation")
    void testBreaking_TightenMinimumConstraint() throws IOException {
        Path carSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "entity", "car.json");
        String originalContent = Files.readString(carSchemaPath);
        
        // Tighten minimum constraint on mileage (increase from 0 to 1000)
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/entity/car.json", schema -> {
            SchemaChangeHelper.tightenMinimumConstraint(schema, "mileage", 1000);
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Event with mileage 0 should fail validation (below new min of 1000)
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", event))
            .exchange()
            .expectStatus().isEqualTo(422)
            .expectBody()
            .jsonPath("$.valid").isEqualTo(false);
        
        // Restore original schema
        Files.writeString(carSchemaPath, originalContent);
    }
    
    @Test
    @Order(15)
    @DisplayName("Breaking: Change additionalProperties true to false - events with extra fields fail")
    void testBreaking_DisallowAdditionalProperties() throws IOException {
        // First allow additionalProperties, then disallow it
        Path eventSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event.json");
        String originalContent = Files.readString(eventSchemaPath);
        
        // Allow additionalProperties first
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event.json", schema -> {
            SchemaChangeHelper.allowAdditionalProperties(schema);
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Now disallow it
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event.json", schema -> {
            SchemaChangeHelper.disallowAdditionalProperties(schema);
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Event with extra field should fail validation
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        event.put("extraField", "not allowed");
        
        webTestClient.post()
            .uri("/api/v1/validate")
            .bodyValue(Map.of("event", event))
            .exchange()
            .expectStatus().isEqualTo(422)
            .expectBody()
            .jsonPath("$.valid").isEqualTo(false);
        
        // Restore original schema
        Files.writeString(eventSchemaPath, originalContent);
    }
    
    // ========== Compatibility Service Integration ==========
    
    @Test
    @Order(20)
    @DisplayName("Compatibility Service: Detect non-breaking changes")
    void testCompatibilityService_NonBreakingChanges() throws IOException {
        Path eventSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event.json");
        String originalContent = Files.readString(eventSchemaPath);
        
        @SuppressWarnings("unchecked")
        Map<String, Object> oldSchema = objectMapper.readValue(originalContent, Map.class);
        
        // Add optional field
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event.json", schema -> {
            SchemaChangeHelper.addOptionalField(schema, "newOptionalField", "string");
        });
        
        String newContent = Files.readString(eventSchemaPath);
        @SuppressWarnings("unchecked")
        Map<String, Object> newSchema = objectMapper.readValue(newContent, Map.class);
        
        CompatibilityService.CompatibilityResult result = compatibilityService.checkCompatibility(oldSchema, newSchema);
        
        assertThat(result.isCompatible()).isTrue();
        assertThat(result.getBreakingChanges()).isEmpty();
        assertThat(result.getNonBreakingChanges()).isNotEmpty();
        assertThat(result.getNonBreakingChanges()).anyMatch(change -> change.contains("newOptionalField"));
        
        // Restore original schema
        Files.writeString(eventSchemaPath, originalContent);
    }
    
    @Test
    @Order(21)
    @DisplayName("Compatibility Service: Detect breaking changes")
    void testCompatibilityService_BreakingChanges() throws IOException {
        Path headerSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event-header.json");
        String originalContent = Files.readString(headerSchemaPath);
        
        @SuppressWarnings("unchecked")
        Map<String, Object> oldSchema = objectMapper.readValue(originalContent, Map.class);
        
        // Add required field
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event-header.json", schema -> {
            SchemaChangeHelper.addRequiredField(schema, "newRequiredField", "string");
        });
        
        String newContent = Files.readString(headerSchemaPath);
        @SuppressWarnings("unchecked")
        Map<String, Object> newSchema = objectMapper.readValue(newContent, Map.class);
        
        CompatibilityService.CompatibilityResult result = compatibilityService.checkCompatibility(oldSchema, newSchema);
        
        assertThat(result.isCompatible()).isFalse();
        assertThat(result.getBreakingChanges()).isNotEmpty();
        assertThat(result.getBreakingChanges()).anyMatch(change -> 
            change.contains("newRequiredField") && change.contains("added"));
        
        // Restore original schema
        Files.writeString(headerSchemaPath, originalContent);
    }
    
    // ========== Git Sync Integration ==========
    
    @Test
    @Order(30)
    @DisplayName("Git Sync: Schema change detected and cache invalidated")
    void testGitSync_SchemaChangeDetection() throws IOException {
        Path eventSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event.json");
        String originalContent = Files.readString(eventSchemaPath);
        
        // Modify schema
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v1/event/event.json", schema -> {
            SchemaChangeHelper.addOptionalField(schema, "syncTestField", "string");
        });
        
        // Sync should pick up the change
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Verify new schema is loaded
        String localDir = gitSyncService.getLocalDir();
        SchemaCacheService.CachedSchema schema = schemaCacheService.loadVersion("v1", localDir);
        assertThat(schema).isNotNull();
        
        // Restore original schema
        Files.writeString(eventSchemaPath, originalContent);
    }
    
    // ========== Compatibility API Endpoint Tests ==========
    
    @Test
    @Order(40)
    @DisplayName("API: Check compatibility - identical schemas")
    void testApi_CompatibilityCheck_IdenticalSchemas() {
        webTestClient.post()
            .uri("/api/v1/schemas/compatibility-checks")
            .bodyValue(Map.of(
                "oldVersion", "v1",
                "newVersion", "v1",
                "type", "event"
            ))
            .exchange()
            .expectStatus().isCreated()
            .expectBody()
            .jsonPath("$.compatible").isEqualTo(true)
            .jsonPath("$.oldVersion").isEqualTo("v1")
            .jsonPath("$.newVersion").isEqualTo("v1")
            .jsonPath("$.breakingChanges").isArray()
            .jsonPath("$.breakingChanges.length()").isEqualTo(0)
            .jsonPath("$.nonBreakingChanges").isArray();
    }
    
    @Test
    @Order(41)
    @DisplayName("API: Check compatibility - non-breaking change detected")
    void testApi_CompatibilityCheck_NonBreakingChange() throws IOException {
        Path eventSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event.json");
        String originalContent = Files.readString(eventSchemaPath);
        
        // Create v2 directory structure and copy v1 schemas
        Path v2EventDir = Paths.get(testRepoDir, "schemas", "v2", "event");
        Files.createDirectories(v2EventDir);
        Files.copy(eventSchemaPath, v2EventDir.resolve("event.json"));
        
        // Also copy event-header.json for v2
        Path headerSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event-header.json");
        Files.copy(headerSchemaPath, v2EventDir.resolve("event-header.json"));
        
        // Modify v2 schema to add optional field
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v2/event/event.json", schema -> {
            SchemaChangeHelper.addOptionalField(schema, "newOptionalField", "string");
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Check compatibility via API
        webTestClient.post()
            .uri("/api/v1/schemas/compatibility-checks")
            .bodyValue(Map.of(
                "oldVersion", "v1",
                "newVersion", "v2",
                "type", "event"
            ))
            .exchange()
            .expectStatus().isCreated()
            .expectBody()
            .jsonPath("$.compatible").isEqualTo(true)
            .jsonPath("$.oldVersion").isEqualTo("v1")
            .jsonPath("$.newVersion").isEqualTo("v2")
            .jsonPath("$.breakingChanges").isArray()
            .jsonPath("$.breakingChanges.length()").isEqualTo(0)
            .jsonPath("$.nonBreakingChanges").isArray()
            .jsonPath("$.nonBreakingChanges.length()").value(org.hamcrest.Matchers.greaterThan(0))
            .jsonPath("$.nonBreakingChanges[0]").value(org.hamcrest.Matchers.containsString("newOptionalField"));
        
        // Cleanup v2 directory
        Files.deleteIfExists(v2EventDir.resolve("event.json"));
        Files.deleteIfExists(v2EventDir.resolve("event-header.json"));
        Files.deleteIfExists(v2EventDir);
        Files.deleteIfExists(Paths.get(testRepoDir, "schemas", "v2"));
        
        // Restore original schema
        Files.writeString(eventSchemaPath, originalContent);
    }
    
    @Test
    @Order(42)
    @DisplayName("API: Check compatibility - breaking change detected")
    void testApi_CompatibilityCheck_BreakingChange() throws IOException {
        Path headerSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event-header.json");
        String originalContent = Files.readString(headerSchemaPath);
        
        // Create v2 directory structure and copy v1 schemas
        Path v2EventDir = Paths.get(testRepoDir, "schemas", "v2", "event");
        Files.createDirectories(v2EventDir);
        Files.copy(headerSchemaPath, v2EventDir.resolve("event-header.json"));
        
        // Also copy event.json for v2
        Path eventSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event.json");
        Files.copy(eventSchemaPath, v2EventDir.resolve("event.json"));
        
        // Modify v2 schema to add required field
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v2/event/event-header.json", schema -> {
            SchemaChangeHelper.addRequiredField(schema, "newRequiredField", "string");
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Check compatibility via API - check event-header schema directly
        // Note: We're checking the event-header schema, but the API expects event type
        // The event schema references event-header, so we need to check at the right level
        // For this test, let's check the entity schema instead which is simpler
        Path carSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "entity", "car.json");
        String carOriginalContent = Files.readString(carSchemaPath);
        
        Path v2EntityDir = Paths.get(testRepoDir, "schemas", "v2", "entity");
        Files.createDirectories(v2EntityDir);
        Files.copy(carSchemaPath, v2EntityDir.resolve("car.json"));
        
        // Modify v2 car schema to add required field
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v2/entity/car.json", schema -> {
            SchemaChangeHelper.addRequiredField(schema, "newRequiredField", "string");
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Check compatibility via API for car entity
        webTestClient.post()
            .uri("/api/v1/schemas/compatibility-checks")
            .bodyValue(Map.of(
                "oldVersion", "v1",
                "newVersion", "v2",
                "type", "car"
            ))
            .exchange()
            .expectStatus().isCreated()
            .expectBody()
            .jsonPath("$.compatible").isEqualTo(false)
            .jsonPath("$.oldVersion").isEqualTo("v1")
            .jsonPath("$.newVersion").isEqualTo("v2")
            .jsonPath("$.breakingChanges").isArray()
            .jsonPath("$.breakingChanges.length()").value(org.hamcrest.Matchers.greaterThan(0))
            .jsonPath("$.breakingChanges[0]").value(org.hamcrest.Matchers.containsString("newRequiredField"));
        
        // Cleanup v2 directories
        Files.deleteIfExists(v2EventDir.resolve("event-header.json"));
        Files.deleteIfExists(v2EventDir.resolve("event.json"));
        Files.deleteIfExists(v2EventDir);
        Files.deleteIfExists(v2EntityDir.resolve("car.json"));
        Files.deleteIfExists(v2EntityDir);
        Files.deleteIfExists(Paths.get(testRepoDir, "schemas", "v2"));
        
        // Restore original schemas
        Files.writeString(headerSchemaPath, originalContent);
        Files.writeString(carSchemaPath, carOriginalContent);
    }
    
    @Test
    @Order(43)
    @DisplayName("API: Check compatibility - entity schema type")
    void testApi_CompatibilityCheck_EntitySchema() throws IOException {
        Path carSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "entity", "car.json");
        String originalContent = Files.readString(carSchemaPath);
        
        // Create v2 directory and copy v1 schema
        Path v2EntityDir = Paths.get(testRepoDir, "schemas", "v2", "entity");
        Files.createDirectories(v2EntityDir);
        Files.copy(carSchemaPath, v2EntityDir.resolve("car.json"));
        
        // Modify v2 schema to add optional field
        SchemaChangeHelper.modifySchemaInRepo(testRepoDir, "schemas/v2/entity/car.json", schema -> {
            SchemaChangeHelper.addOptionalField(schema, "newOptionalField", "string");
        });
        
        gitSyncService.sync();
        schemaCacheService.invalidateAll();
        
        // Check compatibility via API for entity type
        webTestClient.post()
            .uri("/api/v1/schemas/compatibility-checks")
            .bodyValue(Map.of(
                "oldVersion", "v1",
                "newVersion", "v2",
                "type", "car"
            ))
            .exchange()
            .expectStatus().isCreated()
            .expectBody()
            .jsonPath("$.compatible").isEqualTo(true)
            .jsonPath("$.oldVersion").isEqualTo("v1")
            .jsonPath("$.newVersion").isEqualTo("v2")
            .jsonPath("$.nonBreakingChanges").isArray()
            .jsonPath("$.nonBreakingChanges.length()").value(org.hamcrest.Matchers.greaterThan(0));
        
        // Cleanup v2 directory
        Files.deleteIfExists(v2EntityDir.resolve("car.json"));
        Files.deleteIfExists(v2EntityDir);
        Files.deleteIfExists(Paths.get(testRepoDir, "schemas", "v2"));
        
        // Restore original schema
        Files.writeString(carSchemaPath, originalContent);
    }
    
    @Test
    @Order(44)
    @DisplayName("API: Check compatibility - missing version returns 404")
    void testApi_CompatibilityCheck_MissingVersion() {
        webTestClient.post()
            .uri("/api/v1/schemas/compatibility-checks")
            .bodyValue(Map.of(
                "oldVersion", "v1",
                "newVersion", "v999",
                "type", "event"
            ))
            .exchange()
            .expectStatus().isNotFound();
    }
    
    @Test
    @Order(45)
    @DisplayName("API: Check compatibility - missing entity type returns 404")
    void testApi_CompatibilityCheck_MissingEntityType() {
        webTestClient.post()
            .uri("/api/v1/schemas/compatibility-checks")
            .bodyValue(Map.of(
                "oldVersion", "v1",
                "newVersion", "v1",
                "type", "nonexistent"
            ))
            .exchange()
            .expectStatus().isNotFound();
    }
    
    @Test
    @Order(46)
    @DisplayName("API: Check compatibility - default type is event")
    void testApi_CompatibilityCheck_DefaultType() {
        webTestClient.post()
            .uri("/api/v1/schemas/compatibility-checks")
            .bodyValue(Map.of(
                "oldVersion", "v1",
                "newVersion", "v1"
            ))
            .exchange()
            .expectStatus().isCreated()
            .expectBody()
            .jsonPath("$.compatible").isEqualTo(true)
            .jsonPath("$.oldVersion").isEqualTo("v1")
            .jsonPath("$.newVersion").isEqualTo("v1");
    }
    
    @Test
    @Order(47)
    @DisplayName("API: Check compatibility - validation error for missing required fields")
    void testApi_CompatibilityCheck_ValidationError() {
        webTestClient.post()
            .uri("/api/v1/schemas/compatibility-checks")
            .bodyValue(Map.of(
                "oldVersion", "v1"
                // Missing newVersion
            ))
            .exchange()
            .expectStatus().isBadRequest();
    }
}

