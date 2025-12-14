package sync

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"go.uber.org/zap"
)

type GitSync struct {
	repository   string
	branch       string
	localDir     string
	pullInterval time.Duration
	logger       *zap.Logger
	stopChan     chan struct{}
}

func NewGitSync(repository, branch, localDir string, pullInterval time.Duration, logger *zap.Logger) *GitSync {
	return &GitSync{
		repository:   repository,
		branch:       branch,
		localDir:     localDir,
		pullInterval: pullInterval,
		logger:       logger,
		stopChan:     make(chan struct{}),
	}
}

func (gs *GitSync) Start() error {
	// Initial clone/pull
	if err := gs.sync(); err != nil {
		return fmt.Errorf("initial sync failed: %w", err)
	}

	// Start periodic sync
	go gs.periodicSync()

	return nil
}

func (gs *GitSync) Stop() {
	close(gs.stopChan)
}

func (gs *GitSync) sync() error {
	gs.logger.Info("Syncing git repository",
		zap.String("repository", gs.repository),
		zap.String("branch", gs.branch),
		zap.String("local_dir", gs.localDir))

	// Check if directory exists and has .git
	gitDir := filepath.Join(gs.localDir, ".git")
	exists := false
	if _, err := os.Stat(gitDir); err == nil {
		exists = true
	}

	if !exists {
		// Check if repository is a local file:// URL or local path
		if strings.HasPrefix(gs.repository, "file://") || (!strings.Contains(gs.repository, "://") && !strings.HasPrefix(gs.repository, "http")) {
			// Local repository - copy directly
			localPath := strings.TrimPrefix(gs.repository, "file://")
			if err := os.MkdirAll(gs.localDir, 0755); err != nil {
				return fmt.Errorf("failed to create local directory: %w", err)
			}

			// Use rsync or cp to copy files
			cmd := exec.Command("sh", "-c", fmt.Sprintf("cp -r %s/. %s/ 2>/dev/null || cp -r %s/* %s/ 2>/dev/null || true", localPath, gs.localDir, localPath, gs.localDir))
			if err := cmd.Run(); err != nil {
				// Try direct copy
				return gs.copyLocalRepository(localPath, gs.localDir)
			}
			gs.logger.Info("Local repository copied successfully")
		} else {
			// Remote repository - clone
			if err := os.MkdirAll(gs.localDir, 0755); err != nil {
				return fmt.Errorf("failed to create local directory: %w", err)
			}

			cmd := exec.Command("git", "clone", "--branch", gs.branch, "--depth", "1", gs.repository, gs.localDir)
			output, err := cmd.CombinedOutput()
			if err != nil {
				return fmt.Errorf("git clone failed: %w, output: %s", err, string(output))
			}
			gs.logger.Info("Repository cloned successfully")
		}
	} else {
		// Check if this is a local repository
		cmd := exec.Command("git", "remote", "get-url", "origin")
		cmd.Dir = gs.localDir
		output, err := cmd.CombinedOutput()
		hasRemote := err == nil && len(output) > 0

		if !hasRemote || strings.HasPrefix(strings.TrimSpace(string(output)), "file://") {
			// Local repository - just use existing files
			gs.logger.Info("Local repository detected, using existing files")
			return nil
		}

		// Pull latest changes from remote
		cmd = exec.Command("git", "pull", "origin", gs.branch)
		cmd.Dir = gs.localDir
		output, err = cmd.CombinedOutput()
		if err != nil {
			gs.logger.Warn("git pull failed, using cached version",
				zap.Error(err),
				zap.String("output", string(output)))
			// Don't fail on pull errors - use cached version
			return nil
		}
		gs.logger.Info("Repository updated successfully")
	}

	return nil
}

func (gs *GitSync) periodicSync() {
	ticker := time.NewTicker(gs.pullInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			if err := gs.sync(); err != nil {
				gs.logger.Error("Periodic sync failed", zap.Error(err))
			}
		case <-gs.stopChan:
			return
		}
	}
}

func (gs *GitSync) GetLocalDir() string {
	return gs.localDir
}

// copyLocalRepository copies files from a local directory
func (gs *GitSync) copyLocalRepository(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Skip .git directory
		if info.IsDir() && info.Name() == ".git" {
			return filepath.SkipDir
		}

		relPath, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}

		dstPath := filepath.Join(dst, relPath)

		if info.IsDir() {
			return os.MkdirAll(dstPath, info.Mode())
		}

		// Copy file
		srcFile, err := os.Open(path)
		if err != nil {
			return err
		}
		defer srcFile.Close()

		if err := os.MkdirAll(filepath.Dir(dstPath), 0755); err != nil {
			return err
		}

		dstFile, err := os.Create(dstPath)
		if err != nil {
			return err
		}
		defer dstFile.Close()

		if _, err := io.Copy(dstFile, srcFile); err != nil {
			return err
		}

		return os.Chmod(dstPath, info.Mode())
	})
}
