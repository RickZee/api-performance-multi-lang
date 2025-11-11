package service

import (
	"context"
	"encoding/json"
	"fmt"
	"producer-api-go/internal/models"
	"producer-api-go/internal/repository"
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

func (s *EventProcessingService) ProcessEvent(ctx context.Context, event *models.Event) error {
	s.logger.Info("Processing event", zap.String("event_name", event.EventHeader.EventName))

	for _, entityUpdate := range event.EventBody.Entities {
		if err := s.ProcessEntityUpdate(ctx, entityUpdate); err != nil {
			return fmt.Errorf("failed to process entity update: %w", err)
		}
	}

	return nil
}

func (s *EventProcessingService) ProcessEntityUpdate(ctx context.Context, entityUpdate models.EntityUpdate) error {
	s.logger.Info("Processing entity creation",
		zap.String("entity_type", entityUpdate.EntityType),
		zap.String("entity_id", entityUpdate.EntityID),
	)

	exists, err := s.repository.ExistsByEntityTypeAndID(ctx, entityUpdate.EntityType, entityUpdate.EntityID)
	if err != nil {
		return fmt.Errorf("failed to check if entity exists: %w", err)
	}

	if exists {
		s.logger.Warn("Entity already exists, updating", zap.String("entity_id", entityUpdate.EntityID))
		if err := s.UpdateExistingEntity(ctx, entityUpdate); err != nil {
			return fmt.Errorf("failed to update existing entity: %w", err)
		}
		s.logPersistedEventCount()
	} else {
		s.logger.Info("Entity does not exist, creating new", zap.String("entity_id", entityUpdate.EntityID))
		if err := s.CreateNewEntity(ctx, entityUpdate); err != nil {
			return fmt.Errorf("failed to create new entity: %w", err)
		}
		s.logPersistedEventCount()
	}

	return nil
}

func (s *EventProcessingService) CreateNewEntity(ctx context.Context, entityUpdate models.EntityUpdate) error {
	dataJSON := string(entityUpdate.UpdatedAttributes)

	entity := models.NewCarEntity(
		entityUpdate.EntityID,
		entityUpdate.EntityType,
		dataJSON,
	)

	if err := s.repository.Create(ctx, entity); err != nil {
		return fmt.Errorf("failed to insert entity into database: %w", err)
	}

	s.logger.Info("Successfully created entity", zap.String("entity_id", entity.ID))
	return nil
}

func (s *EventProcessingService) UpdateExistingEntity(ctx context.Context, entityUpdate models.EntityUpdate) error {
	existingEntity, err := s.repository.FindByEntityTypeAndID(ctx, entityUpdate.EntityType, entityUpdate.EntityID)
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

	// Parse new attributes
	var newAttributes map[string]interface{}
	if err := json.Unmarshal(entityUpdate.UpdatedAttributes, &newAttributes); err != nil {
		return fmt.Errorf("failed to parse new attributes: %w", err)
	}

	// Merge new attributes into existing data
	for key, value := range newAttributes {
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

