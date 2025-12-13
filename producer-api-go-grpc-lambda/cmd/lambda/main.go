package main

import (
	"context"
	"encoding/json"
	"fmt"
	"producer-api-go-grpc-lambda/internal/config"
	"producer-api-go-grpc-lambda/internal/constants"
	"producer-api-go-grpc-lambda/internal/lambda"
	"producer-api-go-grpc-lambda/internal/lambda/grpcweb"
	"producer-api-go-grpc-lambda/internal/repository"
	"producer-api-go-grpc-lambda/internal/service"
	"producer-api-go-grpc-lambda/proto"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	awslambda "github.com/aws/aws-lambda-go/lambda"
	"go.uber.org/zap"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/encoding/protojson"
	protobuf "google.golang.org/protobuf/proto"
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

	// Initialize repository and service
	businessEventRepo := repository.NewBusinessEventRepository(pool)
	eventService = service.NewEventServiceImpl(businessEventRepo, pool, logger)

	logger.Info(fmt.Sprintf("%s Lambda handler initialized", constants.APIName()))
}

func main() {
	awslambda.Start(handler)
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

	// Check if it's a gRPC-Web request (binary, text, or JSON for testing)
	useText := strings.Contains(contentType, grpcweb.ContentTypeText)
	useJSON := strings.Contains(contentType, "json") || strings.Contains(contentType, "application/json")
	if !strings.Contains(contentType, grpcweb.ContentTypeProto) && !useText && !useJSON {
		return createErrorResponse(codes.InvalidArgument, "Invalid content type, expected gRPC-Web", contentType), nil
	}

	// Route to appropriate method
	switch {
	case serviceName == "EventService" && methodName == "ProcessEvent":
		return handleProcessEvent(ctx, request, useText, useJSON)
	case serviceName == "EventService" && methodName == "HealthCheck":
		return handleHealthCheck(ctx, request, useText, useJSON)
	default:
		return createErrorResponse(codes.Unimplemented, fmt.Sprintf("Method %s.%s not implemented", serviceName, methodName), contentType), nil
	}
}

func handleProcessEvent(ctx context.Context, request events.APIGatewayV2HTTPRequest, useText bool, useJSON bool) (events.APIGatewayV2HTTPResponse, error) {
	contentType := request.Headers["content-type"]
	if contentType == "" {
		contentType = request.Headers["Content-Type"]
	}

	var eventRequest proto.EventRequest

	if useJSON {
		// Handle JSON request (for testing)
		// Parse JSON directly into protobuf message
		unmarshaler := protojson.UnmarshalOptions{
			DiscardUnknown: true,
		}
		if err := unmarshaler.Unmarshal([]byte(request.Body), &eventRequest); err != nil {
			logger.Warn("Failed to unmarshal JSON request", zap.Error(err))
			return createErrorResponse(codes.InvalidArgument, "Invalid JSON message", contentType), nil
		}
	} else {
		// Handle standard gRPC-Web request (binary or text)
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
		if err := protobuf.Unmarshal(messageData, &eventRequest); err != nil {
			logger.Warn("Failed to unmarshal protobuf", zap.Error(err))
			return createErrorResponse(codes.InvalidArgument, "Invalid protobuf message", contentType), nil
		}
	}

	// Process event
	response, err := eventService.ProcessEvent(ctx, &eventRequest)
	if err != nil {
		logger.Error("Error processing event", zap.Error(err))
		return createErrorResponseFromError(err, contentType), nil
	}

	// Encode response
	var body []byte
	var respContentType string
	if useJSON {
		// Return JSON response
		marshaler := protojson.MarshalOptions{
			UseProtoNames: true,
		}
		jsonBytes, err := marshaler.Marshal(response)
		if err != nil {
			logger.Error("Failed to marshal JSON response", zap.Error(err))
			return createErrorResponse(codes.Internal, "Failed to encode response", contentType), nil
		}
		body = jsonBytes
		respContentType = "application/json"
	} else {
		// Return gRPC-Web response
		var err error
		body, respContentType, err = grpcweb.EncodeResponse(response, useText)
		if err != nil {
			logger.Error("Failed to encode response", zap.Error(err))
			return createErrorResponse(codes.Internal, "Failed to encode response", contentType), nil
		}
	}

	headers := map[string]string{
		"Content-Type":                 respContentType,
		"Access-Control-Allow-Origin":  "*",
		"Access-Control-Allow-Methods": "POST, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type, x-grpc-web",
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: 200,
		Headers:    headers,
		Body:       string(body),
	}, nil
}

func handleHealthCheck(ctx context.Context, request events.APIGatewayV2HTTPRequest, useText bool, useJSON bool) (events.APIGatewayV2HTTPResponse, error) {
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
	var body []byte
	var respContentType string
	if useJSON {
		// Return JSON response
		marshaler := protojson.MarshalOptions{
			UseProtoNames: true,
		}
		jsonBytes, err := marshaler.Marshal(response)
		if err != nil {
			logger.Error("Failed to marshal JSON response", zap.Error(err))
			return createErrorResponse(codes.Internal, "Failed to encode response", contentType), nil
		}
		body = jsonBytes
		respContentType = "application/json"
	} else {
		// Return gRPC-Web response
		var err error
		body, respContentType, err = grpcweb.EncodeResponse(response, useText)
		if err != nil {
			logger.Error("Failed to encode response", zap.Error(err))
			return createErrorResponse(codes.Internal, "Failed to encode response", contentType), nil
		}
	}

	headers := map[string]string{
		"Content-Type":                 respContentType,
		"Access-Control-Allow-Origin":  "*",
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
	useJSON := strings.Contains(contentType, "json") || strings.Contains(contentType, "application/json")

	var body []byte
	var respContentType string

	if useJSON {
		// Return JSON error response
		errorResponse := map[string]interface{}{
			"error":  message,
			"code":   int(code),
			"status": code.String(),
		}
		jsonBytes, _ := json.Marshal(errorResponse)
		body = jsonBytes
		respContentType = "application/json"
	} else {
		// Return gRPC-Web error response
		body, respContentType, _ = grpcweb.EncodeError(status.Error(code, message), useText)
	}

	headers := map[string]string{
		"Content-Type":                 respContentType,
		"Access-Control-Allow-Origin":  "*",
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
