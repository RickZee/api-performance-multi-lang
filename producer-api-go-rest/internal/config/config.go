package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	DatabaseURL  string
	ServerPort   int
	LogLevel     string
	AuthEnabled  bool
	JWTSecretKey string
}

func Load() (*Config, error) {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		databaseURL = "postgresql://postgres:password@localhost:5432/car_entities"
	}

	serverPortStr := os.Getenv("SERVER_PORT")
	if serverPortStr == "" {
		serverPortStr = "9083"
	}
	serverPort, err := strconv.Atoi(serverPortStr)
	if err != nil {
		return nil, fmt.Errorf("invalid SERVER_PORT: %w", err)
	}

	logLevel := os.Getenv("LOG_LEVEL")
	if logLevel == "" {
		logLevel = "info"
	}

	authEnabled := os.Getenv("AUTH_ENABLED") == "true" || os.Getenv("AUTH_ENABLED") == "1"
	jwtSecretKey := os.Getenv("JWT_SECRET_KEY")
	if jwtSecretKey == "" {
		jwtSecretKey = "test-signing-key-for-jwt-tokens-not-for-production-use"
	}

	return &Config{
		DatabaseURL:  databaseURL,
		ServerPort:   serverPort,
		LogLevel:     logLevel,
		AuthEnabled:  authEnabled,
		JWTSecretKey: jwtSecretKey,
	}, nil
}

