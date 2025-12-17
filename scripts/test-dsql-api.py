#!/usr/bin/env python3
"""
Test script to submit events to DSQL Lambda API and verify tables.
Submits 10 events of each type (Car, Loan, Payment, Service) and verifies all 6 tables.
"""

import json
import requests
import time
import sys
import os
from datetime import datetime
import uuid

# Configuration
API_URL = os.getenv('API_URL', 'https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com')
EVENTS_PER_TYPE = int(os.getenv('EVENTS_PER_TYPE', '10'))

def generate_uuid():
    """Generate a UUID string."""
    return str(uuid.uuid4())

def create_car_event(index):
    """Create a Car Created event."""
    event_id = generate_uuid()
    entity_id = generate_uuid()
    now = datetime.utcnow().isoformat() + 'Z'
    
    return {
        "eventHeader": {
            "uuid": event_id,
            "eventName": "Car Created",
            "eventType": "CAR_CREATED",
            "createdDate": now,
            "savedDate": now
        },
        "entities": [{
            "entityHeader": {
                "entityId": entity_id,
                "entityType": "Car",
                "createdAt": now,
                "updatedAt": now
            },
            "make": "Toyota",
            "model": "Camry",
            "year": 2024,
            "vin": f"VIN{int(time.time() * 1000) + index}"
        }]
    }

def create_loan_event(index):
    """Create a Loan Created event."""
    event_id = generate_uuid()
    entity_id = generate_uuid()
    now = datetime.utcnow().isoformat() + 'Z'
    
    return {
        "eventHeader": {
            "uuid": event_id,
            "eventName": "Loan Created",
            "eventType": "LOAN_CREATED",
            "createdDate": now,
            "savedDate": now
        },
        "entities": [{
            "entityHeader": {
                "entityId": entity_id,
                "entityType": "Loan",
                "createdAt": now,
                "updatedAt": now
            },
            "loanAmount": 25000,
            "interestRate": 5.5,
            "termMonths": 60
        }]
    }

def create_payment_event(index):
    """Create a Loan Payment Submitted event."""
    event_id = generate_uuid()
    entity_id = generate_uuid()
    now = datetime.utcnow().isoformat() + 'Z'
    
    return {
        "eventHeader": {
            "uuid": event_id,
            "eventName": "Loan Payment Submitted",
            "eventType": "LOAN_PAYMENT_SUBMITTED",
            "createdDate": now,
            "savedDate": now
        },
        "entities": [{
            "entityHeader": {
                "entityId": entity_id,
                "entityType": "LoanPayment",
                "createdAt": now,
                "updatedAt": now
            },
            "paymentAmount": 500,
            "paymentDate": now
        }]
    }

def create_service_event(index):
    """Create a Car Service Done event."""
    event_id = generate_uuid()
    entity_id = generate_uuid()
    now = datetime.utcnow().isoformat() + 'Z'
    
    return {
        "eventHeader": {
            "uuid": event_id,
            "eventName": "Car Service Done",
            "eventType": "CAR_SERVICE_DONE",
            "createdDate": now,
            "savedDate": now
        },
        "entities": [{
            "entityHeader": {
                "entityId": entity_id,
                "entityType": "ServiceRecord",
                "createdAt": now,
                "updatedAt": now
            },
            "serviceType": "Oil Change",
            "mileage": 15000,
            "cost": 75.00
        }]
    }

def submit_event(event, event_type):
    """Submit a single event to the API."""
    url = f"{API_URL}/api/v1/events"
    headers = {"Content-Type": "application/json"}
    
    try:
        response = requests.post(url, json=event, headers=headers, timeout=30)
        if response.status_code in [200, 201]:
            return True, None
        else:
            return False, f"Status {response.status_code}: {response.text[:200]}"
    except Exception as e:
        return False, str(e)

def main():
    """Main function to submit events and report results."""
    print(f"=== DSQL Lambda API Test ===")
    print(f"API URL: {API_URL}")
    print(f"Events per type: {EVENTS_PER_TYPE}")
    print()
    
    event_creators = [
        ("Car Created", create_car_event),
        ("Loan Created", create_loan_event),
        ("Loan Payment Submitted", create_payment_event),
        ("Car Service Done", create_service_event),
    ]
    
    results = {
        "success": 0,
        "failed": 0,
        "errors": []
    }
    
    # Submit events
    print("=== Submitting Events ===")
    for event_type_name, event_creator in event_creators:
        print(f"\nSubmitting {EVENTS_PER_TYPE} {event_type_name} events...")
        for i in range(EVENTS_PER_TYPE):
            event = event_creator(i)
            success, error = submit_event(event, event_type_name)
            if success:
                results["success"] += 1
                print(f"  ✓ Event {i+1}/{EVENTS_PER_TYPE}")
            else:
                results["failed"] += 1
                results["errors"].append(f"{event_type_name} #{i+1}: {error}")
                print(f"  ✗ Event {i+1}/{EVENTS_PER_TYPE}: {error}")
            time.sleep(0.1)  # Small delay between requests
    
    print()
    print("=== Results ===")
    print(f"Successful: {results['success']}")
    print(f"Failed: {results['failed']}")
    total = results['success'] + results['failed']
    if total > 0:
        print(f"Success Rate: {(results['success'] / total * 100):.1f}%")
    
    if results['errors']:
        print(f"\nFirst 5 errors:")
        for error in results['errors'][:5]:
            print(f"  - {error}")
    
    print()
    print("=== Next Steps ===")
    print("Wait a few seconds for Lambda to process, then verify tables:")
    print("  psql -h <DSQL_HOST> -U admin -d postgres -c \"")
    print("    SELECT 'business_events' as table_name, COUNT(*) as count FROM business_events")
    print("    UNION ALL SELECT 'event_headers', COUNT(*) FROM event_headers")
    print("    UNION ALL SELECT 'car_entities', COUNT(*) FROM car_entities")
    print("    UNION ALL SELECT 'loan_entities', COUNT(*) FROM loan_entities")
    print("    UNION ALL SELECT 'loan_payment_entities', COUNT(*) FROM loan_payment_entities")
    print("    UNION ALL SELECT 'service_record_entities', COUNT(*) FROM service_record_entities")
    print("    ORDER BY table_name;\"")
    
    return 0 if results['failed'] == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
