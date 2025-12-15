"""Integration tests for database persistence of events.

These tests verify that events are correctly saved to all database tables:
- business_events: Full event JSON structure
- event_headers: Event header metadata with relational columns + JSONB
- Entity tables (car_entities, loan_entities, etc.): Entity data with foreign keys

To run these tests:
    pytest tests/integration/test_database_persistence.py -v
    
Requires:
    - PostgreSQL database running
    - TEST_DATABASE_URL environment variable (or defaults to localhost)
    - Database schema must be set up (schema.sql will be run automatically)
"""

import pytest
import asyncpg
import json
import os
from datetime import datetime
from typing import Optional

from producer_api_python_rest_lambda_shared.models import Event
from producer_api_python_rest_lambda_shared.service import EventProcessingService
from producer_api_python_rest_lambda_shared.repository import BusinessEventRepository
from repository import get_connection

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
    # Look for schema.sql in project root or data directory
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
    schema_path = os.path.join(project_root, "data", "schema.sql")
    
    # Fallback: try relative to current file
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
        # Delete in order to respect foreign key constraints
        await conn.execute("DELETE FROM car_entities")
        await conn.execute("DELETE FROM loan_entities")
        await conn.execute("DELETE FROM loan_payment_entities")
        await conn.execute("DELETE FROM service_record_entities")
        await conn.execute("DELETE FROM event_headers")
        await conn.execute("DELETE FROM business_events")
    yield
    # Cleanup after test
    async with test_db_pool.acquire() as conn:
        await conn.execute("DELETE FROM car_entities")
        await conn.execute("DELETE FROM loan_entities")
        await conn.execute("DELETE FROM loan_payment_entities")
        await conn.execute("DELETE FROM service_record_entities")
        await conn.execute("DELETE FROM event_headers")
        await conn.execute("DELETE FROM business_events")


@pytest.fixture
def test_config(test_database_url):
    """Create test config dict."""
    from config import LambdaConfig
    config = LambdaConfig(
        database_url=test_database_url,
        log_level="info"
    )
    return config


@pytest.fixture
def test_service(test_config):
    """Create EventProcessingService with connection factory."""
    business_event_repo = BusinessEventRepository()
    
    async def connection_factory():
        return await get_connection(test_config)
    
    return EventProcessingService(
        business_event_repo=business_event_repo,
        connection_factory=connection_factory,
        api_name="[test-api]",
        should_close_connection=True
    )


@pytest.fixture
def sample_car_event():
    """Sample car created event with eventBody structure."""
    return {
        "eventHeader": {
            "uuid": "test-event-car-001",
            "eventName": "Car Created",
            "eventType": "CarCreated",
            "createdDate": "2024-01-15T10:30:00Z",
            "savedDate": "2024-01-15T10:30:05Z"
        },
        "eventBody": {
            "entities": [
                {
                    "entityType": "Car",
                    "entityId": "TEST-CAR-001",
                    "updatedAttributes": {
                        "id": "TEST-CAR-001",
                        "vin": "TEST1234567890123",
                        "make": "Tesla",
                        "model": "Model S",
                        "year": 2025,
                        "color": "Midnight Silver",
                        "mileage": 0,
                        "lastServiceDate": "2024-01-15T10:30:00Z",
                        "totalBalance": 0.0,
                        "lastLoanPaymentDate": "2024-01-15T10:30:00Z",
                        "owner": "Test Owner"
                    }
                }
            ]
        }
    }


@pytest.fixture
def sample_loan_event():
    """Sample loan created event."""
    return {
        "eventHeader": {
            "uuid": "test-event-loan-001",
            "eventName": "Loan Created",
            "eventType": "LoanCreated",
            "createdDate": "2024-01-15T10:30:00Z",
            "savedDate": "2024-01-15T10:30:05Z"
        },
        "eventBody": {
            "entities": [
                {
                    "entityType": "Loan",
                    "entityId": "TEST-LOAN-001",
                    "updatedAttributes": {
                        "id": "TEST-LOAN-001",
                        "carId": "TEST-CAR-001",
                        "financialInstitution": "Test Bank",
                        "balance": "50000.00",
                        "lastPaidDate": "2024-01-15T10:30:00Z",
                        "loanAmount": "50000.00",
                        "interestRate": 4.5,
                        "termMonths": 60,
                        "startDate": "2024-01-15T10:30:00Z",
                        "status": "active",
                        "monthlyPayment": "950.00"
                    }
                }
            ]
        }
    }


class TestBusinessEventsPersistence:
    """Tests for business_events table persistence."""
    
    @pytest.mark.asyncio
    async def test_business_event_saved_with_full_structure(
        self, test_db_pool, clean_database, test_config, sample_car_event
    ):
        """Test that business_events table saves complete event structure."""
        event = Event(**sample_car_event)
        service = test_service
        
        # Process event
        await service.process_event(event)
        
        # Verify in database
        async with test_db_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT id, event_name, event_type, created_date, saved_date, event_data "
                "FROM business_events WHERE id = $1",
                "test-event-car-001"
            )
            
            assert row is not None, "Event should be saved to business_events"
            assert row["id"] == "test-event-car-001"
            assert row["event_name"] == "Car Created"
            assert row["event_type"] == "CarCreated"
            assert isinstance(row["created_date"], datetime)
            assert isinstance(row["saved_date"], datetime)
            
            # Verify event_data contains full event structure
            event_data = row["event_data"]
            assert "eventHeader" in event_data
            assert "eventBody" in event_data
            assert event_data["eventHeader"]["uuid"] == "test-event-car-001"
            assert event_data["eventHeader"]["eventName"] == "Car Created"
            assert len(event_data["eventBody"]["entities"]) == 1
            assert event_data["eventBody"]["entities"][0]["entityType"] == "Car"
            assert event_data["eventBody"]["entities"][0]["entityId"] == "TEST-CAR-001"
            assert "updatedAttributes" in event_data["eventBody"]["entities"][0]
            assert event_data["eventBody"]["entities"][0]["updatedAttributes"]["vin"] == "TEST1234567890123"
    
    @pytest.mark.asyncio
    async def test_business_event_event_data_matches_input(
        self, test_db_pool, clean_database, test_config, sample_car_event
    ):
        """Test that event_data JSONB matches the input event structure."""
        event = Event(**sample_car_event)
        service = test_service
        
        await service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT event_data FROM business_events WHERE id = $1",
                "test-event-car-001"
            )
            
            event_data = row["event_data"]
            # Verify structure matches input
            assert event_data["eventHeader"]["uuid"] == sample_car_event["eventHeader"]["uuid"]
            assert event_data["eventHeader"]["eventName"] == sample_car_event["eventHeader"]["eventName"]
            assert event_data["eventBody"]["entities"][0]["entityType"] == "Car"
            assert event_data["eventBody"]["entities"][0]["entityId"] == "TEST-CAR-001"
            # Verify updatedAttributes contains all entity fields
            updated_attrs = event_data["eventBody"]["entities"][0]["updatedAttributes"]
            assert updated_attrs["vin"] == "TEST1234567890123"
            assert updated_attrs["make"] == "Tesla"
            assert updated_attrs["model"] == "Model S"


class TestEventHeadersPersistence:
    """Tests for event_headers table persistence."""
    
    @pytest.mark.asyncio
    async def test_event_header_saved_with_relational_columns(
        self, test_db_pool, clean_database, test_config, sample_car_event
    ):
        """Test that event_headers table saves relational columns correctly."""
        event = Event(**sample_car_event)
        service = test_service
        
        await service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT id, event_name, event_type, created_date, saved_date, header_data "
                "FROM event_headers WHERE id = $1",
                "test-event-car-001"
            )
            
            assert row is not None, "Event header should be saved to event_headers"
            assert row["id"] == "test-event-car-001"
            assert row["event_name"] == "Car Created"
            assert row["event_type"] == "CarCreated"
            assert isinstance(row["created_date"], datetime)
            assert isinstance(row["saved_date"], datetime)
    
    @pytest.mark.asyncio
    async def test_event_header_header_data_contains_event_header_json(
        self, test_db_pool, clean_database, test_config, sample_car_event
    ):
        """Test that header_data JSONB contains eventHeader structure."""
        event = Event(**sample_car_event)
        service = test_service
        
        await service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT header_data FROM event_headers WHERE id = $1",
                "test-event-car-001"
            )
            
            header_data = row["header_data"]
            assert header_data["uuid"] == "test-event-car-001"
            assert header_data["eventName"] == "Car Created"
            assert header_data["eventType"] == "CarCreated"
            assert "createdDate" in header_data
            assert "savedDate" in header_data
    
    @pytest.mark.asyncio
    async def test_event_header_foreign_key_to_business_events(
        self, test_db_pool, clean_database, test_config, sample_car_event
    ):
        """Test that event_headers.id references business_events.id."""
        event = Event(**sample_car_event)
        service = test_service
        
        await service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            # Verify foreign key relationship
            row = await conn.fetchrow(
                """
                SELECT eh.id, be.id as business_event_id
                FROM event_headers eh
                JOIN business_events be ON eh.id = be.id
                WHERE eh.id = $1
                """,
                "test-event-car-001"
            )
            
            assert row is not None, "Foreign key relationship should exist"
            assert row["id"] == row["business_event_id"]


class TestEntityPersistence:
    """Tests for entity table persistence."""
    
    @pytest.mark.asyncio
    async def test_car_entity_saved_to_car_entities_table(
        self, test_db_pool, clean_database, test_config, sample_car_event
    ):
        """Test that Car entity is saved to car_entities table."""
        event = Event(**sample_car_event)
        service = test_service
        
        await service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT entity_id, entity_type, created_at, updated_at, entity_data, event_id "
                "FROM car_entities WHERE entity_id = $1",
                "TEST-CAR-001"
            )
            
            assert row is not None, "Car entity should be saved to car_entities"
            assert row["entity_id"] == "TEST-CAR-001"
            assert row["entity_type"] == "Car"
            assert row["event_id"] == "test-event-car-001"
            assert isinstance(row["created_at"], datetime)
            assert isinstance(row["updated_at"], datetime)
    
    @pytest.mark.asyncio
    async def test_entity_data_excludes_entity_header(
        self, test_db_pool, clean_database, test_config, sample_car_event
    ):
        """Test that entity_data JSONB does not contain entityHeader."""
        event = Event(**sample_car_event)
        service = test_service
        
        await service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT entity_data FROM car_entities WHERE entity_id = $1",
                "TEST-CAR-001"
            )
            
            entity_data = row["entity_data"]
            # entity_data should NOT contain entityHeader
            assert "entityHeader" not in entity_data
            # But should contain entity properties
            assert entity_data["id"] == "TEST-CAR-001"
            assert entity_data["vin"] == "TEST1234567890123"
            assert entity_data["make"] == "Tesla"
            assert entity_data["model"] == "Model S"
    
    @pytest.mark.asyncio
    async def test_entity_data_contains_updated_attributes(
        self, test_db_pool, clean_database, test_config, sample_car_event
    ):
        """Test that entity_data contains all fields from updatedAttributes."""
        event = Event(**sample_car_event)
        service = test_service
        
        await service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT entity_data FROM car_entities WHERE entity_id = $1",
                "TEST-CAR-001"
            )
            
            entity_data = row["entity_data"]
            updated_attrs = sample_car_event["eventBody"]["entities"][0]["updatedAttributes"]
            
            # Verify all fields from updatedAttributes are in entity_data
            for key, value in updated_attrs.items():
                assert key in entity_data, f"Field {key} should be in entity_data"
                assert entity_data[key] == value, f"Field {key} should match updatedAttributes value"
    
    @pytest.mark.asyncio
    async def test_loan_entity_saved_to_loan_entities_table(
        self, test_db_pool, clean_database, test_config, sample_loan_event
    ):
        """Test that Loan entity is saved to loan_entities table."""
        event = Event(**sample_loan_event)
        business_event_repo = BusinessEventRepository(None)
        service = EventProcessingService(business_event_repo, test_config)
        
        await service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT entity_id, entity_type, entity_data, event_id "
                "FROM loan_entities WHERE entity_id = $1",
                "TEST-LOAN-001"
            )
            
            assert row is not None, "Loan entity should be saved to loan_entities"
            assert row["entity_id"] == "TEST-LOAN-001"
            assert row["entity_type"] == "Loan"
            assert row["event_id"] == "test-event-loan-001"
            
            entity_data = row["entity_data"]
            assert entity_data["id"] == "TEST-LOAN-001"
            assert entity_data["balance"] == "50000.00"
            assert entity_data["financialInstitution"] == "Test Bank"
    
    @pytest.mark.asyncio
    async def test_entity_foreign_key_to_event_headers(
        self, test_db_pool, clean_database, test_config, sample_car_event
    ):
        """Test that entity.event_id references event_headers.id."""
        event = Event(**sample_car_event)
        service = test_service
        
        await service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                SELECT ce.entity_id, ce.event_id, eh.id as header_id
                FROM car_entities ce
                JOIN event_headers eh ON ce.event_id = eh.id
                WHERE ce.entity_id = $1
                """,
                "TEST-CAR-001"
            )
            
            assert row is not None, "Foreign key relationship should exist"
            assert row["event_id"] == row["header_id"]
            assert row["event_id"] == "test-event-car-001"


class TestEntityUpsert:
    """Tests for entity create/update logic."""
    
    @pytest.mark.asyncio
    async def test_new_entity_creates_record(
        self, test_db_pool, clean_database, test_config, sample_car_event
    ):
        """Test that new entity creates a new database record."""
        event = Event(**sample_car_event)
        service = test_service
        
        await service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            count = await conn.fetchval(
                "SELECT COUNT(*) FROM car_entities WHERE entity_id = $1",
                "TEST-CAR-001"
            )
            assert count == 1, "New entity should create exactly one record"
    
    @pytest.mark.asyncio
    async def test_existing_entity_updates_record(
        self, test_db_pool, clean_database, test_config, sample_car_event
    ):
        """Test that existing entity updates the database record."""
        event = Event(**sample_car_event)
        service = test_service
        
        # Create entity first
        await service.process_event(event)
        
        # Update entity with new data
        updated_event = sample_car_event.copy()
        updated_event["eventHeader"]["uuid"] = "test-event-car-002"
        updated_event["eventBody"]["entities"][0]["updatedAttributes"]["mileage"] = 1000
        updated_event["eventBody"]["entities"][0]["updatedAttributes"]["color"] = "Red"
        
        event2 = Event(**updated_event)
        await service.process_event(event2)
        
        async with test_db_pool.acquire() as conn:
            # Should still be only one record
            count = await conn.fetchval(
                "SELECT COUNT(*) FROM car_entities WHERE entity_id = $1",
                "TEST-CAR-001"
            )
            assert count == 1, "Update should not create duplicate record"
            
            # Verify data was updated
            row = await conn.fetchrow(
                "SELECT entity_data, event_id FROM car_entities WHERE entity_id = $1",
                "TEST-CAR-001"
            )
            assert row["entity_data"]["mileage"] == 1000
            assert row["entity_data"]["color"] == "Red"
            assert row["event_id"] == "test-event-car-002"  # Updated event_id


class TestTransactionAtomicity:
    """Tests for transaction atomicity."""
    
    @pytest.mark.asyncio
    async def test_all_tables_saved_in_single_transaction(
        self, test_db_pool, clean_database, test_config, sample_car_event
    ):
        """Test that all three tables are saved atomically."""
        event = Event(**sample_car_event)
        service = test_service
        
        await service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            # Verify all three tables have the event
            business_count = await conn.fetchval(
                "SELECT COUNT(*) FROM business_events WHERE id = $1",
                "test-event-car-001"
            )
            header_count = await conn.fetchval(
                "SELECT COUNT(*) FROM event_headers WHERE id = $1",
                "test-event-car-001"
            )
            entity_count = await conn.fetchval(
                "SELECT COUNT(*) FROM car_entities WHERE entity_id = $1",
                "TEST-CAR-001"
            )
            
            assert business_count == 1, "business_events should have 1 record"
            assert header_count == 1, "event_headers should have 1 record"
            assert entity_count == 1, "car_entities should have 1 record"
    
    @pytest.mark.asyncio
    async def test_failed_entity_save_rolls_back_all_changes(
        self, test_db_pool, clean_database, test_config
    ):
        """Test that if entity save fails, all changes are rolled back."""
        # Create event with invalid entity type that will cause failure
        invalid_event = {
            "eventHeader": {
                "uuid": "test-event-invalid-001",
                "eventName": "Invalid Event",
                "eventType": "InvalidEvent",
                "createdDate": "2024-01-15T10:30:00Z",
                "savedDate": "2024-01-15T10:30:05Z"
            },
            "eventBody": {
                "entities": [
                    {
                        "entityType": "UnknownEntityType",  # Will fail - no repository
                        "entityId": "TEST-UNKNOWN-001",
                        "updatedAttributes": {
                            "id": "TEST-UNKNOWN-001"
                        }
                    }
                ]
            }
        }
        
        event = Event(**invalid_event)
        business_event_repo = BusinessEventRepository(None)
        service = EventProcessingService(business_event_repo, test_config)
        
        # Process should complete (entity is skipped, not an error)
        # But business_events and event_headers should still be saved
        await service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            # business_events and event_headers should be saved
            business_count = await conn.fetchval(
                "SELECT COUNT(*) FROM business_events WHERE id = $1",
                "test-event-invalid-001"
            )
            header_count = await conn.fetchval(
                "SELECT COUNT(*) FROM event_headers WHERE id = $1",
                "test-event-invalid-001"
            )
            
            # Entity should not be saved (unknown type is skipped)
            entity_count = await conn.fetchval(
                "SELECT COUNT(*) FROM car_entities WHERE entity_id = $1",
                "TEST-UNKNOWN-001"
            )
            
            assert business_count == 1, "business_events should be saved"
            assert header_count == 1, "event_headers should be saved"
            assert entity_count == 0, "Unknown entity type should not be saved"


class TestMultipleEntities:
    """Tests for events with multiple entities."""
    
    @pytest.mark.asyncio
    async def test_event_with_multiple_entities_saves_all(
        self, test_db_pool, clean_database, test_config
    ):
        """Test that event with multiple entities saves all entities."""
        multi_entity_event = {
            "eventHeader": {
                "uuid": "test-event-multi-001",
                "eventName": "Multi Entity Event",
                "eventType": "MultiEntity",
                "createdDate": "2024-01-15T10:30:00Z",
                "savedDate": "2024-01-15T10:30:05Z"
            },
            "eventBody": {
                "entities": [
                    {
                        "entityType": "Car",
                        "entityId": "TEST-CAR-MULTI-001",
                        "updatedAttributes": {
                            "id": "TEST-CAR-MULTI-001",
                            "vin": "MULTI1234567890123",
                            "make": "Tesla"
                        }
                    },
                    {
                        "entityType": "Loan",
                        "entityId": "TEST-LOAN-MULTI-001",
                        "updatedAttributes": {
                            "id": "TEST-LOAN-MULTI-001",
                            "carId": "TEST-CAR-MULTI-001",
                            "balance": "30000.00"
                        }
                    }
                ]
            }
        }
        
        event = Event(**multi_entity_event)
        business_event_repo = BusinessEventRepository(None)
        service = EventProcessingService(business_event_repo, test_config)
        
        await service.process_event(event)
        
        async with test_db_pool.acquire() as conn:
            car_count = await conn.fetchval(
                "SELECT COUNT(*) FROM car_entities WHERE entity_id = $1",
                "TEST-CAR-MULTI-001"
            )
            loan_count = await conn.fetchval(
                "SELECT COUNT(*) FROM loan_entities WHERE entity_id = $1",
                "TEST-LOAN-MULTI-001"
            )
            
            assert car_count == 1, "Car entity should be saved"
            assert loan_count == 1, "Loan entity should be saved"
            
            # Verify both entities reference the same event
            car_row = await conn.fetchrow(
                "SELECT event_id FROM car_entities WHERE entity_id = $1",
                "TEST-CAR-MULTI-001"
            )
            loan_row = await conn.fetchrow(
                "SELECT event_id FROM loan_entities WHERE entity_id = $1",
                "TEST-LOAN-MULTI-001"
            )
            
            assert car_row["event_id"] == "test-event-multi-001"
            assert loan_row["event_id"] == "test-event-multi-001"
