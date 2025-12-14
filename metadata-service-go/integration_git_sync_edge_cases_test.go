package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"go.uber.org/zap"
	syncservice "metadata-service/internal/sync"
	"metadata-service/internal/testutil"
)

func TestGitSync_RepositoryDeletedAfterClone(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "git-sync-deleted-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	repoDir, err := testutil.SetupTestRepo(tempDir)
	if err != nil {
		t.Fatalf("Failed to setup test repo: %v", err)
	}

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	gitSync := syncservice.NewGitSync(repoDir, "main", cacheDir, 1*time.Second, logger)

	if err := gitSync.Start(); err != nil {
		t.Fatalf("Failed to start git sync: %v", err)
	}
	defer gitSync.Stop()

	// Wait for initial clone
	time.Sleep(500 * time.Millisecond)

	// Delete the repository
	testutil.CleanupTestRepo(repoDir)

	// Wait for next pull attempt
	time.Sleep(2 * time.Second)

	// Should handle gracefully - using cached version
	// Verify cache still exists
	if _, err := os.Stat(cacheDir); os.IsNotExist(err) {
		t.Error("Cache directory should still exist after repo deletion")
	}
}

func TestGitSync_SchemaFileCorrupted(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "git-sync-corrupted-*")
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

	gitSync := syncservice.NewGitSync(repoDir, "main", cacheDir, 1*time.Second, logger)

	if err := gitSync.Start(); err != nil {
		t.Fatalf("Failed to start git sync: %v", err)
	}
	defer gitSync.Stop()

	// Wait for initial clone
	time.Sleep(500 * time.Millisecond)

	// Corrupt a schema file
	corruptedSchemaPath := filepath.Join(repoDir, "schemas", "v1", "event", "event.json")
	os.WriteFile(corruptedSchemaPath, []byte("{ invalid json }"), 0644)

	// Commit the corrupted file
	cmd := exec.Command("git", "add", ".")
	cmd.Dir = repoDir
	cmd.Run()

	cmd = exec.Command("git", "commit", "-m", "Corrupt schema")
	cmd.Dir = repoDir
	cmd.Run()

	// Wait for pull
	time.Sleep(2 * time.Second)

	// Service should handle corrupted schema gracefully
	// Cache directory should still exist
	if _, err := os.Stat(cacheDir); os.IsNotExist(err) {
		t.Error("Cache directory should exist even with corrupted schema")
	}
}

func TestGitSync_BranchSwitch(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "git-sync-branch-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	repoDir, err := testutil.SetupTestRepo(tempDir)
	if err != nil {
		t.Fatalf("Failed to setup test repo: %v", err)
	}
	defer testutil.CleanupTestRepo(repoDir)

	// Create a feature branch
	cmd := exec.Command("git", "checkout", "-b", "feature-branch")
	cmd.Dir = repoDir
	cmd.Run()

	// Add a new schema version
	v2Dir := filepath.Join(repoDir, "schemas", "v2", "event")
	os.MkdirAll(v2Dir, 0755)

	v1EventPath := filepath.Join(repoDir, "schemas", "v1", "event", "event.json")
	v2EventPath := filepath.Join(v2Dir, "event.json")
	data, _ := os.ReadFile(v1EventPath)
	os.WriteFile(v2EventPath, data, 0644)

	cmd = exec.Command("git", "add", ".")
	cmd.Dir = repoDir
	cmd.Run()

	cmd = exec.Command("git", "commit", "-m", "Add v2 on feature branch")
	cmd.Dir = repoDir
	cmd.Run()

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	// Sync from feature branch
	gitSync := syncservice.NewGitSync(repoDir, "feature-branch", cacheDir, 1*time.Second, logger)

	if err := gitSync.Start(); err != nil {
		t.Fatalf("Failed to start git sync: %v", err)
	}
	defer gitSync.Stop()

	// Wait for sync
	time.Sleep(2 * time.Second)

	// Verify v2 was pulled from feature branch
	v2CacheDir := filepath.Join(cacheDir, "schemas", "v2")
	if _, err := os.Stat(v2CacheDir); os.IsNotExist(err) {
		t.Error("v2 schema should be pulled from feature branch")
	}
}

func TestGitSync_ConcurrentPulls(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "git-sync-concurrent-*")
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

	gitSync := syncservice.NewGitSync(repoDir, "main", cacheDir, 100*time.Millisecond, logger)

	if err := gitSync.Start(); err != nil {
		t.Fatalf("Failed to start git sync: %v", err)
	}
	defer gitSync.Stop()

	// Make multiple commits rapidly
	for i := 0; i < 5; i++ {
		// Create a file
		testFile := filepath.Join(repoDir, "test", "file.txt")
		os.MkdirAll(filepath.Dir(testFile), 0755)
		os.WriteFile(testFile, []byte("test"), 0644)

		cmd := exec.Command("git", "add", ".")
		cmd.Dir = repoDir
		cmd.Run()

		cmd = exec.Command("git", "commit", "-m", "Test commit")
		cmd.Dir = repoDir
		cmd.Run()

		time.Sleep(150 * time.Millisecond)
	}

	// Should handle concurrent pulls without crashing
	time.Sleep(1 * time.Second)

	// Verify cache still exists
	if _, err := os.Stat(cacheDir); os.IsNotExist(err) {
		t.Error("Cache should exist after concurrent pulls")
	}
}

func TestGitSync_EmptyRepository(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "git-sync-empty-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Create empty git repo
	repoDir := filepath.Join(tempDir, "empty-repo")
	os.MkdirAll(repoDir, 0755)

	cmd := exec.Command("git", "init")
	cmd.Dir = repoDir
	cmd.Run()

	cmd = exec.Command("git", "commit", "--allow-empty", "-m", "Initial commit")
	cmd.Dir = repoDir
	cmd.Run()

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	gitSync := syncservice.NewGitSync(repoDir, "main", cacheDir, 1*time.Minute, logger)

	// Should handle empty repo gracefully
	err = gitSync.Start()
	if err != nil {
		t.Logf("Expected error or graceful handling for empty repo: %v", err)
	} else {
		gitSync.Stop()
	}
}

func TestGitSync_PartialCloneFailure(t *testing.T) {
	// This test simulates a scenario where clone starts but fails
	// In practice, this is hard to simulate without mocking
	// We'll test that the service handles errors gracefully
	tempDir, err := os.MkdirTemp("", "git-sync-partial-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Use a non-existent repository path
	invalidRepo := filepath.Join(tempDir, "nonexistent", "repo")
	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	gitSync := syncservice.NewGitSync(invalidRepo, "main", cacheDir, 1*time.Minute, logger)

	// Should fail gracefully
	err = gitSync.Start()
	if err == nil {
		t.Error("Expected error for non-existent repository")
		gitSync.Stop()
	}
}

func TestGitSync_GetLocalDir(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "git-sync-getdir-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	gitSync := syncservice.NewGitSync("", "main", cacheDir, 1*time.Minute, logger)

	localDir := gitSync.GetLocalDir()
	if localDir != cacheDir {
		t.Errorf("Expected local dir %s, got %s", cacheDir, localDir)
	}
}

