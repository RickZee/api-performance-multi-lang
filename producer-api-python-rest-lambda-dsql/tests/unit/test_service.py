"""Unit tests for EventProcessingService."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import datetime

from producer_api_shared.models import Event
from producer_api_shared.service import EventProcessingService
from producer_api_shared.repository import BusinessEventRepository, EntityRepository, EventHeaderRepository


@pytest.fixture
def mock_connection():
    """Mock asyncpg connection."""
    conn = AsyncMock()
    conn.transaction = MagicMock()
    conn.transaction.return_value.__aenter__ = AsyncMock()
    conn.transaction.return_value.__aexit__ = AsyncMock(return_value=None)
    conn.close = AsyncMock()
    return conn


@pytest.fixture
def mock_connection_factory(mock_connection):
    """Mock connection factory."""
    async def factory():
        return mock_connection
    return factory


@pytest.fixture
def mock_business_event_repo():
    """Mock BusinessEventRepository."""
    repo = MagicMock(spec=BusinessEventRepository)
    repo.create = AsyncMock()
    return repo


@pytest.fixture
def mock_entity_repo():
    """Mock EntityRepository."""
    repo = MagicMock(spec=EntityRepository)
    repo.exists_by_entity_id = AsyncMock(return_value=False)
    repo.create = AsyncMock()
    repo.update = AsyncMock()
    return repo


@pytest.fixture
def service(mock_business_event_repo, mock_connection_factory):
    """Create EventProcessingService with mocked dependencies."""
    return EventProcessingService(
        business_event_repo=mock_business_event_repo,
        connection_factory=mock_connection_factory,
        api_name="[test-api]",
        should_close_connection=True
    )


class TestEventProcessingService:
    """Tests for EventProcessingService."""
    
    @pytest.mark.asyncio
    async def test_get_entity_repository_car(self, service):
        """Test getting repository for Car entity type."""
        repo = service._get_entity_repository("Car")
        assert repo is not None
        assert repo.table_name == "car_entities"
    
    @pytest.mark.asyncio
    async def test_get_entity_repository_loan(self, service):
        """Test getting repository for Loan entity type."""
        repo = service._get_entity_repository("Loan")
        assert repo is not None
        assert repo.table_name == "loan_entities"
    
    @pytest.mark.asyncio
    async def test_get_entity_repository_exact_match(self, service):
        """Test repository lookup uses exact entity type match."""
        repo = service._get_entity_repository("Car")
        assert repo.table_name == "car_entities"
    
    @pytest.mark.asyncio
    async def test_get_entity_repository_unknown_type(self, service):
        """Test getting repository for unknown entity type returns None."""
        repo = service._get_entity_repository("UnknownType")
        assert repo is None
    
    @pytest.mark.asyncio
    async def test_process_entity_update_new_entity(self, service, mock_connection):
        """Test processing a new entity (doesn't exist)."""
        from producer_api_shared.models.event import EntityUpdate
        
        entity_update = EntityUpdate(
            entityType="Car",
            entityId="CAR-2024-001",
            updatedAttributes={"id": "CAR-2024-001", "vin": "5TDJKRFH4LS123456"}
        )
        
        with patch.object(service, '_get_entity_repository') as mock_get_repo:
            mock_repo = MagicMock(spec=EntityRepository)
            mock_repo.exists_by_entity_id = AsyncMock(return_value=False)
            mock_repo.create = AsyncMock()
            mock_get_repo.return_value = mock_repo
            
            await service.process_entity_update(entity_update, "event-123", conn=mock_connection)
            
            mock_repo.exists_by_entity_id.assert_called_once_with("CAR-2024-001", conn=mock_connection)
            mock_repo.create.assert_called_once()
            call_args = mock_repo.create.call_args
            entity_data = call_args.kwargs['entity_data']
            assert entity_data["id"] == "CAR-2024-001"
            assert entity_data["vin"] == "5TDJKRFH4LS123456"
    
    @pytest.mark.asyncio
    async def test_process_entity_update_existing_entity(self, service, mock_connection):
        """Test processing an existing entity (update)."""
        from producer_api_shared.models.event import EntityUpdate
        
        entity_update = EntityUpdate(
            entityType="Car",
            entityId="CAR-2024-001",
            updatedAttributes={"id": "CAR-2024-001", "vin": "UPDATED123"}
        )
        
        with patch.object(service, '_get_entity_repository') as mock_get_repo:
            mock_repo = MagicMock(spec=EntityRepository)
            mock_repo.exists_by_entity_id = AsyncMock(return_value=True)
            mock_repo.update = AsyncMock()
            mock_get_repo.return_value = mock_repo
            
            await service.process_entity_update(entity_update, "event-123", conn=mock_connection)
            
            mock_repo.exists_by_entity_id.assert_called_once_with("CAR-2024-001", conn=mock_connection)
            mock_repo.update.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_create_new_entity_extracts_data(self, service, mock_connection):
        """Test create_new_entity extracts entity data correctly."""
        from producer_api_shared.models.event import EntityUpdate
        
        entity_update = EntityUpdate(
            entityType="Car",
            entityId="CAR-2024-001",
            updatedAttributes={"id": "CAR-2024-001", "vin": "5TDJKRFH4LS123456"}
        )
        
        mock_repo = MagicMock(spec=EntityRepository)
        mock_repo.create = AsyncMock()
        
        await service.create_new_entity(
            mock_repo, entity_update, "event-123", conn=mock_connection
        )
        
        mock_repo.create.assert_called_once()
        call_args = mock_repo.create.call_args
        assert call_args.kwargs['entity_id'] == "CAR-2024-001"
        assert call_args.kwargs['entity_type'] == "Car"
        assert call_args.kwargs['entity_data']["id"] == "CAR-2024-001"
        assert call_args.kwargs['entity_data']["vin"] == "5TDJKRFH4LS123456"
    
    @pytest.mark.asyncio
    async def test_update_existing_entity_extracts_data(self, service, mock_connection):
        """Test update_existing_entity extracts entity data correctly."""
        from producer_api_shared.models.event import EntityUpdate
        
        entity_update = EntityUpdate(
            entityType="Car",
            entityId="CAR-2024-001",
            updatedAttributes={"id": "CAR-2024-001", "vin": "UPDATED123"}
        )
        
        mock_repo = MagicMock(spec=EntityRepository)
        mock_repo.update = AsyncMock()
        
        await service.update_existing_entity(
            mock_repo, entity_update, "event-123", conn=mock_connection
        )
        
        mock_repo.update.assert_called_once()
        call_args = mock_repo.update.call_args
        assert call_args.kwargs['entity_id'] == "CAR-2024-001"
        assert call_args.kwargs['entity_data']["id"] == "CAR-2024-001"
    
    @pytest.mark.asyncio
    async def test_parse_datetime_iso_format(self, service):
        """Test _parse_datetime parses ISO format."""
        dt_str = "2024-01-15T10:30:00Z"
        result = service._parse_datetime(dt_str)
        assert isinstance(result, datetime)
    
    @pytest.mark.asyncio
    async def test_parse_datetime_already_datetime(self, service):
        """Test _parse_datetime returns datetime if already datetime."""
        dt = datetime(2024, 1, 15, 10, 30, 0)
        result = service._parse_datetime(dt)
        assert result == dt
    
    @pytest.mark.asyncio
    async def test_parse_datetime_invalid_fallback(self, service):
        """Test _parse_datetime falls back to utcnow on invalid input."""
        result = service._parse_datetime("invalid-date")
        assert isinstance(result, datetime)
