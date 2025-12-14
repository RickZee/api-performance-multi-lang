package validator

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/xeipuuv/gojsonschema"
	"go.uber.org/zap"
)

type JSONSchemaValidator struct {
	logger *zap.Logger
}

type ValidationError struct {
	Field   string
	Message string
}

type ValidationResult struct {
	Valid   bool
	Errors  []ValidationError
	Version string
}

func NewJSONSchemaValidator(logger *zap.Logger) *JSONSchemaValidator {
	return &JSONSchemaValidator{
		logger: logger,
	}
}

func (v *JSONSchemaValidator) ValidateEvent(eventData interface{}, eventSchema map[string]interface{}, entitySchemas map[string]map[string]interface{}, basePath string) (*ValidationResult, error) {
	// Extract version from basePath if possible (e.g., .../schemas/v1/...)
	version := "v1" // Default
	// Look for version pattern in path
	parts := strings.Split(basePath, "/")
	for i, part := range parts {
		if strings.HasPrefix(part, "v") && len(part) > 1 && len(part) <= 10 {
			// Check if next part is "event" or "entity" to confirm it's a version
			if i+1 < len(parts) && (parts[i+1] == "event" || parts[i+1] == "entity") {
				version = part
				break
			}
		}
	}
	
	// If version not found, try to find it by looking for "schemas/vX" pattern
	if version == "v1" {
		pathStr := strings.Join(parts, "/")
		if idx := strings.Index(pathStr, "schemas/v"); idx != -1 {
			remaining := pathStr[idx+8:] // Skip "schemas/v"
			if slashIdx := strings.Index(remaining, "/"); slashIdx != -1 {
				version = "v" + remaining[:slashIdx]
			} else if len(remaining) > 0 {
				version = "v" + remaining
			}
		}
	}

	// Create reference resolver and resolve all $ref references
	resolver := NewReferenceResolver(basePath, entitySchemas, v.logger)
	resolver.SetVersion(version)

	// Resolve references in event schema
	resolvedEventSchema, err := resolver.ResolveSchema(eventSchema)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve event schema references: %w", err)
	}

	// Convert event data to JSON for validation
	eventJSON, err := toJSONBytes(eventData)
	if err != nil {
		return nil, fmt.Errorf("failed to serialize event: %w", err)
	}

	// Create loaders with resolved schema (no $ref references)
	schemaLoader := gojsonschema.NewGoLoader(resolvedEventSchema)
	documentLoader := gojsonschema.NewBytesLoader(eventJSON)

	// Validate
	result, err := gojsonschema.Validate(schemaLoader, documentLoader)
	if err != nil {
		return nil, fmt.Errorf("validation error: %w", err)
	}

	validationResult := &ValidationResult{
		Valid:   result.Valid(),
		Errors:  make([]ValidationError, 0),
		Version: "", // Will be set by caller
	}

	if !result.Valid() {
		for _, desc := range result.Errors() {
			validationResult.Errors = append(validationResult.Errors, ValidationError{
				Field:   desc.Field(),
				Message: desc.Description(),
			})
		}
	}

	return validationResult, nil
}

func toJSONBytes(data interface{}) ([]byte, error) {
	return json.Marshal(data)
}

