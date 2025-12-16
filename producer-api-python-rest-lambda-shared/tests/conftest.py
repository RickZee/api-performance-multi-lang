"""Pytest configuration and shared fixtures."""

import pytest
from datetime import datetime
from typing import Dict, Any


@pytest.fixture
def sample_event_header() -> Dict[str, Any]:
    """Sample event header matching schema format."""
    return {
        "uuid": "550e8400-e29b-41d4-a716-446655440000",
        "eventName": "Car Created",
        "eventType": "CarCreated",
        "createdDate": "2024-01-15T10:30:00Z",
        "savedDate": "2024-01-15T10:30:05Z"
    }


@pytest.fixture
def sample_event(sample_event_header) -> Dict[str, Any]:
    """Sample complete event matching canonical schema."""
    return {
        "eventHeader": sample_event_header,
        "entities": [
            {
                "entityHeader": {
                    "entityId": "CAR-2024-001",
                    "entityType": "Car",
                    "createdAt": "2024-01-15T10:30:00Z",
                    "updatedAt": "2024-01-15T10:30:00Z"
                },
                "id": "CAR-2024-001",
                "vin": "5TDJKRFH4LS123456",
                "make": "Tesla",
                "model": "Model S",
                "year": 2025,
                "color": "Midnight Silver",
                "mileage": 0
            }
        ]
    }
