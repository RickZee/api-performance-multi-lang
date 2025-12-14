package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"metadata-service/internal/api"
	"metadata-service/internal/cache"
	"metadata-service/internal/compat"
	"metadata-service/internal/config"
	"metadata-service/internal/sync"
	"metadata-service/internal/testutil"
	"metadata-service/internal/validator"
)

func TestValidateEvent_StrictMode(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "strict-mode-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	repoDir, err := testutil.SetupTestRepo(tempDir)
	if err != nil {
		t.Fatalf("Failed to setup test repo: %v", err)
	}
	defer testutil.CleanupTestRepo(repoDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	gitSync := sync.NewGitSync(repoDir, "main", cacheDir, 1*time.Minute, logger)
	if err := gitSync.Start(); err != nil {
		t.Fatalf("Failed to start git sync: %v", err)
	}
	defer gitSync.Stop()
	time.Sleep(500 * time.Millisecond)

	schemaCache := cache.NewSchemaCache(cacheDir, logger)
	validator := validator.NewJSONSchemaValidator(logger)
	compatChecker := compat.NewCompatibilityChecker()

	// Create config with strict mode enabled
	cfg := &config.Config{
		Git: config.GitConfig{
			Repository:    repoDir,
			Branch:        "main",
			PullInterval:  1 * time.Minute,
			LocalCacheDir: cacheDir,
		},
		Validation: config.ValidationConfig{
			DefaultVersion:   "v1",
			AcceptedVersions: []string{"v1"},
			StrictMode:       true, // Strict mode enabled
		},
		Server: config.ServerConfig{
			Port:     8080,
			GRPCPort: 9090,
		},
	}

	handlers := api.NewHandlers(cfg, schemaCache, gitSync, validator, compatChecker, logger)

	// Test with invalid event
	event := testutil.InvalidEventMissingRequired()
	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	// Use Gin context (simplified for test)
	c, _ := gin.CreateTestContext(w)
	c.Request = req

	handlers.ValidateEvent(c)

	// In strict mode, should return 422
	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422 in strict mode, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateEvent_LenientMode(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "lenient-mode-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	repoDir, err := testutil.SetupTestRepo(tempDir)
	if err != nil {
		t.Fatalf("Failed to setup test repo: %v", err)
	}
	defer testutil.CleanupTestRepo(repoDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	gitSync := sync.NewGitSync(repoDir, "main", cacheDir, 1*time.Minute, logger)
	if err := gitSync.Start(); err != nil {
		t.Fatalf("Failed to start git sync: %v", err)
	}
	defer gitSync.Stop()
	time.Sleep(500 * time.Millisecond)

	schemaCache := cache.NewSchemaCache(cacheDir, logger)
	validator := validator.NewJSONSchemaValidator(logger)
	compatChecker := compat.NewCompatibilityChecker()

	// Create config with strict mode disabled
	cfg := &config.Config{
		Git: config.GitConfig{
			Repository:    repoDir,
			Branch:        "main",
			PullInterval:  1 * time.Minute,
			LocalCacheDir: cacheDir,
		},
		Validation: config.ValidationConfig{
			DefaultVersion:   "v1",
			AcceptedVersions: []string{"v1"},
			StrictMode:       false, // Lenient mode
		},
		Server: config.ServerConfig{
			Port:     8080,
			GRPCPort: 9090,
		},
	}

	handlers := api.NewHandlers(cfg, schemaCache, gitSync, validator, compatChecker, logger)

	// Test with invalid event
	event := testutil.InvalidEventMissingRequired()
	reqBody := map[string]interface{}{
		"event": event,
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	c, _ := gin.CreateTestContext(w)
	c.Request = req

	handlers.ValidateEvent(c)

	// In lenient mode, should return 200 with valid=false
	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200 in lenient mode, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.ValidateEventResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	// Event should still be marked as invalid
	if response.Valid {
		t.Error("Event should be marked invalid even in lenient mode")
	}
}

func TestValidateBulkEvents_StrictMode(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "bulk-strict-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	repoDir, err := testutil.SetupTestRepo(tempDir)
	if err != nil {
		t.Fatalf("Failed to setup test repo: %v", err)
	}
	defer testutil.CleanupTestRepo(repoDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	gitSync := sync.NewGitSync(repoDir, "main", cacheDir, 1*time.Minute, logger)
	if err := gitSync.Start(); err != nil {
		t.Fatalf("Failed to start git sync: %v", err)
	}
	defer gitSync.Stop()
	time.Sleep(500 * time.Millisecond)

	schemaCache := cache.NewSchemaCache(cacheDir, logger)
	validator := validator.NewJSONSchemaValidator(logger)
	compatChecker := compat.NewCompatibilityChecker()

	cfg := &config.Config{
		Git: config.GitConfig{
			Repository:    repoDir,
			Branch:        "main",
			PullInterval:  1 * time.Minute,
			LocalCacheDir: cacheDir,
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

	handlers := api.NewHandlers(cfg, schemaCache, gitSync, validator, compatChecker, logger)

	validEvent := testutil.ValidCarCreatedEvent()
	invalidEvent := testutil.InvalidEventMissingRequired()

	reqBody := map[string]interface{}{
		"events": []interface{}{validEvent, invalidEvent},
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	c, _ := gin.CreateTestContext(w)
	c.Request = req

	handlers.ValidateBulkEvents(c)

	// In strict mode with invalid events, should return 422
	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422 in strict mode with invalid events, got %d. Body: %s", w.Code, w.Body.String())
	}
}

func TestValidateBulkEvents_LenientMode(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "bulk-lenient-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	repoDir, err := testutil.SetupTestRepo(tempDir)
	if err != nil {
		t.Fatalf("Failed to setup test repo: %v", err)
	}
	defer testutil.CleanupTestRepo(repoDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	gitSync := sync.NewGitSync(repoDir, "main", cacheDir, 1*time.Minute, logger)
	if err := gitSync.Start(); err != nil {
		t.Fatalf("Failed to start git sync: %v", err)
	}
	defer gitSync.Stop()
	time.Sleep(500 * time.Millisecond)

	schemaCache := cache.NewSchemaCache(cacheDir, logger)
	validator := validator.NewJSONSchemaValidator(logger)
	compatChecker := compat.NewCompatibilityChecker()

	cfg := &config.Config{
		Git: config.GitConfig{
			Repository:    repoDir,
			Branch:        "main",
			PullInterval:  1 * time.Minute,
			LocalCacheDir: cacheDir,
		},
		Validation: config.ValidationConfig{
			DefaultVersion:   "v1",
			AcceptedVersions: []string{"v1"},
			StrictMode:       false, // Lenient mode
		},
		Server: config.ServerConfig{
			Port:     8080,
			GRPCPort: 9090,
		},
	}

	handlers := api.NewHandlers(cfg, schemaCache, gitSync, validator, compatChecker, logger)

	validEvent := testutil.ValidCarCreatedEvent()
	invalidEvent := testutil.InvalidEventMissingRequired()

	reqBody := map[string]interface{}{
		"events": []interface{}{validEvent, invalidEvent},
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	c, _ := gin.CreateTestContext(w)
	c.Request = req

	handlers.ValidateBulkEvents(c)

	// In lenient mode, should return 200 even with some invalid events
	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200 in lenient mode, got %d. Body: %s", w.Code, w.Body.String())
	}

	var response api.ValidateBulkEventsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	// Should still report invalid events in results
	if response.Summary.Invalid == 0 {
		t.Error("Should report invalid events even in lenient mode")
	}
}

