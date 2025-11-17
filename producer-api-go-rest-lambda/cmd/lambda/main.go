package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"producer-api-go-rest-lambda/internal/config"
	"producer-api-go-rest-lambda/internal/constants"
	"producer-api-go-rest-lambda/internal/errors"
	"producer-api-go-rest-lambda/internal/lambda"
	"producer-api-go-rest-lambda/internal/models"
	"producer-api-go-rest-lambda/internal/repository"
	"producer-api-go-rest-lambda/internal/service"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"go.uber.org/zap"
)

var (
	eventService *service.EventProcessingService
	logger       *zap.Logger
)

func init() {
	// Initialize logger
	var err error
	cfg, err := config.LoadLambdaConfig()
	if err != nil {
		panic(fmt.Sprintf("Failed to load Lambda config: %v", err))
	}

	if cfg.LogLevel == "debug" {
		logger, _ = zap.NewDevelopment()
	} else {
		logger, _ = zap.NewProduction()
	}

	// Initialize database connection pool
	pool, err := lambda.GetConnectionPool(cfg.DatabaseURL, logger)
	if err != nil {
		logger.Fatal("Failed to initialize connection pool", zap.Error(err))
	}

	// Run migrations (if needed)
	if err := runMigrations(cfg.DatabaseURL, logger); err != nil {
		logger.Warn("Failed to run migrations", zap.Error(err))
	}

	// Initialize repository and service
	repo := repository.NewCarEntityRepository(pool)
	eventService = service.NewEventProcessingService(repo, logger)

	logger.Info(fmt.Sprintf("%s Lambda handler initialized", constants.APIName()))
}

func main() {
	lambda.Start(handler)
}

func handler(ctx context.Context, request events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	// Extract path and method
	path := request.RequestContext.HTTP.Path
	method := request.RequestContext.HTTP.Method

	logger.Info(fmt.Sprintf("%s Lambda request", constants.APIName()),
		zap.String("method", method),
		zap.String("path", path),
	)

	// Route requests
	switch {
	case path == "/api/v1/events/health" && method == "GET":
		return handleHealthCheck(ctx)
	case path == "/api/v1/events" && method == "POST":
		return handleProcessEvent(ctx, request)
	case path == "/api/v1/events/bulk" && method == "POST":
		return handleBulkEvents(ctx, request)
	default:
		return createResponse(404, map[string]interface{}{
			"error":  "Not Found",
			"status": 404,
		}), nil
	}
}

func handleHealthCheck(ctx context.Context) (events.APIGatewayV2HTTPResponse, error) {
	return createResponse(200, map[string]interface{}{
		"status":  "healthy",
		"message": "Producer API is healthy",
	}), nil
}

func handleProcessEvent(ctx context.Context, request events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	// Parse request body
	var event models.Event
	if err := json.Unmarshal([]byte(request.Body), &event); err != nil {
		logger.Warn(fmt.Sprintf("%s Invalid JSON", constants.APIName()), zap.Error(err))
		return createResponse(400, map[string]interface{}{
			"error":  "Invalid JSON",
			"status": 400,
		}), nil
	}

	// Validate event
	if event.EventHeader.EventName == "" {
		return createResponse(422, map[string]interface{}{
			"error":  "Event header event_name is required",
			"status": 422,
		}), nil
	}

	if len(event.EventBody.Entities) == 0 {
		return createResponse(422, map[string]interface{}{
			"error":  "Event body must contain at least one entity",
			"status": 422,
		}), nil
	}

	// Validate each entity
	for _, entity := range event.EventBody.Entities {
		if entity.EntityType == "" {
			return createResponse(422, map[string]interface{}{
				"error":  "Entity type cannot be empty",
				"status": 422,
			}), nil
		}
		if entity.EntityID == "" {
			return createResponse(422, map[string]interface{}{
				"error":  "Entity ID cannot be empty",
				"status": 422,
			}), nil
		}
	}

	logger.Info(fmt.Sprintf("%s Received event", constants.APIName()), zap.String("event_name", event.EventHeader.EventName))

	// Process event
	if err := eventService.ProcessEvent(ctx, &event); err != nil {
		logger.Error(fmt.Sprintf("%s Error processing event", constants.APIName()), zap.Error(err))
		appErr := errors.NewInternalError(err)
		return createResponse(appErr.StatusCode, map[string]interface{}{
			"error":  appErr.Message,
			"status": appErr.StatusCode,
		}), nil
	}

	return createResponse(200, map[string]interface{}{
		"success": true,
		"message": "Event processed successfully",
	}), nil
}

func handleBulkEvents(ctx context.Context, request events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	// Parse request body
	var events []models.Event
	if err := json.Unmarshal([]byte(request.Body), &events); err != nil {
		logger.Warn(fmt.Sprintf("%s Invalid JSON", constants.APIName()), zap.Error(err))
		return createResponse(400, map[string]interface{}{
			"error":  "Invalid JSON",
			"status": 400,
		}), nil
	}

	if len(events) == 0 {
		return createResponse(422, map[string]interface{}{
			"error":  "Invalid request: events list is null or empty",
			"status": 422,
		}), nil
	}

	logger.Info(fmt.Sprintf("%s Received bulk request", constants.APIName()), zap.Int("event_count", len(events)))

	processedCount := 0
	failedCount := 0

	for _, event := range events {
		// Validate event
		if event.EventHeader.EventName == "" {
			failedCount++
			continue
		}

		if len(event.EventBody.Entities) == 0 {
			failedCount++
			continue
		}

		// Validate entities
		valid := true
		for _, entity := range event.EventBody.Entities {
			if entity.EntityType == "" || entity.EntityID == "" {
				valid = false
				break
			}
		}

		if !valid {
			failedCount++
			continue
		}

		if err := eventService.ProcessEvent(ctx, &event); err != nil {
			logger.Error(fmt.Sprintf("%s Error processing event in bulk", constants.APIName()), zap.Error(err))
			failedCount++
			continue
		}

		processedCount++
	}

	success := failedCount == 0
	message := "All events processed successfully"
	if !success {
		message = fmt.Sprintf("Processed %d events, %d failed", processedCount, failedCount)
	}

	return createResponse(200, map[string]interface{}{
		"success":          success,
		"message":          message,
		"processedCount":   processedCount,
		"failedCount":      failedCount,
		"batchId":          fmt.Sprintf("batch-%d", time.Now().UnixMilli()),
		"processingTimeMs": 100,
	}), nil
}

func createResponse(statusCode int, body interface{}) events.APIGatewayV2HTTPResponse {
	bodyBytes, err := json.Marshal(body)
	if err != nil {
		logger.Error("Failed to marshal response", zap.Error(err))
		bodyBytes = []byte(`{"error":"Internal server error"}`)
		statusCode = 500
	}

	headers := map[string]string{
		"Content-Type": "application/json",
		"Access-Control-Allow-Origin": "*",
		"Access-Control-Allow-Methods": "GET, POST, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type",
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: statusCode,
		Headers:    headers,
		Body:       string(bodyBytes),
	}
}

func runMigrations(databaseURL string, logger *zap.Logger) error {
	// Read migration file
	migrationSQL, err := os.ReadFile("migrations/001_initial_schema.sql")
	if err != nil {
		// In Lambda, migrations might be in a different location
		// Try alternative paths
		paths := []string{
			"migrations/001_initial_schema.sql",
			"/var/task/migrations/001_initial_schema.sql",
			"./migrations/001_initial_schema.sql",
		}
		for _, path := range paths {
			if migrationSQL, err = os.ReadFile(path); err == nil {
				break
			}
		}
		if err != nil {
			return fmt.Errorf("failed to read migration file: %w", err)
		}
	}

	// Execute migration using connection pool
	pool, err := lambda.GetConnectionPool(databaseURL, logger)
	if err != nil {
		return fmt.Errorf("failed to get connection pool: %w", err)
	}

	// Split SQL by semicolons and execute each statement
	statements := strings.Split(string(migrationSQL), ";")
	for _, stmt := range statements {
		stmt = strings.TrimSpace(stmt)
		if stmt == "" || strings.HasPrefix(stmt, "--") {
			continue
		}
		if _, err := pool.Exec(context.Background(), stmt); err != nil {
			// Ignore "already exists" errors
			if !strings.Contains(err.Error(), "already exists") {
				return fmt.Errorf("failed to execute migration: %w", err)
			}
		}
	}

	return nil
}

