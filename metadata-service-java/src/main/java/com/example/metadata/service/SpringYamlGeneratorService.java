package com.example.metadata.service;

import com.example.metadata.model.Filter;
import com.example.metadata.model.FilterCondition;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

/**
 * Service for generating Spring Boot YAML configuration from Filter objects.
 */
@Service
@Slf4j
public class SpringYamlGeneratorService {

    /**
     * Generate complete YAML configuration from a list of filters.
     * Filters out disabled, deleted, and pending_deletion filters.
     */
    public String generateYaml(List<Filter> filters) {
        if (filters == null || filters.isEmpty()) {
            return generateEmptyYaml();
        }

        // Filter out disabled, deleted, and pending_deletion filters
        List<Filter> enabledFilters = filters.stream()
            .filter(filter -> {
                if (filter == null) {
                    return false;
                }
                // Skip disabled filters
                if (!filter.isEnabled()) {
                    return false;
                }
                // Skip deleted filters
                String status = filter.getStatus();
                if ("deleted".equals(status) || "pending_deletion".equals(status)) {
                    return false;
                }
                return true;
            })
            .collect(Collectors.toList());

        if (enabledFilters.isEmpty()) {
            return generateEmptyYaml();
        }

        List<String> lines = new ArrayList<>();
        
        // Header comments
        lines.add("# Generated Spring Boot Filter Configuration");
        lines.add("# Generated at: " + Instant.now().toString());
        lines.add("# Source: Metadata Service API");
        lines.add("# DO NOT EDIT MANUALLY - This file is auto-generated");
        lines.add("");

        // Track deprecated filters for warnings
        List<String> deprecatedFilters = enabledFilters.stream()
            .filter(f -> "deprecated".equals(f.getStatus()))
            .map(Filter::getId)
            .collect(Collectors.toList());

        if (!deprecatedFilters.isEmpty()) {
            lines.add("# WARNING: The following filters are deprecated and may be removed soon:");
            for (String filterId : deprecatedFilters) {
                lines.add("#   - " + filterId);
            }
            lines.add("");
        }

        lines.add("filters:");

        // Generate YAML for each filter
        for (Filter filter : enabledFilters) {
            lines.addAll(generateFilterYaml(filter));
        }

        return String.join("\n", lines);
    }

    /**
     * Generate YAML for a single filter.
     */
    public List<String> generateFilterYaml(Filter filter) {
        List<String> lines = new ArrayList<>();
        
        lines.add("  - id: " + filter.getId());
        lines.add("    name: " + escapeYamlString(filter.getName()));
        
        if (filter.getDescription() != null && !filter.getDescription().isEmpty()) {
            lines.add("    description: " + escapeYamlString(filter.getDescription()));
        }
        
        // Add -spring suffix to outputTopic if not already present
        String outputTopic = filter.getOutputTopic();
        if (outputTopic != null && !outputTopic.endsWith("-spring")) {
            outputTopic = outputTopic + "-spring";
        }
        lines.add("    outputTopic: " + outputTopic);
        
        String conditionLogic = "AND";
        List<FilterCondition> conditions = new ArrayList<>();
        if (filter.getConditions() != null) {
            conditionLogic = filter.getConditions().getLogic() != null ? filter.getConditions().getLogic() : "AND";
            conditions = filter.getConditions().getConditions() != null ? filter.getConditions().getConditions() : new ArrayList<>();
        }
        lines.add("    conditionLogic: " + conditionLogic);
        
        // Add enabled field
        lines.add("    enabled: " + filter.isEnabled());
        
        // Add conditions
        if (conditions != null && !conditions.isEmpty()) {
            lines.add("    conditions:");
            for (FilterCondition condition : conditions) {
                lines.addAll(formatCondition(condition));
            }
        } else {
            lines.add("    conditions: []");
        }

        return lines;
    }

    /**
     * Format a filter condition to YAML.
     */
    private List<String> formatCondition(FilterCondition condition) {
        List<String> lines = new ArrayList<>();
        lines.add("      - field: " + condition.getField());
        lines.add("        operator: " + condition.getOperator());
        
        // Handle value based on operator type
        if (condition.getValue() != null) {
            lines.add("        value: " + formatYamlValue(condition.getValue()));
        }
        
        if (condition.getValues() != null && !condition.getValues().isEmpty()) {
            lines.add("        values:");
            for (Object value : condition.getValues()) {
                lines.add("          - " + formatYamlValue(value));
            }
        }
        
        if (condition.getMin() != null) {
            lines.add("        min: " + formatYamlValue(condition.getMin()));
        }
        
        if (condition.getMax() != null) {
            lines.add("        max: " + formatYamlValue(condition.getMax()));
        }
        
        if (condition.getValueType() != null && !condition.getValueType().isEmpty()) {
            lines.add("        valueType: " + condition.getValueType());
        }

        return lines;
    }

    /**
     * Format a value for YAML output.
     */
    private String formatYamlValue(Object value) {
        if (value == null) {
            return "null";
        }
        
        if (value instanceof String) {
            String str = (String) value;
            // Quote strings that contain special characters or are numbers/booleans
            if (needsQuoting(str)) {
                return "\"" + escapeYamlString(str) + "\"";
            }
            return str;
        }
        
        if (value instanceof Number || value instanceof Boolean) {
            return value.toString();
        }
        
        // Default: quote as string
        return "\"" + escapeYamlString(value.toString()) + "\"";
    }

    /**
     * Check if a string needs to be quoted in YAML.
     */
    private boolean needsQuoting(String str) {
        if (str == null || str.isEmpty()) {
            return true;
        }
        
        // Quote if it looks like a number or boolean
        if (str.matches("^-?\\d+(\\.\\d+)?$") || 
            str.equalsIgnoreCase("true") || 
            str.equalsIgnoreCase("false") ||
            str.equalsIgnoreCase("null")) {
            return true;
        }
        
        // Quote if it contains special characters
        if (str.contains(":") || str.contains("#") || str.contains("|") || 
            str.contains("&") || str.contains("*") || str.contains("?") ||
            str.contains("-") || str.contains(" ") || str.startsWith("!") ||
            str.startsWith("@") || str.startsWith("`")) {
            return true;
        }
        
        return false;
    }

    /**
     * Escape special characters in YAML strings.
     */
    private String escapeYamlString(String str) {
        if (str == null) {
            return "";
        }
        // Escape backslashes and quotes
        return str.replace("\\", "\\\\")
                  .replace("\"", "\\\"")
                  .replace("\n", "\\n")
                  .replace("\r", "\\r");
    }

    /**
     * Generate empty YAML configuration.
     */
    private String generateEmptyYaml() {
        List<String> lines = new ArrayList<>();
        lines.add("# Generated Spring Boot Filter Configuration");
        lines.add("# Generated at: " + Instant.now().toString());
        lines.add("# Source: Metadata Service API");
        lines.add("# DO NOT EDIT MANUALLY - This file is auto-generated");
        lines.add("");
        lines.add("filters: []");
        return String.join("\n", lines);
    }
}

