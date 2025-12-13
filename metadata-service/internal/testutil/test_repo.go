package testutil

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// SetupTestRepo creates a temporary git repository with test schemas
func SetupTestRepo(baseDir string) (string, error) {
	repoDir := filepath.Join(baseDir, "test-schema-repo")
	if err := os.MkdirAll(repoDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create repo directory: %w", err)
	}

	// Initialize git repo
	cmd := exec.Command("git", "init")
	cmd.Dir = repoDir
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("failed to init git repo: %w", err)
	}

	// Create v1 schemas
	v1EventDir := filepath.Join(repoDir, "schemas", "v1", "event")
	v1EntityDir := filepath.Join(repoDir, "schemas", "v1", "entity")
	if err := os.MkdirAll(v1EventDir, 0755); err != nil {
		return "", err
	}
	if err := os.MkdirAll(v1EntityDir, 0755); err != nil {
		return "", err
	}

	// Write event-header.json
	eventHeader := `{
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
}`
	if err := os.WriteFile(filepath.Join(v1EventDir, "event-header.json"), []byte(eventHeader), 0644); err != nil {
		return "", err
	}

	// Write entity-header.json
	entityHeader := `{
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
      "enum": ["Car", "Loan", "LoanPayment", "ServiceRecord"]
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
}`
	if err := os.WriteFile(filepath.Join(v1EntityDir, "entity-header.json"), []byte(entityHeader), 0644); err != nil {
		return "", err
	}

	// Write car.json
	carSchema := `{
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
    },
    "color": {
      "type": "string"
    },
    "mileage": {
      "type": "integer",
      "minimum": 0
    }
  },
  "required": ["entityHeader", "id", "vin", "make", "model", "year", "color", "mileage"],
  "additionalProperties": false
}`
	if err := os.WriteFile(filepath.Join(v1EntityDir, "car.json"), []byte(carSchema), 0644); err != nil {
		return "", err
	}

	// Write event.json
	eventSchema := `{
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
          {
            "$ref": "../entity/car.json"
          }
        ]
      },
      "minItems": 1
    }
  },
  "required": ["eventHeader", "entities"],
  "additionalProperties": false
}`
	if err := os.WriteFile(filepath.Join(v1EventDir, "event.json"), []byte(eventSchema), 0644); err != nil {
		return "", err
	}

	// Commit files
	cmd = exec.Command("git", "add", ".")
	cmd.Dir = repoDir
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("failed to git add: %w", err)
	}

	cmd = exec.Command("git", "config", "user.email", "test@example.com")
	cmd.Dir = repoDir
	cmd.Run()

	cmd = exec.Command("git", "config", "user.name", "Test User")
	cmd.Dir = repoDir
	cmd.Run()

	cmd = exec.Command("git", "commit", "-m", "Initial commit")
	cmd.Dir = repoDir
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("failed to git commit: %w", err)
	}

	return repoDir, nil
}

// CleanupTestRepo removes the test repository
func CleanupTestRepo(repoDir string) error {
	return os.RemoveAll(repoDir)
}

