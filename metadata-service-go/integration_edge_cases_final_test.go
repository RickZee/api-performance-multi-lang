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

func TestValidateEvent_EmptyEventObject(t *testing.T) {
	reqBody := map[string]interface{}{
		"event": map[string]interface{}{},
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422 for empty event, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_NullEvent(t *testing.T) {
	reqBody := map[string]interface{}{
		"event": nil,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should handle null event gracefully
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle null event gracefully, got 500. Body: %s", w.Body.String())
	}
}

func TestValidateEvent_EventAsString(t *testing.T) {
	reqBody := map[string]interface{}{
		"event": "not an object",
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422 for string event, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateBulkEvents_NullInArray(t *testing.T) {
	validEvent := testutil.ValidCarCreatedEvent()

	reqBody := map[string]interface{}{
		"events": []interface{}{validEvent, nil, validEvent},
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should handle null in array
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle null in array, got 500. Body: %s", w.Body.String())
	}

	var response api.ValidateBulkEventsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err == nil {
		if response.Summary.Total != 3 {
			t.Errorf("Expected 3 total events, got %d", response.Summary.Total)
		}
	}
}

func TestValidateBulkEvents_NonArrayEvents(t *testing.T) {
	reqBody := map[string]interface{}{
		"events": "not an array",
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should handle non-array gracefully
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle non-array events, got 500. Body: %s", w.Body.String())
	}
}

func TestGetSchema_InvalidQueryParam(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/schemas/v1?type=event&invalid=param", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should ignore invalid query params
	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_WithVersionAndExtraFields(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()

	reqBody := map[string]interface{}{
		"event":   event,
		"version": "v1",
		"extra":   "field",
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should ignore extra fields in request
	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_MaximumLengthString(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Create string at maximum length if constraint exists
	maxLengthString := make([]byte, 100)
	for i := range maxLengthString {
		maxLengthString[i] = 'A'
	}

	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["make"] = string(maxLengthString)
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

	// Should handle maximum length string
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle maximum length string, got 500")
	}
}

func TestValidateEvent_MinimumLengthString(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Create string at minimum length
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["make"] = "A" // Single character
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

	// Should handle minimum length string
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle minimum length string, got 500")
	}
}

func TestValidateEvent_ExactMinimumValue(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set value to exact minimum
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["year"] = 1900 // Minimum value
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

	// Should accept exact minimum
	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200 for exact minimum, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_ExactMaximumValue(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set value to exact maximum
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["year"] = 2030 // Maximum value
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

	// Should accept exact maximum
	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200 for exact maximum, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_OneBelowMinimum(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set value one below minimum
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["year"] = 1899 // One below minimum (1900)
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
		t.Errorf("Expected status 422 for one below minimum, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_OneAboveMaximum(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set value one above maximum
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["year"] = 2031 // One above maximum (2030)
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
		t.Errorf("Expected status 422 for one above maximum, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateBulkEvents_AllNull(t *testing.T) {
	reqBody := map[string]interface{}{
		"events": []interface{}{nil, nil, nil},
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should handle all null events
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle all null events, got 500. Body: %s", w.Body.String())
	}

	var response api.ValidateBulkEventsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err == nil {
		if response.Summary.Total != 3 {
			t.Errorf("Expected 3 total events, got %d", response.Summary.Total)
		}
	}
}

func TestGetSchema_CaseInsensitiveType(t *testing.T) {
	// Test if type parameter is case-sensitive
	testCases := []string{"EVENT", "Event", "event", "CaR", "CAR", "car"}

	for _, testType := range testCases {
		req := httptest.NewRequest("GET", "/api/v1/schemas/v1?type="+testType, nil)
		w := httptest.NewRecorder()

		router := setupTestRouter()
		router.ServeHTTP(w, req)

		// Should handle case variations
		if w.Code == http.StatusInternalServerError {
			t.Logf("Type parameter %s may be case-sensitive", testType)
		}
	}
}

func TestValidateEvent_WhitespaceOnlyStrings(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Set string fields to whitespace only
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["make"] = "   "
			entity["model"] = "\t\n"
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

	// Should handle whitespace-only strings
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle whitespace-only strings, got 500")
	}
}
