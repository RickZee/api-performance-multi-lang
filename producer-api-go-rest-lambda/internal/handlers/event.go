package handlers

import (
	"fmt"
	"net/http"
	"producer-api-go-rest-lambda/internal/errors"
	"producer-api-go-rest-lambda/internal/models"
	"producer-api-go-rest-lambda/internal/service"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"producer-api-go-rest-lambda/internal/constants"
)

type EventHandler struct {
	service *service.EventProcessingService
	logger  *zap.Logger
}

func NewEventHandler(service *service.EventProcessingService, logger *zap.Logger) *EventHandler {
	return &EventHandler{
		service: service,
		logger:  logger,
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

	h.logger.Info(fmt.Sprintf("%s Received event", constants.APIName()), zap.String("event_name", event.EventHeader.EventName))

	if err := h.service.ProcessEvent(c.Request.Context(), &event); err != nil {
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
			h.logger.Error(fmt.Sprintf("%s Error processing event in bulk", constants.APIName()), zap.Error(err))
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

