package com.example.metadata.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.networknt.schema.*;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.*;
import java.util.stream.Collectors;

@Service
@Slf4j
public class SchemaValidationService {
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Data
    public static class ValidationResult {
        private boolean valid;
        private List<ValidationError> errors = new ArrayList<>();
        private String version;
    }

    @Data
    public static class ValidationError {
        private String field;
        private String message;
    }

    public ValidationResult validateEvent(
            Map<String, Object> eventData,
            Map<String, Object> eventSchema,
            Map<String, Map<String, Object>> entitySchemas,
            String basePath
    ) throws IOException {
        // Extract version from basePath
        String version = extractVersion(basePath);
        
        // Resolve $ref references
        Map<String, Object> resolvedSchema = resolveReferences(eventSchema, entitySchemas, basePath);
        
        // Remove $id fields to prevent URL fetching by the validator
        removeIdFields(resolvedSchema);
        
        // Create JSON Schema validator
        // Note: We've already resolved all $ref references, so the validator shouldn't need to fetch URLs
        JsonSchemaFactory factory = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012);
        JsonSchema schema = factory.getSchema(objectMapper.writeValueAsString(resolvedSchema));
        
        // Validate event - convert eventData to JsonNode
        JsonNode eventNode = objectMapper.valueToTree(eventData);
        Set<ValidationMessage> validationMessages = schema.validate(eventNode);
        
        ValidationResult result = new ValidationResult();
        result.setValid(validationMessages.isEmpty());
        result.setVersion(version);
        
        if (!validationMessages.isEmpty()) {
            result.setErrors(validationMessages.stream()
                .map(msg -> {
                    ValidationError error = new ValidationError();
                    error.setField(msg.getPath());
                    error.setMessage(msg.getMessage());
                    return error;
                })
                .collect(Collectors.toList()));
        }
        
        return result;
    }
    
    @SuppressWarnings("unchecked")
    private void removeIdFields(Map<String, Object> schema) {
        schema.remove("$id");
        for (Object value : schema.values()) {
            if (value instanceof Map) {
                removeIdFields((Map<String, Object>) value);
            } else if (value instanceof List) {
                for (Object item : (List<?>) value) {
                    if (item instanceof Map) {
                        removeIdFields((Map<String, Object>) item);
                    }
                }
            }
        }
    }

    private String extractVersion(String basePath) {
        // Look for version pattern in path (e.g., .../schemas/v1/...)
        String[] parts = basePath.split("/");
        for (int i = 0; i < parts.length; i++) {
            String part = parts[i];
            if (part.startsWith("v") && part.length() > 1 && part.length() <= 10) {
                // Check if next part is "event" or "entity" to confirm it's a version
                if (i + 1 < parts.length && (parts[i + 1].equals("event") || parts[i + 1].equals("entity"))) {
                    return part;
                }
            }
        }
        
        // Try to find "schemas/vX" pattern
        int idx = basePath.indexOf("schemas/v");
        if (idx != -1) {
            String remaining = basePath.substring(idx + 8); // Skip "schemas/v"
            int slashIdx = remaining.indexOf("/");
            if (slashIdx != -1) {
                String version = remaining.substring(0, slashIdx);
                // If version already starts with 'v', return as-is, otherwise add 'v' prefix
                return version.startsWith("v") ? version : "v" + version;
            } else if (remaining.length() > 0) {
                String version = remaining;
                return version.startsWith("v") ? version : "v" + version;
            }
        }
        
        // Try to find "/vX" pattern anywhere in the path
        for (String part : parts) {
            if (part.startsWith("v") && part.length() > 1 && part.length() <= 10 && part.matches("v\\d+")) {
                return part;
            }
        }
        
        return "v1"; // Default
    }

    private Map<String, Object> resolveReferences(
            Map<String, Object> schema,
            Map<String, Map<String, Object>> entitySchemas,
            String basePath
    ) {
        Map<String, Object> resolved = new HashMap<>(schema);
        resolveReferencesRecursive(resolved, entitySchemas, basePath);
        return resolved;
    }

    @SuppressWarnings("unchecked")
    private void resolveReferencesRecursive(
            Map<String, Object> schema,
            Map<String, Map<String, Object>> entitySchemas,
            String basePath
    ) {
        if (schema.containsKey("$ref")) {
            String ref = (String) schema.get("$ref");
            Map<String, Object> resolvedSchema = null;
            
            if (ref.startsWith("#/definitions/") || ref.startsWith("#/$defs/")) {
                String entityName = ref.substring(ref.lastIndexOf("/") + 1);
                resolvedSchema = entitySchemas.get(entityName);
            } else if (ref.startsWith("./") || ref.startsWith("../") || !ref.contains("://")) {
                // Relative file reference or simple filename
                String fileName = ref.substring(ref.lastIndexOf("/") + 1);
                // Try multiple variations: with extension, without extension, full filename
                resolvedSchema = entitySchemas.get(fileName);
                if (resolvedSchema == null && fileName.endsWith(".json")) {
                    String fileNameWithoutExt = fileName.substring(0, fileName.length() - 5);
                    resolvedSchema = entitySchemas.get(fileNameWithoutExt);
                } else if (resolvedSchema == null && !fileName.endsWith(".json")) {
                    resolvedSchema = entitySchemas.get(fileName + ".json");
                }
            }
            
            if (resolvedSchema != null) {
                // Create a deep copy to avoid modifying the original
                Map<String, Object> resolvedCopy = new HashMap<>(resolvedSchema);
                // Remove $id from resolved schema to prevent URL fetching
                resolvedCopy.remove("$id");
                // Merge resolved schema into current schema
                schema.putAll(resolvedCopy);
                schema.remove("$ref");
                // Recursively resolve references in the resolved schema
                resolveReferencesRecursive(schema, entitySchemas, basePath);
            }
        }
        
        // Recursively process nested objects and arrays
        for (Map.Entry<String, Object> entry : schema.entrySet()) {
            Object value = entry.getValue();
            if (value instanceof Map) {
                resolveReferencesRecursive((Map<String, Object>) value, entitySchemas, basePath);
            } else if (value instanceof List) {
                for (Object item : (List<?>) value) {
                    if (item instanceof Map) {
                        resolveReferencesRecursive((Map<String, Object>) item, entitySchemas, basePath);
                    }
                }
            }
        }
    }
}
