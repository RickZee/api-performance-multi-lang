package api

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"metadata-service/internal/cache"
	"metadata-service/internal/compat"
	"metadata-service/internal/config"
	"metadata-service/internal/sync"
	"metadata-service/internal/validator"
)

type Handlers struct {
	config          *config.Config
	cache           *cache.SchemaCache
	gitSync         *sync.GitSync
	validator       *validator.JSONSchemaValidator
	compatChecker   *compat.CompatibilityChecker
	logger          *zap.Logger
}

func NewHandlers(cfg *config.Config, schemaCache *cache.SchemaCache, gitSync *sync.GitSync, val *validator.JSONSchemaValidator, compatChecker *compat.CompatibilityChecker, logger *zap.Logger) *Handlers {
	return &Handlers{
		config:        cfg,
		cache:         schemaCache,
		gitSync:       gitSync,
		validator:     val,
		compatChecker: compatChecker,
		logger:        logger,
	}
}

func (h *Handlers) ValidateEvent(c *gin.Context) {
	var req ValidateEventRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body", "details": err.Error()})
		return
	}

	// Determine version to use
	version := req.Version
	if version == "" {
		version = h.config.Validation.DefaultVersion
	}
	if version == "latest" {
		versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
		if err != nil || len(versions) == 0 {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get schema versions"})
			return
		}
		version = versions[len(versions)-1] // Use last version as latest
	}

	// Validate against multiple versions if configured
	acceptedVersions := h.config.Validation.AcceptedVersions
	if len(acceptedVersions) == 0 {
		acceptedVersions = []string{version}
	}

	var validationResult *validator.ValidationResult
	var validatedVersion string

	for _, v := range acceptedVersions {
		if v == "latest" {
			v = version
		}
		schema, err := h.cache.LoadVersion(v, h.gitSync.GetLocalDir())
		if err != nil {
			continue
		}

		result, err := h.validator.ValidateEvent(req.Event, schema.EventSchema, schema.EntitySchemas, h.gitSync.GetLocalDir())
		if err != nil {
			h.logger.Warn("Validation error", zap.String("version", v), zap.Error(err))
			continue
		}

		if result.Valid {
			validationResult = result
			validatedVersion = v
			break
		}

		// If this is the first attempt, store it
		if validationResult == nil {
			validationResult = result
			validatedVersion = v
		}
	}

	if validationResult == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to validate event"})
		return
	}

	response := ValidateEventResponse{
		Valid:   validationResult.Valid,
		Version: validatedVersion,
	}

	if !validationResult.Valid {
		response.Errors = make([]ValidationError, len(validationResult.Errors))
		for i, err := range validationResult.Errors {
			response.Errors[i] = ValidationError{
				Field:   err.Field,
				Message: err.Message,
			}
		}

		if h.config.Validation.StrictMode {
			c.JSON(http.StatusUnprocessableEntity, response)
			return
		}
	}

	c.JSON(http.StatusOK, response)
}

func (h *Handlers) ValidateBulkEvents(c *gin.Context) {
	var req ValidateBulkEventsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body", "details": err.Error()})
		return
	}

	results := make([]ValidateEventResponse, len(req.Events))
	summary := BulkSummary{
		Total: len(req.Events),
	}

	for i, event := range req.Events {
		// Create a temporary request for each event
		eventReq := ValidateEventRequest{
			Event:   event,
			Version: req.Version,
		}

		// Use internal validation logic
		version := eventReq.Version
		if version == "" {
			version = h.config.Validation.DefaultVersion
		}
		if version == "latest" {
			versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
			if err == nil && len(versions) > 0 {
				version = versions[len(versions)-1]
			}
		}

		cachedSchema, err := h.cache.LoadVersion(version, h.gitSync.GetLocalDir())
		if err != nil {
			results[i] = ValidateEventResponse{
				Valid:   false,
				Version:  version,
				Errors:   []ValidationError{{Field: "", Message: "Failed to load schema"}},
			}
			summary.Invalid++
			continue
		}

		result, err := h.validator.ValidateEvent(event, cachedSchema.EventSchema, cachedSchema.EntitySchemas, h.gitSync.GetLocalDir())
		if err != nil {
			results[i] = ValidateEventResponse{
				Valid:   false,
				Version: version,
				Errors:  []ValidationError{{Field: "", Message: err.Error()}},
			}
			summary.Invalid++
			continue
		}

		response := ValidateEventResponse{
			Valid:   result.Valid,
			Version: version,
		}

		if !result.Valid {
			response.Errors = make([]ValidationError, len(result.Errors))
			for j, err := range result.Errors {
				response.Errors[j] = ValidationError{
					Field:   err.Field,
					Message: err.Message,
				}
			}
			summary.Invalid++
		} else {
			summary.Valid++
		}

		results[i] = response
	}

	response := ValidateBulkEventsResponse{
		Results: results,
		Summary: summary,
	}

	statusCode := http.StatusOK
	if h.config.Validation.StrictMode && summary.Invalid > 0 {
		statusCode = http.StatusUnprocessableEntity
	}

	c.JSON(statusCode, response)
}

func (h *Handlers) GetVersions(c *gin.Context) {
	versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get versions", "details": err.Error()})
		return
	}

	response := VersionsResponse{
		Versions: versions,
		Default:  h.config.Validation.DefaultVersion,
	}

	c.JSON(http.StatusOK, response)
}

func (h *Handlers) GetSchema(c *gin.Context) {
	version := c.Param("version")
	if version == "" {
		version = h.config.Validation.DefaultVersion
	}
	if version == "latest" {
		versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
		if err != nil || len(versions) == 0 {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get schema versions"})
			return
		}
		version = versions[len(versions)-1]
	}

	schemaType := c.Query("type")
	if schemaType == "" {
		schemaType = "event"
	}

	cachedSchema, err := h.cache.LoadVersion(version, h.gitSync.GetLocalDir())
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Schema version not found", "version": version})
		return
	}

	var schema map[string]interface{}
	switch strings.ToLower(schemaType) {
	case "event":
		schema = cachedSchema.EventSchema
	default:
		if entitySchema, ok := cachedSchema.EntitySchemas[schemaType]; ok {
			schema = entitySchema
		} else {
			c.JSON(http.StatusNotFound, gin.H{"error": "Schema type not found", "type": schemaType})
			return
		}
	}

	response := SchemaResponse{
		Version: version,
		Schema:  schema,
	}

	c.JSON(http.StatusOK, response)
}

func (h *Handlers) Health(c *gin.Context) {
	response := HealthResponse{
		Status: "healthy",
	}

	versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
	if err == nil && len(versions) > 0 {
		response.Version = versions[len(versions)-1]
	}

	c.JSON(http.StatusOK, response)
}

