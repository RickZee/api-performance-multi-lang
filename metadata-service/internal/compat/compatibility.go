package compat

import (
	"fmt"
	"reflect"
)

type CompatibilityChecker struct{}

type CompatibilityResult struct {
	Compatible bool
	Reason     string
	BreakingChanges []string
	NonBreakingChanges []string
}

func NewCompatibilityChecker() *CompatibilityChecker {
	return &CompatibilityChecker{}
}

func (cc *CompatibilityChecker) CheckCompatibility(oldSchema, newSchema map[string]interface{}) *CompatibilityResult {
	result := &CompatibilityResult{
		Compatible:         true,
		BreakingChanges:    make([]string, 0),
		NonBreakingChanges: make([]string, 0),
	}

	// Check required fields
	oldRequired := getRequiredFields(oldSchema)
	newRequired := getRequiredFields(newSchema)

	// Check for removed required fields (breaking)
	for field := range oldRequired {
		if !newRequired[field] {
			result.Compatible = false
			result.BreakingChanges = append(result.BreakingChanges, fmt.Sprintf("Required field '%s' was removed", field))
		}
	}

	// Check for new required fields (breaking)
	for field := range newRequired {
		if !oldRequired[field] {
			result.Compatible = false
			result.BreakingChanges = append(result.BreakingChanges, fmt.Sprintf("New required field '%s' was added", field))
		}
	}

	// Check properties
	oldProps := getProperties(oldSchema)
	newProps := getProperties(newSchema)

	// Check for removed properties (breaking if was required)
	for propName, propSchema := range oldProps {
		if _, exists := newProps[propName]; !exists {
			if oldRequired[propName] {
				result.Compatible = false
				result.BreakingChanges = append(result.BreakingChanges, fmt.Sprintf("Required property '%s' was removed", propName))
			} else {
				result.NonBreakingChanges = append(result.NonBreakingChanges, fmt.Sprintf("Optional property '%s' was removed", propName))
			}
		} else {
			// Check for type changes (breaking)
			oldType := getType(propSchema)
			newType := getType(newProps[propName])
			if oldType != "" && newType != "" && oldType != newType {
				result.Compatible = false
				result.BreakingChanges = append(result.BreakingChanges, fmt.Sprintf("Property '%s' type changed from %s to %s", propName, oldType, newType))
			}

			// Check for constraint tightening (breaking)
			if isConstraintTightened(propSchema, newProps[propName]) {
				result.Compatible = false
				result.BreakingChanges = append(result.BreakingChanges, fmt.Sprintf("Property '%s' constraints were tightened", propName))
			}

			// Check for constraint relaxation (non-breaking)
			if isConstraintRelaxed(propSchema, newProps[propName]) {
				result.NonBreakingChanges = append(result.NonBreakingChanges, fmt.Sprintf("Property '%s' constraints were relaxed", propName))
			}
		}
	}

	// Check for new optional properties (non-breaking)
	for propName := range newProps {
		if _, exists := oldProps[propName]; !exists {
			if !newRequired[propName] {
				result.NonBreakingChanges = append(result.NonBreakingChanges, fmt.Sprintf("New optional property '%s' was added", propName))
			}
		}
	}

	// Check enum values
	oldEnum := getEnumValues(oldSchema)
	newEnum := getEnumValues(newSchema)
	if len(oldEnum) > 0 || len(newEnum) > 0 {
		// Check for removed enum values (breaking)
		for _, val := range oldEnum {
			if !contains(newEnum, val) {
				result.Compatible = false
				result.BreakingChanges = append(result.BreakingChanges, fmt.Sprintf("Enum value '%v' was removed", val))
			}
		}
		// Check for new enum values (non-breaking)
		for _, val := range newEnum {
			if !contains(oldEnum, val) {
				result.NonBreakingChanges = append(result.NonBreakingChanges, fmt.Sprintf("New enum value '%v' was added", val))
			}
		}
	}

	if !result.Compatible {
		result.Reason = fmt.Sprintf("Found %d breaking changes", len(result.BreakingChanges))
	} else if len(result.NonBreakingChanges) > 0 {
		result.Reason = fmt.Sprintf("Compatible with %d non-breaking changes", len(result.NonBreakingChanges))
	} else {
		result.Reason = "Fully compatible"
	}

	return result
}

func getRequiredFields(schema map[string]interface{}) map[string]bool {
	required := make(map[string]bool)
	if req, ok := schema["required"].([]interface{}); ok {
		for _, field := range req {
			if fieldStr, ok := field.(string); ok {
				required[fieldStr] = true
			}
		}
	}
	return required
}

func getProperties(schema map[string]interface{}) map[string]interface{} {
	props := make(map[string]interface{})
	if propsMap, ok := schema["properties"].(map[string]interface{}); ok {
		return propsMap
	}
	return props
}

func getType(propSchema interface{}) string {
	if propMap, ok := propSchema.(map[string]interface{}); ok {
		if typeVal, ok := propMap["type"].(string); ok {
			return typeVal
		}
	}
	return ""
}

func getEnumValues(schema map[string]interface{}) []interface{} {
	if enum, ok := schema["enum"].([]interface{}); ok {
		return enum
	}
	return []interface{}{}
}

func isConstraintTightened(oldSchema, newSchema interface{}) bool {
	oldMap, oldOk := oldSchema.(map[string]interface{})
	newMap, newOk := newSchema.(map[string]interface{})
	if !oldOk || !newOk {
		return false
	}

	// Check minimum
	if oldMin, oldOk := getNumber(oldMap, "minimum"); oldOk {
		if newMin, newOk := getNumber(newMap, "minimum"); newOk {
			if newMin > oldMin {
				return true
			}
		}
	}

	// Check maximum
	if oldMax, oldOk := getNumber(oldMap, "maximum"); oldOk {
		if newMax, newOk := getNumber(newMap, "maximum"); newOk {
			if newMax < oldMax {
				return true
			}
		}
	}

	return false
}

func isConstraintRelaxed(oldSchema, newSchema interface{}) bool {
	oldMap, oldOk := oldSchema.(map[string]interface{})
	newMap, newOk := newSchema.(map[string]interface{})
	if !oldOk || !newOk {
		return false
	}

	// Check minimum
	if oldMin, oldOk := getNumber(oldMap, "minimum"); oldOk {
		if newMin, newOk := getNumber(newMap, "minimum"); newOk {
			if newMin < oldMin {
				return true
			}
		}
	}

	// Check maximum
	if oldMax, oldOk := getNumber(oldMap, "maximum"); oldOk {
		if newMax, newOk := getNumber(newMap, "maximum"); newOk {
			if newMax > oldMax {
				return true
			}
		}
	}

	return false
}

func getNumber(m map[string]interface{}, key string) (float64, bool) {
	if val, ok := m[key]; ok {
		switch v := val.(type) {
		case float64:
			return v, true
		case int:
			return float64(v), true
		case int64:
			return float64(v), true
		}
	}
	return 0, false
}

func contains(slice []interface{}, item interface{}) bool {
	for _, v := range slice {
		if reflect.DeepEqual(v, item) {
			return true
		}
	}
	return false
}

