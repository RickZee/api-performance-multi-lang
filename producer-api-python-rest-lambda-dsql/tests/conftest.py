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
def sample_car_entity() -> Dict[str, Any]:
    """Sample car entity matching schema format."""
    return {
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
        "mileage": 0,
        "lastServiceDate": "2024-01-15T10:30:00Z",
        "totalBalance": 0.0,
        "lastLoanPaymentDate": "2024-01-15T10:30:00Z",
        "owner": "John Doe"
    }


@pytest.fixture
def sample_loan_entity() -> Dict[str, Any]:
    """Sample loan entity matching schema format."""
    return {
        "entityHeader": {
            "entityId": "LOAN-2024-001",
            "entityType": "Loan",
            "createdAt": "2024-01-15T10:30:00Z",
            "updatedAt": "2024-01-15T10:30:00Z"
        },
        "id": "LOAN-2024-001",
        "carId": "CAR-2024-001",
        "financialInstitution": "First National Bank",
        "balance": "50000.00",
        "lastPaidDate": "2024-01-15T10:30:00Z",
        "loanAmount": "50000.00",
        "interestRate": 4.5,
        "termMonths": 60,
        "startDate": "2024-01-15T10:30:00Z",
        "status": "active",
        "monthlyPayment": "950.00"
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
                "mileage": 0,
                "lastServiceDate": "2024-01-15T10:30:00Z",
                "totalBalance": 0.0,
                "lastLoanPaymentDate": "2024-01-15T10:30:00Z",
                "owner": "John Doe"
            }
        ]
    }


@pytest.fixture
def sample_bulk_events(sample_event_header) -> list:
    """Sample bulk events for testing."""
    return [
        {
            "eventHeader": {
                **sample_event_header,
                "uuid": "550e8400-e29b-41d4-a716-446655440001",
                "eventName": "Car Created",
                "eventType": "CarCreated"
            },
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
                    "make": "Tesla"
                }
            ]
        },
        {
            "eventHeader": {
                **sample_event_header,
                "uuid": "550e8400-e29b-41d4-a716-446655440002",
                "eventName": "Loan Created",
                "eventType": "LoanCreated"
            },
            "entities": [
                {
                    "entityHeader": {
                        "entityId": "LOAN-2024-001",
                        "entityType": "Loan",
                        "createdAt": "2024-01-15T10:30:00Z",
                        "updatedAt": "2024-01-15T10:30:00Z"
                    },
                    "id": "LOAN-2024-001",
                    "carId": "CAR-2024-001",
                    "balance": "50000.00"
                }
            ]
        }
    ]


@pytest.fixture
def invalid_event_missing_entity_header() -> Dict[str, Any]:
    """Invalid event missing entityHeader (using eventBody structure)."""
    return {
        "eventHeader": {
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "eventName": "Car Created",
            "eventType": "CarCreated",
            "createdDate": "2024-01-15T10:30:00Z",
            "savedDate": "2024-01-15T10:30:05Z"
        },
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
                "make": "Tesla"
            }
        ]
    }


@pytest.fixture
def invalid_event_missing_entity_type() -> Dict[str, Any]:
    """Invalid event with entity missing entityType."""
    return {
        "eventHeader": {
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "eventName": "Car Created",
            "eventType": "CarCreated",
            "createdDate": "2024-01-15T10:30:00Z",
            "savedDate": "2024-01-15T10:30:05Z"
        },
        "entities": [
            {
                "entityHeader": {
                    "entityId": "CAR-2024-001",
                    # Missing entityType
                    "createdAt": "2024-01-15T10:30:00Z",
                    "updatedAt": "2024-01-15T10:30:00Z"
                },
                "id": "CAR-2024-001",
                "vin": "5TDJKRFH4LS123456"
            }
        ]
    }
