# Test Suite for Producer API Python REST Lambda DSQL

This directory contains the test suite for the Producer API Python REST Lambda DSQL implementation.

## Structure

```
tests/
├── conftest.py              # Shared pytest fixtures
├── unit/                    # Unit tests
│   ├── test_models.py      # Event model tests
│   ├── test_service.py      # Service layer tests
│   └── test_repositories.py # Repository tests
└── integration/             # Integration tests
    └── test_api.py          # API endpoint tests
```

## Running Tests

### Run all tests
```bash
pytest
```

### Run only unit tests
```bash
pytest tests/unit/
```

### Run only integration tests
```bash
# API integration tests (no database required)
pytest tests/integration/test_api.py

# Database integration tests (requires database)
pytest tests/integration/test_database_persistence.py

# All integration tests
pytest tests/integration/
```

### Run with coverage
```bash
pytest --cov=. --cov-report=html
```

### Run specific test file
```bash
pytest tests/unit/test_models.py
```

### Run specific test
```bash
pytest tests/unit/test_models.py::TestEvent::test_valid_event
```

## Test Categories

- **Unit Tests**: Test individual components in isolation with mocks
  - Models: Event, EventHeader, EntityUpdate validation
  - Service: EventProcessingService business logic
  - Repositories: Database operation logic

- **Integration Tests**: Test API endpoints and request/response flow
  - FastAPI endpoints (app.py) - Uses mocked services
  - Lambda handler (lambda_handler.py) - Uses mocked services
  - **Database Persistence Tests** - Verify events are correctly saved to database
    - Tests all three tables: business_events, event_headers, entity tables
    - Verifies data structure matches input
    - Tests transaction atomicity
    - Tests entity upsert logic
    - Requires real PostgreSQL database

## Test Fixtures

Common test fixtures are defined in `conftest.py`:
- `sample_event_header`: Valid event header
- `sample_car_entity`: Valid car entity
- `sample_loan_entity`: Valid loan entity
- `sample_event`: Complete valid event
- `sample_bulk_events`: Multiple events for bulk testing
- Invalid event fixtures for negative testing

## Dependencies

Testing dependencies are listed in `requirements.txt`:
- `pytest>=7.4.0` - Test framework
- `pytest-asyncio>=0.21.0` - Async test support
- `pytest-cov>=4.1.0` - Coverage reporting
- `httpx>=0.24.0` - HTTP client for integration tests

## Notes

- Unit tests mock database connections to avoid requiring a real database
- API integration tests (`test_api.py`) use mocked services - no database required
- Database integration tests (`test_database_persistence.py`) require a real PostgreSQL database
- Database tests automatically set up schema from `data/schema.sql`
- Database tests clean data before/after each test to ensure isolation
- Set `TEST_DATABASE_URL` environment variable to specify test database (defaults to localhost)

## Database Integration Tests

See [tests/integration/README.md](integration/README.md) for detailed documentation on database persistence tests.

These tests verify:
- Events are correctly saved to `business_events` table with full JSON structure
- Event headers are correctly saved to `event_headers` table with relational columns + JSONB
- Entities are correctly extracted and saved to entity tables (car_entities, loan_entities, etc.)
- Foreign key relationships are correctly established
- Transaction atomicity (all-or-nothing saves)
- Entity upsert logic (create new vs update existing)
