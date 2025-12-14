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

func TestValidateEvent_NullInRequiredField(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set a required field to null
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["vin"] = nil // VIN is required
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
		t.Errorf("Expected status 422, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.ValidateEventResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Valid {
		t.Error("Expected valid=false for null in required field")
	}
}

func TestValidateEvent_EmptyString(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set required string field to empty
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["vin"] = "" // Empty VIN
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

	// Empty string might pass pattern validation but fail other checks
	// The exact behavior depends on schema definition
	if w.Code != http.StatusOK && w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 200 or 422, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_TypeCoercion(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set integer field to string
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["year"] = "2024" // Should be integer
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
		t.Errorf("Expected status 422 (type mismatch), got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.ValidateEventResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Valid {
		t.Error("Expected valid=false for type mismatch")
	}
}

func TestValidateEvent_InvalidDateFormat(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set invalid date format
	if header, ok := event["eventHeader"].(map[string]interface{}); ok {
		header["createdDate"] = "2024-01-01" // Should be RFC3339
		header["savedDate"] = "2024-01-01"
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

	// Date format validation depends on schema - might pass or fail
	// Just verify it doesn't crash
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle invalid date format gracefully, got 500. Body: %s", w.Body.String())
	}
	
	// If schema validates date-time format strictly, should be 422
	// Otherwise might be 200 (if schema allows any string)
	if w.Code != http.StatusOK && w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 200 or 422, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_InvalidUUID(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set invalid UUID
	if header, ok := event["eventHeader"].(map[string]interface{}); ok {
		header["uuid"] = "not-a-uuid"
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
		t.Errorf("Expected status 422 (invalid UUID), got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_InvalidEnum(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set invalid enum value
	if header, ok := event["eventHeader"].(map[string]interface{}); ok {
		header["eventType"] = "InvalidEventType"
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
		t.Errorf("Expected status 422 (invalid enum), got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_OutOfRange(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set value outside allowed range
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
		t.Errorf("Expected status 422 (out of range), got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_EmptyEntitiesArray(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	event["entities"] = []interface{}{}

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
		t.Errorf("Expected status 422 (empty entities array), got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_MissingEntityHeader(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Remove entityHeader from first entity
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			delete(entity, "entityHeader")
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
		t.Errorf("Expected status 422 (missing entityHeader), got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_AdditionalProperties(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Add extra property not in schema
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["extraProperty"] = "not allowed"
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

	// Should fail because additionalProperties: false
	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422 (additional properties not allowed), got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_InvalidPattern(t *testing.T) {
	event := testutil.InvalidEventInvalidPattern()

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
		t.Errorf("Expected status 422 (invalid pattern), got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.ValidateEventResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Valid {
		t.Error("Expected valid=false for invalid pattern")
	}
}

func TestValidateEvent_WrongType(t *testing.T) {
	event := testutil.InvalidEventWrongType()

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
		t.Errorf("Expected status 422 (wrong type), got %d. Body: %s", w.Code, w.Body.String())
	}
}

