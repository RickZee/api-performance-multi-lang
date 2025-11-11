#!/bin/bash

# Test script for Producer API
echo "Testing Producer API..."

# Wait for the API to be ready
echo "Waiting for Producer API to be ready..."
sleep 10

# Test health endpoint
echo "Testing health endpoint..."
curl -f http://localhost:8081/api/v1/events/health
if [ $? -eq 0 ]; then
    echo "Health check passed"
else
    echo "Health check failed"
    exit 1
fi

# Test event processing
echo "Testing event processing..."
curl -X POST http://localhost:8081/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "eventHeader": {
      "uuid": "550e8400-e29b-41d4-a716-446655440000",
      "eventName": "LoanPaymentSubmitted",
      "createdDate": "2024-01-15T10:30:00Z",
      "savedDate": "2024-01-15T10:30:05Z",
      "eventType": "LoanPaymentSubmitted"
    },
    "eventBody": {
      "entities": [
        {
          "entityType": "Loan",
          "entityId": "loan-12345",
          "updatedAttributes": {
            "balance": 24439.75,
            "lastPaidDate": "2024-01-15T10:30:00Z"
          }
        },
        {
          "entityType": "LoanPayment",
          "entityId": "payment-12345",
          "updatedAttributes": {
            "paymentAmount": 560.25,
            "paymentDate": "2024-01-15T10:30:00Z",
            "paymentMethod": "ACH",
            "transactionId": "txn-987654321",
            "financialInstitution": "ABC Bank",
            "accountLast4": "1234"
          }
        }
      ]
    }
  }'

if [ $? -eq 0 ]; then
    echo "Event processing test passed"
else
    echo "Event processing test failed"
    exit 1
fi

echo "All tests passed!"
