package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"metadata-service/internal/api"
	"metadata-service/internal/cache"
	"metadata-service/internal/compat"
	"metadata-service/internal/config"
	"metadata-service/internal/sync"
	"metadata-service/internal/validator"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

func main() {
	// Initialize logger
	logger, err := zap.NewProduction()
	if err != nil {
		panic(fmt.Sprintf("failed to initialize logger: %v", err))
	}
	defer logger.Sync()

	// Load configuration
	configPath := os.Getenv("CONFIG_PATH")
	cfg, err := config.LoadConfig(configPath)
	if err != nil {
		logger.Fatal("Failed to load configuration", zap.Error(err))
	}

	logger.Info("Starting metadata service",
		zap.String("repository", cfg.Git.Repository),
		zap.String("branch", cfg.Git.Branch),
		zap.Int("port", cfg.Server.Port))

	// Initialize components
	schemaCache := cache.NewSchemaCache(cfg.Git.LocalCacheDir, logger)
	gitSync := sync.NewGitSync(cfg.Git.Repository, cfg.Git.Branch, cfg.Git.LocalCacheDir, cfg.Git.PullInterval, logger)

	// Start git sync
	if err := gitSync.Start(); err != nil {
		logger.Fatal("Failed to start git sync", zap.Error(err))
	}
	defer gitSync.Stop()

	jsonValidator := validator.NewJSONSchemaValidator(logger)
	compatChecker := compat.NewCompatibilityChecker()

	// Initialize handlers
	handlers := api.NewHandlers(cfg, schemaCache, gitSync, jsonValidator, compatChecker, logger)

	// Setup router
	router := gin.Default()

	// API routes
	v1 := router.Group("/api/v1")
	{
		v1.POST("/validate", handlers.ValidateEvent)
		v1.POST("/validate/bulk", handlers.ValidateBulkEvents)
		v1.GET("/schemas/versions", handlers.GetVersions)
		v1.GET("/schemas/:version", handlers.GetSchema)
		v1.GET("/health", handlers.Health)

		// Filter routes
		v1.POST("/filters", handlers.CreateFilter)
		v1.GET("/filters", handlers.ListFilters)
		v1.GET("/filters/:id", handlers.GetFilter)
		v1.PUT("/filters/:id", handlers.UpdateFilter)
		v1.DELETE("/filters/:id", handlers.DeleteFilter)
		v1.POST("/filters/:id/generate", handlers.GenerateSQL)
		v1.POST("/filters/:id/validate", handlers.ValidateSQL)
		v1.POST("/filters/:id/approve", handlers.ApproveFilter)
		v1.POST("/filters/:id/deploy", handlers.DeployFilter)
		v1.GET("/filters/:id/status", handlers.GetFilterStatus)
	}

	// Start server
	server := &http.Server{
		Addr:    fmt.Sprintf(":%d", cfg.Server.Port),
		Handler: router,
	}

	// Graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
		<-sigChan

		logger.Info("Shutting down server...")
		cancel()
		if err := server.Shutdown(ctx); err != nil {
			logger.Error("Server shutdown error", zap.Error(err))
		}
	}()

	logger.Info("Server started", zap.Int("port", cfg.Server.Port))
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		logger.Fatal("Server failed", zap.Error(err))
	}

	logger.Info("Server stopped")
}
