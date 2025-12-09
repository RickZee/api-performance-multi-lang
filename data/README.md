# Data Folder Structure

This directory contains JSON schemas, entity data samples, and event templates for the event-based processing system.

## Directory Structure

```
data/
├── schemas/           # JSON Schema definitions
│   ├── event/         # Event schemas
│   │   ├── event.json
│   │   └── event-header.json
│   └── entity/        # Entity schemas
│       ├── entity-header.json
│       ├── car.json
│       ├── loan.json
│       ├── loan-payment.json
│       ├── service-record.json
│       ├── service-details.json
│       └── part-used.json
├── entities/          # Sample entity data files
│   └── car/
│       ├── car-small.json
│       ├── car-medium.json
│       └── car-large.json
└── templates/         # Event templates for code generation
    └── event-templates.json
```

## Schemas

### Event Schemas

Located in `schemas/event/`:

- **`event.json`**: Main event schema defining the structure of events in the system. Events consist of:
  - `eventHeader`: Metadata about the event (see `event-header.json`)
  - `entities`: Array of entities affected by the event

- **`event-header.json`**: Common event header structure containing:
  - `uuid`: Unique identifier for the event (UUID format)
  - `eventName`: Readable event description (e.g., "Car Created", "Loan Created", "Loan Payment Submitted", "Car Service Done")
  - `createdDate`: ISO 8601 timestamp when the event was created
  - `savedDate`: ISO 8601 timestamp when the event was saved
  - `eventType`: Readable event description (deprecated: use `eventName` instead)

### Entity Schemas

Located in `schemas/entity/`:

- **`entity-header.json`**: Common entity header structure used by all entities:
  - `entityId`: Unique identifier for the entity
  - `entityType`: Type of the entity (enum: Car, Loan, LoanPayment, ServiceRecord, PartUsed, ServiceDetails)
  - `createdAt`: ISO 8601 timestamp when the entity was created
  - `updatedAt`: ISO 8601 timestamp when the entity was last updated

- **`car.json`**: Car entity schema
- **`loan.json`**: Loan entity schema
- **`loan-payment.json`**: Loan payment entity schema
- **`service-record.json`**: Service record entity schema
- **`service-details.json`**: Service details entity schema
- **`part-used.json`**: Part used entity schema

All entity schemas:
- Reference `entity-header.json` for the common `entityHeader` property
- Define entity-specific properties
- Do NOT include `createdAt`/`updatedAt` directly (these are in the entity header)

## Entity Data Files

Located in `entities/`:

Sample entity data files that conform to the entity schemas. Currently includes:
- `car/car-small.json`: Minimal car entity example
- `car/car-medium.json`: Medium complexity car entity example
- `car/car-large.json`: Complex car entity example

These files are used for testing and development purposes. They must conform to the corresponding entity schema structure.

## Event Templates

Located in `templates/`:

- **`event-templates.json`**: Template definitions for generating events. Each template includes:
  - `eventHeader`: Event header with template variables (e.g., `${uuid}`, `${timestamp}`)
  - `entities`: Array of entity templates with template variables

Templates are used for code generation and testing. The structure matches the event schema format.

## Schema References

Schemas use JSON Schema draft 2020-12 and reference each other using relative paths:

- Event schemas reference entity schemas using `../entity/` paths
- Entity schemas reference the header using `entity-header.json` (same directory)
- Entity schemas can reference other entity schemas using relative paths within the same directory

## Usage

### Validating Data Against Schemas

Entity data files should be validated against their corresponding schemas. The schemas use JSON Schema draft 2020-12 format.

### Event Structure

All events must follow the structure defined in `schemas/event/event.json`:
- Events contain an `eventHeader` and an `entities` array
- Entities in the array must match one of the defined entity schemas
- Each entity must include the `entityHeader` property

### Entity Structure

All entities must:
- Include the `entityHeader` property referencing the entity header schema
- Include all required fields as defined in their schema
- Not include `createdAt`/`updatedAt` at the root level (these are in the `entityHeader`)

## Notes

- The `eventType` field in event headers is deprecated but kept for backward compatibility. Use `eventName` instead.
- Entity timestamps (`createdAt`, `updatedAt`) are defined in the entity header, not as direct properties of the entity.
- All date-time fields use ISO 8601 format.
- All monetary amounts use `multipleOf: 0.01` for precision.

