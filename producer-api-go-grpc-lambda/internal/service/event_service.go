package service

import (
	"context"
	"fmt"
	"producer-api-go-grpc-lambda/internal/models"
	"producer-api-go-grpc-lambda/internal/repository"
	"producer-api-go-grpc-lambda/proto"

	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"producer-api-go-grpc-lambda/internal/constants"
)

type EventServiceImpl struct {
	proto.UnimplementedEventServiceServer
	eventProcessingService *EventProcessingService
	logger                 *zap.Logger
}

func NewEventServiceImpl(
	businessEventRepo *repository.BusinessEventRepository,
	pool *pgxpool.Pool,
	logger *zap.Logger,
) *EventServiceImpl {
	return &EventServiceImpl{
		eventProcessingService: NewEventProcessingService(businessEventRepo, pool, logger),
		logger:                 logger,
	}
}

func (s *EventServiceImpl) ProcessEvent(ctx context.Context, req *proto.EventRequest) (*proto.EventResponse, error) {
	eventName := "unknown"
	if req.EventHeader != nil {
		eventName = req.EventHeader.EventName
	}
	s.logger.Info(fmt.Sprintf("%s Received gRPC event", constants.APIName()), zap.String("event_name", eventName))

	// Validate request
	if req.EventHeader == nil {
		return nil, status.Error(codes.InvalidArgument, "Invalid event: missing eventHeader")
	}

	// Validate event_name is not empty
	if req.EventHeader.EventName == "" {
		return nil, status.Error(codes.InvalidArgument, "Invalid event: eventName cannot be empty")
	}

	if req.EventBody == nil {
		return nil, status.Error(codes.InvalidArgument, "Invalid event: missing eventBody")
	}

	// Validate entities list is not empty
	if len(req.EventBody.Entities) == 0 {
		return nil, status.Error(codes.InvalidArgument, "Invalid event: entities list cannot be empty")
	}

	// Validate each entity
	for _, entityUpdate := range req.EventBody.Entities {
		if entityUpdate.EntityType == "" {
			return nil, status.Error(codes.InvalidArgument, "Invalid entity: entityType cannot be empty")
		}
		if entityUpdate.EntityId == "" {
			return nil, status.Error(codes.InvalidArgument, "Invalid entity: entityId cannot be empty")
		}
	}

	// Convert protobuf to internal model
	event, err := models.ConvertFromProto(req)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, fmt.Sprintf("Failed to convert request: %v", err))
	}

	// Process event
	if err := s.eventProcessingService.ProcessEvent(ctx, event); err != nil {
		// Check if it's a duplicate event error
		if dupErr, ok := err.(*repository.DuplicateEventError); ok {
			s.logger.Warn(fmt.Sprintf("%s Duplicate event ID: %s", constants.APIName(), dupErr.EventID))
			return nil, status.Error(codes.AlreadyExists, fmt.Sprintf("Event with ID '%s' already exists", dupErr.EventID))
		}

		s.logger.Error(fmt.Sprintf("%s Error processing event", constants.APIName()), zap.Error(err))
		return nil, status.Error(codes.Internal, fmt.Sprintf("Failed to process event: %v", err))
	}

	return &proto.EventResponse{
		Success: true,
		Message: "Event processed successfully",
	}, nil
}

func (s *EventServiceImpl) HealthCheck(ctx context.Context, req *proto.HealthRequest) (*proto.HealthResponse, error) {
	s.logger.Info(fmt.Sprintf("%s Health check requested", constants.APIName()))

	return &proto.HealthResponse{
		Healthy: true,
		Message: "Producer gRPC API is healthy",
	}, nil
}
