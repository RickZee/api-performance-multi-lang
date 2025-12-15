"""Unit tests for EventProcessingService (PG version)."""

import pytest
from unittest.mock import AsyncMock, MagicMock
from datetime import datetime

from producer_api_python_rest_lambda_shared.models import Event
from producer_api_python_rest_lambda_shared.service import EventProcessingService
from producer_api_python_rest_lambda_shared.repository import BusinessEventRepository, EntityRepository


@pytest.fixture
def mock_connection():
    """Mock asyncpg connection."""
    conn = AsyncMock()
    conn.transaction = MagicMock()
    conn.transaction.return_value.__aenter__ = AsyncMock()
    conn.transaction.return_value.__aexit__ = AsyncMock(return_value=None)
    # For pool connections, we release instead of close
    conn._pool = MagicMock()
    conn._pool.release = AsyncMock()
    return conn


@pytest.fixture
def mock_pool(mock_connection):
    """Mock asyncpg pool."""
    pool = AsyncMock()
    pool.acquire = AsyncMock(return_value=mock_connection)
    pool._loop = MagicMock()
    return pool


@pytest.fixture
def mock_connection_factory(mock_pool):
    """Mock connection factory for pool."""
    async def factory():
        return await mock_pool.acquire()
    return factory


@pytest.fixture
def mock_business_event_repo():
    """Mock BusinessEventRepository."""
    repo = MagicMock(spec=BusinessEventRepository)
    repo.create = AsyncMock()
    return repo


@pytest.fixture
def service(mock_business_event_repo, mock_connection_factory):
    """Create EventProcessingService with mocked dependencies (PG pool pattern)."""
    return EventProcessingService(
        business_event_repo=mock_business_event_repo,
        connection_factory=mock_connection_factory,
        api_name="[test-api-pg]",
        should_close_connection=True  # Will auto-detect pool and release
    )


class TestEventProcessingService:
    """Tests for EventProcessingService with pool connections."""
    
    @pytest.mark.asyncio
    async def test_process_event_with_pool(self, service, mock_connection, mock_pool, sample_event):
        """Test processing event with pool connection (releases instead of closes)."""
        event = Event(**sample_event)
        
        from unittest.mock import patch
        with patch.object(service, '_get_entity_repository') as mock_get_repo:
            mock_repo = MagicMock(spec=EntityRepository)
            mock_repo.exists_by_entity_id = AsyncMock(return_value=False)
            mock_repo.create = AsyncMock()
            mock_get_repo.return_value = mock_repo
            
            await service.process_event(event)
            
            # Verify connection was acquired from pool
            mock_pool.acquire.assert_called_once()
            # Verify connection was released back to pool (not closed)
            mock_connection._pool.release.assert_called_once_with(mock_connection)
            # Verify connection was NOT closed
            assert not hasattr(mock_connection, 'close') or not mock_connection.close.called
    
    @pytest.mark.asyncio
    async def test_get_entity_repository_car(self, service):
        """Test getting repository for Car entity type."""
        repo = service._get_entity_repository("Car")
        assert repo is not None
        assert repo.table_name == "car_entities"
    
    @pytest.mark.asyncio
    async def test_get_entity_repository_unknown_type(self, service):
        """Test getting repository for unknown entity type returns None."""
        repo = service._get_entity_repository("UnknownType")
        assert repo is None
