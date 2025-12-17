package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"producer-api-go/internal/config"
	"producer-api-go/internal/constants"
	"producer-api-go/internal/handlers"
	"producer-api-go/internal/middleware"
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

	logger.Info(fmt.Sprintf("%s Starting Producer API Go server", constants.APIName()),
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

	logger.Info(fmt.Sprintf("%s Connected to database", constants.APIName()))

	// Initialize repository and service
	businessEventRepo := repository.NewBusinessEventRepository(pool)
	eventService := service.NewEventProcessingService(businessEventRepo, pool, logger)

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
	
	// Apply auth middleware if enabled (health check is always public)
	api.Use(middleware.JWTAuthMiddleware(logger, cfg.AuthEnabled))
	
	{
		api.POST("", eventHandler.ProcessEvent)
		api.POST("/bulk", eventHandler.ProcessBulkEvents)
	}
	
	// Health check is always public (no auth required)
	router.GET("/api/v1/events/health", healthHandler.HealthCheck)

	// Start server
	addr := fmt.Sprintf(":%d", cfg.ServerPort)
	logger.Info(fmt.Sprintf("%s Server listening", constants.APIName()), zap.String("address", addr))

	if err := http.ListenAndServe(addr, router); err != nil {
		logger.Fatal("Failed to start server", zap.Error(err))
	}
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
