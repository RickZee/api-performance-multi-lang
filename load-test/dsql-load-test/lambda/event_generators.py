"""Event generation functions for load testing."""

import uuid
import random
import string
from datetime import datetime
from typing import Optional, Dict, Any


def generate_uuid() -> str:
    """Generate a UUID v4."""
    return str(uuid.uuid4())


def generate_timestamp() -> str:
    """Generate ISO 8601 timestamp."""
    return datetime.utcnow().isoformat() + 'Z'


def random_string(length: int) -> str:
    """Generate random string of given length."""
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def random_int_between(min_val: int, max_val: int) -> int:
    """Generate random integer between min and max (inclusive)."""
    return random.randint(min_val, max_val)


def generate_car_created_event(car_id: Optional[str] = None) -> Dict[str, Any]:
    """Generate Car Created event."""
    timestamp = generate_timestamp()
    date_str = datetime.utcnow().strftime('%Y%m%d')
    id_val = car_id or f"CAR-{date_str}-{random_int_between(1, 9999)}"
    event_uuid = generate_uuid()
    
    makes = ["Tesla", "Toyota", "Honda", "Ford", "BMW"]
    models = ["Model S", "Camry", "Accord", "F-150", "3 Series"]
    colors = ["Midnight Silver", "Pearl White", "Deep Blue", "Red", "Black"]
    
    return {
        "eventHeader": {
            "uuid": event_uuid,
            "eventName": "Car Created",
            "eventType": "CarCreated",
            "createdDate": timestamp,
            "savedDate": timestamp
        },
        "entities": [{
            "entityHeader": {
                "entityId": id_val,
                "entityType": "Car",
                "createdAt": timestamp,
                "updatedAt": timestamp
            },
            "id": id_val,
            "vin": random_string(17).upper(),
            "make": makes[random_int_between(0, len(makes)-1)],
            "model": models[random_int_between(0, len(models)-1)],
            "year": random_int_between(2020, 2025),
            "color": colors[random_int_between(0, len(colors)-1)],
            "mileage": random_int_between(0, 50000),
            "lastServiceDate": timestamp,
            "totalBalance": 0.0,
            "lastLoanPaymentDate": timestamp,
            "owner": f"{random_string(8)} {random_string(10)}"
        }]
    }


def generate_loan_created_event(car_id: str, loan_id: Optional[str] = None) -> Dict[str, Any]:
    """Generate Loan Created event."""
    timestamp = generate_timestamp()
    date_str = datetime.utcnow().strftime('%Y%m%d')
    id_val = loan_id or f"LOAN-{date_str}-{random_int_between(1, 9999)}"
    event_uuid = generate_uuid()
    loan_amount = random_int_between(20000, 80000)
    interest_rate = round(random.uniform(0.02, 0.07), 4)
    term_months = [36, 48, 60, 72][random_int_between(0, 3)]
    
    # Calculate monthly payment
    monthly_rate = interest_rate / 12
    monthly_payment = (loan_amount * monthly_rate * (1 + monthly_rate) ** term_months) / \
                     ((1 + monthly_rate) ** term_months - 1)
    
    institutions = ["First National Bank", "Chase Bank", "Wells Fargo", "Bank of America"]
    
    return {
        "eventHeader": {
            "uuid": event_uuid,
            "eventName": "Loan Created",
            "eventType": "LoanCreated",
            "createdDate": timestamp,
            "savedDate": timestamp
        },
        "entities": [{
            "entityHeader": {
                "entityId": id_val,
                "entityType": "Loan",
                "createdAt": timestamp,
                "updatedAt": timestamp
            },
            "id": id_val,
            "carId": car_id,
            "financialInstitution": institutions[random_int_between(0, len(institutions)-1)],
            "balance": f"{loan_amount:.2f}",
            "lastPaidDate": timestamp,
            "loanAmount": f"{loan_amount:.2f}",
            "interestRate": interest_rate,
            "termMonths": term_months,
            "startDate": timestamp,
            "status": "active",
            "monthlyPayment": f"{monthly_payment:.2f}"
        }]
    }


def generate_loan_payment_event(loan_id: str, amount: Optional[float] = None) -> Dict[str, Any]:
    """Generate Loan Payment Submitted event."""
    timestamp = generate_timestamp()
    date_str = datetime.utcnow().strftime('%Y%m%d')
    payment_id = f"PAYMENT-{date_str}-{random_int_between(1, 9999)}"
    event_uuid = generate_uuid()
    payment_amount = amount or round(random.uniform(500, 2000), 2)
    
    return {
        "eventHeader": {
            "uuid": event_uuid,
            "eventName": "Loan Payment Submitted",
            "eventType": "LoanPaymentSubmitted",
            "createdDate": timestamp,
            "savedDate": timestamp
        },
        "entities": [{
            "entityHeader": {
                "entityId": payment_id,
                "entityType": "LoanPayment",
                "createdAt": timestamp,
                "updatedAt": timestamp
            },
            "id": payment_id,
            "loanId": loan_id,
            "amount": f"{payment_amount:.2f}",
            "paymentDate": timestamp
        }]
    }


def generate_car_service_event(car_id: str, service_id: Optional[str] = None) -> Dict[str, Any]:
    """Generate Car Service Done event."""
    timestamp = generate_timestamp()
    date_str = datetime.utcnow().strftime('%Y%m%d')
    id_val = service_id or f"SERVICE-{date_str}-{random_int_between(1, 9999)}"
    event_uuid = generate_uuid()
    amount_paid = round(random.uniform(100, 1100), 2)
    mileage_at_service = random_int_between(1000, 100000)
    
    dealers = [
        "Tesla Service Center - San Francisco",
        "Toyota Service Center - Los Angeles",
        "Honda Service Center - New York",
        "Ford Service Center - Chicago",
        "BMW Service Center - Miami"
    ]
    dealer_id = f"DEALER-{random_int_between(1, 999)}"
    dealer_name = dealers[random_int_between(0, len(dealers)-1)]
    
    descriptions = [
        "Regular maintenance service including tire rotation, brake inspection, and fluid top-up",
        "Oil change and filter replacement",
        "Brake pad replacement and brake fluid flush",
        "Transmission service and fluid change",
        "Battery replacement and electrical system check"
    ]
    description = descriptions[random_int_between(0, len(descriptions)-1)]
    
    return {
        "eventHeader": {
            "uuid": event_uuid,
            "eventName": "Car Service Done",
            "eventType": "CarServiceDone",
            "createdDate": timestamp,
            "savedDate": timestamp
        },
        "entities": [{
            "entityHeader": {
                "entityId": id_val,
                "entityType": "ServiceRecord",
                "createdAt": timestamp,
                "updatedAt": timestamp
            },
            "id": id_val,
            "carId": car_id,
            "serviceDate": timestamp,
            "amountPaid": f"{amount_paid:.2f}",
            "dealerId": dealer_id,
            "dealerName": dealer_name,
            "mileageAtService": mileage_at_service,
            "description": description
        }]
    }
