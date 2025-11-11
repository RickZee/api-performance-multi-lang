package service

import (
	"context"
	"encoding/json"
	"fmt"
	"producer-api-go-grpc/internal/models"
	"producer-api-go-grpc/internal/repository"
	"sync/atomic"
	"time"

	"go.uber.org/zap"
)

type EventProcessingService struct {
	repository          *repository.CarEntityRepository
	persistedEventCount *atomic.Uint64
	logger              *zap.Logger
}

func NewEventProcessingService(repo *repository.CarEntityRepository, logger *zap.Logger) *EventProcessingService {
	return &EventProcessingService{
		repository:          repo,
		persistedEventCount: &atomic.Uint64{},
		logger:              logger,
	}
}

func (s *EventProcessingService) logPersistedEventCount() {
	count := s.persistedEventCount.Add(1)
	if count%10 == 0 {
		s.logger.Info("*** Persisted events count", zap.Uint64("count", count))
	}
}

func (s *EventProcessingService) ProcessEntityUpdate(ctx context.Context, entityType, entityID string, updatedAttributes map[string]string) error {
	s.logger.Info("Processing entity creation",
		zap.String("entity_type", entityType),
		zap.String("entity_id", entityID),
	)

	exists, err := s.repository.ExistsByEntityTypeAndID(ctx, entityType, entityID)
	if err != nil {
		return fmt.Errorf("failed to check if entity exists: %w", err)
	}

	if exists {
		s.logger.Warn("Entity already exists, updating", zap.String("entity_id", entityID))
		if err := s.UpdateExistingEntity(ctx, entityType, entityID, updatedAttributes); err != nil {
			return fmt.Errorf("failed to update existing entity: %w", err)
		}
		s.logPersistedEventCount()
	} else {
		s.logger.Info("Entity does not exist, creating new", zap.String("entity_id", entityID))
		if err := s.CreateNewEntity(ctx, entityType, entityID, updatedAttributes); err != nil {
			return fmt.Errorf("failed to create new entity: %w", err)
		}
		s.logPersistedEventCount()
	}

	return nil
}

func (s *EventProcessingService) CreateNewEntity(ctx context.Context, entityType, entityID string, updatedAttributes map[string]string) error {
	// Convert map[string]string to JSON
	dataJSON, err := json.Marshal(updatedAttributes)
	if err != nil {
		return fmt.Errorf("failed to serialize entity data: %w", err)
	}

	entity := models.NewCarEntity(
		entityID,
		entityType,
		string(dataJSON),
	)

	if err := s.repository.Create(ctx, entity); err != nil {
		return fmt.Errorf("failed to insert entity into database: %w", err)
	}

	s.logger.Info("Successfully created entity", zap.String("entity_id", entity.ID))
	return nil
}

func (s *EventProcessingService) UpdateExistingEntity(ctx context.Context, entityType, entityID string, updatedAttributes map[string]string) error {
	existingEntity, err := s.repository.FindByEntityTypeAndID(ctx, entityType, entityID)
	if err != nil {
		return fmt.Errorf("failed to find existing entity: %w", err)
	}
	if existingEntity == nil {
		return fmt.Errorf("entity not found for update")
	}

	// Parse existing data
	var existingData map[string]interface{}
	if err := json.Unmarshal([]byte(existingEntity.Data), &existingData); err != nil {
		return fmt.Errorf("failed to parse existing entity data: %w", err)
	}

	// Merge new attributes into existing data
	for key, value := range updatedAttributes {
		existingData[key] = value
	}

	// Serialize merged data
	mergedData, err := json.Marshal(existingData)
	if err != nil {
		return fmt.Errorf("failed to serialize updated entity data: %w", err)
	}

	// Update entity
	now := time.Now()
	existingEntity.Data = string(mergedData)
	existingEntity.UpdatedAt = &now

	if err := s.repository.Update(ctx, existingEntity); err != nil {
		return fmt.Errorf("failed to update entity in database: %w", err)
	}

	s.logger.Info("Successfully updated entity", zap.String("entity_id", existingEntity.ID))
	return nil
}

