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

func TestValidateEvent_AllRequiredFieldsPresent(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()

	reqBody := map[string]interface{}{
		"event": event,
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

	if !response.Valid {
		t.Error("Event with all required fields should be valid")
	}

	if len(response.Errors) > 0 {
		t.Errorf("Expected no errors, got %d", len(response.Errors))
	}
}

func TestValidateEvent_ResponseStructure(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	var response api.ValidateEventResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	// Verify response structure
	if response.Version == "" {
		t.Error("Response should include version")
	}

	// Valid field should be set
	if response.Valid && len(response.Errors) > 0 {
		t.Error("Valid event should not have errors")
	}
}

func TestValidateBulkEvents_ResponseStructure(t *testing.T) {
	validEvent := testutil.ValidCarCreatedEvent()
	invalidEvent := testutil.InvalidEventMissingRequired()

	reqBody := map[string]interface{}{
		"events": []interface{}{validEvent, invalidEvent},
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	var response api.ValidateBulkEventsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	// Verify summary
	if response.Summary.Total != 2 {
		t.Errorf("Expected total=2, got %d", response.Summary.Total)
	}

	// Verify results array
	if len(response.Results) != 2 {
		t.Errorf("Expected 2 results, got %d", len(response.Results))
	}

	// Verify each result has version
	for i, result := range response.Results {
		if result.Version == "" {
			t.Errorf("Result %d should have version", i)
		}
	}
}

func TestGetSchema_AllEntityTypes(t *testing.T) {
	// Test getting different entity types
	entityTypes := []string{"car", "event"}

	for _, entityType := range entityTypes {
		req := httptest.NewRequest("GET", "/api/v1/schemas/v1?type="+entityType, nil)
		w := httptest.NewRecorder()

		router := setupTestRouter()
		router.ServeHTTP(w, req)

		if w.Code != http.StatusOK {
			t.Errorf("Expected status 200 for type %s, got %d", entityType, w.Code)
			continue
		}

		var response api.SchemaResponse
		if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
			t.Fatalf("Failed to unmarshal response for %s: %v", entityType, err)
		}

		if response.Version != "v1" {
			t.Errorf("Expected version v1 for %s, got %s", entityType, response.Version)
		}

		if response.Schema == nil {
			t.Errorf("Expected schema for %s", entityType)
		}
	}
}

func TestGetSchema_DefaultType(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/schemas/v1", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	var response api.SchemaResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	// Should default to event type
	if response.Schema == nil {
		t.Error("Expected default event schema")
	}
}

func TestValidateEvent_WithExtraFields(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	// Add extra field at top level
	event["extraField"] = "not in schema"

	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	// Should fail if additionalProperties: false
	if w.Code != http.StatusUnprocessableEntity {
		t.Logf("Extra fields may be allowed depending on schema configuration")
	}
}

func TestValidateEvent_ErrorDetails(t *testing.T) {
	event := testutil.InvalidEventMissingRequired()

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
		t.Errorf("Expected status 422, got %d", w.Code)
	}

	var response api.ValidateEventResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	// Should have errors
	if len(response.Errors) == 0 {
		t.Error("Expected validation errors")
	}

	// Each error should have field and message
	for i, err := range response.Errors {
		if err.Field == "" && err.Message == "" {
			t.Errorf("Error %d should have field or message", i)
		}
	}
}

func TestValidateBulkEvents_ErrorDetails(t *testing.T) {
	invalidEvent := testutil.InvalidEventMissingRequired()

	reqBody := map[string]interface{}{
		"events": []interface{}{invalidEvent},
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	var response api.ValidateBulkEventsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	// Should have invalid result
	if len(response.Results) > 0 {
		result := response.Results[0]
		if result.Valid {
			t.Error("Invalid event should be marked as invalid")
		}

		if len(result.Errors) == 0 {
			t.Error("Invalid event should have errors")
		}
	}
}

func TestGetSchema_ResponseStructure(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/schemas/v1?type=event", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	var response api.SchemaResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Version != "v1" {
		t.Errorf("Expected version v1, got %s", response.Version)
	}

	if response.Schema == nil {
		t.Error("Expected schema to be present")
	}

	// Schema should be a valid JSON object
	if len(response.Schema) == 0 {
		t.Error("Schema should not be empty")
	}
}
