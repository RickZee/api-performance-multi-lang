package testutil

import (
	"encoding/json"
	"time"
)

// ValidCarCreatedEvent returns a valid CarCreated event for testing
func ValidCarCreatedEvent() map[string]interface{} {
	return map[string]interface{}{
		"eventHeader": map[string]interface{}{
			"uuid":        "550e8400-e29b-41d4-a716-446655440000",
			"eventName":   "Car Created",
			"eventType":   "CarCreated",
			"createdDate": time.Now().UTC().Format(time.RFC3339),
			"savedDate":   time.Now().UTC().Format(time.RFC3339),
		},
		"entities": []interface{}{
			map[string]interface{}{
				"entityHeader": map[string]interface{}{
					"entityId":   "CAR-001",
					"entityType": "Car",
					"createdAt":  time.Now().UTC().Format(time.RFC3339),
					"updatedAt":  time.Now().UTC().Format(time.RFC3339),
				},
				"id":      "CAR-001",
				"vin":     "5TDJKRFH4LS123456",
				"make":    "Tesla",
				"model":   "Model S",
				"year":    2024,
				"color":   "Red",
				"mileage": 0,
			},
		},
	}
}

// InvalidEventMissingRequired returns an event missing required fields
func InvalidEventMissingRequired() map[string]interface{} {
	return map[string]interface{}{
		"eventHeader": map[string]interface{}{
			"uuid": "550e8400-e29b-41d4-a716-446655440000",
			// Missing required fields
		},
		"entities": []interface{}{},
	}
}

// InvalidEventWrongType returns an event with wrong field types
func InvalidEventWrongType() map[string]interface{} {
	return map[string]interface{}{
		"eventHeader": map[string]interface{}{
			"uuid":        "550e8400-e29b-41d4-a716-446655440000",
			"eventName":   "Car Created",
			"eventType":   "CarCreated",
			"createdDate": time.Now().UTC().Format(time.RFC3339),
			"savedDate":   time.Now().UTC().Format(time.RFC3339),
		},
		"entities": []interface{}{
			map[string]interface{}{
				"entityHeader": map[string]interface{}{
					"entityId":   "CAR-001",
					"entityType": "Car",
					"createdAt":  time.Now().UTC().Format(time.RFC3339),
					"updatedAt":  time.Now().UTC().Format(time.RFC3339),
				},
				"id":      "CAR-001",
				"vin":     "5TDJKRFH4LS123456",
				"make":    "Tesla",
				"model":   "Model S",
				"year":    "2024", // Wrong type - should be integer
				"color":   "Red",
				"mileage": 0,
			},
		},
	}
}

// InvalidEventInvalidPattern returns an event with invalid pattern
func InvalidEventInvalidPattern() map[string]interface{} {
	return map[string]interface{}{
		"eventHeader": map[string]interface{}{
			"uuid":        "550e8400-e29b-41d4-a716-446655440000",
			"eventName":   "Car Created",
			"eventType":   "CarCreated",
			"createdDate": time.Now().UTC().Format(time.RFC3339),
			"savedDate":   time.Now().UTC().Format(time.RFC3339),
		},
		"entities": []interface{}{
			map[string]interface{}{
				"entityHeader": map[string]interface{}{
					"entityId":   "CAR-001",
					"entityType": "Car",
					"createdAt":  time.Now().UTC().Format(time.RFC3339),
					"updatedAt":  time.Now().UTC().Format(time.RFC3339),
				},
				"id":      "CAR-001",
				"vin":     "INVALID-VIN", // Invalid VIN pattern
				"make":    "Tesla",
				"model":   "Model S",
				"year":    2024,
				"color":   "Red",
				"mileage": 0,
			},
		},
	}
}

// EventToJSON converts an event map to JSON bytes
func EventToJSON(event map[string]interface{}) ([]byte, error) {
	return json.Marshal(event)
}

