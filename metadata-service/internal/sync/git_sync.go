package sync

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
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
		// Clone repository
		if err := os.MkdirAll(gs.localDir, 0755); err != nil {
			return fmt.Errorf("failed to create local directory: %w", err)
		}

		cmd := exec.Command("git", "clone", "--branch", gs.branch, "--depth", "1", gs.repository, gs.localDir)
		output, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("git clone failed: %w, output: %s", err, string(output))
		}
		gs.logger.Info("Repository cloned successfully")
	} else {
		// Pull latest changes
		cmd := exec.Command("git", "pull", "origin", gs.branch)
		cmd.Dir = gs.localDir
		output, err := cmd.CombinedOutput()
		if err != nil {
			gs.logger.Warn("git pull failed, using cached version",
				zap.Error(err),
				zap.String("output", string(output)))
			return fmt.Errorf("git pull failed: %w", err)
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

