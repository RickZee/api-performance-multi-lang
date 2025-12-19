# Event Payload Samples

This directory contains example event payloads for each event type and payload size used in the load testing suite.

## Generated Samples

### Event Types

1. **Car Created** (`car-created-*.json`)
   - Event type: `CarCreated`
   - Contains car entity data (VIN, make, model, year, color, mileage, owner, etc.)

2. **Loan Created** (`loan-created-*.json`)
   - Event type: `LoanCreated`
   - Contains loan entity data (carId, financialInstitution, loanAmount, interestRate, termMonths, monthlyPayment, etc.)

3. **Loan Payment Submitted** (`loan-payment-submitted-*.json`)
   - Event type: `LoanPaymentSubmitted`
   - Contains loan payment entity data (loanId, amount, paymentDate)

4. **Car Service Done** (`car-service-done-*.json`)
   - Event type: `CarServiceDone`
   - Contains service record entity data (carId, serviceDate, amountPaid, dealerId, dealerName, mileageAtService, description)

### Payload Sizes

Each event type is available in 5 different sizes:

| Size | Target Bytes | Description |
|------|--------------|-------------|
| **default** | ~400-500 | Small payload with minimal data (no expansion) |
| **4k** | 4,096 | Medium payload with nested structures |
| **8k** | 8,192 | Large payload with expanded arrays |
| **32k** | 32,768 | Very large payload with extensive nested data |
| **64k** | 65,536 | Maximum payload size |

### File Naming Convention

Files are named using the pattern: `{event-type}-{size}.json`

Examples:
- `car-created-default.json` - Car Created event, default size
- `loan-created-4k.json` - Loan Created event, 4KB size
- `loan-payment-submitted-64k.json` - Loan Payment Submitted event, 64KB size

## Payload Structure

All payloads follow the standard event structure:

```json
{
  "eventHeader": {
    "uuid": "event-uuid",
    "eventName": "Event Name",
    "eventType": "EventType",
    "createdDate": "ISO-8601-timestamp",
    "savedDate": "ISO-8601-timestamp"
  },
  "entities": [
    {
      "entityHeader": {
        "entityId": "entity-id",
        "entityType": "EntityType",
        "createdAt": "ISO-8601-timestamp",
        "updatedAt": "ISO-8601-timestamp"
      },
      // Entity-specific fields...
    }
  ]
}
```

## Payload Expansion

For sizes larger than `default`, payloads are expanded with:

- **Car events**: Owner info, insurance details, maintenance records, features array, service history
- **Loan events**: Financial institution details, payment history, loan terms
- **Service events**: Dealer information, parts list, technician details
- **All events**: Metadata fields and padding to reach target size

## Usage

These samples can be used for:

1. **Testing**: Reference examples for API testing
2. **Documentation**: Examples of event payload structures
3. **Development**: Templates for creating new events
4. **Load Testing**: Examples of different payload sizes

## Regenerating Samples

To regenerate all samples:

```bash
cd data/samples
python3 generate_samples.py
```

The generator script creates all combinations of event types and sizes automatically.

## File Sizes

Actual file sizes may vary slightly from target sizes due to:
- JSON formatting (indentation, spacing)
- Variable-length string fields
- Random data generation

All files are formatted with 2-space indentation for readability.
