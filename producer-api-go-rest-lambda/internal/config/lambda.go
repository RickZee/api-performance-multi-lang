package config

import (
	"fmt"
	"os"
)

// LambdaConfig holds Lambda-specific configuration
type LambdaConfig struct {
	DatabaseURL string
	LogLevel    string
	// Aurora Serverless specific settings
	AuroraEndpoint string
	DatabaseName   string
	DatabaseUser   string
	DatabasePassword string
}

// LoadLambdaConfig loads configuration for Lambda environment
// Supports both direct DATABASE_URL and Aurora Serverless component-based configuration
func LoadLambdaConfig() (*LambdaConfig, error) {
	cfg := &LambdaConfig{}

	// Try to get DATABASE_URL first (standard approach)
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		// Fall back to Aurora Serverless component-based configuration
		auroraEndpoint := os.Getenv("AURORA_ENDPOINT")
		databaseName := os.Getenv("DATABASE_NAME")
		databaseUser := os.Getenv("DATABASE_USER")
		databasePassword := os.Getenv("DATABASE_PASSWORD")

		if auroraEndpoint != "" && databaseName != "" && databaseUser != "" && databasePassword != "" {
			// Construct connection string for Aurora Serverless
			// Format: postgresql://user:password@host:port/database
			// Aurora Serverless typically uses port 5432
			databaseURL = fmt.Sprintf("postgresql://%s:%s@%s:5432/%s",
				databaseUser, databasePassword, auroraEndpoint, databaseName)
			cfg.AuroraEndpoint = auroraEndpoint
			cfg.DatabaseName = databaseName
			cfg.DatabaseUser = databaseUser
			cfg.DatabasePassword = databasePassword
		} else {
			// Default for local development/testing
			databaseURL = "postgresql://postgres:password@localhost:5432/car_entities"
		}
	}

	cfg.DatabaseURL = databaseURL

	// Log level
	logLevel := os.Getenv("LOG_LEVEL")
	if logLevel == "" {
		logLevel = "info"
	}
	cfg.LogLevel = logLevel

	return cfg, nil
}

