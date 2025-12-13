package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"go.uber.org/zap"
	"metadata-service/internal/cache"
	"metadata-service/internal/sync"
	"metadata-service/internal/testutil"
)

func TestGitSync_InitialClone(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "git-sync-test-*")
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

	// Wait for initial sync
	time.Sleep(1 * time.Second)

	// Verify cache directory was created
	if _, err := os.Stat(cacheDir); os.IsNotExist(err) {
		t.Error("Cache directory was not created")
	}

	// Verify .git directory exists (indicating clone was successful)
	gitDir := filepath.Join(cacheDir, ".git")
	if _, err := os.Stat(gitDir); os.IsNotExist(err) {
		t.Error("Git directory was not created")
	}

	// Verify schemas directory exists
	schemasDir := filepath.Join(cacheDir, "schemas", "v1")
	if _, err := os.Stat(schemasDir); os.IsNotExist(err) {
		t.Error("Schemas directory was not created")
	}
}

func TestGitSync_PullUpdates(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "git-sync-pull-test-*")
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

	gitSync := sync.NewGitSync(repoDir, "main", cacheDir, 1*time.Second, logger)

	if err := gitSync.Start(); err != nil {
		t.Fatalf("Failed to start git sync: %v", err)
	}
	defer gitSync.Stop()

	// Wait for initial sync
	time.Sleep(500 * time.Millisecond)

	// Create a new version in the repo
	v2Dir := filepath.Join(repoDir, "schemas", "v2", "event")
	if err := os.MkdirAll(v2Dir, 0755); err != nil {
		t.Fatalf("Failed to create v2 directory: %v", err)
	}

	// Copy v1 event.json to v2
	v1EventPath := filepath.Join(repoDir, "schemas", "v1", "event", "event.json")
	v2EventPath := filepath.Join(v2Dir, "event.json")
	data, err := os.ReadFile(v1EventPath)
	if err != nil {
		t.Fatalf("Failed to read v1 event: %v", err)
	}
	if err := os.WriteFile(v2EventPath, data, 0644); err != nil {
		t.Fatalf("Failed to write v2 event: %v", err)
	}

	// Commit the change
	cmd := exec.Command("git", "add", ".")
	cmd.Dir = repoDir
	if err := cmd.Run(); err != nil {
		t.Fatalf("Failed to git add: %v", err)
	}

	cmd = exec.Command("git", "commit", "-m", "Add v2 schema")
	cmd.Dir = repoDir
	if err := cmd.Run(); err != nil {
		t.Fatalf("Failed to git commit: %v", err)
	}

	// Wait for pull interval
	time.Sleep(2 * time.Second)

	// Verify v2 was pulled
	v2CacheDir := filepath.Join(cacheDir, "schemas", "v2")
	if _, err := os.Stat(v2CacheDir); os.IsNotExist(err) {
		t.Error("v2 schema directory was not pulled")
	}
}

func TestGitSync_HandlesPullFailure(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "git-sync-failure-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Use a non-existent repository
	invalidRepo := filepath.Join(tempDir, "nonexistent")
	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	gitSync := sync.NewGitSync(invalidRepo, "main", cacheDir, 1*time.Minute, logger)

	// Should fail on initial sync
	err = gitSync.Start()
	if err == nil {
		t.Error("Expected error when starting with invalid repo")
		gitSync.Stop()
	}
}

func TestSchemaCache_Invalidation(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "cache-invalidation-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	cache := cache.NewSchemaCache(cacheDir, logger)

	// Invalidate all
	cache.InvalidateAll()

	// Invalidate specific version
	cache.Invalidate("v1")

	// Should not panic
}

