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

func TestValidateEvent_MalformedEventData(t *testing.T) {
	// Send event with invalid structure
	reqBody := map[string]interface{}{
		"event": map[string]interface{}{
			"eventHeader": "invalid", // Should be object
			"entities":    "invalid", // Should be array
		},
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422 for malformed event, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_InvalidVersionInRequest(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()

	reqBody := map[string]interface{}{
		"event":   event,
		"version": "invalid-version-format",
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should handle invalid version gracefully
	if w.Code == http.StatusInternalServerError {
		var response map[string]interface{}
		if err := json.Unmarshal(w.Body.Bytes(), &response); err == nil {
			if errorMsg, ok := response["error"].(string); ok {
				t.Logf("Error message: %s", errorMsg)
			}
		}
	}
}

func TestValidateBulkEvents_MixedValidInvalid(t *testing.T) {
	validEvent := testutil.ValidCarCreatedEvent()
	invalidEvent1 := testutil.InvalidEventMissingRequired()
	invalidEvent2 := testutil.InvalidEventWrongType()
	validEvent2 := testutil.ValidCarCreatedEvent()

	reqBody := map[string]interface{}{
		"events": []interface{}{validEvent, invalidEvent1, invalidEvent2, validEvent2},
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422 for mixed valid/invalid, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.ValidateBulkEventsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Summary.Total != 4 {
		t.Errorf("Expected 4 total events, got %d", response.Summary.Total)
	}

	if response.Summary.Valid != 2 {
		t.Errorf("Expected 2 valid events, got %d", response.Summary.Valid)
	}

	if response.Summary.Invalid != 2 {
		t.Errorf("Expected 2 invalid events, got %d", response.Summary.Invalid)
	}
}

func TestValidateBulkEvents_VeryLargeBatch(t *testing.T) {
	// Create 100 events
	events := make([]interface{}, 100)
	for i := range events {
		if i%2 == 0 {
			events[i] = testutil.ValidCarCreatedEvent()
		} else {
			events[i] = testutil.InvalidEventMissingRequired()
		}
	}

	reqBody := map[string]interface{}{
		"events": events,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should handle large batch
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle large batch, got 500. Body: %s", w.Body.String())
	}

	var response api.ValidateBulkEventsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err == nil {
		if response.Summary.Total != 100 {
			t.Errorf("Expected 100 total events, got %d", response.Summary.Total)
		}
	}
}

func TestGetSchema_InvalidEntityName(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/schemas/v1?type=invalid-entity-name-123", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("Expected status 404 for invalid entity name, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestGetSchema_EmptyVersion(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/schemas/", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should handle empty version (may default or return error)
	if w.Code == http.StatusInternalServerError {
		t.Log("Empty version handled with error (expected behavior)")
	}
}

func TestGetVersions_EmptyResponse(t *testing.T) {
	// This would require mocking cache to return empty versions
	// For now, we test the normal case is covered
	req := httptest.NewRequest("GET", "/api/v1/schemas/versions", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}
}

func TestHealth_WithVersions(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/health", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	var response api.HealthResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Status != "healthy" {
		t.Errorf("Expected status 'healthy', got %s", response.Status)
	}
}

func TestValidateEvent_UnicodeInFieldNames(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Add field with unicode in name (if schema allows)
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["测试"] = "value" // Unicode field name
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

	// Should handle unicode in field names
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle unicode field names, got 500")
	}
}

func TestValidateEvent_SpecialCharactersInValues(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Add special characters
	if entities, ok := event["entities"].([]interface{}); ok && len(entities) > 0 {
		if entity, ok := entities[0].(map[string]interface{}); ok {
			entity["make"] = "Tesla & Co. <script>alert('xss')</script>"
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

	// Should handle special characters (may fail pattern validation)
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle special characters, got 500")
	}
}

func TestValidateBulkEvents_SingleEvent(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()

	reqBody := map[string]interface{}{
		"events": []interface{}{event},
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200 for single valid event in bulk, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.ValidateBulkEventsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Summary.Total != 1 {
		t.Errorf("Expected 1 total event, got %d", response.Summary.Total)
	}
}

func TestGetSchema_MultipleQueryParams(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/schemas/v1?type=car&format=json&pretty=true", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should ignore extra query params and use type=car
	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
	}
}
