package com.example.streamprocessor.config;

import com.example.streamprocessor.model.EventHeader;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.function.Predicate;

/**
 * Evaluates filter conditions against EventHeader objects.
 */
public class FilterConditionEvaluator {
    
    private static final Logger log = LoggerFactory.getLogger(FilterConditionEvaluator.class);
    
    /**
     * Creates a predicate that evaluates all conditions for a filter.
     */
    public static Predicate<EventHeader> createPredicate(FilterConfig filterConfig) {
        if (filterConfig == null || filterConfig.getConditions() == null || filterConfig.getConditions().isEmpty()) {
            return value -> false;
        }
        
        List<FilterCondition> conditions = filterConfig.getConditions();
        String conditionLogic = filterConfig.getConditionLogic() != null ? filterConfig.getConditionLogic() : "AND";
        
        return value -> {
            if (value == null) {
                return false;
            }
            
            boolean result;
            if ("OR".equalsIgnoreCase(conditionLogic)) {
                // OR logic: at least one condition must be true
                result = false;
                for (FilterCondition condition : conditions) {
                    if (evaluateCondition(condition, value)) {
                        result = true;
                        break;
                    }
                }
            } else {
                // AND logic (default): all conditions must be true
                result = true;
                for (FilterCondition condition : conditions) {
                    if (!evaluateCondition(condition, value)) {
                        result = false;
                        break;
                    }
                }
            }
            
            return result;
        };
    }
    
    /**
     * Evaluates a single condition against an EventHeader.
     */
    private static boolean evaluateCondition(FilterCondition condition, EventHeader value) {
        String field = condition.getField();
        String operator = condition.getOperator();
        
        Object fieldValue = getFieldValue(field, value);
        
        switch (operator) {
            case "equals":
                return compareEquals(fieldValue, condition.getValue());
            case "in":
                return compareIn(fieldValue, condition.getValues());
            case "notIn":
                return !compareIn(fieldValue, condition.getValues());
            case "greaterThan":
                return compareGreaterThan(fieldValue, condition.getValue());
            case "lessThan":
                return compareLessThan(fieldValue, condition.getValue());
            case "greaterThanOrEqual":
                return compareGreaterThanOrEqual(fieldValue, condition.getValue());
            case "lessThanOrEqual":
                return compareLessThanOrEqual(fieldValue, condition.getValue());
            case "between":
                return compareBetween(fieldValue, condition.getMin(), condition.getMax());
            case "matches":
                return compareMatches(fieldValue, condition.getValue());
            case "isNull":
                return fieldValue == null;
            case "isNotNull":
                return fieldValue != null;
            default:
                log.warn("Unknown operator: {}", operator);
                return false;
        }
    }
    
    /**
     * Gets the field value from EventHeader using reflection.
     */
    private static Object getFieldValue(String field, EventHeader value) {
        if (value == null) {
            return null;
        }
        
        switch (field) {
            case "id":
                return value.getId();
            case "event_name":
                return value.getEventName();
            case "event_type":
                return value.getEventType();
            case "created_date":
                return value.getCreatedDate();
            case "saved_date":
                return value.getSavedDate();
            case "header_data":
                return value.getHeaderData();
            case "__op":
                return value.getOp();
            case "__table":
                return value.getTable();
            case "__ts_ms":
                return value.getTsMs();
            default:
                log.warn("Unknown field: {}", field);
                return null;
        }
    }
    
    private static boolean compareEquals(Object fieldValue, String expectedValue) {
        if (fieldValue == null) {
            return expectedValue == null;
        }
        return fieldValue.toString().equals(expectedValue);
    }
    
    private static boolean compareIn(Object fieldValue, List<String> values) {
        if (fieldValue == null || values == null) {
            return false;
        }
        return values.contains(fieldValue.toString());
    }
    
    private static boolean compareGreaterThan(Object fieldValue, String expectedValue) {
        if (fieldValue == null || expectedValue == null) {
            return false;
        }
        try {
            if (fieldValue instanceof Number && isNumeric(expectedValue)) {
                return ((Number) fieldValue).doubleValue() > Double.parseDouble(expectedValue);
            }
            return fieldValue.toString().compareTo(expectedValue) > 0;
        } catch (Exception e) {
            log.warn("Error comparing values: {}", e.getMessage());
            return false;
        }
    }
    
    private static boolean compareLessThan(Object fieldValue, String expectedValue) {
        if (fieldValue == null || expectedValue == null) {
            return false;
        }
        try {
            if (fieldValue instanceof Number && isNumeric(expectedValue)) {
                return ((Number) fieldValue).doubleValue() < Double.parseDouble(expectedValue);
            }
            return fieldValue.toString().compareTo(expectedValue) < 0;
        } catch (Exception e) {
            log.warn("Error comparing values: {}", e.getMessage());
            return false;
        }
    }
    
    private static boolean compareGreaterThanOrEqual(Object fieldValue, String expectedValue) {
        return compareEquals(fieldValue, expectedValue) || compareGreaterThan(fieldValue, expectedValue);
    }
    
    private static boolean compareLessThanOrEqual(Object fieldValue, String expectedValue) {
        return compareEquals(fieldValue, expectedValue) || compareLessThan(fieldValue, expectedValue);
    }
    
    private static boolean compareBetween(Object fieldValue, String min, String max) {
        return compareGreaterThanOrEqual(fieldValue, min) && compareLessThanOrEqual(fieldValue, max);
    }
    
    private static boolean compareMatches(Object fieldValue, String pattern) {
        if (fieldValue == null || pattern == null) {
            return false;
        }
        // Simple pattern matching - convert SQL LIKE to Java regex
        String regex = pattern.replace("%", ".*").replace("_", ".");
        return fieldValue.toString().matches(regex);
    }
    
    private static boolean isNumeric(String str) {
        try {
            Double.parseDouble(str);
            return true;
        } catch (NumberFormatException e) {
            return false;
        }
    }
}

