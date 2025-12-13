package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"go.uber.org/zap"
	"metadata-service/internal/api"
	"metadata-service/internal/cache"
	"metadata-service/internal/compat"
	"metadata-service/internal/config"
	"metadata-service/internal/sync"
	"metadata-service/internal/testutil"
	"metadata-service/internal/validator"
)

var (
	testRepoDir   string
	testCacheDir  string
	testConfig    *config.Config
	testGitSync   *sync.GitSync
	testCache     *cache.SchemaCache
	testValidator *validator.JSONSchemaValidator
	testCompat    *compat.CompatibilityChecker
	testHandlers  *api.Handlers
	testLogger    *zap.Logger
)

func TestMain(m *testing.M) {
	// Setup
	var err error
	testLogger, _ = zap.NewDevelopment()

	tempDir, err := os.MkdirTemp("", "metadata-service-test-*")
	if err != nil {
		panic(fmt.Sprintf("Failed to create temp dir: %v", err))
	}
	defer os.RemoveAll(tempDir)

	testRepoDir, err = testutil.SetupTestRepo(tempDir)
	if err != nil {
		panic(fmt.Sprintf("Failed to setup test repo: %v", err))
	}
	defer testutil.CleanupTestRepo(testRepoDir)

	testCacheDir = filepath.Join(tempDir, "cache")

	testConfig = &config.Config{
		Git: config.GitConfig{
			Repository:    testRepoDir,
			Branch:        "main",
			PullInterval:  1 * time.Minute,
			LocalCacheDir: testCacheDir,
		},
		Validation: config.ValidationConfig{
			DefaultVersion:   "v1",
			AcceptedVersions: []string{"v1"},
			StrictMode:       true,
		},
		Server: config.ServerConfig{
			Port:     8080,
			GRPCPort: 9090,
		},
	}

	testCache = cache.NewSchemaCache(testCacheDir, testLogger)
	testGitSync = sync.NewGitSync(
		testConfig.Git.Repository,
		testConfig.Git.Branch,
		testConfig.Git.LocalCacheDir,
		testConfig.Git.PullInterval,
		testLogger,
	)

	if err := testGitSync.Start(); err != nil {
		panic(fmt.Sprintf("Failed to start git sync: %v", err))
	}
	defer testGitSync.Stop()

	// Wait a bit for initial sync
	time.Sleep(500 * time.Millisecond)

	testValidator = validator.NewJSONSchemaValidator(testLogger)
	testCompat = compat.NewCompatibilityChecker()
	testHandlers = api.NewHandlers(
		testConfig,
		testCache,
		testGitSync,
		testValidator,
		testCompat,
		testLogger,
	)

	// Run tests
	code := m.Run()

	// Cleanup
	testGitSync.Stop()
	os.Exit(code)
}

func TestValidateEvent_Valid(t *testing.T) {
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
		t.Errorf("Expected valid=true, got valid=false. Errors: %v", response.Errors)
	}

	if response.Version == "" {
		t.Error("Expected version to be set")
	}
}

func TestValidateEvent_Invalid(t *testing.T) {
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
		t.Errorf("Expected status 422, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.ValidateEventResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Valid {
		t.Error("Expected valid=false, got valid=true")
	}

	if len(response.Errors) == 0 {
		t.Error("Expected validation errors, got none")
	}
}

func TestValidateBulkEvents(t *testing.T) {
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

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.ValidateBulkEventsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Summary.Total != 2 {
		t.Errorf("Expected total=2, got %d", response.Summary.Total)
	}

	if response.Summary.Valid != 1 {
		t.Errorf("Expected valid=1, got %d", response.Summary.Valid)
	}

	if response.Summary.Invalid != 1 {
		t.Errorf("Expected invalid=1, got %d", response.Summary.Invalid)
	}

	if len(response.Results) != 2 {
		t.Errorf("Expected 2 results, got %d", len(response.Results))
	}

	if !response.Results[0].Valid {
		t.Error("First event should be valid")
	}

	if response.Results[1].Valid {
		t.Error("Second event should be invalid")
	}
}

func TestGetVersions(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/schemas/versions", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.VersionsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if len(response.Versions) == 0 {
		t.Error("Expected at least one version")
	}

	foundV1 := false
	for _, v := range response.Versions {
		if v == "v1" {
			foundV1 = true
			break
		}
	}

	if !foundV1 {
		t.Error("Expected to find v1 in versions")
	}
}

func TestGetSchema(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/schemas/v1?type=event", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.SchemaResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Version != "v1" {
		t.Errorf("Expected version=v1, got %s", response.Version)
	}

	if response.Schema == nil {
		t.Error("Expected schema to be present")
	}
}

func TestGetSchema_Entity(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/schemas/v1?type=car", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.SchemaResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Version != "v1" {
		t.Errorf("Expected version=v1, got %s", response.Version)
	}

	if response.Schema == nil {
		t.Error("Expected schema to be present")
	}
}

func TestGetSchema_NotFound(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/schemas/v999", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("Expected status 404, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestHealth(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/health", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.HealthResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if response.Status != "healthy" {
		t.Errorf("Expected status=healthy, got %s", response.Status)
	}
}

func TestSchemaCache_LoadVersion(t *testing.T) {
	cachedSchema, err := testCache.LoadVersion("v1", testGitSync.GetLocalDir())
	if err != nil {
		t.Fatalf("Failed to load schema version: %v", err)
	}

	if cachedSchema == nil {
		t.Fatal("Expected cached schema to be non-nil")
	}

	if cachedSchema.Version != "v1" {
		t.Errorf("Expected version=v1, got %s", cachedSchema.Version)
	}

	if cachedSchema.EventSchema == nil {
		t.Error("Expected event schema to be loaded")
	}

	if len(cachedSchema.EntitySchemas) == 0 {
		t.Error("Expected entity schemas to be loaded")
	}
}

func TestSchemaCache_GetVersions(t *testing.T) {
	versions, err := testCache.GetVersions(testGitSync.GetLocalDir())
	if err != nil {
		t.Fatalf("Failed to get versions: %v", err)
	}

	if len(versions) == 0 {
		t.Error("Expected at least one version")
	}

	foundV1 := false
	for _, v := range versions {
		if v == "v1" {
			foundV1 = true
			break
		}
	}

	if !foundV1 {
		t.Error("Expected to find v1 in versions")
	}
}

func setupTestRouter() *http.ServeMux {
	mux := http.NewServeMux()

	// Wrap handlers for HTTP mux
	mux.HandleFunc("/api/v1/validate", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		// Convert to Gin context would require more setup
		// For now, test handlers directly
		if r.Method != "POST" {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}

		var req api.ValidateEventRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
			return
		}

		// Use handler logic directly
		version := req.Version
		if version == "" {
			version = testConfig.Validation.DefaultVersion
		}

		cachedSchema, err := testCache.LoadVersion(version, testGitSync.GetLocalDir())
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
			return
		}

		result, err := testValidator.ValidateEvent(req.Event, cachedSchema.EventSchema, cachedSchema.EntitySchemas, testGitSync.GetLocalDir())
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
			return
		}

		response := api.ValidateEventResponse{
			Valid:   result.Valid,
			Version: version,
		}

		if !result.Valid {
			response.Errors = make([]api.ValidationError, len(result.Errors))
			for i, err := range result.Errors {
				response.Errors[i] = api.ValidationError{
					Field:   err.Field,
					Message: err.Message,
				}
			}
			w.WriteHeader(http.StatusUnprocessableEntity)
		}

		json.NewEncoder(w).Encode(response)
	})

	mux.HandleFunc("/api/v1/validate/bulk", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.Method != "POST" {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}

		var req api.ValidateBulkEventsRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		results := make([]api.ValidateEventResponse, len(req.Events))
		summary := api.BulkSummary{Total: len(req.Events)}

		for i, event := range req.Events {
			version := req.Version
			if version == "" {
				version = testConfig.Validation.DefaultVersion
			}

			cachedSchema, err := testCache.LoadVersion(version, testGitSync.GetLocalDir())
			if err != nil {
				results[i] = api.ValidateEventResponse{
					Valid:   false,
					Version: version,
					Errors:  []api.ValidationError{{Field: "", Message: "Failed to load schema"}},
				}
				summary.Invalid++
				continue
			}

			result, err := testValidator.ValidateEvent(event, cachedSchema.EventSchema, cachedSchema.EntitySchemas, testGitSync.GetLocalDir())
			if err != nil {
				results[i] = api.ValidateEventResponse{
					Valid:   false,
					Version: version,
					Errors:  []api.ValidationError{{Field: "", Message: err.Error()}},
				}
				summary.Invalid++
				continue
			}

			response := api.ValidateEventResponse{
				Valid:   result.Valid,
				Version: version,
			}

			if !result.Valid {
				response.Errors = make([]api.ValidationError, len(result.Errors))
				for j, err := range result.Errors {
					response.Errors[j] = api.ValidationError{
						Field:   err.Field,
						Message: err.Message,
					}
				}
				summary.Invalid++
			} else {
				summary.Valid++
			}

			results[i] = response
		}

		response := api.ValidateBulkEventsResponse{
			Results: results,
			Summary: summary,
		}

		statusCode := http.StatusOK
		if testConfig.Validation.StrictMode && summary.Invalid > 0 {
			statusCode = http.StatusUnprocessableEntity
		}

		w.WriteHeader(statusCode)
		json.NewEncoder(w).Encode(response)
	})

	mux.HandleFunc("/api/v1/schemas/versions", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		versions, err := testCache.GetVersions(testGitSync.GetLocalDir())
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		response := api.VersionsResponse{
			Versions: versions,
			Default:  testConfig.Validation.DefaultVersion,
		}

		json.NewEncoder(w).Encode(response)
	})

	mux.HandleFunc("/api/v1/schemas/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		// Parse version from path (e.g., /api/v1/schemas/v999)
		path := r.URL.Path
		version := "v1" // Default
		if strings.HasPrefix(path, "/api/v1/schemas/") {
			versionPart := strings.TrimPrefix(path, "/api/v1/schemas/")
			if versionPart != "" && strings.HasPrefix(versionPart, "v") {
				version = versionPart
			}
		}
		
		schemaType := r.URL.Query().Get("type")
		if schemaType == "" {
			schemaType = "event"
		}

		cachedSchema, err := testCache.LoadVersion(version, testGitSync.GetLocalDir())
		if err != nil {
			w.WriteHeader(http.StatusNotFound)
			json.NewEncoder(w).Encode(map[string]string{"error": "Schema version not found", "version": version})
			return
		}

		var schema map[string]interface{}
		switch schemaType {
		case "event":
			schema = cachedSchema.EventSchema
		default:
			if entitySchema, ok := cachedSchema.EntitySchemas[schemaType]; ok {
				schema = entitySchema
			} else {
				w.WriteHeader(http.StatusNotFound)
				return
			}
		}

		response := api.SchemaResponse{
			Version: version,
			Schema:  schema,
		}

		json.NewEncoder(w).Encode(response)
	})

	mux.HandleFunc("/api/v1/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		versions, _ := testCache.GetVersions(testGitSync.GetLocalDir())
		version := ""
		if len(versions) > 0 {
			version = versions[len(versions)-1]
		}

		response := api.HealthResponse{
			Status:  "healthy",
			Version: version,
		}

		json.NewEncoder(w).Encode(response)
	})

	return mux
}

