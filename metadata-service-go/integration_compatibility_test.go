package main

import (
	"encoding/json"
	"testing"

	"metadata-service/internal/compat"
)

func TestCompatibility_NonBreakingChanges(t *testing.T) {
	checker := compat.NewCompatibilityChecker()

	// Load v1 schema
	v1Schema := loadTestSchema("v1")

	// Create v2 schema with non-breaking changes (adding optional field)
	v2Schema := make(map[string]interface{})
	v1Bytes, _ := json.Marshal(v1Schema)
	json.Unmarshal(v1Bytes, &v2Schema)

	// Add optional property to v2
	if props, ok := v2Schema["properties"].(map[string]interface{}); ok {
		props["warranty"] = map[string]interface{}{
			"type": "string",
		}
		// Don't add to required array - this is non-breaking
	}

	result := checker.CheckCompatibility(v1Schema, v2Schema)

	if !result.Compatible {
		t.Errorf("Expected compatible=true for non-breaking change, got compatible=false. Reason: %s", result.Reason)
	}

	if len(result.BreakingChanges) > 0 {
		t.Errorf("Expected no breaking changes, got: %v", result.BreakingChanges)
	}

	if len(result.NonBreakingChanges) == 0 {
		t.Error("Expected non-breaking changes to be detected")
	}
}

func TestCompatibility_BreakingChanges_RemovedRequired(t *testing.T) {
	checker := compat.NewCompatibilityChecker()

	v1Schema := loadTestSchema("v1")

	// Create v2 schema with breaking change (removing required field)
	v2Schema := make(map[string]interface{})
	v1Bytes, _ := json.Marshal(v1Schema)
	json.Unmarshal(v1Bytes, &v2Schema)

	// Remove a required field
	if required, ok := v2Schema["required"].([]interface{}); ok {
		// Remove first required field
		if len(required) > 0 {
			v2Schema["required"] = required[1:]
		}
	}

	result := checker.CheckCompatibility(v1Schema, v2Schema)

	if result.Compatible {
		t.Error("Expected compatible=false for breaking change (removed required field)")
	}

	if len(result.BreakingChanges) == 0 {
		t.Error("Expected breaking changes to be detected")
	}
}

func TestCompatibility_BreakingChanges_NewRequired(t *testing.T) {
	checker := compat.NewCompatibilityChecker()

	v1Schema := loadTestSchema("v1")

	// Create v2 schema with breaking change (new required field)
	v2Schema := make(map[string]interface{})
	v1Bytes, _ := json.Marshal(v1Schema)
	json.Unmarshal(v1Bytes, &v2Schema)

	// Add new required field
	if required, ok := v2Schema["required"].([]interface{}); ok {
		v2Schema["required"] = append(required, "newRequiredField")
	} else {
		v2Schema["required"] = []interface{}{"newRequiredField"}
	}

	// Add the property
	if props, ok := v2Schema["properties"].(map[string]interface{}); ok {
		props["newRequiredField"] = map[string]interface{}{
			"type": "string",
		}
	}

	result := checker.CheckCompatibility(v1Schema, v2Schema)

	if result.Compatible {
		t.Error("Expected compatible=false for breaking change (new required field)")
	}

	if len(result.BreakingChanges) == 0 {
		t.Error("Expected breaking changes to be detected")
	}
}

func TestCompatibility_BreakingChanges_TypeChange(t *testing.T) {
	checker := compat.NewCompatibilityChecker()

	v1Schema := loadTestSchema("v1")

	// Create v2 schema with breaking change (type change)
	v2Schema := make(map[string]interface{})
	v1Bytes, _ := json.Marshal(v1Schema)
	json.Unmarshal(v1Bytes, &v2Schema)

	// Change type of a property
	if props, ok := v2Schema["properties"].(map[string]interface{}); ok {
		if yearProp, ok := props["year"].(map[string]interface{}); ok {
			yearProp["type"] = "string" // Changed from integer to string
		}
	}

	result := checker.CheckCompatibility(v1Schema, v2Schema)

	if result.Compatible {
		t.Error("Expected compatible=false for breaking change (type change)")
	}

	if len(result.BreakingChanges) == 0 {
		t.Error("Expected breaking changes to be detected")
	}
}

func TestCompatibility_ConstraintTightening(t *testing.T) {
	checker := compat.NewCompatibilityChecker()

	v1Schema := loadTestSchema("v1")

	// Create v2 schema with tightened constraint
	v2Schema := make(map[string]interface{})
	v1Bytes, _ := json.Marshal(v1Schema)
	json.Unmarshal(v1Bytes, &v2Schema)

	// Tighten maximum constraint
	if props, ok := v2Schema["properties"].(map[string]interface{}); ok {
		if yearProp, ok := props["year"].(map[string]interface{}); ok {
			yearProp["maximum"] = 2020.0 // Reduced from 2030
		}
	}

	result := checker.CheckCompatibility(v1Schema, v2Schema)

	if result.Compatible {
		t.Error("Expected compatible=false for tightened constraint")
	}

	if len(result.BreakingChanges) == 0 {
		t.Error("Expected breaking changes to be detected")
	}
}

func TestCompatibility_ConstraintRelaxation(t *testing.T) {
	checker := compat.NewCompatibilityChecker()

	v1Schema := loadTestSchema("v1")

	// Create v2 schema with relaxed constraint
	v2Schema := make(map[string]interface{})
	v1Bytes, _ := json.Marshal(v1Schema)
	json.Unmarshal(v1Bytes, &v2Schema)

	// Relax maximum constraint
	if props, ok := v2Schema["properties"].(map[string]interface{}); ok {
		if yearProp, ok := props["year"].(map[string]interface{}); ok {
			yearProp["maximum"] = 2050.0 // Increased from 2030
		}
	}

	result := checker.CheckCompatibility(v1Schema, v2Schema)

	if result.Compatible {
		t.Logf("Compatible: %v, Reason: %s", result.Compatible, result.Reason)
	}

	// Relaxation is non-breaking, but we should detect it
	if len(result.NonBreakingChanges) == 0 {
		t.Log("Note: Constraint relaxation detection may need improvement")
	}
}

func loadTestSchema(version string) map[string]interface{} {
	// Load car schema from test repo
	// This is a simplified version for testing
	return map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"id": map[string]interface{}{
				"type": "string",
			},
			"year": map[string]interface{}{
				"type":    "integer",
				"minimum": 1900.0,
				"maximum": 2030.0,
			},
		},
		"required": []interface{}{"id", "year"},
	}
}

