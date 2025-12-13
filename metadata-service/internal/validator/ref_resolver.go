package validator

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"go.uber.org/zap"
)

// ReferenceResolver resolves $ref references in JSON schemas
type ReferenceResolver struct {
	basePath      string
	eventDir      string
	entityDir     string
	entitySchemas map[string]map[string]interface{}
	logger        *zap.Logger
	resolved      map[string]interface{} // Cache for resolved schemas
	resolving     map[string]bool        // Track references being resolved to detect cycles
}

// NewReferenceResolver creates a new reference resolver
func NewReferenceResolver(basePath string, entitySchemas map[string]map[string]interface{}, logger *zap.Logger) *ReferenceResolver {
	// Determine event and entity directories
	schemasSubDir := filepath.Join(basePath, "schemas")
	if _, err := os.Stat(schemasSubDir); err == nil {
		basePath = schemasSubDir
	}

	return &ReferenceResolver{
		basePath:      basePath,
		eventDir:      filepath.Join(basePath, "v1", "event"), // Will be updated per version
		entityDir:     filepath.Join(basePath, "v1", "entity"), // Will be updated per version
		entitySchemas: entitySchemas,
		logger:        logger,
		resolved:      make(map[string]interface{}),
		resolving:     make(map[string]bool),
	}
}

// SetVersion updates the directories for a specific version
func (rr *ReferenceResolver) SetVersion(version string) {
	rr.eventDir = filepath.Join(rr.basePath, version, "event")
	rr.entityDir = filepath.Join(rr.basePath, version, "entity")
}

// ResolveSchema resolves all $ref references in a schema
func (rr *ReferenceResolver) ResolveSchema(schema map[string]interface{}) (map[string]interface{}, error) {
	return rr.resolveValue(schema).(map[string]interface{}), nil
}

// resolveValue recursively resolves $ref references in any JSON value
func (rr *ReferenceResolver) resolveValue(value interface{}) interface{} {
	switch v := value.(type) {
	case map[string]interface{}:
		// Check if this is a $ref
		if ref, ok := v["$ref"].(string); ok {
			return rr.resolveReference(ref)
		}

		// Recursively resolve all values in the map
		// Skip $id and $schema as they might contain URLs that confuse gojsonschema
		resolved := make(map[string]interface{})
		for k, val := range v {
			if k == "$id" || k == "$schema" {
				// Keep $schema but remove $id to prevent HTTP fetching
				if k == "$schema" {
					resolved[k] = val
				}
				// Skip $id
				continue
			}
			resolved[k] = rr.resolveValue(val)
		}
		return resolved

	case []interface{}:
		// Recursively resolve all values in the array
		resolved := make([]interface{}, len(v))
		for i, val := range v {
			resolved[i] = rr.resolveValue(val)
		}
		return resolved

	default:
		return value
	}
}

// resolveReference resolves a $ref reference to actual schema content
func (rr *ReferenceResolver) resolveReference(ref string) interface{} {
	// Check cache first
	if cached, ok := rr.resolved[ref]; ok {
		return cached
	}

	// Check for circular reference
	if rr.resolving[ref] {
		rr.logger.Warn("Circular reference detected", zap.String("ref", ref))
		return map[string]interface{}{"$ref": ref} // Return original to break cycle
	}

	// Mark as resolving
	rr.resolving[ref] = true
	defer delete(rr.resolving, ref)

	// Resolve the reference
	var resolved interface{}

	// Handle different reference patterns
	if strings.HasPrefix(ref, "../entity/") {
		// Reference to entity schema: ../entity/car.json
		entityName := strings.TrimPrefix(ref, "../entity/")
		entityName = strings.TrimSuffix(entityName, ".json")
		
		if entitySchema, ok := rr.entitySchemas[entityName]; ok {
			// Recursively resolve references in the entity schema
			resolved = rr.resolveValue(entitySchema)
		} else {
			// Try to load from disk
			entityPath := filepath.Join(rr.entityDir, entityName+".json")
			if schema, err := rr.loadSchemaFromFile(entityPath); err == nil {
				resolved = rr.resolveValue(schema)
			} else {
				rr.logger.Warn("Failed to resolve entity reference",
					zap.String("ref", ref),
					zap.String("path", entityPath),
					zap.Error(err))
				return map[string]interface{}{"$ref": ref} // Return original if can't resolve
			}
		}
	} else if strings.HasSuffix(ref, ".json") {
		// Reference to file - could be in event or entity directory
		fileName := ref
		
		// Try event directory first
		filePath := filepath.Join(rr.eventDir, fileName)
		if _, err := os.Stat(filePath); os.IsNotExist(err) {
			// Try entity directory
			filePath = filepath.Join(rr.entityDir, fileName)
		}
		
		if schema, err := rr.loadSchemaFromFile(filePath); err == nil {
			resolved = rr.resolveValue(schema)
		} else {
			rr.logger.Warn("Failed to resolve file reference",
				zap.String("ref", ref),
				zap.String("path", filePath),
				zap.Error(err))
			return map[string]interface{}{"$ref": ref} // Return original if can't resolve
		}
	} else {
		// Unknown reference pattern
		rr.logger.Warn("Unknown reference pattern", zap.String("ref", ref))
		return map[string]interface{}{"$ref": ref}
	}

	// Cache the resolved schema
	rr.resolved[ref] = resolved
	return resolved
}

// loadSchemaFromFile loads a JSON schema from a file
func (rr *ReferenceResolver) loadSchemaFromFile(filePath string) (map[string]interface{}, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read file: %w", err)
	}

	var schema map[string]interface{}
	if err := json.Unmarshal(data, &schema); err != nil {
		return nil, fmt.Errorf("failed to parse JSON: %w", err)
	}

	return schema, nil
}

