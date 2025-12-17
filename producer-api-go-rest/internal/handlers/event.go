package handlers

import (
	"fmt"
	"net/http"
	"os"
	"producer-api-go/internal/errors"
	"producer-api-go/internal/metadata"
	"producer-api-go/internal/models"
	"producer-api-go/internal/repository"
	"producer-api-go/internal/service"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"producer-api-go/internal/constants"
)

type EventHandler struct {
	service        *service.EventProcessingService
	metadataClient *metadata.Client
	logger         *zap.Logger
}

func NewEventHandler(service *service.EventProcessingService, logger *zap.Logger) *EventHandler {
	metadataURL := os.Getenv("METADATA_SERVICE_URL")
	metadataTimeout := 5 * time.Second
	if timeoutStr := os.Getenv("METADATA_SERVICE_TIMEOUT"); timeoutStr != "" {
		if timeout, err := time.ParseDuration(timeoutStr); err == nil {
			metadataTimeout = timeout
		}
	}

	metadataClient := metadata.NewClient(metadataURL, metadataTimeout, logger)

	return &EventHandler{
		service:        service,
		metadataClient: metadataClient,
		logger:         logger,
	}
}

func (h *EventHandler) ProcessEvent(c *gin.Context) {
	var event models.Event
	if err := c.ShouldBindJSON(&event); err != nil {
		h.logger.Warn(fmt.Sprintf("%s Invalid JSON", constants.APIName()), zap.Error(err))
		c.JSON(http.StatusBadRequest, gin.H{
			"error":  "Invalid JSON",
			"status": http.StatusBadRequest,
		})
		return
	}

	// Validate event
	if event.EventHeader.EventName == "" {
		c.JSON(http.StatusUnprocessableEntity, gin.H{
			"error":  "Event header event_name is required",
			"status": http.StatusUnprocessableEntity,
		})
		return
	}

	if len(event.EventBody.Entities) == 0 {
		c.JSON(http.StatusUnprocessableEntity, gin.H{
			"error":  "Event body must contain at least one entity",
			"status": http.StatusUnprocessableEntity,
		})
		return
	}

	// Validate each entity
	for _, entity := range event.EventBody.Entities {
		if entity.EntityType == "" {
			c.JSON(http.StatusUnprocessableEntity, gin.H{
				"error":  "Entity type cannot be empty",
				"status": http.StatusUnprocessableEntity,
			})
			return
		}
		if entity.EntityID == "" {
			c.JSON(http.StatusUnprocessableEntity, gin.H{
				"error":  "Entity ID cannot be empty",
				"status": http.StatusUnprocessableEntity,
			})
			return
		}
	}

	// Validate against metadata service
	if h.metadataClient.IsEnabled() {
		validationResult, err := h.metadataClient.ValidateEvent(&event)
		if err != nil {
			h.logger.Warn(fmt.Sprintf("%s Metadata validation error", constants.APIName()), zap.Error(err))
			// Continue processing if validation service is unavailable (fail open)
		} else if !validationResult.Valid {
			h.logger.Warn(fmt.Sprintf("%s Event validation failed", constants.APIName()),
				zap.String("version", validationResult.Version),
				zap.Int("error_count", len(validationResult.Errors)))
			c.JSON(http.StatusUnprocessableEntity, gin.H{
				"error":   "Schema validation failed",
				"details": validationResult.Errors,
				"version": validationResult.Version,
				"status":  http.StatusUnprocessableEntity,
			})
			return
		}
	}

	h.logger.Info(fmt.Sprintf("%s Received event", constants.APIName()), zap.String("event_name", event.EventHeader.EventName))

	if err := h.service.ProcessEvent(c.Request.Context(), &event); err != nil {
		// Check if it's a duplicate event error
		if dupErr, ok := err.(*repository.DuplicateEventError); ok {
			h.logger.Warn(fmt.Sprintf("%s Duplicate event ID: %s", constants.APIName(), dupErr.EventID))
			c.JSON(http.StatusConflict, gin.H{
				"error":   "Conflict",
				"message": dupErr.Message,
				"eventId": dupErr.EventID,
				"status":  http.StatusConflict,
			})
			return
		}

		h.logger.Error(fmt.Sprintf("%s Error processing event", constants.APIName()), zap.Error(err))
		appErr := errors.NewInternalError(err)
		c.JSON(appErr.StatusCode, gin.H{
			"error":  appErr.Message,
			"status": appErr.StatusCode,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Event processed successfully",
	})
}

func (h *EventHandler) ProcessBulkEvents(c *gin.Context) {
	var events []models.Event
	if err := c.ShouldBindJSON(&events); err != nil {
		h.logger.Warn(fmt.Sprintf("%s Invalid JSON", constants.APIName()), zap.Error(err))
		c.JSON(http.StatusBadRequest, gin.H{
			"error":  "Invalid JSON",
			"status": http.StatusBadRequest,
		})
		return
	}

	if len(events) == 0 {
		c.JSON(http.StatusUnprocessableEntity, gin.H{
			"error":  "Invalid request: events list is null or empty",
			"status": http.StatusUnprocessableEntity,
		})
		return
	}

	h.logger.Info(fmt.Sprintf("%s Received bulk request", constants.APIName()), zap.Int("event_count", len(events)))

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

		if err := h.service.ProcessEvent(c.Request.Context(), &event); err != nil {
			// Check if it's a duplicate event error
			if dupErr, ok := err.(*repository.DuplicateEventError); ok {
				h.logger.Warn(fmt.Sprintf("%s Duplicate event ID in bulk: %s", constants.APIName(), dupErr.EventID))
			} else {
				h.logger.Error(fmt.Sprintf("%s Error processing event in bulk", constants.APIName()), zap.Error(err))
			}
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

	c.JSON(http.StatusOK, gin.H{
		"success":          success,
		"message":          message,
		"processedCount":   processedCount,
		"failedCount":      failedCount,
		"batchId":          fmt.Sprintf("batch-%d", time.Now().UnixMilli()),
		"processingTimeMs": 100,
	})
}
