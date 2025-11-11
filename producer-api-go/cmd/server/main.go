package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"producer-api-go/internal/config"
	"producer-api-go/internal/handlers"
	"producer-api-go/internal/repository"
	"producer-api-go/internal/service"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
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

	logger.Info("Starting Producer API Go server",
		zap.Int("port", cfg.ServerPort),
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
	eventService := service.NewEventProcessingService(repo, logger)

	// Initialize handlers
	eventHandler := handlers.NewEventHandler(eventService, logger)
	healthHandler := handlers.NewHealthHandler()

	// Set up Gin router
	if cfg.LogLevel != "debug" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.Use(ginLogger(logger))
	router.Use(gin.Recovery())
	router.Use(corsMiddleware())

	// Register routes
	api := router.Group("/api/v1/events")
	{
		api.POST("", eventHandler.ProcessEvent)
		api.POST("/bulk", eventHandler.ProcessBulkEvents)
		api.GET("/health", healthHandler.HealthCheck)
	}

	// Start server
	addr := fmt.Sprintf(":%d", cfg.ServerPort)
	logger.Info("Server listening", zap.String("address", addr))

	if err := http.ListenAndServe(addr, router); err != nil {
		logger.Fatal("Failed to start server", zap.Error(err))
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

func ginLogger(logger *zap.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		query := c.Request.URL.RawQuery

		c.Next()

		latency := time.Since(start)
		logger.Info("HTTP request",
			zap.Int("status", c.Writer.Status()),
			zap.String("method", c.Request.Method),
			zap.String("path", path),
			zap.String("query", query),
			zap.String("ip", c.ClientIP()),
			zap.Duration("latency", latency),
		)
	}
}

func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}

