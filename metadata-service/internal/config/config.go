package config

import (
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Git        GitConfig        `yaml:"git"`
	Validation ValidationConfig `yaml:"validation"`
	Server     ServerConfig      `yaml:"server"`
}

type GitConfig struct {
	Repository    string        `yaml:"repository"`
	Branch        string        `yaml:"branch"`
	PullInterval  time.Duration `yaml:"pull_interval"`
	LocalCacheDir string        `yaml:"local_cache_dir"`
}

type ValidationConfig struct {
	DefaultVersion  string   `yaml:"default_version"`
	AcceptedVersions []string `yaml:"accepted_versions"`
	StrictMode     bool     `yaml:"strict_mode"`
}

type ServerConfig struct {
	Port     int `yaml:"port"`
	GRPCPort int `yaml:"grpc_port"`
}

func LoadConfig(configPath string) (*Config, error) {
	// Default config
	config := &Config{
		Git: GitConfig{
			Repository:    getEnv("GIT_REPOSITORY", ""),
			Branch:        getEnv("GIT_BRANCH", "main"),
			PullInterval:  5 * time.Minute,
			LocalCacheDir: getEnv("LOCAL_CACHE_DIR", "/tmp/schema-cache"),
		},
		Validation: ValidationConfig{
			DefaultVersion:   getEnv("DEFAULT_VERSION", "latest"),
			AcceptedVersions: []string{"v1", "v2"},
			StrictMode:       true,
		},
		Server: ServerConfig{
			Port:     getEnvInt("SERVER_PORT", 8080),
			GRPCPort: getEnvInt("GRPC_PORT", 9090),
		},
	}

	// Load from YAML if provided
	if configPath != "" {
		data, err := os.ReadFile(configPath)
		if err != nil {
			return nil, fmt.Errorf("failed to read config file: %w", err)
		}

		if err := yaml.Unmarshal(data, config); err != nil {
			return nil, fmt.Errorf("failed to parse config file: %w", err)
		}
	}

	// Override with environment variables (env vars take precedence)
	if repo := os.Getenv("GIT_REPOSITORY"); repo != "" {
		config.Git.Repository = repo
	}
	if branch := os.Getenv("GIT_BRANCH"); branch != "" {
		config.Git.Branch = branch
	}
	if cacheDir := os.Getenv("LOCAL_CACHE_DIR"); cacheDir != "" {
		config.Git.LocalCacheDir = cacheDir
	}
	if defaultVer := os.Getenv("DEFAULT_VERSION"); defaultVer != "" {
		config.Validation.DefaultVersion = defaultVer
	}
	if strictMode := os.Getenv("STRICT_MODE"); strictMode != "" {
		config.Validation.StrictMode = strictMode == "true"
	}

	// Validate required fields
	if config.Git.Repository == "" {
		return nil, fmt.Errorf("git repository is required (set GIT_REPOSITORY env var or config file)")
	}

	return config, nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		var result int
		if _, err := fmt.Sscanf(value, "%d", &result); err == nil {
			return result
		}
	}
	return defaultValue
}

