package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"metadata-service/internal/api"

	"github.com/gin-gonic/gin"
)

func TestFilterE2E_CreateGenerateApproveDeploy(t *testing.T) {
	// Setup router
	router := gin.New()
	router.Use(gin.Recovery())

	v1 := router.Group("/api/v1")
	{
		v1.POST("/filters", testHandlers.CreateFilter)
		v1.GET("/filters", testHandlers.ListFilters)
		v1.GET("/filters/:id", testHandlers.GetFilter)
		v1.POST("/filters/:id/generate", testHandlers.GenerateSQL)
		v1.POST("/filters/:id/approve", testHandlers.ApproveFilter)
		v1.POST("/filters/:id/deploy", testHandlers.DeployFilter)
		v1.GET("/filters/:id/status", testHandlers.GetFilterStatus)
	}

	// Step 1: Create a filter
	t.Run("CreateFilter", func(t *testing.T) {
		createReq := api.CreateFilterRequest{
			Name:        "Service Events for Dealer 001",
			Description: "Routes service events from Tesla Service Center SF to dedicated topic",
			ConsumerID:  "dealer-001-service-consumer",
			OutputTopic: "filtered-service-events-dealer-001",
			Conditions: []api.FilterCondition{
				{
					Field:           "event_type",
					Operator:        "equals",
					Value:           "CarServiceDone",
					ValueType:       "string",
					LogicalOperator: "AND",
				},
				{
					Field:           "header_data.dealerId",
					Operator:        "equals",
					Value:           "DEALER-001",
					ValueType:       "string",
					LogicalOperator: "AND",
				},
			},
			Enabled:        true,
			ConditionLogic: "AND",
		}

		reqBody, _ := json.Marshal(createReq)
		req := httptest.NewRequest("POST", "/api/v1/filters?version=v1", bytes.NewBuffer(reqBody))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		if w.Code != http.StatusCreated {
			t.Errorf("Expected status 201, got %d. Body: %s", w.Code, w.Body.String())
			return
		}

		var response api.FilterResponse
		if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
			t.Fatalf("Failed to unmarshal response: %v", err)
		}

		if response.ID == "" {
			t.Error("Expected filter ID to be set")
		}

		if response.Status != "pending_approval" {
			t.Errorf("Expected status 'pending_approval', got '%s'", response.Status)
		}

		// Store filter ID for subsequent tests
		filterID := response.ID

		// Step 2: Generate SQL
		t.Run("GenerateSQL", func(t *testing.T) {
			req := httptest.NewRequest("POST", fmt.Sprintf("/api/v1/filters/%s/generate?version=v1", filterID), nil)
			w := httptest.NewRecorder()

			router.ServeHTTP(w, req)

			if w.Code != http.StatusOK {
				t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
				return
			}

			var sqlResponse api.GenerateSQLResponse
			if err := json.Unmarshal(w.Body.Bytes(), &sqlResponse); err != nil {
				t.Fatalf("Failed to unmarshal response: %v", err)
			}

			if !sqlResponse.Valid {
				t.Errorf("Expected SQL to be valid, but got errors: %v", sqlResponse.ValidationErrors)
			}

			if sqlResponse.SQL == "" {
				t.Error("Expected SQL to be generated")
			}

			if len(sqlResponse.Statements) < 2 {
				t.Errorf("Expected at least 2 SQL statements (CREATE TABLE and INSERT), got %d", len(sqlResponse.Statements))
			}

			// Verify SQL contains expected elements
			sql := sqlResponse.SQL
			if !contains(sql, "CREATE TABLE") {
				t.Error("Expected SQL to contain CREATE TABLE statement")
			}
			if !contains(sql, "INSERT INTO") {
				t.Error("Expected SQL to contain INSERT INTO statement")
			}
			if !contains(sql, "filtered-service-events-dealer-001") {
				t.Error("Expected SQL to contain output topic name")
			}
			if !contains(sql, "CarServiceDone") {
				t.Error("Expected SQL to contain event type filter")
			}
		})

		// Step 3: Approve filter
		t.Run("ApproveFilter", func(t *testing.T) {
			approveReq := api.ApproveFilterRequest{
				ApprovedBy: "test-user",
			}

			reqBody, _ := json.Marshal(approveReq)
			req := httptest.NewRequest("POST", fmt.Sprintf("/api/v1/filters/%s/approve?version=v1", filterID), bytes.NewBuffer(reqBody))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()

			router.ServeHTTP(w, req)

			if w.Code != http.StatusOK {
				t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
				return
			}

			var response api.FilterResponse
			if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
				t.Fatalf("Failed to unmarshal response: %v", err)
			}

			if response.Status != "approved" {
				t.Errorf("Expected status 'approved', got '%s'", response.Status)
			}

			if response.ApprovedBy != "test-user" {
				t.Errorf("Expected approvedBy 'test-user', got '%s'", response.ApprovedBy)
			}

			if response.ApprovedAt == nil {
				t.Error("Expected approvedAt to be set")
			}
		})

		// Step 4: Deploy filter (will fail if Confluent Cloud not configured, but should test the flow)
		t.Run("DeployFilter", func(t *testing.T) {
			// Check if Confluent Cloud is configured
			apiKey := os.Getenv("CONFLUENT_CLOUD_API_KEY")
			apiSecret := os.Getenv("CONFLUENT_CLOUD_API_SECRET")
			computePoolID := os.Getenv("CONFLUENT_FLINK_COMPUTE_POOL_ID")

			if apiKey == "" || apiSecret == "" || computePoolID == "" {
				t.Skip("Skipping deployment test - Confluent Cloud credentials not configured")
				return
			}

			deployReq := api.DeployFilterRequest{
				Force: false,
			}

			reqBody, _ := json.Marshal(deployReq)
			req := httptest.NewRequest("POST", fmt.Sprintf("/api/v1/filters/%s/deploy?version=v1", filterID), bytes.NewBuffer(reqBody))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()

			router.ServeHTTP(w, req)

			// Deployment might succeed or fail depending on Confluent Cloud setup
			// We just verify the API responds correctly
			if w.Code != http.StatusOK && w.Code != http.StatusInternalServerError {
				t.Errorf("Expected status 200 or 500, got %d. Body: %s", w.Code, w.Body.String())
				return
			}

			if w.Code == http.StatusOK {
				var response api.DeployFilterResponse
				if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
					t.Fatalf("Failed to unmarshal response: %v", err)
				}

				if response.Status != "deployed" {
					t.Errorf("Expected status 'deployed', got '%s'", response.Status)
				}

				if len(response.FlinkStatementIDs) == 0 {
					t.Error("Expected Flink statement IDs to be returned")
				}
			}
		})

		// Step 5: Get filter status
		t.Run("GetFilterStatus", func(t *testing.T) {
			req := httptest.NewRequest("GET", fmt.Sprintf("/api/v1/filters/%s/status?version=v1", filterID), nil)
			w := httptest.NewRecorder()

			router.ServeHTTP(w, req)

			if w.Code != http.StatusOK {
				t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
				return
			}

			var response api.FilterStatusResponse
			if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
				t.Fatalf("Failed to unmarshal response: %v", err)
			}

			if response.FilterID != filterID {
				t.Errorf("Expected filterID '%s', got '%s'", filterID, response.FilterID)
			}
		})

		// Step 6: List filters
		t.Run("ListFilters", func(t *testing.T) {
			req := httptest.NewRequest("GET", "/api/v1/filters?version=v1", nil)
			w := httptest.NewRecorder()

			router.ServeHTTP(w, req)

			if w.Code != http.StatusOK {
				t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
				return
			}

			var response api.ListFiltersResponse
			if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
				t.Fatalf("Failed to unmarshal response: %v", err)
			}

			if response.Total == 0 {
				t.Error("Expected at least one filter")
			}

			// Verify our filter is in the list
			found := false
			for _, f := range response.Filters {
				if f.ID == filterID {
					found = true
					break
				}
			}

			if !found {
				t.Error("Expected to find created filter in list")
			}
		})
	})
}

func TestFilterE2E_UpdateDelete(t *testing.T) {
	router := gin.New()
	router.Use(gin.Recovery())

	v1 := router.Group("/api/v1")
	{
		v1.POST("/filters", testHandlers.CreateFilter)
		v1.PUT("/filters/:id", testHandlers.UpdateFilter)
		v1.DELETE("/filters/:id", testHandlers.DeleteFilter)
		v1.GET("/filters/:id", testHandlers.GetFilter)
	}

	// Create a filter first
	createReq := api.CreateFilterRequest{
		Name:        "Test Filter for Update",
		Description: "Test description",
		ConsumerID:  "test-consumer",
		OutputTopic: "test-topic",
		Conditions: []api.FilterCondition{
			{
				Field:    "event_type",
				Operator: "equals",
				Value:    "CarCreated",
			},
		},
		Enabled: true,
	}

	reqBody, _ := json.Marshal(createReq)
	req := httptest.NewRequest("POST", "/api/v1/filters?version=v1", bytes.NewBuffer(reqBody))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("Failed to create filter: %d, %s", w.Code, w.Body.String())
	}

	var createResponse api.FilterResponse
	json.Unmarshal(w.Body.Bytes(), &createResponse)
	filterID := createResponse.ID

	// Test update
	t.Run("UpdateFilter", func(t *testing.T) {
		updateReq := api.UpdateFilterRequest{
			Name:        "Updated Filter Name",
			Description: "Updated description",
		}

		reqBody, _ := json.Marshal(updateReq)
		req := httptest.NewRequest("PUT", fmt.Sprintf("/api/v1/filters/%s?version=v1", filterID), bytes.NewBuffer(reqBody))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		if w.Code != http.StatusOK {
			t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
			return
		}

		var response api.FilterResponse
		if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
			t.Fatalf("Failed to unmarshal response: %v", err)
		}

		if response.Name != "Updated Filter Name" {
			t.Errorf("Expected name 'Updated Filter Name', got '%s'", response.Name)
		}

		if response.Version <= createResponse.Version {
			t.Error("Expected version to be incremented")
		}
	})

	// Test delete
	t.Run("DeleteFilter", func(t *testing.T) {
		req := httptest.NewRequest("DELETE", fmt.Sprintf("/api/v1/filters/%s?version=v1", filterID), nil)
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		if w.Code != http.StatusNoContent {
			t.Errorf("Expected status 204, got %d. Body: %s", w.Code, w.Body.String())
			return
		}

		// Verify filter is deleted
		req = httptest.NewRequest("GET", fmt.Sprintf("/api/v1/filters/%s?version=v1", filterID), nil)
		w = httptest.NewRecorder()
		router.ServeHTTP(w, req)

		if w.Code != http.StatusNotFound {
			t.Errorf("Expected status 404 after deletion, got %d", w.Code)
		}
	})
}

func TestFilterE2E_ValidateSQL(t *testing.T) {
	router := gin.New()
	router.Use(gin.Recovery())

	v1 := router.Group("/api/v1")
	{
		v1.POST("/filters/:id/validate", testHandlers.ValidateSQL)
	}

	validSQL := `
CREATE TABLE test_table (
    id STRING
) WITH (
    'connector' = 'confluent'
);

INSERT INTO test_table
SELECT id FROM source_table;
`

	reqBody, _ := json.Marshal(api.ValidateSQLRequest{SQL: validSQL})
	req := httptest.NewRequest("POST", "/api/v1/filters/test-id/validate", bytes.NewBuffer(reqBody))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
		return
	}

	var response api.ValidateSQLResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if !response.Valid {
		t.Errorf("Expected SQL to be valid, got errors: %v", response.Errors)
	}
}

// Helper function
func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr ||
		(len(s) > len(substr) && containsSubstring(s, substr)))
}

func containsSubstring(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
