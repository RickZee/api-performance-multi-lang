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
        
        // Check for removed required fields (breaking if field is also removed from properties)
        // If field still exists but is no longer required, that's non-breaking
        Map<String, Object> oldProps = getProperties(oldSchema);
        Map<String, Object> newProps = getProperties(newSchema);
        
        for (String field : oldRequired) {
            if (!newRequired.contains(field)) {
                if (!newProps.containsKey(field)) {
                    // Field was completely removed - breaking
                    result.setCompatible(false);
                    result.getBreakingChanges().add("Required field '" + field + "' was removed");
                } else {
                    // Field still exists but is no longer required - non-breaking
                    result.getNonBreakingChanges().add("Required field '" + field + "' was made optional");
                }
            }
        }
        
        // Check for new required fields (breaking)
        for (String field : newRequired) {
            if (!oldRequired.contains(field)) {
                result.setCompatible(false);
                result.getBreakingChanges().add("New required field '" + field + "' was added");
            }
        }
        
        // Properties already retrieved above
        
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
                } else {
                    // Check for enum changes
                    checkEnumChanges(propName, entry.getValue(), newProps.get(propName), result);
                    
                    // Check for constraint changes (min/max)
                    checkConstraintChanges(propName, entry.getValue(), newProps.get(propName), result);
                }
            }
        }
        
        // Check for new optional properties (non-breaking)
        for (String propName : newProps.keySet()) {
            if (!oldProps.containsKey(propName) && !newRequired.contains(propName)) {
                result.getNonBreakingChanges().add("New optional property '" + propName + "' was added");
            }
        }
        
        // Check additionalProperties changes
        checkAdditionalPropertiesChanges(oldSchema, newSchema, result);
        
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
    
    @SuppressWarnings("unchecked")
    private void checkEnumChanges(String propName, Object oldSchemaObj, Object newSchemaObj, CompatibilityResult result) {
        if (!(oldSchemaObj instanceof Map) || !(newSchemaObj instanceof Map)) {
            return;
        }
        
        Map<String, Object> oldSchema = (Map<String, Object>) oldSchemaObj;
        Map<String, Object> newSchema = (Map<String, Object>) newSchemaObj;
        
        Object oldEnumObj = oldSchema.get("enum");
        Object newEnumObj = newSchema.get("enum");
        
        if (oldEnumObj == null && newEnumObj == null) {
            return; // No enum in either
        }
        
        if (oldEnumObj == null || newEnumObj == null) {
            // Enum added or removed - this is a type change, already handled
            return;
        }
        
        if (!(oldEnumObj instanceof List) || !(newEnumObj instanceof List)) {
            return;
        }
        
        List<?> oldEnum = (List<?>) oldEnumObj;
        List<?> newEnum = (List<?>) newEnumObj;
        
        Set<Object> oldEnumSet = new HashSet<>(oldEnum);
        Set<Object> newEnumSet = new HashSet<>(newEnum);
        
        // Check for removed enum values (breaking)
        for (Object value : oldEnumSet) {
            if (!newEnumSet.contains(value)) {
                result.setCompatible(false);
                result.getBreakingChanges().add("Property '" + propName + "' enum value '" + value + "' was removed");
            }
        }
        
        // Check for added enum values (non-breaking)
        for (Object value : newEnumSet) {
            if (!oldEnumSet.contains(value)) {
                result.getNonBreakingChanges().add("Property '" + propName + "' enum value '" + value + "' was added");
            }
        }
    }
    
    @SuppressWarnings("unchecked")
    private void checkConstraintChanges(String propName, Object oldSchemaObj, Object newSchemaObj, CompatibilityResult result) {
        if (!(oldSchemaObj instanceof Map) || !(newSchemaObj instanceof Map)) {
            return;
        }
        
        Map<String, Object> oldSchema = (Map<String, Object>) oldSchemaObj;
        Map<String, Object> newSchema = (Map<String, Object>) newSchemaObj;
        
        // Check minimum constraint
        Object oldMin = oldSchema.get("minimum");
        Object newMin = newSchema.get("minimum");
        if (oldMin != null && newMin != null) {
            if (oldMin instanceof Number && newMin instanceof Number) {
                double oldMinVal = ((Number) oldMin).doubleValue();
                double newMinVal = ((Number) newMin).doubleValue();
                if (newMinVal > oldMinVal) {
                    result.setCompatible(false);
                    result.getBreakingChanges().add("Property '" + propName + "' minimum constraint tightened from " + oldMinVal + " to " + newMinVal);
                } else if (newMinVal < oldMinVal) {
                    result.getNonBreakingChanges().add("Property '" + propName + "' minimum constraint relaxed from " + oldMinVal + " to " + newMinVal);
                }
            }
        } else if (oldMin == null && newMin != null) {
            // Minimum added - this is constraint tightening (breaking)
            result.setCompatible(false);
            result.getBreakingChanges().add("Property '" + propName + "' minimum constraint was added");
        } else if (oldMin != null && newMin == null) {
            // Minimum removed - this is constraint relaxing (non-breaking)
            result.getNonBreakingChanges().add("Property '" + propName + "' minimum constraint was removed");
        }
        
        // Check maximum constraint
        Object oldMax = oldSchema.get("maximum");
        Object newMax = newSchema.get("maximum");
        if (oldMax != null && newMax != null) {
            if (oldMax instanceof Number && newMax instanceof Number) {
                double oldMaxVal = ((Number) oldMax).doubleValue();
                double newMaxVal = ((Number) newMax).doubleValue();
                if (newMaxVal < oldMaxVal) {
                    result.setCompatible(false);
                    result.getBreakingChanges().add("Property '" + propName + "' maximum constraint tightened from " + oldMaxVal + " to " + newMaxVal);
                } else if (newMaxVal > oldMaxVal) {
                    result.getNonBreakingChanges().add("Property '" + propName + "' maximum constraint relaxed from " + oldMaxVal + " to " + newMaxVal);
                }
            }
        } else if (oldMax == null && newMax != null) {
            // Maximum added - this is constraint tightening (breaking)
            result.setCompatible(false);
            result.getBreakingChanges().add("Property '" + propName + "' maximum constraint was added");
        } else if (oldMax != null && newMax == null) {
            // Maximum removed - this is constraint relaxing (non-breaking)
            result.getNonBreakingChanges().add("Property '" + propName + "' maximum constraint was removed");
        }
    }
    
    @SuppressWarnings("unchecked")
    private void checkAdditionalPropertiesChanges(Map<String, Object> oldSchema, Map<String, Object> newSchema, CompatibilityResult result) {
        Object oldAdditional = oldSchema.get("additionalProperties");
        Object newAdditional = newSchema.get("additionalProperties");
        
        if (oldAdditional == null && newAdditional == null) {
            return; // Both default (true)
        }
        
        boolean oldAllows = oldAdditional == null || Boolean.TRUE.equals(oldAdditional);
        boolean newAllows = newAdditional == null || Boolean.TRUE.equals(newAdditional);
        
        if (oldAllows && !newAllows) {
            // Changed from true to false - breaking (disallows extra properties)
            result.setCompatible(false);
            result.getBreakingChanges().add("additionalProperties changed from true to false (breaking)");
        } else if (!oldAllows && newAllows) {
            // Changed from false to true - non-breaking (allows extra properties)
            result.getNonBreakingChanges().add("additionalProperties changed from false to true (non-breaking)");
        }
    }
}
