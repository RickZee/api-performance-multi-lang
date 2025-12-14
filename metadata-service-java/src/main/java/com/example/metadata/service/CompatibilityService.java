package com.example.metadata.service;

import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.*;

@Service
@Slf4j
public class CompatibilityService {
    
    @Data
    public static class CompatibilityResult {
        private boolean compatible = true;
        private String reason;
        private List<String> breakingChanges = new ArrayList<>();
        private List<String> nonBreakingChanges = new ArrayList<>();
    }

    public CompatibilityResult checkCompatibility(
            Map<String, Object> oldSchema,
            Map<String, Object> newSchema
    ) {
        CompatibilityResult result = new CompatibilityResult();
        
        // Check required fields
        Set<String> oldRequired = getRequiredFields(oldSchema);
        Set<String> newRequired = getRequiredFields(newSchema);
        
        // Check for removed required fields (breaking)
        for (String field : oldRequired) {
            if (!newRequired.contains(field)) {
                result.setCompatible(false);
                result.getBreakingChanges().add("Required field '" + field + "' was removed");
            }
        }
        
        // Check for new required fields (breaking)
        for (String field : newRequired) {
            if (!oldRequired.contains(field)) {
                result.setCompatible(false);
                result.getBreakingChanges().add("New required field '" + field + "' was added");
            }
        }
        
        // Check properties
        Map<String, Object> oldProps = getProperties(oldSchema);
        Map<String, Object> newProps = getProperties(newSchema);
        
        // Check for removed properties
        for (Map.Entry<String, Object> entry : oldProps.entrySet()) {
            String propName = entry.getKey();
            if (!newProps.containsKey(propName)) {
                if (oldRequired.contains(propName)) {
                    result.setCompatible(false);
                    result.getBreakingChanges().add("Required property '" + propName + "' was removed");
                } else {
                    result.getNonBreakingChanges().add("Optional property '" + propName + "' was removed");
                }
            } else {
                // Check for type changes
                String oldType = getType(entry.getValue());
                String newType = getType(newProps.get(propName));
                if (oldType != null && newType != null && !oldType.equals(newType)) {
                    result.setCompatible(false);
                    result.getBreakingChanges().add("Property '" + propName + "' type changed from " + oldType + " to " + newType);
                }
            }
        }
        
        // Check for new optional properties (non-breaking)
        for (String propName : newProps.keySet()) {
            if (!oldProps.containsKey(propName) && !newRequired.contains(propName)) {
                result.getNonBreakingChanges().add("New optional property '" + propName + "' was added");
            }
        }
        
        if (!result.isCompatible()) {
            result.setReason("Schema contains breaking changes");
        } else if (!result.getNonBreakingChanges().isEmpty()) {
            result.setReason("Schema contains non-breaking changes");
        } else {
            result.setReason("Schemas are compatible");
        }
        
        return result;
    }

    @SuppressWarnings("unchecked")
    private Set<String> getRequiredFields(Map<String, Object> schema) {
        Set<String> required = new HashSet<>();
        Object requiredObj = schema.get("required");
        if (requiredObj instanceof List) {
            for (Object item : (List<?>) requiredObj) {
                if (item instanceof String) {
                    required.add((String) item);
                }
            }
        }
        return required;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> getProperties(Map<String, Object> schema) {
        Map<String, Object> properties = new HashMap<>();
        Object propsObj = schema.get("properties");
        if (propsObj instanceof Map) {
            properties.putAll((Map<String, Object>) propsObj);
        }
        return properties;
    }

    @SuppressWarnings("unchecked")
    private String getType(Object schemaObj) {
        if (schemaObj instanceof Map) {
            Map<String, Object> schema = (Map<String, Object>) schemaObj;
            Object typeObj = schema.get("type");
            if (typeObj instanceof String) {
                return (String) typeObj;
            }
        }
        return null;
    }
}
