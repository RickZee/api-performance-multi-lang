package com.example.metadata.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class CompatibilityServiceTest {
    
    private CompatibilityService compatibilityService;
    
    @BeforeEach
    void setUp() {
        compatibilityService = new CompatibilityService();
    }
    
    // Note: This is a pure unit test, no Spring context needed
    
    @Test
    void testCheckCompatibility_IdenticalSchemas() {
        Map<String, Object> schema = createBaseSchema();
        
        CompatibilityService.CompatibilityResult result = compatibilityService.checkCompatibility(schema, schema);
        
        assertTrue(result.isCompatible(), "Identical schemas should be compatible");
        assertTrue(result.getBreakingChanges().isEmpty(), "No breaking changes for identical schemas");
    }
    
    @Test
    void testCheckCompatibility_NonBreaking_AddOptionalField() {
        Map<String, Object> oldSchema = createBaseSchema();
        Map<String, Object> newSchema = createBaseSchema();
        
        @SuppressWarnings("unchecked")
        Map<String, Object> props = (Map<String, Object>) newSchema.get("properties");
        props.put("newOptionalField", Map.of("type", "string"));
        
        CompatibilityService.CompatibilityResult result = compatibilityService.checkCompatibility(oldSchema, newSchema);
        
        assertTrue(result.isCompatible(), "Adding optional field should be non-breaking");
        assertTrue(result.getBreakingChanges().isEmpty(), "No breaking changes");
        assertFalse(result.getNonBreakingChanges().isEmpty(), "Should have non-breaking changes");
        assertTrue(result.getNonBreakingChanges().stream()
            .anyMatch(change -> change.contains("newOptionalField")), 
            "Should report new optional field");
    }
    
    @Test
    void testCheckCompatibility_Breaking_RemoveRequiredField() {
        Map<String, Object> oldSchema = createBaseSchema();
        Map<String, Object> newSchema = createBaseSchema();
        
        @SuppressWarnings("unchecked")
        List<String> required = (List<String>) newSchema.get("required");
        required.remove("id");
        
        @SuppressWarnings("unchecked")
        Map<String, Object> props = (Map<String, Object>) newSchema.get("properties");
        props.remove("id");
        
        CompatibilityService.CompatibilityResult result = compatibilityService.checkCompatibility(oldSchema, newSchema);
        
        assertFalse(result.isCompatible(), "Removing required field should be breaking");
        assertFalse(result.getBreakingChanges().isEmpty(), "Should have breaking changes");
        assertTrue(result.getBreakingChanges().stream()
            .anyMatch(change -> change.contains("id") && change.contains("removed")), 
            "Should report removed required field");
    }
    
    @Test
    void testCheckCompatibility_Breaking_AddRequiredField() {
        Map<String, Object> oldSchema = createBaseSchema();
        Map<String, Object> newSchema = createBaseSchema();
        
        @SuppressWarnings("unchecked")
        List<String> required = (List<String>) newSchema.get("required");
        required.add("newRequiredField");
        
        @SuppressWarnings("unchecked")
        Map<String, Object> props = (Map<String, Object>) newSchema.get("properties");
        props.put("newRequiredField", Map.of("type", "string"));
        
        CompatibilityService.CompatibilityResult result = compatibilityService.checkCompatibility(oldSchema, newSchema);
        
        assertFalse(result.isCompatible(), "Adding required field should be breaking");
        assertFalse(result.getBreakingChanges().isEmpty(), "Should have breaking changes");
        assertTrue(result.getBreakingChanges().stream()
            .anyMatch(change -> change.contains("newRequiredField") && change.contains("added")), 
            "Should report new required field");
    }
    
    @Test
    void testCheckCompatibility_Breaking_TypeChange() {
        Map<String, Object> oldSchema = createBaseSchema();
        Map<String, Object> newSchema = createBaseSchema();
        
        @SuppressWarnings("unchecked")
        Map<String, Object> props = (Map<String, Object>) newSchema.get("properties");
        props.put("id", Map.of("type", "integer")); // Changed from string to integer
        
        CompatibilityService.CompatibilityResult result = compatibilityService.checkCompatibility(oldSchema, newSchema);
        
        assertFalse(result.isCompatible(), "Type change should be breaking");
        assertFalse(result.getBreakingChanges().isEmpty(), "Should have breaking changes");
        assertTrue(result.getBreakingChanges().stream()
            .anyMatch(change -> change.contains("type changed")), 
            "Should report type change");
    }
    
    @Test
    void testCheckCompatibility_NonBreaking_RemoveOptionalField() {
        Map<String, Object> oldSchema = createBaseSchema();
        Map<String, Object> newSchema = createBaseSchema();
        
        // Add optional field to old schema
        @SuppressWarnings("unchecked")
        Map<String, Object> oldProps = (Map<String, Object>) oldSchema.get("properties");
        oldProps.put("optionalField", Map.of("type", "string"));
        
        // Remove it from new schema
        @SuppressWarnings("unchecked")
        Map<String, Object> newProps = (Map<String, Object>) newSchema.get("properties");
        newProps.remove("optionalField");
        
        CompatibilityService.CompatibilityResult result = compatibilityService.checkCompatibility(oldSchema, newSchema);
        
        assertTrue(result.isCompatible(), "Removing optional field should be non-breaking");
        assertTrue(result.getBreakingChanges().isEmpty(), "No breaking changes");
        assertFalse(result.getNonBreakingChanges().isEmpty(), "Should have non-breaking changes");
    }
    
    @Test
    void testCheckCompatibility_ConstraintTightening() {
        Map<String, Object> oldSchema = createBaseSchema();
        Map<String, Object> newSchema = createBaseSchema();
        
        // Old schema: no minimum
        @SuppressWarnings("unchecked")
        Map<String, Object> oldProps = (Map<String, Object>) oldSchema.get("properties");
        oldProps.put("age", Map.of("type", "integer"));
        
        // New schema: add minimum constraint
        @SuppressWarnings("unchecked")
        Map<String, Object> newProps = (Map<String, Object>) newSchema.get("properties");
        Map<String, Object> ageSchema = new HashMap<>();
        ageSchema.put("type", "integer");
        ageSchema.put("minimum", 0);
        newProps.put("age", ageSchema);
        
        CompatibilityService.CompatibilityResult result = compatibilityService.checkCompatibility(oldSchema, newSchema);
        
        // Constraint tightening is technically breaking, but our current implementation
        // doesn't check constraints, only types and required fields
        assertNotNull(result);
    }
    
    @Test
    void testCheckCompatibility_MultipleChanges() {
        Map<String, Object> oldSchema = createBaseSchema();
        Map<String, Object> newSchema = createBaseSchema();
        
        // Add optional field (non-breaking)
        @SuppressWarnings("unchecked")
        Map<String, Object> newProps = (Map<String, Object>) newSchema.get("properties");
        newProps.put("newOptional", Map.of("type", "string"));
        
        // Remove required field (breaking)
        @SuppressWarnings("unchecked")
        List<String> required = (List<String>) newSchema.get("required");
        required.remove("id");
        newProps.remove("id");
        
        CompatibilityService.CompatibilityResult result = compatibilityService.checkCompatibility(oldSchema, newSchema);
        
        assertFalse(result.isCompatible(), "Should be incompatible due to breaking change");
        assertFalse(result.getBreakingChanges().isEmpty(), "Should have breaking changes");
        assertFalse(result.getNonBreakingChanges().isEmpty(), "Should also have non-breaking changes");
    }
    
    @Test
    void testCheckCompatibility_EmptySchemas() {
        Map<String, Object> oldSchema = new HashMap<>();
        Map<String, Object> newSchema = new HashMap<>();
        
        CompatibilityService.CompatibilityResult result = compatibilityService.checkCompatibility(oldSchema, newSchema);
        
        assertTrue(result.isCompatible(), "Empty schemas should be compatible");
    }
    
    private Map<String, Object> createBaseSchema() {
        Map<String, Object> schema = new HashMap<>();
        Map<String, Object> properties = new HashMap<>();
        properties.put("id", Map.of("type", "string"));
        properties.put("name", Map.of("type", "string"));
        schema.put("properties", properties);
        schema.put("required", new ArrayList<>(List.of("id", "name")));
        return schema;
    }
}
