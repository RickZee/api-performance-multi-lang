"""Integration tests for API endpoints."""

import pytest
import json
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient

from app import app
from models.event import Event
from repository import BusinessEventRepository, DuplicateEventError


@pytest.fixture
def client():
    """Create test client for FastAPI app."""
    return TestClient(app)


@pytest.fixture
def mock_service():
    """Mock EventProcessingService."""
    service = MagicMock()
    service.process_event = AsyncMock()
    return service


class TestHealthEndpoint:
    """Tests for health check endpoint."""
    
    def test_health_check(self, client):
        """Test health check endpoint."""
        response = client.get("/api/v1/events/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "message" in data


class TestSingleEventEndpoint:
    """Tests for single event processing endpoint."""
    
    def test_process_event_success(self, client, sample_event, mock_service):
        """Test successful event processing."""
        with patch('app.get_service', return_value=mock_service):
            response = client.post("/api/v1/events", json=sample_event)
            assert response.status_code == 200
            data = response.json()
            assert data["success"] is True
            assert "message" in data
            mock_service.process_event.assert_called_once()
    
    def test_process_event_missing_event_name(self, client, sample_event):
        """Test event processing with missing eventName."""
        invalid_event = sample_event.copy()
        invalid_event["eventHeader"]["eventName"] = ""
        
        response = client.post("/api/v1/events", json=invalid_event)
        assert response.status_code == 422
        assert "event_name is required" in response.json()["detail"]
    
    def test_process_event_missing_entities(self, client, sample_event_header):
        """Test event processing with missing entities."""
        invalid_event = {
            "eventHeader": sample_event_header,
            "eventBody": {
                "entities": []
            }
        }
        
        response = client.post("/api/v1/events", json=invalid_event)
        assert response.status_code == 422
        assert "at least one entity" in response.json()["detail"].lower()
    
    def test_process_event_missing_entity_type(self, client, sample_event_header):
        """Test event processing with entity missing entityType."""
        invalid_event = {
            "eventHeader": sample_event_header,
            "eventBody": {
                "entities": [
                    {
                        "entityId": "CAR-2024-001",
                        # Missing entityType
                        "updatedAttributes": {
                            "id": "CAR-2024-001",
                            "vin": "TEST1234567890123"
                        }
                    }
                ]
            }
        }
        
        response = client.post("/api/v1/events", json=invalid_event)
        assert response.status_code == 422
        assert "entity type" in response.json()["detail"].lower()
    
    def test_process_event_missing_entity_id(self, client, sample_event_header):
        """Test event processing with entity missing entityId."""
        invalid_event = {
            "eventHeader": sample_event_header,
            "eventBody": {
                "entities": [
                    {
                        "entityType": "Car",
                        # Missing entityId
                        "updatedAttributes": {
                            "id": "CAR-2024-001",
                            "vin": "TEST1234567890123"
                        }
                    }
                ]
            }
        }
        
        response = client.post("/api/v1/events", json=invalid_event)
        assert response.status_code == 422
        assert "entity id" in response.json()["detail"].lower()
    
    def test_process_event_duplicate_error(self, client, sample_event, mock_service):
        """Test event processing with duplicate event ID."""
        error = DuplicateEventError("event-123", "Event already exists")
        mock_service.process_event.side_effect = error
        
        with patch('app.get_service', return_value=mock_service):
            response = client.post("/api/v1/events", json=sample_event)
            assert response.status_code == 409
            data = response.json()
            assert data["detail"]["error"] == "Conflict"
            assert "eventId" in data["detail"]
    
    def test_process_event_invalid_json(self, client):
        """Test event processing with invalid JSON."""
        response = client.post(
            "/api/v1/events",
            data="invalid json",
            headers={"Content-Type": "application/json"}
        )
        assert response.status_code == 422


class TestBulkEventsEndpoint:
    """Tests for bulk event processing endpoint."""
    
    def test_process_bulk_events_success(self, client, sample_bulk_events, mock_service):
        """Test successful bulk event processing."""
        with patch('app.get_service', return_value=mock_service):
            response = client.post("/api/v1/events/bulk", json=sample_bulk_events)
            assert response.status_code == 200
            data = response.json()
            assert data["success"] is True
            assert "processed" in data
            assert "failed" in data
            assert data["processed"] == 2
            assert data["failed"] == 0
            assert mock_service.process_event.call_count == 2
    
    def test_process_bulk_events_empty_list(self, client):
        """Test bulk event processing with empty list."""
        response = client.post("/api/v1/events/bulk", json=[])
        assert response.status_code == 422
        assert "null or empty" in response.json()["detail"].lower()
    
    def test_process_bulk_events_partial_failure(self, client, sample_bulk_events, mock_service):
        """Test bulk event processing with partial failures."""
        # First event succeeds, second fails
        def side_effect(event):
            if event.event_header.event_name == "Loan Created":
                raise Exception("Processing error")
        
        mock_service.process_event.side_effect = side_effect
        
        with patch('app.get_service', return_value=mock_service):
            response = client.post("/api/v1/events/bulk", json=sample_bulk_events)
            assert response.status_code == 200
            data = response.json()
            assert data["processed"] == 1
            assert data["failed"] == 1
            assert len(data["errors"]) > 0
    
    def test_process_bulk_events_duplicate_errors(self, client, sample_bulk_events, mock_service):
        """Test bulk event processing with duplicate event errors."""
        error = DuplicateEventError("event-123", "Event already exists")
        mock_service.process_event.side_effect = error
        
        with patch('app.get_service', return_value=mock_service):
            response = client.post("/api/v1/events/bulk", json=sample_bulk_events)
            assert response.status_code == 200
            data = response.json()
            assert data["failed"] == 2
            assert "duplicate" in str(data["errors"][0]).lower()


class TestLambdaHandler:
    """Tests for Lambda handler."""
    
    @pytest.fixture
    def lambda_event(self, sample_event):
        """Create Lambda API Gateway event."""
        import json
        return {
            "requestContext": {
                "http": {
                    "method": "POST",
                    "path": "/api/v1/events"
                }
            },
            "body": json.dumps(sample_event)
        }
    
    @pytest.mark.asyncio
    async def test_lambda_handler_health_check(self):
        """Test Lambda handler health check."""
        from lambda_handler import handler
        import json
        
        event = {
            "requestContext": {
                "http": {
                    "method": "GET",
                    "path": "/api/v1/events/health"
                }
            },
            "body": "{}"
        }
        
        response = handler(event, None)
        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["status"] == "healthy"
    
    @pytest.mark.asyncio
    async def test_lambda_handler_process_event(self, sample_event, mock_service):
        """Test Lambda handler processes event."""
        from lambda_handler import handler
        
        with patch('lambda_handler._initialize_service', return_value=mock_service):
            event = {
                "requestContext": {
                    "http": {
                        "method": "POST",
                        "path": "/api/v1/events"
                    }
                },
                "body": str(sample_event).replace("'", '"')
            }
            
            import json
            event["body"] = json.dumps(sample_event)
            
            response = handler(event, None)
            assert response["statusCode"] == 200
            body = json.loads(response["body"])
            assert body["success"] is True
    
    @pytest.mark.asyncio
    async def test_lambda_handler_invalid_json(self):
        """Test Lambda handler with invalid JSON."""
        from lambda_handler import handler
        
        event = {
            "requestContext": {
                "http": {
                    "method": "POST",
                    "path": "/api/v1/events"
                }
            },
            "body": "invalid json"
        }
        
        response = handler(event, None)
        assert response["statusCode"] == 400
    
    @pytest.mark.asyncio
    async def test_lambda_handler_not_found(self):
        """Test Lambda handler returns 404 for unknown path."""
        from lambda_handler import handler
        
        event = {
            "requestContext": {
                "http": {
                    "method": "GET",
                    "path": "/api/v1/unknown"
                }
            },
            "body": "{}"
        }
        
        response = handler(event, None)
        assert response["statusCode"] == 404
