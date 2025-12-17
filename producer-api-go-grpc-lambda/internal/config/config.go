package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	DatabaseURL   string
	GRPCServerPort int
	LogLevel      string
}

func Load() (*Config, error) {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		databaseURL = "postgresql://postgres:password@localhost:5432/car_entities"
	}

	grpcPortStr := os.Getenv("GRPC_SERVER_PORT")
	if grpcPortStr == "" {
		grpcPortStr = "9092"
	}
	grpcPort, err := strconv.Atoi(grpcPortStr)
	if err != nil {
		return nil, fmt.Errorf("invalid GRPC_SERVER_PORT: %w", err)
	}

	logLevel := os.Getenv("LOG_LEVEL")
	if logLevel == "" {
		logLevel = "info"
	}

	return &Config{
		DatabaseURL:   databaseURL,
		GRPCServerPort: grpcPort,
		LogLevel:      logLevel,
	}, nil
}
