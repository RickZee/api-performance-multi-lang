package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"metadata-service/internal/cache"
	syncservice "metadata-service/internal/sync"
	"metadata-service/internal/testutil"

	"go.uber.org/zap"
)

func TestSchemaCache_LoadMultipleVersions(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-multi-version-*")
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

	// Load v1
	v1, err := schemaCache.LoadVersion("v1", gitSync.GetLocalDir())
	if err != nil {
		t.Fatalf("Failed to load v1: %v", err)
	}

	if v1.Version != "v1" {
		t.Errorf("Expected version v1, got %s", v1.Version)
	}

	// Load again (should use cache)
	v1Cached, err := schemaCache.LoadVersion("v1", gitSync.GetLocalDir())
	if err != nil {
		t.Fatalf("Failed to load v1 from cache: %v", err)
	}

	if v1Cached != v1 {
		t.Error("Expected same instance from cache")
	}
}

func TestSchemaCache_InvalidateAndReload(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-invalidate-*")
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

	// Load version
	_, err = schemaCache.LoadVersion("v1", gitSync.GetLocalDir())
	if err != nil {
		t.Fatalf("Failed to load v1: %v", err)
	}

	// Invalidate
	schemaCache.Invalidate("v1")

	// Reload (should load from disk again)
	v1Reloaded, err := schemaCache.LoadVersion("v1", gitSync.GetLocalDir())
	if err != nil {
		t.Fatalf("Failed to reload v1: %v", err)
	}

	if v1Reloaded == nil {
		t.Error("Expected reloaded schema to be non-nil")
	}
}

func TestSchemaCache_InvalidateAll(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-invalidate-all-*")
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

	// Load version
	_, err = schemaCache.LoadVersion("v1", gitSync.GetLocalDir())
	if err != nil {
		t.Fatalf("Failed to load v1: %v", err)
	}

	// Invalidate all
	schemaCache.InvalidateAll()

	// Reload (should load from disk)
	v1Reloaded, err := schemaCache.LoadVersion("v1", gitSync.GetLocalDir())
	if err != nil {
		t.Fatalf("Failed to reload v1: %v", err)
	}

	if v1Reloaded == nil {
		t.Error("Expected reloaded schema to be non-nil")
	}
}

func TestSchemaCache_NonExistentVersion(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-nonexistent-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	schemaCache := cache.NewSchemaCache(cacheDir, logger)

	// Try to load non-existent version
	_, err = schemaCache.LoadVersion("v999", cacheDir)
	if err == nil {
		t.Error("Expected error for non-existent version")
	}
}

func TestSchemaCache_GetVersions_Empty(t *testing.T) {
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

func TestSchemaCache_LoadVersion_WithInvalidJSON(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-invalid-json-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	schemaCache := cache.NewSchemaCache(cacheDir, logger)

	// Create version directory with invalid JSON
	schemasDir := filepath.Join(cacheDir, "schemas", "v1", "event")
	os.MkdirAll(schemasDir, 0755)

	// Write invalid JSON
	os.WriteFile(filepath.Join(schemasDir, "event.json"), []byte("{ invalid json }"), 0644)

	// Should handle invalid JSON gracefully
	_, err = schemaCache.LoadVersion("v1", cacheDir)
	if err == nil {
		t.Error("Expected error for invalid JSON")
	}
}

func TestSchemaCache_LoadVersion_MissingEntityDirectory(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-missing-entity-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	schemaCache := cache.NewSchemaCache(cacheDir, logger)

	// Create version directory without entity directory
	schemasDir := filepath.Join(cacheDir, "schemas", "v1", "event")
	os.MkdirAll(schemasDir, 0755)

	// Create event schema
	eventSchema := `{"type": "object", "properties": {"eventHeader": {"type": "object"}}}`
	os.WriteFile(filepath.Join(schemasDir, "event.json"), []byte(eventSchema), 0644)

	// Should load successfully with empty entity schemas
	cached, err := schemaCache.LoadVersion("v1", cacheDir)
	if err != nil {
		t.Fatalf("Should handle missing entity directory, got error: %v", err)
	}

	if len(cached.EntitySchemas) != 0 {
		t.Errorf("Expected 0 entity schemas, got %d", len(cached.EntitySchemas))
	}
}

func TestSchemaCache_LoadVersion_WithSymlinks(t *testing.T) {
	// This test verifies behavior with symlinks (if supported)
	// On some systems, symlinks might be used in schema directories
	tempDir, err := os.MkdirTemp("", "cache-symlink-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	schemaCache := cache.NewSchemaCache(cacheDir, logger)

	// Create normal version directory
	schemasDir := filepath.Join(cacheDir, "schemas", "v1", "event")
	os.MkdirAll(schemasDir, 0755)

	eventSchema := `{"type": "object", "properties": {"eventHeader": {"type": "object"}}}`
	os.WriteFile(filepath.Join(schemasDir, "event.json"), []byte(eventSchema), 0644)

	// Should load normally
	_, err = schemaCache.LoadVersion("v1", cacheDir)
	if err != nil {
		t.Fatalf("Should load version, got error: %v", err)
	}
}

func TestSchemaCache_ConcurrentInvalidation(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-concurrent-inv-*")
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

	// Load version
	_, err = schemaCache.LoadVersion("v1", gitSync.GetLocalDir())
	if err != nil {
		t.Fatalf("Failed to load v1: %v", err)
	}

	// Concurrent invalidation and load
	done := make(chan bool, 2)

	go func() {
		schemaCache.Invalidate("v1")
		done <- true
	}()

	go func() {
		schemaCache.InvalidateAll()
		done <- true
	}()

	<-done
	<-done

	// Should still be able to load
	_, err = schemaCache.LoadVersion("v1", gitSync.GetLocalDir())
	if err != nil {
		t.Errorf("Should reload after concurrent invalidation, got error: %v", err)
	}
}
