"""Shared constants for Producer API."""

# Entity type to table name mapping
ENTITY_TABLE_MAP = {
    "Car": "car_entities",
    "Loan": "loan_entities",
    "LoanPayment": "loan_payment_entities",
    "ServiceRecord": "service_record_entities",
}

# Retry configuration
MAX_RETRIES = 3
INITIAL_RETRY_DELAY = 0.1  # 100ms
MAX_RETRY_DELAY = 2.0  # 2 seconds
