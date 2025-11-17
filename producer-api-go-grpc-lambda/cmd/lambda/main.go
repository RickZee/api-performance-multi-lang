package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"producer-api-go-grpc-lambda/internal/config"
	"producer-api-go-grpc-lambda/internal/constants"
	"producer-api-go-grpc-lambda/internal/lambda"
	"producer-api-go-grpc-lambda/internal/lambda/grpcweb"
	"producer-api-go-grpc-lambda/internal/repository"
	"producer-api-go-grpc-lambda/internal/service"
	"producer-api-go-grpc-lambda/proto"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"go.uber.org/zap"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

var (
	eventService *service.EventServiceImpl
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
	eventService = service.NewEventServiceImpl(repo, logger)

	logger.Info(fmt.Sprintf("%s Lambda handler initialized", constants.APIName()))
}

func main() {
	lambda.Start(handler)
}

func handler(ctx context.Context, request events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	// Extract path and method
	path := request.RequestContext.HTTP.Path
	method := request.RequestContext.HTTP.Method
	contentType := request.Headers["content-type"]
	if contentType == "" {
		contentType = request.Headers["Content-Type"]
	}

	logger.Info(fmt.Sprintf("%s Lambda gRPC-Web request", constants.APIName()),
		zap.String("method", method),
		zap.String("path", path),
		zap.String("content_type", contentType),
	)

	// Parse service and method from path
	serviceName, methodName, err := grpcweb.ParseMethodPath(path)
	if err != nil {
		logger.Warn("Invalid gRPC-Web path", zap.Error(err), zap.String("path", path))
		return createErrorResponse(codes.InvalidArgument, "Invalid path format", contentType), nil
	}

	// Check if it's a gRPC-Web request
	useText := strings.Contains(contentType, grpcweb.ContentTypeText)
	if !strings.Contains(contentType, grpcweb.ContentTypeProto) && !useText {
		return createErrorResponse(codes.InvalidArgument, "Invalid content type, expected gRPC-Web", contentType), nil
	}

	// Route to appropriate method
	switch {
	case serviceName == "EventService" && methodName == "ProcessEvent":
		return handleProcessEvent(ctx, request, useText)
	case serviceName == "EventService" && methodName == "HealthCheck":
		return handleHealthCheck(ctx, request, useText)
	default:
		return createErrorResponse(codes.Unimplemented, fmt.Sprintf("Method %s.%s not implemented", serviceName, methodName), contentType), nil
	}
}

func handleProcessEvent(ctx context.Context, request events.APIGatewayV2HTTPRequest, useText bool) (events.APIGatewayV2HTTPResponse, error) {
	contentType := request.Headers["content-type"]
	if contentType == "" {
		contentType = request.Headers["Content-Type"]
	}

	// Decode gRPC-Web request
	decodedBody, err := grpcweb.DecodeRequest(contentType, []byte(request.Body))
	if err != nil {
		logger.Warn("Failed to decode gRPC-Web request", zap.Error(err))
		return createErrorResponse(codes.InvalidArgument, "Failed to decode request", contentType), nil
	}

	// Read gRPC-Web frame
	messageData, _, err := grpcweb.ReadGRPCWebFrame(decodedBody)
	if err != nil {
		logger.Warn("Failed to read gRPC-Web frame", zap.Error(err))
		return createErrorResponse(codes.InvalidArgument, "Invalid gRPC-Web frame", contentType), nil
	}

	// Unmarshal protobuf
	var eventRequest proto.EventRequest
	if err := proto.Unmarshal(messageData, &eventRequest); err != nil {
		logger.Warn("Failed to unmarshal protobuf", zap.Error(err))
		return createErrorResponse(codes.InvalidArgument, "Invalid protobuf message", contentType), nil
	}

	// Process event
	response, err := eventService.ProcessEvent(ctx, &eventRequest)
	if err != nil {
		logger.Error("Error processing event", zap.Error(err))
		return createErrorResponseFromError(err, contentType), nil
	}

	// Encode response
	body, respContentType, err := grpcweb.EncodeResponse(response, useText)
	if err != nil {
		logger.Error("Failed to encode response", zap.Error(err))
		return createErrorResponse(codes.Internal, "Failed to encode response", contentType), nil
	}

	headers := map[string]string{
		"Content-Type": respContentType,
		"Access-Control-Allow-Origin": "*",
		"Access-Control-Allow-Methods": "POST, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type, x-grpc-web",
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: 200,
		Headers:    headers,
		Body:       string(body),
	}, nil
}

func handleHealthCheck(ctx context.Context, request events.APIGatewayV2HTTPRequest, useText bool) (events.APIGatewayV2HTTPResponse, error) {
	contentType := request.Headers["content-type"]
	if contentType == "" {
		contentType = request.Headers["Content-Type"]
	}

	// Create health check request
	healthRequest := &proto.HealthRequest{
		Service: "EventService",
	}

	// Process health check
	response, err := eventService.HealthCheck(ctx, healthRequest)
	if err != nil {
		logger.Error("Error in health check", zap.Error(err))
		return createErrorResponseFromError(err, contentType), nil
	}

	// Encode response
	body, respContentType, err := grpcweb.EncodeResponse(response, useText)
	if err != nil {
		logger.Error("Failed to encode response", zap.Error(err))
		return createErrorResponse(codes.Internal, "Failed to encode response", contentType), nil
	}

	headers := map[string]string{
		"Content-Type": respContentType,
		"Access-Control-Allow-Origin": "*",
		"Access-Control-Allow-Methods": "POST, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type, x-grpc-web",
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: 200,
		Headers:    headers,
		Body:       string(body),
	}, nil
}

func createErrorResponse(code codes.Code, message string, contentType string) events.APIGatewayV2HTTPResponse {
	useText := strings.Contains(contentType, grpcweb.ContentTypeText)
	body, respContentType, statusCode := grpcweb.EncodeError(status.Error(code, message), useText)

	headers := map[string]string{
		"Content-Type": respContentType,
		"Access-Control-Allow-Origin": "*",
		"Access-Control-Allow-Methods": "POST, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type, x-grpc-web",
	}

	// Map gRPC status codes to HTTP status codes
	httpStatusCode := 200
	if code == codes.InvalidArgument {
		httpStatusCode = 400
	} else if code == codes.NotFound {
		httpStatusCode = 404
	} else if code == codes.Internal {
		httpStatusCode = 500
	} else if code == codes.Unimplemented {
		httpStatusCode = 501
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: httpStatusCode,
		Headers:    headers,
		Body:       string(body),
	}
}

func createErrorResponseFromError(err error, contentType string) events.APIGatewayV2HTTPResponse {
	st, ok := status.FromError(err)
	if !ok {
		st = status.New(codes.Internal, err.Error())
	}
	return createErrorResponse(st.Code(), st.Message(), contentType)
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

