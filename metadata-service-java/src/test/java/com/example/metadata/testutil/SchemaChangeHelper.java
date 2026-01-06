package com.example.metadata.testutil;

import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.*;

/**
 * Helper utility for creating and modifying schemas in test repositories
 * to test breaking and non-breaking schema changes.
 */
public class SchemaChangeHelper {
    
    private static final ObjectMapper objectMapper = new ObjectMapper();
    
    /**
     * Modifies a schema file in the test repository.
     * 
     * @param repoDir The repository directory
     * @param schemaPath Relative path to schema file (e.g., "schemas/v1/event/event.json")
     * @param modifier Function to modify the schema map
     */
    @SuppressWarnings("unchecked")
    public static void modifySchemaInRepo(String repoDir, String schemaPath, SchemaModifier modifier) throws IOException {
        Path fullPath = Paths.get(repoDir, schemaPath);
        if (!Files.exists(fullPath)) {
            throw new IOException("Schema file not found: " + fullPath);
        }
        
        String content = Files.readString(fullPath);
        Map<String, Object> schema = objectMapper.readValue(content, Map.class);
        
        modifier.modify(schema);
        
        String newContent = objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(schema);
        Files.writeString(fullPath, newContent);
    }
    
    /**
     * Creates a non-breaking change: adds an optional field to a schema.
     */
    @SuppressWarnings("unchecked")
    public static void addOptionalField(Map<String, Object> schema, String fieldName, String fieldType) {
        Map<String, Object> properties = (Map<String, Object>) schema.get("properties");
        if (properties == null) {
            properties = new HashMap<>();
            schema.put("properties", properties);
        }
        
        Map<String, Object> fieldSchema = new HashMap<>();
        fieldSchema.put("type", fieldType);
        properties.put(fieldName, fieldSchema);
        // Field is not added to required array, so it's optional
    }
    
    /**
     * Creates a non-breaking change: removes an optional field from a schema.
     */
    @SuppressWarnings("unchecked")
    public static void removeOptionalField(Map<String, Object> schema, String fieldName) {
        Map<String, Object> properties = (Map<String, Object>) schema.get("properties");
        if (properties != null) {
            properties.remove(fieldName);
        }
    }
    
    /**
     * Creates a non-breaking change: makes a required field optional.
     */
    @SuppressWarnings("unchecked")
    public static void makeRequiredFieldOptional(Map<String, Object> schema, String fieldName) {
        List<String> required = (List<String>) schema.get("required");
        if (required != null) {
            required.remove(fieldName);
        }
    }
    
    /**
     * Creates a breaking change: removes a required field.
     */
    @SuppressWarnings("unchecked")
    public static void removeRequiredField(Map<String, Object> schema, String fieldName) {
        Map<String, Object> properties = (Map<String, Object>) schema.get("properties");
        if (properties != null) {
            properties.remove(fieldName);
        }
        List<String> required = (List<String>) schema.get("required");
        if (required != null) {
            required.remove(fieldName);
        }
    }
    
    /**
     * Creates a breaking change: adds a new required field.
     */
    @SuppressWarnings("unchecked")
    public static void addRequiredField(Map<String, Object> schema, String fieldName, String fieldType) {
        Map<String, Object> properties = (Map<String, Object>) schema.get("properties");
        if (properties == null) {
            properties = new HashMap<>();
            schema.put("properties", properties);
        }
        
        Map<String, Object> fieldSchema = new HashMap<>();
        fieldSchema.put("type", fieldType);
        properties.put(fieldName, fieldSchema);
        
        List<String> required = (List<String>) schema.get("required");
        if (required == null) {
            required = new ArrayList<>();
            schema.put("required", required);
        }
        required.add(fieldName);
    }
    
    /**
     * Creates a breaking change: changes a field's type.
     */
    @SuppressWarnings("unchecked")
    public static void changeFieldType(Map<String, Object> schema, String fieldName, String newType) {
        Map<String, Object> properties = (Map<String, Object>) schema.get("properties");
        if (properties != null) {
            Map<String, Object> fieldSchema = (Map<String, Object>) properties.get(fieldName);
            if (fieldSchema != null) {
                fieldSchema.put("type", newType);
            }
        }
    }
    
    /**
     * Creates a non-breaking change: adds an enum value.
     */
    @SuppressWarnings("unchecked")
    public static void addEnumValue(Map<String, Object> schema, String fieldName, String enumValue) {
        Map<String, Object> properties = (Map<String, Object>) schema.get("properties");
        if (properties != null) {
            Map<String, Object> fieldSchema = (Map<String, Object>) properties.get(fieldName);
            if (fieldSchema != null) {
                List<String> enumValues = (List<String>) fieldSchema.get("enum");
                if (enumValues == null) {
                    enumValues = new ArrayList<>();
                    fieldSchema.put("enum", enumValues);
                }
                if (!enumValues.contains(enumValue)) {
                    enumValues.add(enumValue);
                }
            }
        }
    }
    
    /**
     * Creates a breaking change: removes an enum value.
     */
    @SuppressWarnings("unchecked")
    public static void removeEnumValue(Map<String, Object> schema, String fieldName, String enumValue) {
        Map<String, Object> properties = (Map<String, Object>) schema.get("properties");
        if (properties != null) {
            Map<String, Object> fieldSchema = (Map<String, Object>) properties.get(fieldName);
            if (fieldSchema != null) {
                List<String> enumValues = (List<String>) fieldSchema.get("enum");
                if (enumValues != null) {
                    enumValues.remove(enumValue);
                }
            }
        }
    }
    
    /**
     * Creates a non-breaking change: relaxes a minimum constraint.
     */
    @SuppressWarnings("unchecked")
    public static void relaxMinimumConstraint(Map<String, Object> schema, String fieldName, Number newMinimum) {
        Map<String, Object> properties = (Map<String, Object>) schema.get("properties");
        if (properties != null) {
            Map<String, Object> fieldSchema = (Map<String, Object>) properties.get(fieldName);
            if (fieldSchema != null) {
                fieldSchema.put("minimum", newMinimum);
            }
        }
    }
    
    /**
     * Creates a breaking change: tightens a minimum constraint.
     */
    @SuppressWarnings("unchecked")
    public static void tightenMinimumConstraint(Map<String, Object> schema, String fieldName, Number newMinimum) {
        Map<String, Object> properties = (Map<String, Object>) schema.get("properties");
        if (properties != null) {
            Map<String, Object> fieldSchema = (Map<String, Object>) properties.get(fieldName);
            if (fieldSchema != null) {
                fieldSchema.put("minimum", newMinimum);
            }
        }
    }
    
    /**
     * Creates a non-breaking change: relaxes a maximum constraint.
     */
    @SuppressWarnings("unchecked")
    public static void relaxMaximumConstraint(Map<String, Object> schema, String fieldName, Number newMaximum) {
        Map<String, Object> properties = (Map<String, Object>) schema.get("properties");
        if (properties != null) {
            Map<String, Object> fieldSchema = (Map<String, Object>) properties.get(fieldName);
            if (fieldSchema != null) {
                fieldSchema.put("maximum", newMaximum);
            }
        }
    }
    
    /**
     * Creates a breaking change: tightens a maximum constraint.
     */
    @SuppressWarnings("unchecked")
    public static void tightenMaximumConstraint(Map<String, Object> schema, String fieldName, Number newMaximum) {
        Map<String, Object> properties = (Map<String, Object>) schema.get("properties");
        if (properties != null) {
            Map<String, Object> fieldSchema = (Map<String, Object>) properties.get(fieldName);
            if (fieldSchema != null) {
                fieldSchema.put("maximum", newMaximum);
            }
        }
    }
    
    /**
     * Creates a non-breaking change: changes additionalProperties from false to true.
     */
    public static void allowAdditionalProperties(Map<String, Object> schema) {
        schema.put("additionalProperties", true);
    }
    
    /**
     * Creates a breaking change: changes additionalProperties from true to false.
     */
    public static void disallowAdditionalProperties(Map<String, Object> schema) {
        schema.put("additionalProperties", false);
    }
    
    /**
     * Functional interface for modifying schemas.
     */
    @FunctionalInterface
    public interface SchemaModifier {
        void modify(Map<String, Object> schema) throws IOException;
    }
}

