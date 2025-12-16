package service

import (
	"context"
	"encoding/json"
	"fmt"
	"producer-api-go-rest-lambda/internal/models"
	"producer-api-go-rest-lambda/internal/repository"
	"strconv"
	"sync/atomic"
	"time"

	"producer-api-go-rest-lambda/internal/constants"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// Entity type to table name mapping
var entityTableMap = map[string]string{
	"Car":           "car_entities",
	"Loan":          "loan_entities",
	"LoanPayment":   "loan_payment_entities",
	"ServiceRecord": "service_record_entities",
}

type EventProcessingService struct {
	businessEventRepo   *repository.BusinessEventRepository
	eventHeaderRepo     *repository.EventHeaderRepository
	pool                *pgxpool.Pool
	persistedEventCount *atomic.Uint64
	logger              *zap.Logger
}

func NewEventProcessingService(
	businessEventRepo *repository.BusinessEventRepository,
	pool *pgxpool.Pool,
	logger *zap.Logger,
) *EventProcessingService {
	return &EventProcessingService{
		businessEventRepo:   businessEventRepo,
		eventHeaderRepo:     repository.NewEventHeaderRepository(pool),
		pool:                pool,
		persistedEventCount: &atomic.Uint64{},
		logger:              logger,
	}
}

func (s *EventProcessingService) logPersistedEventCount() {
	count := s.persistedEventCount.Add(1)
	if count%10 == 0 {
		s.logger.Info(fmt.Sprintf("%s *** Persisted events count", constants.APIName()), zap.Uint64("count", count))
	}
}

func (s *EventProcessingService) getEntityRepository(entityType string) *repository.EntityRepository {
	tableName, ok := entityTableMap[entityType]
	if !ok {
		s.logger.Warn(fmt.Sprintf("%s Unknown entity type: %s", constants.APIName(), entityType))
		return nil
	}
	return repository.NewEntityRepository(s.pool, tableName)
}

// ProcessEvent processes a single event within a transaction.
// All database operations (business_events, event_headers, entities) are executed
// atomically within a single transaction. If any operation fails, all changes are rolled back.
func (s *EventProcessingService) ProcessEvent(ctx context.Context, event *models.Event) error {
	s.logger.Info(fmt.Sprintf("%s Processing event: %s", constants.APIName(), event.EventHeader.EventName))

	// Generate event ID if not provided
	eventID := event.EventHeader.UUID
	if eventID == nil || *eventID == "" {
		id := fmt.Sprintf("event-%s", time.Now().UTC().Format(time.RFC3339Nano))
		eventID = &id
	}

	// Begin transaction
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx) // Rollback if not committed

	// 1. Save entire event to business_events table
	if err := s.saveBusinessEvent(ctx, event, *eventID, tx); err != nil {
		return fmt.Errorf("failed to save business event: %w", err)
	}

	// 2. Save event header to event_headers table
	if err := s.saveEventHeader(ctx, event, *eventID, tx); err != nil {
		return fmt.Errorf("failed to save event header: %w", err)
	}

	// 3. Extract and save entities to their respective tables
	for _, entityUpdate := range event.Entities {
		if err := s.processEntityUpdate(ctx, entityUpdate, *eventID, tx); err != nil {
			return fmt.Errorf("failed to process entity update: %w", err)
		}
	}

	// Commit transaction
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	s.logPersistedEventCount()
	s.logger.Info(fmt.Sprintf("%s Successfully processed event in transaction: %s", constants.APIName(), *eventID))
	return nil
}

func (s *EventProcessingService) saveBusinessEvent(
	ctx context.Context,
	event *models.Event,
	eventID string,
	tx pgx.Tx,
) error {
	eventName := event.EventHeader.EventName
	eventType := event.EventHeader.EventType
	createdDate := event.EventHeader.CreatedDate
	savedDate := event.EventHeader.SavedDate

	// Use current time if dates are not provided
	now := time.Now()
	if createdDate == nil {
		createdDate = &now
	}
	if savedDate == nil {
		savedDate = &now
	}

	// Convert event to map for JSONB storage
	eventJSON, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal event: %w", err)
	}

	var eventData map[string]interface{}
	if err := json.Unmarshal(eventJSON, &eventData); err != nil {
		return fmt.Errorf("failed to unmarshal event data: %w", err)
	}

	err = s.businessEventRepo.Create(ctx, eventID, eventName, eventType, createdDate, savedDate, eventData, tx)
	if err != nil {
		return err
	}

	s.logger.Info(fmt.Sprintf("%s Successfully saved business event: %s", constants.APIName(), eventID))
	return nil
}

func (s *EventProcessingService) saveEventHeader(
	ctx context.Context,
	event *models.Event,
	eventID string,
	tx pgx.Tx,
) error {
	eventName := event.EventHeader.EventName
	eventType := event.EventHeader.EventType
	createdDate := event.EventHeader.CreatedDate
	savedDate := event.EventHeader.SavedDate

	// Use current time if dates are not provided
	now := time.Now()
	if createdDate == nil {
		createdDate = &now
	}
	if savedDate == nil {
		savedDate = &now
	}

	// Convert eventHeader to map for JSONB storage
	headerJSON, err := json.Marshal(event.EventHeader)
	if err != nil {
		return fmt.Errorf("failed to marshal event header: %w", err)
	}

	var headerData map[string]interface{}
	if err := json.Unmarshal(headerJSON, &headerData); err != nil {
		return fmt.Errorf("failed to unmarshal header data: %w", err)
	}

	err = s.eventHeaderRepo.Create(ctx, eventID, eventName, eventType, createdDate, savedDate, headerData, tx)
	if err != nil {
		return err
	}

	s.logger.Info(fmt.Sprintf("%s Successfully saved event header: %s", constants.APIName(), eventID))
	return nil
}

func (s *EventProcessingService) processEntityUpdate(
	ctx context.Context,
	entity models.Entity,
	eventID string,
	tx pgx.Tx,
) error {
	s.logger.Info(fmt.Sprintf("%s Processing entity for type: %s and id: %s",
		constants.APIName(), entity.EntityHeader.EntityType, entity.EntityHeader.EntityID))

	entityRepo := s.getEntityRepository(entity.EntityHeader.EntityType)
	if entityRepo == nil {
		s.logger.Warn(fmt.Sprintf("%s Skipping entity with unknown type: %s",
			constants.APIName(), entity.EntityHeader.EntityType))
		return nil
	}

	exists, err := entityRepo.ExistsByEntityID(ctx, entity.EntityHeader.EntityID, tx)
	if err != nil {
		return fmt.Errorf("failed to check if entity exists: %w", err)
	}

	if exists {
		s.logger.Warn(fmt.Sprintf("%s Entity already exists, updating: %s",
			constants.APIName(), entity.EntityHeader.EntityID))
		return s.updateExistingEntity(ctx, entityRepo, entityUpdate, eventID, tx)
	} else {
		s.logger.Info(fmt.Sprintf("%s Entity does not exist, creating new: %s",
			constants.APIName(), entity.EntityHeader.EntityID))
		return s.createNewEntity(ctx, entityRepo, entityUpdate, eventID, tx)
	}
}

func (s *EventProcessingService) createNewEntity(
	ctx context.Context,
	entityRepo *repository.EntityRepository,
	entity models.Entity,
	eventID string,
	tx pgx.Tx,
) error {
	entityID := entity.EntityHeader.EntityID
	entityType := entity.EntityHeader.EntityType
	now := time.Now()

	// Extract entity data from entity properties
	entityData := entity.Properties

	// Use createdAt and updatedAt from entityHeader
	createdAt := &entity.EntityHeader.CreatedAt
	updatedAt := &entity.EntityHeader.UpdatedAt

	err := entityRepo.Create(ctx, entityID, entityType, createdAt, updatedAt, entityData, &eventID, tx)
	if err != nil {
		return fmt.Errorf("failed to create entity: %w", err)
	}

	s.logger.Info(fmt.Sprintf("%s Successfully created entity: %s", constants.APIName(), entityID))
	return nil
}

func (s *EventProcessingService) updateExistingEntity(
	ctx context.Context,
	entityRepo *repository.EntityRepository,
	entity models.Entity,
	eventID string,
	tx pgx.Tx,
) error {
	entityID := entity.EntityHeader.EntityID
	updatedAt := time.Now()

	// Extract entity data from entity properties
	entityData := entity.Properties

	// Remove entityHeader fields that might be at top level
	delete(entityData, "createdAt")
	delete(entityData, "created_at")
	delete(entityData, "updatedAt")
	delete(entityData, "updated_at")

	err := entityRepo.Update(ctx, entityID, updatedAt, entityData, &eventID, tx)
	if err != nil {
		return fmt.Errorf("failed to update entity: %w", err)
	}

	s.logger.Info(fmt.Sprintf("%s Successfully updated entity: %s", constants.APIName(), entityID))
	return nil
}

func (s *EventProcessingService) parseDateTime(dtStr string) (time.Time, error) {
	// Try ISO 8601 formats
	formats := []string{
		time.RFC3339,
		time.RFC3339Nano,
		"2006-01-02T15:04:05Z",
		"2006-01-02T15:04:05.000Z",
		"2006-01-02T15:04:05Z07:00",
	}

	for _, format := range formats {
		if t, err := time.Parse(format, dtStr); err == nil {
			return t, nil
		}
	}

	// Try parsing as Unix timestamp (milliseconds)
	if ms, err := strconv.ParseInt(dtStr, 10, 64); err == nil {
		secs := ms / 1000
		nsecs := (ms % 1000) * 1000000
		return time.Unix(secs, nsecs), nil
	}

	return time.Now(), fmt.Errorf("unable to parse datetime string: %s", dtStr)
}
