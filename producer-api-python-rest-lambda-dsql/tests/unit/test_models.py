"""Unit tests for event models."""

import pytest
from datetime import datetime
from pydantic import ValidationError

from producer_api_python_rest_lambda_shared.models import Event, EventHeader


class TestEventHeader:
    """Tests for EventHeader model."""
    
    def test_valid_event_header(self):
        """Test creating a valid EventHeader."""
        header = EventHeader(
            uuid="550e8400-e29b-41d4-a716-446655440000",
            eventName="Car Created",
            eventType="CarCreated",
            createdDate="2024-01-15T10:30:00Z",
            savedDate="2024-01-15T10:30:05Z"
        )
        assert header.uuid == "550e8400-e29b-41d4-a716-446655440000"
        assert header.event_name == "Car Created"
        assert header.event_type == "CarCreated"
        assert isinstance(header.created_date, datetime)
        assert isinstance(header.saved_date, datetime)
    
    def test_event_header_with_snake_case(self):
        """Test EventHeader accepts snake_case aliases."""
        header = EventHeader(
            uuid="550e8400-e29b-41d4-a716-446655440000",
            event_name="Car Created",
            event_type="CarCreated",
            created_date="2024-01-15T10:30:00Z",
            saved_date="2024-01-15T10:30:05Z"
        )
        assert header.event_name == "Car Created"
        assert header.event_type == "CarCreated"
    
    def test_event_header_optional_fields(self):
        """Test EventHeader with optional fields."""
        header = EventHeader(eventName="Test Event")
        assert header.event_name == "Test Event"
        assert header.uuid is None
        assert header.event_type is None
        assert header.created_date is None
        assert header.saved_date is None
    
    def test_event_header_missing_required(self):
        """Test EventHeader requires eventName."""
        with pytest.raises(ValidationError):
            EventHeader()
    
    def test_event_header_date_parsing_iso(self):
        """Test EventHeader parses ISO 8601 dates."""
        header = EventHeader(
            eventName="Test",
            createdDate="2024-01-15T10:30:00Z",
            savedDate="2024-01-15T10:30:05Z"
        )
        assert isinstance(header.created_date, datetime)
        assert isinstance(header.saved_date, datetime)
    
    def test_event_header_date_parsing_timestamp(self):
        """Test EventHeader parses Unix timestamp (milliseconds)."""
        timestamp_ms = int(datetime(2024, 1, 15, 10, 30, 0).timestamp() * 1000)
        header = EventHeader(
            eventName="Test",
            createdDate=timestamp_ms,
            savedDate=timestamp_ms
        )
        assert isinstance(header.created_date, datetime)
        assert isinstance(header.saved_date, datetime)


# EntityHeader model removed - entities are now EntityUpdate objects in EventBody


class TestEvent:
    """Tests for Event model."""
    
    def test_valid_event(self, sample_event):
        """Test creating a valid Event."""
        event = Event(**sample_event)
        assert event.event_header.event_name == "Car Created"
        assert len(event.event_body.entities) == 1
        assert event.event_body.entities[0].entity_type == "Car"
        assert event.event_body.entities[0].entity_id == "CAR-2024-001"
    
    def test_event_with_multiple_entities(self, sample_event_header):
        """Test Event with multiple entities."""
        event = Event(
            eventHeader=sample_event_header,
            eventBody={
                "entities": [
                    {
                        "entityType": "Car",
                        "entityId": "CAR-2024-001",
                        "updatedAttributes": {"id": "CAR-2024-001", "vin": "TEST123"}
                    },
                    {
                        "entityType": "Loan",
                        "entityId": "LOAN-2024-001",
                        "updatedAttributes": {"id": "LOAN-2024-001", "balance": "50000.00"}
                    }
                ]
            }
        )
        assert len(event.event_body.entities) == 2
        assert event.event_body.entities[0].entity_type == "Car"
        assert event.event_body.entities[1].entity_type == "Loan"
    
    def test_event_missing_entities(self, sample_event_header):
        """Test Event with empty entities list (allowed by model)."""
        # Note: Pydantic allows empty lists by default, validation happens at service layer
        event = Event(
            eventHeader=sample_event_header,
            eventBody={"entities": []}
        )
        assert len(event.event_body.entities) == 0
    
    def test_event_entity_missing_type(self, sample_event_header):
        """Test Event validates entityType requirement."""
        with pytest.raises(ValidationError) as exc_info:
            Event(
                eventHeader=sample_event_header,
                eventBody={
                    "entities": [
                        {
                            "entityId": "CAR-2024-001",
                            "updatedAttributes": {"id": "CAR-2024-001"}
                        }
                    ]
                }
            )
        assert "entityType" in str(exc_info.value) or "entity_type" in str(exc_info.value)
    
    def test_event_entity_missing_id(self, sample_event_header):
        """Test Event validates entityId requirement."""
        with pytest.raises(ValidationError) as exc_info:
            Event(
                eventHeader=sample_event_header,
                eventBody={
                    "entities": [
                        {
                            "entityType": "Car",
                            "updatedAttributes": {"id": "CAR-2024-001"}
                        }
                    ]
                }
            )
        assert "entityId" in str(exc_info.value) or "entity_id" in str(exc_info.value)
    
    def test_event_snake_case_aliases(self, sample_event_header):
        """Test Event accepts snake_case aliases."""
        event_dict = {
            "event_header": sample_event_header,
            "event_body": {
                "entities": [
                    {
                        "entityType": "Car",
                        "entityId": "CAR-2024-001",
                        "updatedAttributes": {"id": "CAR-2024-001"}
                    }
                ]
            }
        }
        event = Event(**event_dict)
        assert event.event_header.event_name == "Car Created"
        assert len(event.event_body.entities) == 1
