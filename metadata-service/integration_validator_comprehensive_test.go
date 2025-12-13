package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"metadata-service/internal/api"
	"metadata-service/internal/testutil"
)

func TestValidateEvent_ArrayItemValidation(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Add invalid entity to array
	if entities, ok := event["entities"].([]interface{}); ok {
		entities = append(entities, map[string]interface{}{
			"id": "INVALID", // Missing required fields
		})
		event["entities"] = entities
	}

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422 for invalid array item, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_DeeplyNestedObject(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Add deeply nested structure
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["nested"] = map[string]interface{}{
				"level1": map[string]interface{}{
					"level2": map[string]interface{}{
						"level3": map[string]interface{}{
							"level4": map[string]interface{}{
								"value": "deep",
							},
						},
					},
				},
			}
		}
	}

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should handle deeply nested structures
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle deeply nested objects, got 500. Body: %s", w.Body.String())
	}
}

func TestValidateEvent_InvalidArrayType(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set entities to wrong type
	event["entities"] = "not-an-array"

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422 for wrong array type, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_InvalidObjectType(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set eventHeader to wrong type
	event["eventHeader"] = "not-an-object"

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422 for wrong object type, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_MultipleValidationErrors(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Introduce multiple errors
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["year"] = "not-a-number" // Type error
			entity["vin"] = "INVALID"       // Pattern error
			delete(entity, "make")          // Missing required
		}
	}

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422 for multiple errors, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.ValidateEventResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err == nil {
		if len(response.Errors) < 2 {
			t.Errorf("Expected multiple errors, got %d", len(response.Errors))
		}
	}
}

func TestValidateEvent_ZeroValue(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set numeric field to zero
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["year"] = 0
			entity["mileage"] = 0
		}
	}

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Zero values should be valid if within constraints
	if w.Code != http.StatusOK && w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 200 or 422, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_UnicodeCharacters(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Add unicode characters
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["make"] = "Tesla 🚗"
			entity["model"] = "Model S 中文"
		}
	}

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should handle unicode characters
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle unicode characters, got 500. Body: %s", w.Body.String())
	}
}

func TestValidateEvent_ExtremelyLongString(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Create very long string
	longString := make([]byte, 10000)
	for i := range longString {
		longString[i] = 'A'
	}

	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["make"] = string(longString)
		}
	}

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should handle long strings (may fail validation if maxLength constraint exists)
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle long strings, got 500. Body: %s", w.Body.String())
	}
}

func TestValidateEvent_NegativeNumber(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set negative number
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["year"] = -1
			entity["mileage"] = -100
		}
	}

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should fail validation if minimum constraint exists
	if w.Code != http.StatusOK && w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 200 or 422, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_ExceedMaximum(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set value exceeding maximum
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["year"] = 3000 // Exceeds maximum (2030)
		}
	}

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422 for exceeding maximum, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_BelowMinimum(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set value below minimum
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["year"] = 1800 // Below minimum (1900)
		}
	}

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422 for below minimum, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_InvalidBoolean(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Add boolean field with wrong type
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["isNew"] = "true" // Should be boolean, not string
		}
	}

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// May pass if schema doesn't have isNew field, or fail if it does
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle type mismatch gracefully, got 500. Body: %s", w.Body.String())
	}
}
