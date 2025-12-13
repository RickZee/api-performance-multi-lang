package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"go.uber.org/zap"
	"metadata-service/internal/validator"
)

func TestReferenceResolver_CircularReference(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "ref-resolver-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	logger, _ := zap.NewDevelopment()

	// Create schemas with circular reference
	// A.json references B.json, B.json references A.json
	schemasDir := filepath.Join(tempDir, "schemas", "v1")
	eventDir := filepath.Join(schemasDir, "event")
	entityDir := filepath.Join(schemasDir, "entity")

	os.MkdirAll(eventDir, 0755)
	os.MkdirAll(entityDir, 0755)

	// Create A.json that references B.json
	aSchema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"refB": map[string]interface{}{
				"$ref": "b.json",
			},
		},
	}

	// Create B.json that references A.json
	bSchema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"refA": map[string]interface{}{
				"$ref": "a.json",
			},
		},
	}

	// Write schemas to disk
	aData, _ := json.Marshal(aSchema)
	bData, _ := json.Marshal(bSchema)
	os.WriteFile(filepath.Join(entityDir, "a.json"), aData, 0644)
	os.WriteFile(filepath.Join(entityDir, "b.json"), bData, 0644)

	// Create resolver
	resolver := validator.NewReferenceResolver(tempDir, make(map[string]map[string]interface{}), logger)
	resolver.SetVersion("v1")

	// Try to resolve - should detect cycle and not panic
	result, err := resolver.ResolveSchema(aSchema)
	if err != nil {
		t.Logf("Expected error or cycle detection: %v", err)
	}

	// Should not panic and should return something (even if with unresolved refs)
	if result == nil {
		t.Error("Resolver should return result even with circular reference")
	}
}

func TestReferenceResolver_MissingFile(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "ref-resolver-missing-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	logger, _ := zap.NewDevelopment()

	schemasDir := filepath.Join(tempDir, "schemas", "v1", "event")
	os.MkdirAll(schemasDir, 0755)

	// Create schema with reference to non-existent file
	schema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"missing": map[string]interface{}{
				"$ref": "nonexistent.json",
			},
		},
	}

	resolver := validator.NewReferenceResolver(tempDir, make(map[string]map[string]interface{}), logger)
	resolver.SetVersion("v1")

	// Should handle missing file gracefully
	result, err := resolver.ResolveSchema(schema)
	if err != nil {
		t.Logf("Expected error for missing file: %v", err)
	}

	// Should return schema with unresolved $ref
	if result == nil {
		t.Error("Resolver should return result even with missing file")
	}
}

func TestReferenceResolver_DeeplyNested(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "ref-resolver-nested-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	logger, _ := zap.NewDevelopment()

	schemasDir := filepath.Join(tempDir, "schemas", "v1")
	eventDir := filepath.Join(schemasDir, "event")
	entityDir := filepath.Join(schemasDir, "entity")

	os.MkdirAll(eventDir, 0755)
	os.MkdirAll(entityDir, 0755)

	// Create chain: A -> B -> C -> D
	dSchema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"value": map[string]interface{}{
				"type": "string",
			},
		},
	}

	cSchema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"refD": map[string]interface{}{
				"$ref": "../entity/d.json",
			},
		},
	}

	bSchema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"refC": map[string]interface{}{
				"$ref": "../entity/c.json",
			},
		},
	}

	aSchema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"refB": map[string]interface{}{
				"$ref": "../entity/b.json",
			},
		},
	}

	// Write schemas
	dData, _ := json.Marshal(dSchema)
	cData, _ := json.Marshal(cSchema)
	bData, _ := json.Marshal(bSchema)
	aData, _ := json.Marshal(aSchema)

	os.WriteFile(filepath.Join(entityDir, "d.json"), dData, 0644)
	os.WriteFile(filepath.Join(entityDir, "c.json"), cData, 0644)
	os.WriteFile(filepath.Join(entityDir, "b.json"), bData, 0644)
	os.WriteFile(filepath.Join(eventDir, "a.json"), aData, 0644)

	resolver := validator.NewReferenceResolver(tempDir, make(map[string]map[string]interface{}), logger)
	resolver.SetVersion("v1")

	// Should resolve all nested references
	result, err := resolver.ResolveSchema(aSchema)
	if err != nil {
		t.Fatalf("Failed to resolve nested references: %v", err)
	}

	// Verify D is resolved in the chain
	resultJSON, _ := json.MarshalIndent(result, "", "  ")
	if !contains(resultJSON, "value") {
		t.Error("Deeply nested reference should be resolved")
	}
}

func TestReferenceResolver_InvalidJSON(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "ref-resolver-invalid-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	logger, _ := zap.NewDevelopment()

	schemasDir := filepath.Join(tempDir, "schemas", "v1", "entity")
	os.MkdirAll(schemasDir, 0755)

	// Create file with invalid JSON
	os.WriteFile(filepath.Join(schemasDir, "invalid.json"), []byte("{ invalid json }"), 0644)

	schema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"ref": map[string]interface{}{
				"$ref": "../entity/invalid.json",
			},
		},
	}

	resolver := validator.NewReferenceResolver(tempDir, make(map[string]map[string]interface{}), logger)
	resolver.SetVersion("v1")

	// Should handle invalid JSON gracefully
	result, err := resolver.ResolveSchema(schema)
	if err != nil {
		t.Logf("Expected error for invalid JSON: %v", err)
	}

	// Should return schema with unresolved $ref
	if result == nil {
		t.Error("Resolver should return result even with invalid JSON")
	}
}

func TestReferenceResolver_MultipleReferences(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "ref-resolver-multiple-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	logger, _ := zap.NewDevelopment()

	schemasDir := filepath.Join(tempDir, "schemas", "v1")
	eventDir := filepath.Join(schemasDir, "event")
	entityDir := filepath.Join(schemasDir, "entity")

	os.MkdirAll(eventDir, 0755)
	os.MkdirAll(entityDir, 0755)

	// Create referenced schemas
	headerSchema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"id": map[string]interface{}{
				"type": "string",
			},
		},
	}

	carSchema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"entityHeader": map[string]interface{}{
				"$ref": "entity-header.json",
			},
			"vin": map[string]interface{}{
				"type": "string",
			},
		},
	}

	// Write schemas
	headerData, _ := json.Marshal(headerSchema)
	carData, _ := json.Marshal(carSchema)
	os.WriteFile(filepath.Join(entityDir, "entity-header.json"), headerData, 0644)
	os.WriteFile(filepath.Join(entityDir, "car.json"), carData, 0644)

	// Create schema with multiple references
	schema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"car": map[string]interface{}{
				"$ref": "../entity/car.json",
			},
			"header": map[string]interface{}{
				"$ref": "entity-header.json",
			},
		},
	}

	resolver := validator.NewReferenceResolver(tempDir, make(map[string]map[string]interface{}), logger)
	resolver.SetVersion("v1")

	result, err := resolver.ResolveSchema(schema)
	if err != nil {
		t.Fatalf("Failed to resolve multiple references: %v", err)
	}

	// Verify both references are resolved
	resultJSON, _ := json.MarshalIndent(result, "", "  ")
	if !contains(resultJSON, "vin") || !contains(resultJSON, "id") {
		t.Error("Multiple references should all be resolved")
	}
}

func contains(data []byte, substr string) bool {
	if len(data) == 0 || len(substr) == 0 {
		return false
	}
	return containsInMiddle(data, substr)
}

func containsInMiddle(data []byte, substr string) bool {
	for i := 0; i <= len(data)-len(substr); i++ {
		if string(data[i:i+len(substr)]) == substr {
			return true
		}
	}
	return false
}

