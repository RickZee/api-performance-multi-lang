"""Unit tests for repository classes."""

import pytest
import json
from unittest.mock import AsyncMock, MagicMock
from datetime import datetime

from producer_api_python_rest_lambda_shared.repository import (
    EntityRepository,
    BusinessEventRepository,
    EventHeaderRepository
)


class TestEntityRepository:
    """Tests for EntityRepository."""
    
    @pytest.fixture
    def entity_repo(self):
        """Create EntityRepository instance."""
        return EntityRepository("test_entities")
    
    @pytest.fixture
    def mock_connection(self):
        """Mock asyncpg connection."""
        conn = AsyncMock()
        conn.fetchval = AsyncMock()
        conn.execute = AsyncMock()
        return conn
    
    @pytest.mark.asyncio
    async def test_exists_by_entity_id_true(self, entity_repo, mock_connection):
        """Test exists_by_entity_id returns True when entity exists."""
        mock_connection.fetchval.return_value = True
        
        result = await entity_repo.exists_by_entity_id("TEST-001", conn=mock_connection)
        
        assert result is True
        mock_connection.fetchval.assert_called_once()
        call_args = mock_connection.fetchval.call_args[0]
        assert "SELECT EXISTS" in call_args[0]
        assert call_args[1] == "TEST-001"
    
    @pytest.mark.asyncio
    async def test_exists_by_entity_id_false(self, entity_repo, mock_connection):
        """Test exists_by_entity_id returns False when entity doesn't exist."""
        mock_connection.fetchval.return_value = False
        
        result = await entity_repo.exists_by_entity_id("TEST-001", conn=mock_connection)
        
        assert result is False
    
    @pytest.mark.asyncio
    async def test_exists_by_entity_id_requires_connection(self, entity_repo):
        """Test exists_by_entity_id requires connection."""
        mock_conn = AsyncMock()
        await entity_repo.exists_by_entity_id("TEST-001", conn=mock_conn)
        mock_conn.fetchval.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_create_entity(self, entity_repo, mock_connection):
        """Test create entity."""
        entity_id = "TEST-001"
        entity_type = "Car"
        created_at = datetime(2024, 1, 15, 10, 30, 0)
        updated_at = datetime(2024, 1, 15, 10, 30, 5)
        entity_data = {"id": "TEST-001", "vin": "TEST1234567890123"}
        event_id = "event-123"
        
        await entity_repo.create(
            entity_id=entity_id,
            entity_type=entity_type,
            created_at=created_at,
            updated_at=updated_at,
            entity_data=entity_data,
            event_id=event_id,
            conn=mock_connection
        )
        
        mock_connection.execute.assert_called_once()
        call_args = mock_connection.execute.call_args[0]
        assert "INSERT INTO" in call_args[0]
        assert call_args[1] == entity_id
        assert call_args[2] == entity_type
        assert call_args[3] == created_at
        assert call_args[4] == updated_at
        # Verify entity_data is JSON stringified
        assert isinstance(call_args[5], str)
        assert json.loads(call_args[5]) == entity_data
        assert call_args[6] == event_id
    
    @pytest.mark.asyncio
    async def test_create_entity_requires_connection(self, entity_repo):
        """Test create requires connection."""
        mock_conn = AsyncMock()
        await entity_repo.create(
            entity_id="TEST-001",
            entity_type="Car",
            created_at=datetime.now(),
            updated_at=datetime.now(),
            entity_data={},
            conn=mock_conn
        )
        mock_conn.execute.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_update_entity(self, entity_repo, mock_connection):
        """Test update entity."""
        entity_id = "TEST-001"
        updated_at = datetime(2024, 1, 15, 10, 30, 5)
        entity_data = {"id": "TEST-001", "vin": "UPDATED1234567890123"}
        event_id = "event-456"
        
        await entity_repo.update(
            entity_id=entity_id,
            updated_at=updated_at,
            entity_data=entity_data,
            event_id=event_id,
            conn=mock_connection
        )
        
        mock_connection.execute.assert_called_once()
        call_args = mock_connection.execute.call_args[0]
        assert "UPDATE" in call_args[0]
        assert call_args[1] == updated_at
        # Verify entity_data is JSON stringified
        assert isinstance(call_args[2], str)
        assert json.loads(call_args[2]) == entity_data
        assert call_args[3] == event_id
        assert call_args[4] == entity_id
    
    @pytest.mark.asyncio
    async def test_update_entity_requires_connection(self, entity_repo):
        """Test update requires connection."""
        mock_conn = AsyncMock()
        await entity_repo.update(
            entity_id="TEST-001",
            updated_at=datetime.now(),
            entity_data={},
            conn=mock_conn
        )
        mock_conn.execute.assert_called_once()


class TestBusinessEventRepository:
    """Tests for BusinessEventRepository."""
    
    @pytest.fixture
    def business_event_repo(self):
        """Create BusinessEventRepository instance."""
        return BusinessEventRepository()
    
    @pytest.fixture
    def mock_connection(self):
        """Mock asyncpg connection."""
        conn = AsyncMock()
        conn.execute = AsyncMock()
        return conn
    
    @pytest.mark.asyncio
    async def test_create_business_event(self, business_event_repo, mock_connection):
        """Test create business event."""
        event_id = "event-123"
        event_name = "Car Created"
        event_type = "CarCreated"
        created_date = datetime(2024, 1, 15, 10, 30, 0)
        saved_date = datetime(2024, 1, 15, 10, 30, 5)
        event_data = {"eventHeader": {}, "entities": []}
        
        await business_event_repo.create(
            event_id=event_id,
            event_name=event_name,
            event_type=event_type,
            created_date=created_date,
            saved_date=saved_date,
            event_data=event_data,
            conn=mock_connection
        )
        
        mock_connection.execute.assert_called_once()
        call_args = mock_connection.execute.call_args[0]
        assert "INSERT INTO" in call_args[0] or "business_events" in call_args[0]


class TestEventHeaderRepository:
    """Tests for EventHeaderRepository."""
    
    @pytest.fixture
    def event_header_repo(self):
        """Create EventHeaderRepository instance."""
        return EventHeaderRepository()
    
    @pytest.fixture
    def mock_connection(self):
        """Mock asyncpg connection."""
        conn = AsyncMock()
        conn.execute = AsyncMock()
        return conn
    
    @pytest.mark.asyncio
    async def test_create_event_header(self, event_header_repo, mock_connection):
        """Test create event header."""
        event_id = "event-123"
        event_name = "Car Created"
        event_type = "CarCreated"
        created_date = datetime(2024, 1, 15, 10, 30, 0)
        saved_date = datetime(2024, 1, 15, 10, 30, 5)
        header_data = {"uuid": "550e8400-e29b-41d4-a716-446655440000"}
        
        await event_header_repo.create(
            event_id=event_id,
            event_name=event_name,
            event_type=event_type,
            created_date=created_date,
            saved_date=saved_date,
            header_data=header_data,
            conn=mock_connection
        )
        
        mock_connection.execute.assert_called_once()
        call_args = mock_connection.execute.call_args[0]
        assert "INSERT INTO" in call_args[0] or "event_headers" in call_args[0]
