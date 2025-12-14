package filter

import (
	"fmt"
	"strings"

	"go.uber.org/zap"
)

// Generator generates Flink SQL from filter configurations
type Generator struct {
	logger *zap.Logger
}

// NewGenerator creates a new Flink SQL generator
func NewGenerator(logger *zap.Logger) *Generator {
	return &Generator{
		logger: logger,
	}
}

// GenerateSQLResponse represents the response from SQL generation
type GenerateSQLResponse struct {
	FilterID         string
	SQL              string
	Statements       []string
	Valid            bool
	ValidationErrors []string
}

// GenerateSQL generates Flink SQL statements for a filter
func (g *Generator) GenerateSQL(filter *Filter) (*GenerateSQLResponse, error) {
	if !filter.Enabled {
		return &GenerateSQLResponse{
			FilterID:         filter.ID,
			Valid:            false,
			ValidationErrors: []string{"filter is disabled"},
		}, nil
	}

	var statements []string
	var errors []string

	// Generate sink table statement
	sinkTableSQL, err := g.generateSinkTable(filter)
	if err != nil {
		errors = append(errors, fmt.Sprintf("failed to generate sink table: %v", err))
	} else {
		statements = append(statements, sinkTableSQL)
	}

	// Generate INSERT statement
	insertSQL, err := g.generateInsertStatement(filter)
	if err != nil {
		errors = append(errors, fmt.Sprintf("failed to generate INSERT statement: %v", err))
	} else {
		statements = append(statements, insertSQL)
	}

	// Combine all statements
	fullSQL := strings.Join(statements, "\n\n")

	return &GenerateSQLResponse{
		FilterID:         filter.ID,
		SQL:              fullSQL,
		Statements:       statements,
		Valid:            len(errors) == 0,
		ValidationErrors: errors,
	}, nil
}

// generateSinkTable generates the CREATE TABLE statement for the sink
func (g *Generator) generateSinkTable(filter *Filter) (string, error) {
	tableName := filter.OutputTopic

	sql := fmt.Sprintf(`-- Sink Table: %s
CREATE TABLE `+"`%s`"+` (
    `+"`key`"+` BYTES,
    `+"`id`"+` STRING,
    `+"`event_name`"+` STRING,
    `+"`event_type`"+` STRING,
    `+"`created_date`"+` STRING,
    `+"`saved_date`"+` STRING,
    `+"`header_data`"+` STRING,
    `+"`__op`"+` STRING,
    `+"`__table`"+` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry'
);`, filter.Name, tableName)

	return sql, nil
}

// generateInsertStatement generates the INSERT INTO ... SELECT ... WHERE statement
func (g *Generator) generateInsertStatement(filter *Filter) (string, error) {
	tableName := filter.OutputTopic

	// Build WHERE clause from conditions
	whereClauses := []string{"`__op` = 'c'"} // Always filter for create operations

	for i, condition := range filter.Conditions {
		whereClause, err := g.generateWhereClause(condition, i > 0, filter.ConditionLogic)
		if err != nil {
			return "", fmt.Errorf("failed to generate WHERE clause for condition %d: %w", i, err)
		}
		if whereClause != "" {
			whereClauses = append(whereClauses, whereClause)
		}
	}

	whereSQL := strings.Join(whereClauses, " AND ")
	if filter.ConditionLogic == "OR" && len(filter.Conditions) > 1 {
		// For OR logic, we need to group conditions differently
		orClauses := []string{"`__op` = 'c'"}
		for _, condition := range filter.Conditions {
			whereClause, err := g.generateWhereClause(condition, false, "")
			if err == nil && whereClause != "" {
				orClauses = append(orClauses, whereClause)
			}
		}
		whereSQL = strings.Join(orClauses[:1], " AND ") + " AND (" + strings.Join(orClauses[1:], " OR ") + ")"
	}

	sql := fmt.Sprintf(`-- INSERT Statement: %s
INSERT INTO `+"`%s`"+`
SELECT 
    CAST(`+"`id`"+` AS BYTES) AS `+"`key`"+`,
    `+"`id`"+`,
    `+"`event_name`"+`,
    `+"`event_type`"+`,
    `+"`created_date`"+`,
    `+"`saved_date`"+`,
    `+"`header_data`"+`,
    `+"`__op`"+`,
    `+"`__table`"+`
FROM `+"`raw-event-headers`"+`
WHERE %s;`, filter.Name, tableName, whereSQL)

	return sql, nil
}

// generateWhereClause generates a WHERE clause for a single condition
func (g *Generator) generateWhereClause(condition FilterCondition, isNotFirst bool, conditionLogic string) (string, error) {
	field := condition.Field
	operator := condition.Operator
	valueType := condition.ValueType
	if valueType == "" {
		valueType = "string"
	}

	// Convert field path to SQL expression
	fieldExpr, err := g.fieldToSQL(field)
	if err != nil {
		return "", fmt.Errorf("invalid field path: %w", err)
	}

	var clause string

	switch operator {
	case "equals":
		value := g.formatValue(condition.Value, valueType)
		clause = fmt.Sprintf("%s = %s", fieldExpr, value)

	case "in":
		values := condition.Values
		if len(values) == 0 {
			return "", fmt.Errorf("'in' operator requires at least one value")
		}
		formattedValues := make([]string, len(values))
		for i, v := range values {
			formattedValues[i] = g.formatValue(v, valueType)
		}
		clause = fmt.Sprintf("%s IN (%s)", fieldExpr, strings.Join(formattedValues, ", "))

	case "notIn":
		values := condition.Values
		if len(values) == 0 {
			return "", fmt.Errorf("'notIn' operator requires at least one value")
		}
		formattedValues := make([]string, len(values))
		for i, v := range values {
			formattedValues[i] = g.formatValue(v, valueType)
		}
		clause = fmt.Sprintf("%s NOT IN (%s)", fieldExpr, strings.Join(formattedValues, ", "))

	case "greaterThan":
		value := g.formatValue(condition.Value, valueType)
		clause = fmt.Sprintf("%s > %s", fieldExpr, value)

	case "lessThan":
		value := g.formatValue(condition.Value, valueType)
		clause = fmt.Sprintf("%s < %s", fieldExpr, value)

	case "greaterThanOrEqual":
		value := g.formatValue(condition.Value, valueType)
		clause = fmt.Sprintf("%s >= %s", fieldExpr, value)

	case "lessThanOrEqual":
		value := g.formatValue(condition.Value, valueType)
		clause = fmt.Sprintf("%s <= %s", fieldExpr, value)

	case "between":
		min := g.formatValue(condition.Min, valueType)
		max := g.formatValue(condition.Max, valueType)
		clause = fmt.Sprintf("%s BETWEEN %s AND %s", fieldExpr, min, max)

	case "matches":
		value := g.formatValue(condition.Value, valueType)
		// Flink SQL uses REGEXP for pattern matching
		clause = fmt.Sprintf("%s REGEXP %s", fieldExpr, value)

	case "isNull":
		clause = fmt.Sprintf("%s IS NULL", fieldExpr)

	case "isNotNull":
		clause = fmt.Sprintf("%s IS NOT NULL", fieldExpr)

	default:
		return "", fmt.Errorf("unsupported operator: %s", operator)
	}

	return clause, nil
}

// fieldToSQL converts a field path to a SQL expression
func (g *Generator) fieldToSQL(field string) (string, error) {
	// Handle direct column references
	if strings.HasPrefix(field, "`") || !strings.Contains(field, ".") {
		// Direct column name (e.g., event_type, id)
		if !strings.HasPrefix(field, "`") {
			field = "`" + field + "`"
		}
		return field, nil
	}

	// Handle nested JSON paths (e.g., header_data.dealerId)
	parts := strings.Split(field, ".")
	if len(parts) < 2 {
		return "", fmt.Errorf("invalid field path: %s", field)
	}

	// First part should be a column name
	column := parts[0]
	if !strings.HasPrefix(column, "`") {
		column = "`" + column + "`"
	}

	// Build JSON path expression
	jsonPath := "$"
	for i := 1; i < len(parts); i++ {
		jsonPath += "." + parts[i]
	}

	// Use JSON_VALUE function for JSON path extraction
	return fmt.Sprintf("JSON_VALUE(%s, '%s')", column, jsonPath), nil
}

// formatValue formats a value for SQL
func (g *Generator) formatValue(value interface{}, valueType string) string {
	if value == nil {
		return "NULL"
	}

	switch valueType {
	case "number":
		return fmt.Sprintf("%v", value)
	case "boolean":
		if b, ok := value.(bool); ok {
			if b {
				return "TRUE"
			}
			return "FALSE"
		}
		return fmt.Sprintf("%v", value)
	case "timestamp":
		// Timestamps should be strings in SQL
		return fmt.Sprintf("'%v'", value)
	default: // string
		// Escape single quotes in strings
		str := fmt.Sprintf("%v", value)
		str = strings.ReplaceAll(str, "'", "''")
		return fmt.Sprintf("'%s'", str)
	}
}
