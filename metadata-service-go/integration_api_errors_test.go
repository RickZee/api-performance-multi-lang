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

func TestValidateEvent_InvalidJSON(t *testing.T) {
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBufferString("invalid json"))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("Expected status 400, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_MissingEventField(t *testing.T) {
	reqBody := map[string]interface{}{
		"version": "v1",
		// Missing "event" field
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should still attempt validation but fail because event is nil/empty
	if w.Code != http.StatusInternalServerError && w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 500 or 422, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_WrongContentType(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	// Missing Content-Type header
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should still work (our router doesn't strictly enforce Content-Type)
	// But we verify it doesn't crash
	if w.Code == http.StatusInternalServerError {
		t.Errorf("Should handle missing Content-Type gracefully, got %d", w.Code)
	}
}

func TestValidateEvent_WrongHTTPMethod(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	
	// Test GET method
	req := httptest.NewRequest("GET", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected status 405, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateBulkEvents_EmptyArray(t *testing.T) {
	reqBody := map[string]interface{}{
		"events": []interface{}{},
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200 for empty array, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.ValidateBulkEventsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Summary.Total != 0 {
		t.Errorf("Expected total=0, got %d", response.Summary.Total)
	}
}

func TestValidateBulkEvents_InvalidJSON(t *testing.T) {
	req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBufferString("invalid json"))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("Expected status 400, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestGetSchema_InvalidVersionFormat(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/schemas/v999", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// v999 doesn't exist, should return 404
	if w.Code != http.StatusNotFound {
		t.Errorf("Expected status 404 for non-existent version, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestGetSchema_MissingTypeParameter(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/schemas/v1", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200 (should default to event type), got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.SchemaResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Schema == nil {
		t.Error("Expected schema to be present (defaults to event)")
	}
}

func TestGetVersions_ServiceError(t *testing.T) {
	// This test would require mocking cache to return error
	// For now, we test the happy path is covered
	// This is a placeholder for when we add mocking
}

func TestValidateEvent_ExplicitVersion(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()

	reqBody := map[string]interface{}{
		"event":   event,
		"version": "v1",
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.ValidateEventResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Version != "v1" {
		t.Errorf("Expected version=v1, got %s", response.Version)
	}
}

func TestValidateEvent_InvalidVersion(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()

	reqBody := map[string]interface{}{
		"event":   event,
		"version": "v999",
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusInternalServerError {
		t.Errorf("Expected status 500 (version not found), got %d. Body: %s", w.Code, w.Body.String())
	}
}

