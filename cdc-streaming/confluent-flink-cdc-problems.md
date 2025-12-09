# Confluent Flink CDC Streaming Problems and Solutions

### Problems Identified

#### 1. Nested JSON in `updatedAttributes` vs. `MAP<STRING, STRING>`

**Issue**: The API data model uses flexible nested JSON:

```json
{
  "updatedAttributes": {
    "loan": { "loanAmount": 50000, "balance": 50000 }
  }
}
```

But Flink SQL defines it as `MAP<STRING, STRING>`, which only supports flat string key-value pairs.

**Impact**:

- Cannot filter on nested paths like `updatedAttributes.loan.loanAmount`
- Cannot perform numeric comparisons (values are strings)
- Filter configurations in `filters.yaml` referencing nested attributes fail

#### 2. Confluent Flink Automatic Eventtime Inference

**Issue**: Confluent Flink automatically infers eventtime from timestamp columns like `__ts_ms`.

**Impact**:

- Unwanted watermark generation
- Conflicts with explicit eventtime definitions
- Processing overhead even when not needed

**Current Workaround**: Sink tables exclude `__ts_ms` to avoid inference.

#### 3. SQL Dialect Differences

**Apache Flink vs. Confluent Cloud Flink**:

| Feature | Apache Flink | Confluent Cloud |
|---------|--------------|-----------------|
| Connector | `'kafka'` | `'confluent'` |
| Topic specification | `'topic' = 'name'` | Table name = topic name |
| `PROCTIME()` | Supported | Not supported |
| Nested ROW types | Full support | Limited support |

#### 4. Schema Mismatch Chain

```
API Data Model (nested JSON) 
    → PostgreSQL (JSONB) 
    → Debezium CDC (flat JSON or envelope format) 
    → Flink SQL (MAP<STRING, STRING> or STRING)
```

Each transformation loses or changes structure.

### Solutions

## Category 1: Data Model Changes

### Solution 1A: Flatten `updatedAttributes` at API Level

**Description**: Modify producer APIs to flatten nested structures before database storage.

**Implementation**:

```json
// Before (nested)
{ "updatedAttributes": { "loan": { "loanAmount": 50000 } } }

// After (flattened)
{ "updatedAttributes": { "loan.loanAmount": "50000", "loan.balance": "50000" } }
```

**Pros**:

- Compatible with `MAP<STRING, STRING>`
- No changes to streaming infrastructure
- Simple filtering in Flink SQL

**Cons**:

- Breaking change to API contract
- Requires coordination with all API consumers
- Loss of type information (everything becomes strings)

**Considerations**:

- Can complicate or break data lineage
- Requires API versioning (v1 → v2)
- Full audit trail for schema changes

### Solution 1B: Store `updatedAttributes` as JSON String

**Description**: Store nested JSON as a stringified JSON field, use `JSON_VALUE()` in Flink.

**Database**:

```sql
-- Store as TEXT/VARCHAR instead of JSONB
data JSONB  -- Entire row as JSON
```

**Flink SQL**:

```sql
CREATE TABLE raw_business_events (
    `data` STRING,  -- JSON string
    ...
) WITH (...);

-- Filter using JSON_VALUE()
SELECT * FROM raw_business_events
WHERE CAST(JSON_VALUE(`data`, '$.loan.loanAmount') AS DOUBLE) > 100000;
```

**Pros**:

- Preserves original nested structure
- Full access to nested fields via JSON functions
- No API changes required

**Cons**:

- Performance overhead from JSON parsing
- More complex SQL queries
- Type casting required for comparisons

**Considerations**:

- Data integrity preserved (original structure maintained)
- Full audit capability
- Compliance-friendly (no data loss)

### Solution 1C: Schema-First Design with Avro

**Description**: Define strict Avro schemas with explicit nested record types.

**Avro Schema**:

```json
{
  "name": "UpdatedAttributes",
  "type": "record",
  "fields": [
    {
      "name": "loan",
      "type": ["null", {
        "type": "record",
        "name": "LoanAttributes",
        "fields": [
          {"name": "loanAmount", "type": "double"},
          {"name": "balance", "type": "double"}
        ]
      }]
    }
  ]
}
```

**Flink SQL**:

```sql
CREATE TABLE raw_business_events (
    `updatedAttributes` ROW<
        `loan` ROW<
            `loanAmount` DOUBLE,
            `balance` DOUBLE
        >
    >
) WITH (
    'format' = 'avro-confluent',
    ...
);
```

**Pros**:

- Type safety enforced by Schema Registry
- Efficient serialization/deserialization
- Direct field access in Flink SQL
- Schema evolution support

**Cons**:

- Requires schema upfront
- Less flexible than JSON
- Breaking change for dynamic attributes

**Considerations**:

- Strong data contracts (compliance-friendly)
- Schema versioning for audit trails
- Backward/forward compatibility configurable

## Category 2: Confluent Cloud Customizations

### Solution 2A: Use Debezium Flat Format + JSON Functions

**Description**: Keep Debezium's flat CDC output, store entity data as JSON string, use Confluent Flink's JSON functions.

**Current Implementation** (already in your code):

```sql
CREATE TABLE `raw-business-events` (
    `id` STRING,
    `car_id` STRING,
    `entity_type` STRING,
    `data` STRING,  -- JSON string
    `__op` STRING,
    `__table` STRING
) WITH (
    'connector' = 'confluent',
    'value.format' = 'json-registry'
);

-- Filter using JSON functions
INSERT INTO `filtered-loan-events`
SELECT * FROM `raw-business-events`
WHERE CAST(JSON_VALUE(`data`, '$.loan.loanAmount') AS DOUBLE) > 100000;
```

**Pros**:

- Compatible with Confluent Cloud
- Preserves original data

**Cons**:

- JSON parsing overhead
- More complex filter generation
- Limited optimization by Flink?

**Considerations**:

- Full data preservation
- Auditable transformations

### Solution 2B: Multi-Stage Flink Processing Pipeline

**Description**: Use a staged pipeline: Stage 1 flattens/transforms data, Stage 2 applies business filters.

**Architecture**:

```
[CDC Topic] → [Flink Stage 1: Transform] → [Normalized Topic] → [Flink Stage 2: Filter] → [Filtered Topics]
```

**Stage 1 SQL**:

```sql
-- Transform nested JSON to flat structure
INSERT INTO normalized_events
SELECT 
    id,
    entity_type,
    JSON_VALUE(data, '$.loan.loanAmount') AS loan_amount,
    JSON_VALUE(data, '$.loan.balance') AS loan_balance,
    __op,
    __table
FROM `raw-business-events`
WHERE entity_type = 'Loan';
```

**Stage 2 SQL**:

```sql
-- Apply business filters on normalized data
INSERT INTO filtered_high_value_loans
SELECT * FROM normalized_events
WHERE CAST(loan_amount AS DOUBLE) > 100000;
```

**Pros**:

- Clean separation of concerns
- Intermediate topic for debugging/audit
- Simpler filter logic in Stage 2
- Reusable normalized data

**Cons**:

- Additional latency (two hops)
- Extra Kafka topic storage
- More CFUs required

**Considerations**:

- Can complicate or break data lineage
- Clear audit trail at each stage
- Intermediate data can be retained for compliance

### Solution 2C: Custom UDF for JSON Processing

**Description**: Deploy custom User-Defined Functions (UDFs) to Confluent Flink for complex JSON operations.

**UDF Implementation** (Java):

```java
@ScalarFunction
public class JsonExtractDouble {
    public Double eval(String json, String path) {
        try {
            JsonNode node = objectMapper.readTree(json);
            return node.at(path).asDouble();
        } catch (Exception e) {
            return null;
        }
    }
}
```

**Flink SQL Usage**:

```sql
SELECT * FROM raw_business_events
WHERE JsonExtractDouble(data, '/loan/loanAmount') > 100000;
```

**Pros**:

- Optimized for your specific data model
- Can handle edge cases

**Cons**:

- Custom logic for complex transformations
- Requires UDF deployment to Confluent Cloud
- Additional maintenance burden
- May have CFU overhead

**Considerations**:

- UDF code must be version-controlled and audited
- Testing requirements for financial accuracy

### Solution 2D: Eventtime Handling Configuration

**Description**: Explicit eventtime configuration to avoid automatic inference issues (not supported by Confluent?).

**For Source Tables**:

```sql
-- Explicitly define eventtime
CREATE TABLE `raw-business-events` (
    ...
    `__ts_ms` BIGINT,
    `event_time` AS TO_TIMESTAMP_LTZ(`__ts_ms`, 3),
    WATERMARK FOR `event_time` AS `event_time` - INTERVAL '5' SECOND
) WITH (...);
```

**For Sink Tables** (current workaround):

```sql
-- Exclude __ts_ms to avoid inference
CREATE TABLE `filtered-loan-events` (
    `id` STRING,
    `data` STRING,
    -- NO __ts_ms here
) WITH (...);
```

**Pros**:

- Direct control over time handling
- Avoids automatic inference problems
- Clear watermark semantics

**Cons**:

- Must remember to exclude from sinks
- Different schemas source vs. sink
