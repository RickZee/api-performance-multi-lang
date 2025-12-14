package api

import (
	"net/http"
	"strings"
	"time"

	"metadata-service/internal/cache"
	"metadata-service/internal/compat"
	"metadata-service/internal/config"
	"metadata-service/internal/filter"
	"metadata-service/internal/sync"
	"metadata-service/internal/validator"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type Handlers struct {
	config          *config.Config
	cache           *cache.SchemaCache
	gitSync         *sync.GitSync
	validator       *validator.JSONSchemaValidator
	compatChecker   *compat.CompatibilityChecker
	filterStorage   *filter.Storage
	filterGenerator *filter.Generator
	filterDeployer  *filter.Deployer
	logger          *zap.Logger
}

func NewHandlers(cfg *config.Config, schemaCache *cache.SchemaCache, gitSync *sync.GitSync, val *validator.JSONSchemaValidator, compatChecker *compat.CompatibilityChecker, logger *zap.Logger) *Handlers {
	filterStorage := filter.NewStorage(gitSync.GetLocalDir(), logger)
	filterGenerator := filter.NewGenerator(logger)
	filterDeployer := filter.NewDeployer(logger)

	return &Handlers{
		config:          cfg,
		cache:           schemaCache,
		gitSync:         gitSync,
		validator:       val,
		compatChecker:   compatChecker,
		filterStorage:   filterStorage,
		filterGenerator: filterGenerator,
		filterDeployer:  filterDeployer,
		logger:          logger,
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
				Version: version,
				Errors:  []ValidationError{{Field: "", Message: "Failed to load schema"}},
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

// Filter handlers

func (h *Handlers) CreateFilter(c *gin.Context) {
	version := c.DefaultQuery("version", h.config.Validation.DefaultVersion)
	if version == "latest" {
		versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
		if err == nil && len(versions) > 0 {
			version = versions[len(versions)-1]
		}
	}

	var req CreateFilterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body", "details": err.Error()})
		return
	}

	// Convert API request to filter package request
	filterReq := &filter.FilterRequest{
		Name:           req.Name,
		Description:    req.Description,
		ConsumerID:     req.ConsumerID,
		OutputTopic:    req.OutputTopic,
		Conditions:     convertConditionsToFilter(req.Conditions),
		Enabled:        req.Enabled,
		ConditionLogic: req.ConditionLogic,
	}

	f, err := h.filterStorage.Create(version, filterReq)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to create filter", "details": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, FilterResponse{Filter: convertFilterToAPI(f)})
}

func (h *Handlers) ListFilters(c *gin.Context) {
	version := c.DefaultQuery("version", h.config.Validation.DefaultVersion)
	if version == "latest" {
		versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
		if err == nil && len(versions) > 0 {
			version = versions[len(versions)-1]
		}
	}

	filters, err := h.filterStorage.List(version)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list filters", "details": err.Error()})
		return
	}

	responses := make([]FilterResponse, len(filters))
	for i, f := range filters {
		responses[i] = FilterResponse{Filter: convertFilterToAPI(f)}
	}

	c.JSON(http.StatusOK, ListFiltersResponse{
		Filters: responses,
		Total:   len(responses),
	})
}

func (h *Handlers) GetFilter(c *gin.Context) {
	version := c.DefaultQuery("version", h.config.Validation.DefaultVersion)
	if version == "latest" {
		versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
		if err == nil && len(versions) > 0 {
			version = versions[len(versions)-1]
		}
	}

	filterID := c.Param("id")
	f, err := h.filterStorage.Get(version, filterID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Filter not found", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, FilterResponse{Filter: convertFilterToAPI(f)})
}

func (h *Handlers) UpdateFilter(c *gin.Context) {
	version := c.DefaultQuery("version", h.config.Validation.DefaultVersion)
	if version == "latest" {
		versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
		if err == nil && len(versions) > 0 {
			version = versions[len(versions)-1]
		}
	}

	filterID := c.Param("id")
	var req UpdateFilterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body", "details": err.Error()})
		return
	}

	// Convert API request to filter package request
	updateReq := &filter.UpdateFilterRequest{
		Name:           req.Name,
		Description:    req.Description,
		ConsumerID:     req.ConsumerID,
		OutputTopic:    req.OutputTopic,
		Conditions:     convertConditionsToFilter(req.Conditions),
		Enabled:        req.Enabled,
		ConditionLogic: req.ConditionLogic,
	}

	f, err := h.filterStorage.Update(version, filterID, updateReq)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to update filter", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, FilterResponse{Filter: convertFilterToAPI(f)})
}

func (h *Handlers) DeleteFilter(c *gin.Context) {
	version := c.DefaultQuery("version", h.config.Validation.DefaultVersion)
	if version == "latest" {
		versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
		if err == nil && len(versions) > 0 {
			version = versions[len(versions)-1]
		}
	}

	filterID := c.Param("id")
	if err := h.filterStorage.Delete(version, filterID); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Failed to delete filter", "details": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}

func (h *Handlers) GenerateSQL(c *gin.Context) {
	version := c.DefaultQuery("version", h.config.Validation.DefaultVersion)
	if version == "latest" {
		versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
		if err == nil && len(versions) > 0 {
			version = versions[len(versions)-1]
		}
	}

	filterID := c.Param("id")
	f, err := h.filterStorage.Get(version, filterID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Filter not found", "details": err.Error()})
		return
	}

	// Convert to generator's filter type
	genFilter := convertFilterToGenerator(f)
	result, err := h.filterGenerator.GenerateSQL(genFilter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate SQL", "details": err.Error()})
		return
	}

	// Convert response
	apiResponse := GenerateSQLResponse{
		FilterID:         result.FilterID,
		SQL:              result.SQL,
		Statements:       result.Statements,
		Valid:            result.Valid,
		ValidationErrors: result.ValidationErrors,
	}

	c.JSON(http.StatusOK, apiResponse)
}

func (h *Handlers) ValidateSQL(c *gin.Context) {
	var req ValidateSQLRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body", "details": err.Error()})
		return
	}

	// Basic SQL validation - check for required keywords
	errors := []string{}
	warnings := []string{}

	sql := strings.ToUpper(req.SQL)
	if !strings.Contains(sql, "CREATE TABLE") && !strings.Contains(sql, "INSERT INTO") {
		errors = append(errors, "SQL must contain CREATE TABLE or INSERT INTO statement")
	}

	// Check for SQL injection patterns (basic)
	if strings.Contains(req.SQL, "DROP") || strings.Contains(req.SQL, "DELETE") {
		warnings = append(warnings, "SQL contains potentially dangerous operations")
	}

	valid := len(errors) == 0
	c.JSON(http.StatusOK, ValidateSQLResponse{
		Valid:    valid,
		Errors:   errors,
		Warnings: warnings,
	})
}

func (h *Handlers) ApproveFilter(c *gin.Context) {
	version := c.DefaultQuery("version", h.config.Validation.DefaultVersion)
	if version == "latest" {
		versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
		if err == nil && len(versions) > 0 {
			version = versions[len(versions)-1]
		}
	}

	filterID := c.Param("id")
	var req ApproveFilterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		// Allow empty body
		req = ApproveFilterRequest{}
	}

	approvedBy := req.ApprovedBy
	if approvedBy == "" {
		approvedBy = "system" // Default if not provided
	}

	if err := h.filterStorage.Approve(version, filterID, approvedBy); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to approve filter", "details": err.Error()})
		return
	}

	f, _ := h.filterStorage.Get(version, filterID)
	c.JSON(http.StatusOK, FilterResponse{Filter: convertFilterToAPI(f)})
}

func (h *Handlers) DeployFilter(c *gin.Context) {
	version := c.DefaultQuery("version", h.config.Validation.DefaultVersion)
	if version == "latest" {
		versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
		if err == nil && len(versions) > 0 {
			version = versions[len(versions)-1]
		}
	}

	filterID := c.Param("id")
	var req DeployFilterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		req = DeployFilterRequest{}
	}

	f, err := h.filterStorage.Get(version, filterID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Filter not found", "details": err.Error()})
		return
	}

	// Check if filter is approved (unless force is true)
	if !req.Force && f.Status != "approved" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Filter must be approved before deployment", "status": f.Status})
		return
	}

	// Update status to deploying
	if err := h.filterStorage.UpdateStatus(version, filterID, "deploying"); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update filter status", "details": err.Error()})
		return
	}

	// Generate SQL
	genFilter := convertFilterToGenerator(f)
	sqlResult, err := h.filterGenerator.GenerateSQL(genFilter)
	if err != nil {
		h.filterStorage.UpdateStatus(version, filterID, "failed")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate SQL", "details": err.Error()})
		return
	}

	if !sqlResult.Valid {
		h.filterStorage.UpdateStatus(version, filterID, "failed")
		c.JSON(http.StatusBadRequest, gin.H{"error": "Generated SQL is invalid", "validationErrors": sqlResult.ValidationErrors})
		return
	}

	// Extract statement names
	statementNames := h.filterDeployer.ExtractStatementNames(sqlResult.SQL)
	if len(statementNames) == 0 {
		// Generate default names
		statementNames = []string{f.OutputTopic + "-sink", f.OutputTopic + "-insert"}
	}

	// Deploy statements
	statementIDs, err := h.filterDeployer.DeployStatements(sqlResult.Statements, statementNames)
	if err != nil {
		h.filterStorage.UpdateDeployment(version, filterID, nil, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to deploy filter", "details": err.Error()})
		return
	}

	// Update filter with deployment info
	if err := h.filterStorage.UpdateDeployment(version, filterID, statementIDs, nil); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update deployment status", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, DeployFilterResponse{
		FilterID:          filterID,
		Status:            "deployed",
		FlinkStatementIDs: statementIDs,
		Message:           "Filter deployed successfully",
	})
}

func (h *Handlers) GetFilterStatus(c *gin.Context) {
	version := c.DefaultQuery("version", h.config.Validation.DefaultVersion)
	if version == "latest" {
		versions, err := h.cache.GetVersions(h.gitSync.GetLocalDir())
		if err == nil && len(versions) > 0 {
			version = versions[len(versions)-1]
		}
	}

	filterID := c.Param("id")
	f, err := h.filterStorage.Get(version, filterID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Filter not found", "details": err.Error()})
		return
	}

	// Check Flink statement statuses if deployed
	var statementStatuses []string
	if len(f.FlinkStatementIDs) > 0 {
		for _, stmtID := range f.FlinkStatementIDs {
			status, err := h.filterDeployer.GetStatementStatus(stmtID)
			if err != nil {
				statementStatuses = append(statementStatuses, "unknown")
			} else {
				statementStatuses = append(statementStatuses, status)
			}
		}
	}

	lastChecked := time.Now()
	if f.UpdatedAt != nil {
		lastChecked = *f.UpdatedAt
	}

	c.JSON(http.StatusOK, FilterStatusResponse{
		FilterID:          filterID,
		Status:            f.Status,
		FlinkStatementIDs: f.FlinkStatementIDs,
		DeployedAt:        f.DeployedAt,
		DeploymentError:   f.DeploymentError,
		LastChecked:       lastChecked,
	})
}

// Conversion helper functions

func convertConditionsToFilter(conditions []FilterCondition) []filter.FilterCondition {
	result := make([]filter.FilterCondition, len(conditions))
	for i, c := range conditions {
		result[i] = filter.FilterCondition{
			Field:           c.Field,
			Operator:        c.Operator,
			Value:           c.Value,
			Values:          c.Values,
			Min:             c.Min,
			Max:             c.Max,
			ValueType:       c.ValueType,
			LogicalOperator: c.LogicalOperator,
		}
	}
	return result
}

func convertFilterToAPI(f *filter.Filter) Filter {
	return Filter{
		ID:                f.ID,
		Name:              f.Name,
		Description:       f.Description,
		ConsumerID:        f.ConsumerID,
		OutputTopic:       f.OutputTopic,
		Conditions:        convertConditionsToAPI(f.Conditions),
		Enabled:           f.Enabled,
		ConditionLogic:    f.ConditionLogic,
		Status:            f.Status,
		CreatedAt:         f.CreatedAt,
		UpdatedAt:         f.UpdatedAt,
		ApprovedBy:        f.ApprovedBy,
		ApprovedAt:        f.ApprovedAt,
		DeployedAt:        f.DeployedAt,
		DeploymentError:   f.DeploymentError,
		FlinkStatementIDs: f.FlinkStatementIDs,
		Version:           f.Version,
	}
}

func convertConditionsToAPI(conditions []filter.FilterCondition) []FilterCondition {
	result := make([]FilterCondition, len(conditions))
	for i, c := range conditions {
		result[i] = FilterCondition{
			Field:           c.Field,
			Operator:        c.Operator,
			Value:           c.Value,
			Values:          c.Values,
			Min:             c.Min,
			Max:             c.Max,
			ValueType:       c.ValueType,
			LogicalOperator: c.LogicalOperator,
		}
	}
	return result
}

func convertFilterToGenerator(f *filter.Filter) *filter.Filter {
	// The generator uses the same Filter type from the filter package
	return f
}
