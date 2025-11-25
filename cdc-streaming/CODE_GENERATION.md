# Flink SQL Code Generation Guide

This guide explains how to use the configurable filter query code generation system to automatically generate Flink SQL from YAML filter configurations.

## Overview

The code generation system allows you to:
- Define filters declaratively in YAML
- Automatically generate Flink SQL queries
- Validate configurations before deployment
- Integrate with CI/CD pipelines

## Quick Start

### 1. Install Dependencies

```bash
cd cdc-streaming
pip install -r scripts/requirements.txt
```

### 2. Validate Your Filter Configuration

```bash
python scripts/validate-filters.py \
  --config flink-jobs/filters.yaml \
  --schema schemas/filter-schema.json
```

### 3. Generate SQL

```bash
python scripts/generate-flink-sql.py \
  --config flink-jobs/filters.yaml \
  --output flink-jobs/routing-generated.sql
```

### 4. Validate Generated SQL

```bash
python scripts/validate-sql.py \
  --sql flink-jobs/routing-generated.sql
```

## YAML Configuration Reference

### Basic Filter Structure

```yaml
filters:
  - id: loan-events-filter          # Unique identifier (required)
    name: "Loan Events Filter"      # Human-readable name (required)
    description: "Filters loan events"  # Optional description
    consumerId: loan-consumer       # Consumer identifier (required)
    outputTopic: filtered-loan-events  # Kafka topic name (required)
    enabled: true                   # Enable/disable filter (required)
    conditions:                     # Filter conditions (required)
      - field: eventHeader.eventName
        operator: in
        values: ["LoanCreated", "LoanPaymentSubmitted"]
        valueType: string
    conditionLogic: AND            # How to combine conditions (default: AND)
```

### Field Paths

Field paths specify where to find data in the event structure:

- **Simple fields**: `eventHeader.eventName`
- **Array access**: `eventBody.entities[0].entityType` (0-based in YAML, converted to 1-based in SQL)
- **Map access**: `eventBody.entities[0].updatedAttributes.loan.loanAmount`

### Supported Operators

| Operator | Description | Required Fields | Example |
|----------|-------------|-----------------|---------|
| `equals` | Exact match | `value` | `value: "LoanCreated"` |
| `in` | Match any value in list | `values` | `values: ["LoanCreated", "LoanPayment"]` |
| `notIn` | Exclude values in list | `values` | `values: ["TestEvent"]` |
| `greaterThan` | Numeric greater than | `value` | `value: 50000` |
| `lessThan` | Numeric less than | `value` | `value: 100` |
| `greaterThanOrEqual` | Numeric >= | `value` | `value: 50000` |
| `lessThanOrEqual` | Numeric <= | `value` | `value: 100` |
| `between` | Range check | `min`, `max` | `min: 25000, max: 75000` |
| `matches` | Regex pattern | `value` | `value: "^loan-.*-premium$"` |
| `isNull` | Check for null | (none) | - |
| `isNotNull` | Check for not null | (none) | - |

### Value Types

Specify the type of value for proper SQL casting:

- `string`: String values (default)
- `number`: Numeric values (automatically cast for comparisons)
- `boolean`: Boolean values
- `timestamp`: Timestamp values

### Condition Logic

Multiple conditions can be combined with:

- `AND`: All conditions must match (default)
- `OR`: Any condition can match

You can also specify `logicalOperator` per condition:

```yaml
conditions:
  - field: eventHeader.eventName
    operator: equals
    value: "LoanCreated"
    logicalOperator: OR  # This condition uses OR with previous
  - field: eventHeader.eventName
    operator: equals
    value: "LoanPaymentSubmitted"
```

## Examples

### Example 1: Basic Event Name Filter

```yaml
filters:
  - id: car-created-filter
    name: "Car Created Events"
    consumerId: car-consumer
    outputTopic: filtered-car-events
    conditions:
      - field: eventHeader.eventName
        operator: equals
        value: "CarCreated"
        valueType: string
    enabled: true
```

**Generated SQL:**
```sql
INSERT INTO filtered_car_events
SELECT 
    `eventHeader`,
    `eventBody`,
    `sourceMetadata`,
    ROW('car-created-filter', 'car-consumer', UNIX_TIMESTAMP() * 1000) AS `filterMetadata`
FROM raw_business_events
WHERE `eventHeader`.`eventName` = 'CarCreated';
```

### Example 2: Multiple Event Names (IN)

```yaml
filters:
  - id: payment-events-filter
    name: "Payment Events"
    consumerId: payment-consumer
    outputTopic: filtered-payment-events
    conditions:
      - field: eventHeader.eventName
        operator: in
        values: ["LoanPaymentSubmitted", "PaymentProcessed", "PaymentFailed"]
        valueType: string
    enabled: true
```

### Example 3: Value-Based Filtering

```yaml
filters:
  - id: high-value-loan-filter
    name: "High Value Loans"
    consumerId: loan-consumer
    outputTopic: filtered-high-value-loans
    conditions:
      - field: eventHeader.eventName
        operator: equals
        value: "LoanCreated"
        valueType: string
      - field: eventBody.entities[0].updatedAttributes.loan.loanAmount
        operator: greaterThan
        value: 100000
        valueType: number
    enabled: true
```

**Generated SQL:**
```sql
INSERT INTO filtered_high_value_loans
SELECT 
    `eventHeader`,
    `eventBody`,
    `sourceMetadata`,
    ROW('high-value-loan-filter', 'loan-consumer', UNIX_TIMESTAMP() * 1000) AS `filterMetadata`
FROM raw_business_events
WHERE `eventHeader`.`eventName` = 'LoanCreated' AND CAST(`eventBody`.`entities`[1].`updatedAttributes`['loan.loanAmount'] AS DOUBLE) > 100000;
```

### Example 4: Range Filter (BETWEEN)

```yaml
filters:
  - id: medium-loan-filter
    name: "Medium Value Loans"
    consumerId: loan-consumer
    outputTopic: filtered-medium-loans
    conditions:
      - field: eventHeader.eventName
        operator: equals
        value: "LoanCreated"
        valueType: string
      - field: eventBody.entities[0].updatedAttributes.loan.loanAmount
        operator: between
        min: 25000
        max: 75000
        valueType: number
    enabled: true
```

### Example 5: Pattern Matching

```yaml
filters:
  - id: pattern-match-filter
    name: "Pattern Match Filter"
    consumerId: pattern-consumer
    outputTopic: filtered-pattern-events
    conditions:
      - field: eventBody.entities[0].entityId
        operator: matches
        value: "^loan-.*-premium$"
        valueType: string
    enabled: true
```

## Command Line Options

### generate-flink-sql.py

```bash
python scripts/generate-flink-sql.py [OPTIONS]
```

Options:
- `--config`: Path to YAML filter configuration (default: `flink-jobs/filters.yaml`)
- `--output`: Path to output SQL file (default: `flink-jobs/routing-generated.sql`)
- `--template-dir`: Directory containing Jinja2 templates (default: `scripts/templates`)
- `--schema`: Path to JSON schema for validation (default: `schemas/filter-schema.json`)
- `--kafka-bootstrap`: Kafka bootstrap servers (default: `kafka:29092`)
- `--schema-registry`: Schema Registry URL (default: `http://schema-registry:8081`)
- `--no-validate`: Skip YAML schema validation

### validate-filters.py

```bash
python scripts/validate-filters.py [OPTIONS]
```

Options:
- `--config`: Path to YAML filter configuration (default: `flink-jobs/filters.yaml`)
- `--schema`: Path to JSON schema file (default: `schemas/filter-schema.json`)

### validate-sql.py

```bash
python scripts/validate-sql.py [OPTIONS]
```

Options:
- `--sql`: Path to SQL file (default: `flink-jobs/routing-generated.sql`)

## CI/CD Integration

### GitHub Actions

The repository includes a GitHub Actions workflow (`.github/workflows/generate-flink-sql.yml`) that:

1. Validates YAML filters on push/PR
2. Generates SQL automatically
3. Validates generated SQL
4. Runs tests
5. Uploads artifacts or creates PR comments

### Jenkins Pipeline

Add to your Jenkinsfile:

```groovy
stage('Generate Flink SQL') {
    steps {
        sh '''
            cd cdc-streaming
            pip install -r scripts/requirements.txt
            python scripts/validate-filters.py
            python scripts/generate-flink-sql.py
            python scripts/validate-sql.py
        '''
    }
}
```

### Pre-commit Hook

Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash
cd cdc-streaming
python scripts/validate-filters.py || exit 1
python scripts/generate-flink-sql.py || exit 1
git add flink-jobs/routing-generated.sql
```

## Testing

### Run Unit Tests

```bash
cd cdc-streaming
python -m pytest tests/test_generator.py -v
```

Or directly:

```bash
python tests/test_generator.py
```

### Test with Sample Filters

```bash
python scripts/generate-flink-sql.py \
  --config tests/test_fixtures/sample-filters.yaml \
  --output tests/test_fixtures/test-output.sql
```

## Migration Guide

### From Manual SQL to Generated SQL

1. **Backup existing SQL**: Copy `routing.sql` to `routing.sql.backup`

2. **Convert filters to YAML**: Extract filter logic from SQL and create YAML entries

3. **Generate SQL**: Run the generator to create `routing-generated.sql`

4. **Compare outputs**: Verify generated SQL matches expected behavior

5. **Test**: Deploy generated SQL to test environment

6. **Switch**: Once validated, use generated SQL in production

### Example Migration

**Before (Manual SQL):**
```sql
INSERT INTO filtered_loan_events
SELECT 
    `eventHeader`,
    `eventBody`,
    `sourceMetadata`,
    ROW('loan-events-filter', 'loan-consumer', UNIX_TIMESTAMP() * 1000) AS `filterMetadata`
FROM raw_business_events
WHERE (`eventHeader`.`eventName` = 'LoanCreated' OR `eventHeader`.`eventName` = 'LoanPaymentSubmitted');
```

**After (YAML Config):**
```yaml
filters:
  - id: loan-events-filter
    name: "Loan Events Filter"
    consumerId: loan-consumer
    outputTopic: filtered-loan-events
    conditions:
      - field: eventHeader.eventName
        operator: in
        values: ["LoanCreated", "LoanPaymentSubmitted"]
        valueType: string
    enabled: true
```

## Troubleshooting

### Validation Errors

**Error: "YAML validation failed"**
- Check that all required fields are present
- Verify field paths are correct
- Ensure operators match required fields

**Error: "Invalid field path"**
- Field paths must use dot notation
- Array indices are 0-based in YAML (converted to 1-based in SQL)
- Map keys use dot notation: `updatedAttributes.loan.loanAmount`

### Generation Issues

**No filters generated**
- Check that filters have `enabled: true`
- Verify YAML syntax is correct
- Check for validation errors

**Incorrect SQL output**
- Verify field path translation
- Check operator mappings
- Review template for issues

### Common Mistakes

1. **Array indexing**: Use `[0]` in YAML, not `[1]`
2. **Map access**: Use dot notation: `updatedAttributes.loan.loanAmount`
3. **Value types**: Specify `valueType: number` for numeric comparisons
4. **String values**: Always quote string values in YAML

## Best Practices

1. **Version control**: Commit both YAML configs and generated SQL
2. **Validation**: Always validate before generating
3. **Testing**: Test generated SQL in development first
4. **Documentation**: Add descriptions to filters
5. **Naming**: Use consistent naming conventions for filter IDs and topics
6. **Incremental**: Migrate filters one at a time
7. **Review**: Review generated SQL before deployment

## Advanced Usage

### Custom Templates

Modify `scripts/templates/routing.sql.j2` to customize SQL generation.

### Extending Operators

Add new operators in `generate-flink-sql.py`:

```python
elif operator == 'customOperator':
    # Your custom logic
    sql = f"{field_sql} CUSTOM_FUNCTION({value})"
```

### Schema Extensions

Extend `schemas/filter-schema.json` to support new filter properties.

## Support

For issues or questions:
1. Check this documentation
2. Review example configurations in `filters-examples.yaml`
3. Check test fixtures in `tests/test_fixtures/`
4. Open an issue in the repository


