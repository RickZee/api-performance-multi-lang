package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"producer-api-go-grpc/internal/config"
	"producer-api-go-grpc/internal/constants"
	"producer-api-go-grpc/internal/repository"
	"producer-api-go-grpc/internal/service"
	"producer-api-go-grpc/proto"

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

	logger.Info(fmt.Sprintf("%s Starting Producer API Go gRPC server", constants.APIName()),
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

	logger.Info(fmt.Sprintf("%s Connected to database", constants.APIName()))

	// Initialize repository and service
	businessEventRepo := repository.NewBusinessEventRepository(pool)
	eventService := service.NewEventServiceImpl(businessEventRepo, pool, logger)

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

	logger.Info(fmt.Sprintf("%s gRPC server listening", constants.APIName()), zap.String("address", addr))

	if err := grpcServer.Serve(lis); err != nil {
		logger.Fatal("Failed to serve", zap.Error(err))
	}
}
