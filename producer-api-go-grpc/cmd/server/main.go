package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"os"
	"producer-api-go-grpc/internal/config"
	"producer-api-go-grpc/internal/repository"
	"producer-api-go-grpc/internal/service"
	"producer-api-go-grpc/proto"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"
)

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Initialize logger
	var logger *zap.Logger
	if cfg.LogLevel == "debug" {
		logger, _ = zap.NewDevelopment()
	} else {
		logger, _ = zap.NewProduction()
	}
	defer logger.Sync()

	logger.Info("Starting Producer API Go gRPC server",
		zap.Int("port", cfg.GRPCServerPort),
		zap.String("log_level", cfg.LogLevel),
	)

	// Create database connection pool
	pool, err := pgxpool.New(context.Background(), cfg.DatabaseURL)
	if err != nil {
		logger.Fatal("Failed to create database connection pool", zap.Error(err))
	}
	defer pool.Close()

	// Test connection
	if err := pool.Ping(context.Background()); err != nil {
		logger.Fatal("Failed to ping database", zap.Error(err))
	}

	logger.Info("Connected to database")

	// Run migrations
	if err := runMigrations(cfg.DatabaseURL, logger); err != nil {
		logger.Fatal("Failed to run migrations", zap.Error(err))
	}

	logger.Info("Database migrations completed")

	// Initialize repository and service
	repo := repository.NewCarEntityRepository(pool)
	eventService := service.NewEventServiceImpl(repo, logger)

	// Create gRPC server
	grpcServer := grpc.NewServer()

	// Register service
	// Note: This will fail until proto files are generated
	// Run: ./scripts/generate-proto.sh
	proto.RegisterEventServiceServer(grpcServer, eventService)

	// Enable reflection for testing
	reflection.Register(grpcServer)

	// Start server
	addr := fmt.Sprintf(":%d", cfg.GRPCServerPort)
	lis, err := net.Listen("tcp", addr)
	if err != nil {
		logger.Fatal("Failed to listen", zap.Error(err), zap.String("address", addr))
	}

	logger.Info("gRPC server listening", zap.String("address", addr))

	if err := grpcServer.Serve(lis); err != nil {
		logger.Fatal("Failed to serve", zap.Error(err))
	}
}

func runMigrations(databaseURL string, logger *zap.Logger) error {
	// Read migration file
	migrationSQL, err := os.ReadFile("migrations/001_initial_schema.sql")
	if err != nil {
		return fmt.Errorf("failed to read migration file: %w", err)
	}

	// Connect to database
	pool, err := pgxpool.New(context.Background(), databaseURL)
	if err != nil {
		return fmt.Errorf("failed to connect to database: %w", err)
	}
	defer pool.Close()

	// Execute migration
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	_, err = pool.Exec(ctx, string(migrationSQL))
	if err != nil {
		return fmt.Errorf("failed to execute migration: %w", err)
	}

	return nil
}

