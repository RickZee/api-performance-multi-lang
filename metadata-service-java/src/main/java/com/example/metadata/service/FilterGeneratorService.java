package com.example.metadata.service;

import com.example.metadata.model.Filter;
import com.example.metadata.model.FilterCondition;
import com.example.metadata.model.GenerateSQLResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

@Service
@Slf4j
public class FilterGeneratorService {

    public GenerateSQLResponse generateSQL(Filter filter) {
        if (!filter.isEnabled()) {
            return GenerateSQLResponse.builder()
                .filterId(filter.getId())
                .valid(false)
                .validationErrors(List.of("filter is disabled"))
                .build();
        }

        List<String> statements = new ArrayList<>();
        List<String> errors = new ArrayList<>();

        // Generate sink table statement
        try {
            String sinkTableSQL = generateSinkTable(filter);
            statements.add(sinkTableSQL);
        } catch (Exception e) {
            errors.add("failed to generate sink table: " + e.getMessage());
        }

        // Generate INSERT statement
        try {
            String insertSQL = generateInsertStatement(filter);
            statements.add(insertSQL);
        } catch (Exception e) {
            errors.add("failed to generate INSERT statement: " + e.getMessage());
        }

        // Combine all statements
        String fullSQL = String.join("\n\n", statements);

        return GenerateSQLResponse.builder()
            .filterId(filter.getId())
            .sql(fullSQL)
            .statements(statements)
            .valid(errors.isEmpty())
            .validationErrors(errors.isEmpty() ? null : errors)
            .build();
    }

    private String generateSinkTable(Filter filter) {
        String tableName = filter.getOutputTopic();
        
        return String.format("-- Sink Table: %s\n" +
            "CREATE TABLE `%s` (\n" +
            "    `key` BYTES,\n" +
            "    `id` STRING,\n" +
            "    `event_name` STRING,\n" +
            "    `event_type` STRING,\n" +
            "    `created_date` STRING,\n" +
            "    `saved_date` STRING,\n" +
            "    `header_data` STRING,\n" +
            "    `__op` STRING,\n" +
            "    `__table` STRING\n" +
            ") WITH (\n" +
            "    'connector' = 'confluent',\n" +
            "    'value.format' = 'json-registry'\n" +
            ");", filter.getName(), tableName);
    }

    private String generateInsertStatement(Filter filter) throws Exception {
        String tableName = filter.getOutputTopic();
        List<String> whereClauses = new ArrayList<>();
        whereClauses.add("`__op` = 'c'"); // Always filter for create operations

        for (FilterCondition condition : filter.getConditions()) {
            String whereClause = generateWhereClause(condition, filter.getConditionLogic());
            if (whereClause != null && !whereClause.isEmpty()) {
                whereClauses.add(whereClause);
            }
        }

        String whereSQL = String.join(" AND ", whereClauses);
        
        if ("OR".equals(filter.getConditionLogic()) && filter.getConditions().size() > 1) {
            // For OR logic, group conditions
            List<String> orClauses = new ArrayList<>();
            orClauses.add("`__op` = 'c'");
            for (FilterCondition condition : filter.getConditions()) {
                String clause = generateWhereClause(condition, "");
                if (clause != null && !clause.isEmpty()) {
                    orClauses.add(clause);
                }
            }
            whereSQL = orClauses.get(0) + " AND (" + 
                String.join(" OR ", orClauses.subList(1, orClauses.size())) + ")";
        }

        return String.format("-- INSERT Statement: %s\n" +
            "INSERT INTO `%s`\n" +
            "SELECT \n" +
            "    CAST(`id` AS BYTES) AS `key`,\n" +
            "    `id`,\n" +
            "    `event_name`,\n" +
            "    `event_type`,\n" +
            "    `created_date`,\n" +
            "    `saved_date`,\n" +
            "    `header_data`,\n" +
            "    `__op`,\n" +
            "    `__table`\n" +
            "FROM `raw-event-headers`\n" +
            "WHERE %s;", filter.getName(), tableName, whereSQL);
    }

    private String generateWhereClause(FilterCondition condition, String conditionLogic) throws Exception {
        String field = condition.getField();
        String operator = condition.getOperator();
        String valueType = condition.getValueType() != null ? condition.getValueType() : "string";

        // Convert field path to SQL expression
        String fieldExpr = fieldToSQL(field);

        String clause = null;

        switch (operator) {
            case "equals":
                clause = fieldExpr + " = " + formatValue(condition.getValue(), valueType);
                break;
            case "in":
                if (condition.getValues() == null || condition.getValues().isEmpty()) {
                    throw new Exception("'in' operator requires at least one value");
                }
                String inValues = condition.getValues().stream()
                    .map(v -> formatValue(v, valueType))
                    .collect(Collectors.joining(", "));
                clause = fieldExpr + " IN (" + inValues + ")";
                break;
            case "notIn":
                if (condition.getValues() == null || condition.getValues().isEmpty()) {
                    throw new Exception("'notIn' operator requires at least one value");
                }
                String notInValues = condition.getValues().stream()
                    .map(v -> formatValue(v, valueType))
                    .collect(Collectors.joining(", "));
                clause = fieldExpr + " NOT IN (" + notInValues + ")";
                break;
            case "greaterThan":
                clause = fieldExpr + " > " + formatValue(condition.getValue(), valueType);
                break;
            case "lessThan":
                clause = fieldExpr + " < " + formatValue(condition.getValue(), valueType);
                break;
            case "greaterThanOrEqual":
                clause = fieldExpr + " >= " + formatValue(condition.getValue(), valueType);
                break;
            case "lessThanOrEqual":
                clause = fieldExpr + " <= " + formatValue(condition.getValue(), valueType);
                break;
            case "between":
                clause = fieldExpr + " BETWEEN " + formatValue(condition.getMin(), valueType) + 
                    " AND " + formatValue(condition.getMax(), valueType);
                break;
            case "matches":
                clause = fieldExpr + " REGEXP " + formatValue(condition.getValue(), valueType);
                break;
            case "isNull":
                clause = fieldExpr + " IS NULL";
                break;
            case "isNotNull":
                clause = fieldExpr + " IS NOT NULL";
                break;
            default:
                throw new Exception("unsupported operator: " + operator);
        }

        return clause;
    }

    private String fieldToSQL(String field) {
        // Handle direct column references
        if (field.startsWith("`") || !field.contains(".")) {
            if (!field.startsWith("`")) {
                return "`" + field + "`";
            }
            return field;
        }

        // Handle nested JSON paths (e.g., header_data.dealerId)
        String[] parts = field.split("\\.");
        if (parts.length < 2) {
            throw new IllegalArgumentException("invalid field path: " + field);
        }

        String column = parts[0];
        if (!column.startsWith("`")) {
            column = "`" + column + "`";
        }

        // Build JSON path expression
        String jsonPath = "$." + String.join(".", java.util.Arrays.copyOfRange(parts, 1, parts.length));
        return "JSON_VALUE(" + column + ", '" + jsonPath + "')";
    }

    private String formatValue(Object value, String valueType) {
        if (value == null) {
            return "NULL";
        }

        switch (valueType.toLowerCase()) {
            case "string":
                return "'" + value.toString().replace("'", "''") + "'";
            case "number":
            case "integer":
                return value.toString();
            case "boolean":
                return value.toString();
            default:
                return "'" + value.toString().replace("'", "''") + "'";
        }
    }
}
