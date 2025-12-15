"""Integration tests for database persistence (PG version with connection pool).

These tests verify that events are correctly saved using connection pooling.
"""

import pytest
import asyncpg
import os
from datetime import datetime

from producer_api_python_rest_lambda_shared.models import Event
from producer_api_python_rest_lambda_shared.service import EventProcessingService
from producer_api_python_rest_lambda_shared.repository import BusinessEventRepository
from repository import get_connection_pool

pytestmark = pytest.mark.database


@pytest.fixture(scope="module")
def test_database_url():
    """Get test database URL from environment or use default."""
    return os.getenv(
        "TEST_DATABASE_URL",
        "postgresql://postgres:password@localhost:5432/car_dealership"
    )


@pytest.fixture(scope="module")
async def test_db_pool(test_database_url):
    """Create test database connection pool and set up schema."""
    pool = await asyncpg.create_pool(test_database_url, min_size=1, max_size=5)
    
    # Set up database schema
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
    schema_path = os.path.join(project_root, "data", "schema.sql")
    
    if not os.path.exists(schema_path):
        schema_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
            "data",
            "schema.sql"
        )
    
    if os.path.exists(schema_path):
        async with pool.acquire() as conn:
            with open(schema_path, "r") as f:
                schema_sql = f.read()
            await conn.execute(schema_sql)
    
    yield pool
    await pool.close()


@pytest.fixture(scope="function")
async def clean_database(test_db_pool):
    """Clean database before each test."""
    async with test_db_pool.acquire() as conn:
        await conn.execute("DELETE FROM car_entities")
        await conn.execute("DELETE FROM loan_entities")
        await conn.execute("DELETE FROM loan_payment_entities")
        await conn.execute("DELETE FROM service_record_entities")
        await conn.execute("DELETE FROM event_headers")
        await conn.execute("DELETE FROM business_events")
    yield
    async with test_db_pool.acquire() as conn:
        await conn.execute("DELETE FROM car_entities")
        await conn.execute("DELETE FROM loan_entities")
        await conn.execute("DELETE FROM loan_payment_entities")
        await conn.execute("DELETE FROM service_record_entities")
        await conn.execute("DELETE FROM event_headers")
        await conn.execute("DELETE FROM business_events")


@pytest.fixture
def test_service(test_db_pool):
    """Create EventProcessingService with connection pool factory."""
    business_event_repo = BusinessEventRepository()
    
    async def connection_factory():
        # Acquire connection from pool
        return await test_db_pool.acquire()
    
    return EventProcessingService(
        business_event_repo=business_event_repo,
        connection_factory=connection_factory,
        api_name="[test-api-pg]",
        should_close_connection=True  # Will auto-detect pool and release
    )


@pytest.fixture
def sample_car_event():
    """Sample car created event."""
    return {
        "eventHeader": {
            "uuid": "test-event-car-pg-001",
            "eventName": "Car Created",
            "eventType": "CarCreated",
            "createdDate": "2024-01-15T10:30:00Z",
            "savedDate": "2024-01-15T10:30:05Z"
        },
        "eventBody": {
            "entities": [
                {
                    "entityType": "Car",
                    "entityId": "TEST-CAR-PG-001",
                    "updatedAttributes": {
                        "id": "TEST-CAR-PG-001",
                        "vin": "TEST1234567890123",
                        "make": "Tesla",
                        "model": "Model S",
                        "year": 2025,
                        "color": "Midnight Silver",
                        "mileage": 0
                    }
                }
            ]
        }
    }


class TestPoolConnectionPersistence:
    """Tests for persistence using connection pool."""
    
    @pytest.mark.asyncio
    async def test_event_saved_with_pool(
        self, test_db_pool, clean_database, test_service, sample_car_event
    ):
        """Test that event is saved correctly using connection pool."""
        event = Event(**sample_car_event)
        
        await test_service.process_event(event)
        
        # Verify in database
        async with test_db_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT id, event_name, event_type FROM business_events WHERE id = $1",
                "test-event-car-pg-001"
            )
            
            assert row is not None, "Event should be saved to business_events"
            assert row["id"] == "test-event-car-pg-001"
            assert row["event_name"] == "Car Created"
    
    @pytest.mark.asyncio
    async def test_entity_saved_with_pool(
        self, test_db_pool, clean_database, test_service, sample_car_event
    ):
        """Test that entity is saved correctly using connection pool."""
        event = Event(**sample_car_event)
        
        await test_service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT entity_id, entity_type FROM car_entities WHERE entity_id = $1",
                "TEST-CAR-PG-001"
            )
            
            assert row is not None, "Entity should be saved"
            assert row["entity_id"] == "TEST-CAR-PG-001"
            assert row["entity_type"] == "Car"
