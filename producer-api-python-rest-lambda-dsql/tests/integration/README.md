# Integration Tests

This directory contains integration tests for the Producer API Python REST Lambda DSQL.

## Test Files

- `test_api.py` - API endpoint tests (uses mocked services, no database)
- `test_database_persistence.py` - Database persistence tests (requires real database)

## Database Integration Tests

The `test_database_persistence.py` file contains comprehensive tests that verify events are correctly saved to the database.

### What These Tests Verify

1. **business_events Table**
   - Full event structure is saved as JSONB
   - Relational columns (id, event_name, event_type, etc.) are correctly populated
   - event_data JSONB contains complete event structure with eventHeader and eventBody

2. **event_headers Table**
   - Event header metadata is saved with relational columns
   - header_data JSONB contains eventHeader structure
   - Foreign key relationship to business_events

3. **Entity Tables** (car_entities, loan_entities, etc.)
   - Entities are correctly extracted from updatedAttributes
   - entity_data JSONB contains entity properties (excluding entityHeader)
   - Foreign key relationship to event_headers
   - Entity upsert logic (create vs update)

4. **Transaction Atomicity**
   - All three tables are saved in a single transaction
   - Rollback behavior on errors

5. **Multiple Entities**
   - Events with multiple entities save all entities correctly
   - All entities reference the same event_id

### Running Database Tests

**Prerequisites:**
- PostgreSQL database running
- Database schema set up (schema.sql will be run automatically)

**Set database URL:**
```bash
export TEST_DATABASE_URL="postgresql://postgres:password@localhost:5432/car_dealership"
```

**Run tests:**
```bash
# Run all database integration tests
pytest tests/integration/test_database_persistence.py -v

# Run specific test class
pytest tests/integration/test_database_persistence.py::TestBusinessEventsPersistence -v

# Run specific test
pytest tests/integration/test_database_persistence.py::TestBusinessEventsPersistence::test_business_event_saved_with_full_structure -v

# Run with database marker
pytest -m database -v
```

**Default Database:**
If `TEST_DATABASE_URL` is not set, tests default to:
```
postgresql://postgres:password@localhost:5432/car_dealership
```

### Test Structure

Tests are organized into classes by functionality:

- `TestBusinessEventsPersistence` - business_events table tests
- `TestEventHeadersPersistence` - event_headers table tests
- `TestEntityPersistence` - Entity table tests
- `TestEntityUpsert` - Create/update logic tests
- `TestTransactionAtomicity` - Transaction behavior tests
- `TestMultipleEntities` - Multiple entity handling tests

### Test Fixtures

- `test_database_url` - Database connection URL
- `test_db_pool` - Database connection pool (module scope)
- `clean_database` - Cleans database before/after each test
- `test_config` - LambdaConfig for tests
- `sample_car_event` - Sample car created event
- `sample_loan_event` - Sample loan created event

### Example Test Output

```
tests/integration/test_database_persistence.py::TestBusinessEventsPersistence::test_business_event_saved_with_full_structure PASSED
tests/integration/test_database_persistence.py::TestEventHeadersPersistence::test_event_header_saved_with_relational_columns PASSED
tests/integration/test_database_persistence.py::TestEntityPersistence::test_car_entity_saved_to_car_entities_table PASSED
...
```

### Troubleshooting

**Connection Errors:**
- Ensure PostgreSQL is running
- Check database URL is correct
- Verify database exists and user has permissions

**Schema Errors:**
- Ensure schema.sql exists at `data/schema.sql`
- Check that schema can be executed (tables may already exist)

**Test Failures:**
- Check database logs for constraint violations
- Verify foreign key relationships are correct
- Ensure test data doesn't conflict with existing data
