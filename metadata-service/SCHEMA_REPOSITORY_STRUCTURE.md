# Schema Repository Structure

This document describes the expected structure for the git repository containing JSON schemas used by the metadata service.

## Directory Structure

The metadata service expects schemas to be organized in a versioned directory structure:

```
schemas/
├── v1/
│   ├── event/
│   │   ├── event.json
│   │   └── event-header.json
│   └── entity/
│       ├── entity-header.json
│       ├── car.json
│       ├── loan.json
│       ├── loan-payment.json
│       ├── service-record.json
│       ├── service-details.json
│       └── part-used.json
├── v2/
│   ├── event/
│   │   ├── event.json
│   │   └── event-header.json
│   └── entity/
│       ├── entity-header.json
│       ├── car.json
│       └── ...
└── metadata.json  # Optional: version metadata and compatibility rules
```

## Versioning Convention

- **Version directories**: Use semantic versioning format (e.g., `v1`, `v2`, `v1.1`)
- **Event schemas**: Located in `{version}/event/` directory
- **Entity schemas**: Located in `{version}/entity/` directory
- **Latest version**: The service uses the highest version number as "latest"

## Schema Files

### Event Schema (`event/event.json`)

The main event schema that defines the structure of events:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://example.com/schemas/event/event.json",
  "title": "Event Schema",
  "type": "object",
  "properties": {
    "eventHeader": {
      "$ref": "event-header.json"
    },
    "entities": {
      "type": "array",
      "items": {
        "oneOf": [
          { "$ref": "../entity/car.json" },
          { "$ref": "../entity/loan.json" }
        ]
      },
      "minItems": 1
    }
  },
  "required": ["eventHeader", "entities"],
  "additionalProperties": false
}
```

### Event Header Schema (`event/event-header.json`)

Common event header structure:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://example.com/schemas/event/event-header.json",
  "title": "Event Header Schema",
  "type": "object",
  "properties": {
    "uuid": {
      "type": "string",
      "format": "uuid"
    },
    "eventName": {
      "type": "string"
    },
    "eventType": {
      "type": "string",
      "enum": ["CarCreated", "LoanCreated", "LoanPaymentSubmitted", "CarServiceDone"]
    },
    "createdDate": {
      "type": "string",
      "format": "date-time"
    },
    "savedDate": {
      "type": "string",
      "format": "date-time"
    }
  },
  "required": ["uuid", "eventName", "eventType", "createdDate", "savedDate"],
  "additionalProperties": false
}
```

### Entity Header Schema (`entity/entity-header.json`)

Common entity header structure:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://example.com/schemas/entity/entity-header.json",
  "title": "Entity Header Schema",
  "type": "object",
  "properties": {
    "entityId": {
      "type": "string"
    },
    "entityType": {
      "type": "string",
      "enum": ["Car", "Loan", "LoanPayment", "ServiceRecord", "PartUsed", "ServiceDetails"]
    },
    "createdAt": {
      "type": "string",
      "format": "date-time"
    },
    "updatedAt": {
      "type": "string",
      "format": "date-time"
    }
  },
  "required": ["entityId", "entityType", "createdAt", "updatedAt"],
  "additionalProperties": false
}
```

### Entity Schemas (`entity/*.json`)

Each entity type has its own schema file that references the entity header:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://example.com/schemas/entity/car.json",
  "title": "Car Entity Schema",
  "type": "object",
  "properties": {
    "entityHeader": {
      "$ref": "entity-header.json"
    },
    "id": {
      "type": "string"
    },
    "vin": {
      "type": "string",
      "pattern": "^[A-HJ-NPR-Z0-9]{17}$"
    },
    "make": {
      "type": "string"
    },
    "model": {
      "type": "string"
    },
    "year": {
      "type": "integer",
      "minimum": 1900,
      "maximum": 2030
    }
  },
  "required": ["entityHeader", "id", "vin", "make", "model", "year"],
  "additionalProperties": false
}
```

## Metadata File (Optional)

The `metadata.json` file can contain version metadata and compatibility rules:

```json
{
  "versions": {
    "v1": {
      "released": "2024-01-01",
      "deprecated": false
    },
    "v2": {
      "released": "2024-06-01",
      "deprecated": false,
      "compatible_with": ["v1"]
    }
  },
  "compatibility_rules": {
    "v1_to_v2": {
      "breaking_changes": [],
      "non_breaking_changes": [
        "Added optional 'warranty' field to Car entity"
      ]
    }
  }
}
```

## Reference Resolution

The metadata service resolves `$ref` references using relative paths:

- **Within same directory**: `"$ref": "entity-header.json"`
- **Parent directory**: `"$ref": "../entity/car.json"`
- **Sibling directory**: `"$ref": "../entity/loan.json"`

## Backward Compatibility

When creating a new version:

1. **Non-breaking changes** (automatically accepted):
   - Adding optional properties
   - Relaxing constraints (e.g., increasing max value)
   - Adding new enum values
   - Making required fields optional

2. **Breaking changes** (will be rejected):
   - Removing required properties
   - Adding new required properties
   - Removing enum values
   - Tightening constraints
   - Changing property types

## Example: Creating a New Version

1. Create a new version directory: `schemas/v2/`
2. Copy the previous version's schemas: `cp -r schemas/v1/* schemas/v2/`
3. Make your changes to the v2 schemas
4. Ensure backward compatibility rules are followed
5. Commit and push to the repository
6. The metadata service will automatically detect and load the new version

## Git Repository Setup

### Public Repository

```bash
# Clone and set up structure
git clone https://github.com/your-org/schema-repo.git
cd schema-repo
mkdir -p schemas/v1/event schemas/v1/entity
# Add your schema files
git add schemas/
git commit -m "Add initial schema version v1"
git push
```

### Private Repository (SSH)

The metadata service supports SSH authentication for private repositories:

1. Generate SSH key: `ssh-keygen -t ed25519 -C "metadata-service"`
2. Add public key to repository (GitHub/GitLab deploy keys)
3. Mount private key in metadata service container or use SSH agent

### Private Repository (HTTPS with Token)

For HTTPS authentication:

1. Create a personal access token
2. Use URL format: `https://token@github.com/org/repo.git`
3. Set as `GIT_REPOSITORY` environment variable

## Testing Schema Changes

Before deploying schema changes:

1. Validate JSON Schema syntax using a JSON Schema validator
2. Test with sample events to ensure validation works
3. Check backward compatibility if creating a new version
4. Test with the metadata service's `/api/v1/validate` endpoint

## Best Practices

1. **Version increment**: Always create a new version directory for schema changes
2. **Documentation**: Document breaking changes in `metadata.json`
3. **Testing**: Test schema changes in a development environment first
4. **Gradual rollout**: Support multiple versions during migration periods
5. **Deprecation**: Mark old versions as deprecated in `metadata.json` before removal

