# Producer API Shared Library

Shared functionality for Producer API Python implementations (PostgreSQL and DSQL versions).

## Overview

This package contains common business logic, models, repositories, and services that are shared between:
- `producer-api-python-rest-lambda-pg` (PostgreSQL with connection pooling)
- `producer-api-python-rest-lambda-dsql` (DSQL with direct connections)

## Structure

```
producer_api_shared/
├── models/           # Pydantic models (Event, EventHeader, EventBody, CarEntity)
├── exceptions.py    # Shared exceptions (DuplicateEventError)
├── constants.py     # Shared constants (ENTITY_TABLE_MAP, retry configs)
├── repository/      # Repository layer (business logic only, no connection management)
│   ├── business_event_repo.py
│   ├── entity_repo.py
│   └── event_header_repo.py
└── service/         # Service layer (connection-agnostic business logic)
    └── event_processing.py
```

## Connection Strategy Pattern

The shared service uses a **connection factory pattern** to abstract connection management:

```python
# Connection factory signature
async def connection_factory() -> asyncpg.Connection:
    # Returns a database connection
    pass
```

### PostgreSQL Version (Pool)
```python
async def connection_factory():
    return await pool.acquire()  # Acquire from pool
```

### DSQL Version (Direct)
```python
async def connection_factory():
    return await get_connection(config)  # Create direct connection
```

The service automatically handles cleanup:
- **Pool connections**: Released back to pool
- **Direct connections**: Closed

## Installation

For local development, install as an editable package:

```bash
pip install -e ../producer-api-shared
```

Or add to `requirements.txt`:
```
-e ../producer-api-shared
```

## Usage

### Models
```python
from producer_api_shared.models import Event, EventHeader, EventBody

event = Event(
    eventHeader=EventHeader(eventName="CarCreated", ...),
    eventBody=EventBody(entities=[...])
)
```

### Repositories
```python
from producer_api_shared.repository import BusinessEventRepository

repo = BusinessEventRepository()
await repo.create(
    event_id="...",
    event_name="...",
    # ... other params
    conn=connection  # Connection must be provided explicitly
)
```

### Service
```python
from producer_api_shared.service import EventProcessingService
from producer_api_shared.repository import BusinessEventRepository

# Create connection factory
async def connection_factory():
    return await get_connection(config)

# Initialize service
business_event_repo = BusinessEventRepository()
service = EventProcessingService(
    business_event_repo=business_event_repo,
    connection_factory=connection_factory,
    api_name="[my-api]",
    should_close_connection=True  # True for direct connections, auto-detects pool
)

# Process events
await service.process_event(event)
```

## Key Design Principles

1. **Connection-Agnostic**: Repositories and services accept connections explicitly via `conn` parameter
2. **Transaction Management**: Service layer manages transactions, repositories are stateless
3. **Connection Factory**: Abstract connection acquisition to support different strategies (pool vs direct)
4. **Automatic Cleanup**: Service automatically releases pool connections or closes direct connections

## Dependencies

- `pydantic>=2.0.0` - Data validation and models
- `asyncpg>=0.29.0` - PostgreSQL async driver
- `python-dateutil>=2.8.0` - Date parsing utilities

## Testing

The shared library should have its own test suite. Both projects should run shared library tests as part of their CI.

Integration tests remain project-specific (test connection strategies).
