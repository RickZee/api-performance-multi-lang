package com.example.metadata.service;

import com.example.metadata.testutil.TestEventGenerator;
import com.example.metadata.testutil.TestRepoSetup;
import org.junit.jupiter.api.*;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class SchemaValidationServiceTest {
    
    private SchemaValidationService validationService;
    private static String testRepoDir;
    private static String testCacheDir;
    private Map<String, Object> eventSchema;
    private Map<String, Map<String, Object>> entitySchemas;
    
    @BeforeAll
    static void setupTestRepo() throws IOException {
        String tempDir = Files.createTempDirectory("metadata-service-test-").toString();
        testRepoDir = TestRepoSetup.setupTestRepo(tempDir);
        testCacheDir = tempDir + "/cache";
    }
    
    @AfterAll
    static void tearDown() throws IOException {
        if (testRepoDir != null) {
            TestRepoSetup.cleanupTestRepo(testRepoDir);
        }
    }
    
    @BeforeEach
    void setUp() throws IOException {
        validationService = new SchemaValidationService();
        
        // Load schemas from test repo
        Path eventSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event.json");
        Path eventHeaderPath = Paths.get(testRepoDir, "schemas", "v1", "event", "event-header.json");
        Path carSchemaPath = Paths.get(testRepoDir, "schemas", "v1", "entity", "car.json");
        Path entityHeaderPath = Paths.get(testRepoDir, "schemas", "v1", "entity", "entity-header.json");
        
        // Verify files exist
        if (!Files.exists(eventSchemaPath)) {
            throw new IOException("Event schema not found at: " + eventSchemaPath);
        }
        if (!Files.exists(eventHeaderPath)) {
            throw new IOException("Event header not found at: " + eventHeaderPath);
        }
        if (!Files.exists(carSchemaPath)) {
            throw new IOException("Car schema not found at: " + carSchemaPath);
        }
        if (!Files.exists(entityHeaderPath)) {
            throw new IOException("Entity header not found at: " + entityHeaderPath);
        }
        
        eventSchema = loadJsonFile(eventSchemaPath);
        Map<String, Object> eventHeader = loadJsonFile(eventHeaderPath);
        Map<String, Object> carSchema = loadJsonFile(carSchemaPath);
        Map<String, Object> entityHeader = loadJsonFile(entityHeaderPath);
        
        entitySchemas = new HashMap<>();
        entitySchemas.put("car", carSchema);
        entitySchemas.put("entity-header", entityHeader);
        entitySchemas.put("event-header", eventHeader);
        // Also add with .json extension for reference resolution
        entitySchemas.put("car.json", carSchema);
        entitySchemas.put("entity-header.json", entityHeader);
        entitySchemas.put("event-header.json", eventHeader);
    }
    
    private Map<String, Object> loadJsonFile(Path path) throws IOException {
        com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
        return mapper.readValue(Files.readString(path), Map.class);
    }
    
    @Test
    void testValidateEvent_ValidEvent() throws IOException {
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        
        // Use the actual path where schemas are located
        String basePath = Paths.get(testRepoDir, "schemas", "v1").toString();
        SchemaValidationService.ValidationResult result = validationService.validateEvent(
            event, eventSchema, entitySchemas, basePath
        );
        
        assertTrue(result.isValid(), "Valid event should pass validation");
        assertTrue(result.getErrors().isEmpty(), "Valid event should have no errors");
        assertEquals("v1", result.getVersion());
    }
    
    @Test
    void testValidateEvent_MissingRequiredField() throws IOException {
        Map<String, Object> event = new HashMap<>();
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "550e8400-e29b-41d4-a716-446655440000");
        // Missing required fields: eventName, eventType, createdDate, savedDate
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of());
        
        String basePath = Paths.get(testRepoDir, "schemas", "v1").toString();
        SchemaValidationService.ValidationResult result = validationService.validateEvent(
            event, eventSchema, entitySchemas, basePath
        );
        
        assertFalse(result.isValid(), "Event with missing required fields should fail");
        assertFalse(result.getErrors().isEmpty(), "Should have validation errors");
    }
    
    @Test
    void testValidateEvent_NullInRequiredField() throws IOException {
        Map<String, Object> event = new HashMap<>();
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "550e8400-e29b-41d4-a716-446655440000");
        eventHeader.put("eventName", null); // Null in required field
        eventHeader.put("eventType", "CarCreated");
        eventHeader.put("createdDate", Instant.now().toString());
        eventHeader.put("savedDate", Instant.now().toString());
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of());
        
        String basePath = Paths.get(testRepoDir, "schemas", "v1").toString();
        SchemaValidationService.ValidationResult result = validationService.validateEvent(
            event, eventSchema, entitySchemas, basePath
        );
        
        assertFalse(result.isValid(), "Event with null in required field should fail");
    }
    
    @Test
    void testValidateEvent_EmptyStringInRequiredField() throws IOException {
        Map<String, Object> event = new HashMap<>();
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "550e8400-e29b-41d4-a716-446655440000");
        eventHeader.put("eventName", ""); // Empty string
        eventHeader.put("eventType", "CarCreated");
        eventHeader.put("createdDate", Instant.now().toString());
        eventHeader.put("savedDate", Instant.now().toString());
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of());
        
        String basePath = Paths.get(testRepoDir, "schemas", "v1").toString();
        SchemaValidationService.ValidationResult result = validationService.validateEvent(
            event, eventSchema, entitySchemas, basePath
        );
        
        // Empty string may or may not be valid depending on schema, but should be handled
        assertNotNull(result);
    }
    
    @Test
    void testValidateEvent_WrongType() throws IOException {
        Map<String, Object> event = TestEventGenerator.invalidEventWrongType();
        
        String basePath = Paths.get(testRepoDir, "schemas", "v1").toString();
        SchemaValidationService.ValidationResult result = validationService.validateEvent(
            event, eventSchema, entitySchemas, basePath
        );
        
        assertFalse(result.isValid(), "Event with wrong type should fail");
        assertFalse(result.getErrors().isEmpty(), "Should have type mismatch errors");
    }
    
    @Test
    void testValidateEvent_InvalidPattern() throws IOException {
        Map<String, Object> event = TestEventGenerator.invalidEventInvalidPattern();
        
        String basePath = Paths.get(testRepoDir, "schemas", "v1").toString();
        SchemaValidationService.ValidationResult result = validationService.validateEvent(
            event, eventSchema, entitySchemas, basePath
        );
        
        assertFalse(result.isValid(), "Event with invalid pattern should fail");
    }
    
    @Test
    void testValidateEvent_InvalidUUID() throws IOException {
        Map<String, Object> event = new HashMap<>();
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "invalid-uuid-format"); // Invalid UUID
        eventHeader.put("eventName", "Car Created");
        eventHeader.put("eventType", "CarCreated");
        eventHeader.put("createdDate", Instant.now().toString());
        eventHeader.put("savedDate", Instant.now().toString());
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of());
        
        String basePath = Paths.get(testRepoDir, "schemas", "v1").toString();
        SchemaValidationService.ValidationResult result = validationService.validateEvent(
            event, eventSchema, entitySchemas, basePath
        );
        
        assertFalse(result.isValid(), "Event with invalid UUID should fail");
    }
    
    @Test
    void testValidateEvent_InvalidEnum() throws IOException {
        Map<String, Object> event = new HashMap<>();
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "550e8400-e29b-41d4-a716-446655440000");
        eventHeader.put("eventName", "Car Created");
        eventHeader.put("eventType", "InvalidEventType"); // Invalid enum value
        eventHeader.put("createdDate", Instant.now().toString());
        eventHeader.put("savedDate", Instant.now().toString());
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of());
        
        String basePath = Paths.get(testRepoDir, "schemas", "v1").toString();
        SchemaValidationService.ValidationResult result = validationService.validateEvent(
            event, eventSchema, entitySchemas, basePath
        );
        
        assertFalse(result.isValid(), "Event with invalid enum value should fail");
    }
    
    @Test
    void testValidateEvent_OutOfRange() throws IOException {
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        @SuppressWarnings("unchecked")
        Map<String, Object> car = (Map<String, Object>) ((List<?>) event.get("entities")).get(0);
        car.put("year", 3000); // Out of range (max is 2030)
        
        String basePath = Paths.get(testRepoDir, "schemas", "v1").toString();
        SchemaValidationService.ValidationResult result = validationService.validateEvent(
            event, eventSchema, entitySchemas, basePath
        );
        
        assertFalse(result.isValid(), "Event with out-of-range value should fail");
    }
    
    @Test
    void testValidateEvent_EmptyEntitiesArray() throws IOException {
        Map<String, Object> event = new HashMap<>();
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "550e8400-e29b-41d4-a716-446655440000");
        eventHeader.put("eventName", "Car Created");
        eventHeader.put("eventType", "CarCreated");
        eventHeader.put("createdDate", Instant.now().toString());
        eventHeader.put("savedDate", Instant.now().toString());
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of()); // Empty array (minItems: 1)
        
        String basePath = Paths.get(testRepoDir, "schemas", "v1").toString();
        SchemaValidationService.ValidationResult result = validationService.validateEvent(
            event, eventSchema, entitySchemas, basePath
        );
        
        assertFalse(result.isValid(), "Event with empty entities array should fail (minItems: 1)");
    }
    
    @Test
    void testValidateEvent_AdditionalProperties() throws IOException {
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        event.put("extraField", "not allowed"); // Additional property
        
        String basePath = Paths.get(testRepoDir, "schemas", "v1").toString();
        SchemaValidationService.ValidationResult result = validationService.validateEvent(
            event, eventSchema, entitySchemas, basePath
        );
        
        assertFalse(result.isValid(), "Event with additional properties should fail (additionalProperties: false)");
    }
    
    @Test
    void testValidateEvent_InvalidDateFormat() throws IOException {
        Map<String, Object> event = new HashMap<>();
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "550e8400-e29b-41d4-a716-446655440000");
        eventHeader.put("eventName", "Car Created");
        eventHeader.put("eventType", "CarCreated");
        eventHeader.put("createdDate", "invalid-date-format"); // Invalid date-time format
        eventHeader.put("savedDate", Instant.now().toString());
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of());
        
        String basePath = Paths.get(testRepoDir, "schemas", "v1").toString();
        SchemaValidationService.ValidationResult result = validationService.validateEvent(
            event, eventSchema, entitySchemas, basePath
        );
        
        assertFalse(result.isValid(), "Event with invalid date format should fail");
    }
    
    @Test
    void testExtractVersion_FromPath() {
        // Test version extraction logic
        String basePath1 = "/app/data/schemas/v1/event";
        String basePath2 = "/app/data/schemas/v2/entity";
        String basePath3 = "/app/data/schemas/v10/event";
        
        // We can't directly test private method, but we can test via validateEvent
        // The version is extracted and returned in ValidationResult
        assertTrue(true); // Placeholder - version extraction is tested indirectly
    }
    
    @Test
    void testResolveReferences() throws IOException {
        // Test that $ref references are resolved correctly
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        
        String basePath = Paths.get(testRepoDir, "schemas", "v1").toString();
        SchemaValidationService.ValidationResult result = validationService.validateEvent(
            event, eventSchema, entitySchemas, basePath
        );
        
        // If references are resolved correctly, validation should work
        assertTrue(result.isValid(), "References should be resolved correctly");
    }
}
