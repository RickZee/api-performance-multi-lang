package main

import (
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"go.uber.org/zap"
	"metadata-service/internal/cache"
	syncservice "metadata-service/internal/sync"
	"metadata-service/internal/testutil"
)

func TestSchemaCache_ConcurrentAccess(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-concurrent-*")
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

	// Clone repo to cache dir
	gitSync := syncservice.NewGitSync(repoDir, "main", cacheDir, 1*time.Minute, logger)
	if err := gitSync.Start(); err != nil {
		t.Fatalf("Failed to start git sync: %v", err)
	}
	defer gitSync.Stop()
	time.Sleep(500 * time.Millisecond)

	schemaCache := cache.NewSchemaCache(cacheDir, logger)

	// Test concurrent access with 100 goroutines
	var wg sync.WaitGroup
	numGoroutines := 100
	errors := make(chan error, numGoroutines)

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := schemaCache.LoadVersion("v1", gitSync.GetLocalDir())
			if err != nil {
				errors <- err
			}
		}()
	}

	wg.Wait()
	close(errors)

	// Check for errors
	errorCount := 0
	for err := range errors {
		if err != nil {
			errorCount++
			t.Logf("Concurrent access error: %v", err)
		}
	}

	if errorCount > 0 {
		t.Errorf("Concurrent access should not fail, got %d errors", errorCount)
	}
}

func TestSchemaCache_PartialLoad(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-partial-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	schemaCache := cache.NewSchemaCache(cacheDir, logger)

	// Create version directory with some valid and some invalid schemas
	schemasDir := filepath.Join(cacheDir, "schemas", "v1")
	entityDir := filepath.Join(schemasDir, "entity")
	os.MkdirAll(entityDir, 0755)

	// Create valid schema
	validSchema := `{"type": "object", "properties": {"id": {"type": "string"}}}`
	os.WriteFile(filepath.Join(entityDir, "car.json"), []byte(validSchema), 0644)

	// Create invalid JSON schema
	os.WriteFile(filepath.Join(entityDir, "invalid.json"), []byte("{ invalid json }"), 0644)

	// Should load valid schemas and skip invalid ones
	cached, err := schemaCache.LoadVersion("v1", cacheDir)
	if err != nil {
		t.Fatalf("Should load partial schemas, got error: %v", err)
	}

	if len(cached.EntitySchemas) == 0 {
		t.Error("Should load at least valid schemas")
	}

	// Invalid schema should not be in cache
	if _, ok := cached.EntitySchemas["invalid"]; ok {
		t.Error("Invalid schema should not be cached")
	}
}

func TestSchemaCache_MissingEventSchema(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-missing-event-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	schemaCache := cache.NewSchemaCache(cacheDir, logger)

	// Create version directory without event.json
	schemasDir := filepath.Join(cacheDir, "schemas", "v1")
	os.MkdirAll(schemasDir, 0755)

	// Should handle missing event schema gracefully
	cached, err := schemaCache.LoadVersion("v1", cacheDir)
	if err != nil {
		t.Logf("Expected error for missing event schema: %v", err)
	} else {
		// If it doesn't error, event schema should be empty
		if cached.EventSchema != nil && len(cached.EventSchema) > 0 {
			t.Error("Event schema should be empty when file is missing")
		}
	}
}

func TestSchemaCache_EmptyEntityDirectory(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-empty-entity-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	schemaCache := cache.NewSchemaCache(cacheDir, logger)

	// Create version directory with empty entity directory
	schemasDir := filepath.Join(cacheDir, "schemas", "v1")
	eventDir := filepath.Join(schemasDir, "event")
	entityDir := filepath.Join(schemasDir, "entity")
	os.MkdirAll(eventDir, 0755)
	os.MkdirAll(entityDir, 0755)

	// Create event schema
	eventSchema := `{"type": "object", "properties": {"eventHeader": {"type": "object"}}}`
	os.WriteFile(filepath.Join(eventDir, "event.json"), []byte(eventSchema), 0644)

	// Should load successfully with empty entity directory
	cached, err := schemaCache.LoadVersion("v1", cacheDir)
	if err != nil {
		t.Fatalf("Should handle empty entity directory, got error: %v", err)
	}

	if len(cached.EntitySchemas) != 0 {
		t.Errorf("Expected 0 entity schemas, got %d", len(cached.EntitySchemas))
	}
}

func TestSchemaCache_InvalidationDuringLoad(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-invalidation-*")
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

	gitSync := syncservice.NewGitSync(repoDir, "main", cacheDir, 1*time.Minute, logger)
	if err := gitSync.Start(); err != nil {
		t.Fatalf("Failed to start git sync: %v", err)
	}
	defer gitSync.Stop()
	time.Sleep(500 * time.Millisecond)

	schemaCache := cache.NewSchemaCache(cacheDir, logger)

	// Load version first
	_, err = schemaCache.LoadVersion("v1", gitSync.GetLocalDir())
	if err != nil {
		t.Fatalf("Failed to load version: %v", err)
	}

	// Invalidate while another goroutine is loading
	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		schemaCache.Invalidate("v1")
	}()

	go func() {
		defer wg.Done()
		_, err := schemaCache.LoadVersion("v1", gitSync.GetLocalDir())
		if err != nil {
			t.Logf("Load during invalidation error: %v", err)
		}
	}()

	wg.Wait()

	// Should not panic and should eventually succeed
	_, err = schemaCache.LoadVersion("v1", gitSync.GetLocalDir())
	if err != nil {
		t.Errorf("Should reload after invalidation, got error: %v", err)
	}
}

func TestSchemaCache_GetVersions_EmptyDirectory(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-empty-versions-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	schemaCache := cache.NewSchemaCache(cacheDir, logger)

	// Create empty schemas directory
	schemasDir := filepath.Join(cacheDir, "schemas")
	os.MkdirAll(schemasDir, 0755)

	versions, err := schemaCache.GetVersions(cacheDir)
	if err != nil {
		t.Fatalf("Should handle empty directory, got error: %v", err)
	}

	if len(versions) != 0 {
		t.Errorf("Expected 0 versions, got %d", len(versions))
	}
}

func TestSchemaCache_GetVersions_NonExistentDirectory(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-nonexistent-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	schemaCache := cache.NewSchemaCache(cacheDir, logger)

	// Try to get versions from non-existent directory
	_, err = schemaCache.GetVersions("/nonexistent/directory")
	if err == nil {
		t.Error("Should return error for non-existent directory")
	}
}

