package api

import "time"

// FilterCondition represents a single filter condition
type FilterCondition struct {
	Field           string        `json:"field"`
	Operator        string        `json:"operator"`
	Value           interface{}   `json:"value,omitempty"`
	Values          []interface{} `json:"values,omitempty"`
	Min             interface{}   `json:"min,omitempty"`
	Max             interface{}   `json:"max,omitempty"`
	ValueType       string        `json:"valueType,omitempty"`
	LogicalOperator string        `json:"logicalOperator,omitempty"`
}

// Filter represents a complete filter configuration
type Filter struct {
	ID                string            `json:"id"`
	Name              string            `json:"name"`
	Description       string            `json:"description,omitempty"`
	ConsumerID        string            `json:"consumerId"`
	OutputTopic       string            `json:"outputTopic"`
	Conditions        []FilterCondition `json:"conditions"`
	Enabled           bool              `json:"enabled"`
	ConditionLogic    string            `json:"conditionLogic,omitempty"`
	Status            string            `json:"status,omitempty"`
	CreatedAt         *time.Time        `json:"createdAt,omitempty"`
	UpdatedAt         *time.Time        `json:"updatedAt,omitempty"`
	ApprovedBy        string            `json:"approvedBy,omitempty"`
	ApprovedAt        *time.Time        `json:"approvedAt,omitempty"`
	DeployedAt        *time.Time        `json:"deployedAt,omitempty"`
	DeploymentError   string            `json:"deploymentError,omitempty"`
	FlinkStatementIDs []string          `json:"flinkStatementIds,omitempty"`
	Version           int               `json:"version,omitempty"`
}

// CreateFilterRequest represents a request to create a new filter
type CreateFilterRequest struct {
	Name           string            `json:"name" binding:"required"`
	Description    string            `json:"description,omitempty"`
	ConsumerID     string            `json:"consumerId" binding:"required"`
	OutputTopic    string            `json:"outputTopic" binding:"required"`
	Conditions     []FilterCondition `json:"conditions" binding:"required,min=1"`
	Enabled        bool              `json:"enabled"`
	ConditionLogic string            `json:"conditionLogic,omitempty"`
}

// UpdateFilterRequest represents a request to update an existing filter
type UpdateFilterRequest struct {
	Name           string            `json:"name,omitempty"`
	Description    string            `json:"description,omitempty"`
	ConsumerID     string            `json:"consumerId,omitempty"`
	OutputTopic    string            `json:"outputTopic,omitempty"`
	Conditions     []FilterCondition `json:"conditions,omitempty"`
	Enabled        *bool             `json:"enabled,omitempty"`
	ConditionLogic string            `json:"conditionLogic,omitempty"`
}

// FilterResponse represents a filter in API responses
type FilterResponse struct {
	Filter
}

// ListFiltersResponse represents a response containing multiple filters
type ListFiltersResponse struct {
	Filters []FilterResponse `json:"filters"`
	Total   int              `json:"total"`
}

// GenerateSQLResponse represents the response from SQL generation
type GenerateSQLResponse struct {
	FilterID         string   `json:"filterId"`
	SQL              string   `json:"sql"`
	Statements       []string `json:"statements"` // Individual SQL statements
	Valid            bool     `json:"valid"`
	ValidationErrors []string `json:"validationErrors,omitempty"`
}

// ValidateSQLRequest represents a request to validate generated SQL
type ValidateSQLRequest struct {
	SQL string `json:"sql" binding:"required"`
}

// ValidateSQLResponse represents the response from SQL validation
type ValidateSQLResponse struct {
	Valid    bool     `json:"valid"`
	Errors   []string `json:"errors,omitempty"`
	Warnings []string `json:"warnings,omitempty"`
}

// ApproveFilterRequest represents a request to approve a filter
type ApproveFilterRequest struct {
	ApprovedBy string `json:"approvedBy,omitempty"`
	Notes      string `json:"notes,omitempty"`
}

// DeployFilterRequest represents a request to deploy a filter
type DeployFilterRequest struct {
	Force bool `json:"force,omitempty"` // Force deployment even if not approved
}

// DeployFilterResponse represents the response from filter deployment
type DeployFilterResponse struct {
	FilterID          string   `json:"filterId"`
	Status            string   `json:"status"`
	FlinkStatementIDs []string `json:"flinkStatementIds,omitempty"`
	Message           string   `json:"message"`
	Error             string   `json:"error,omitempty"`
}

// FilterStatusResponse represents the deployment status of a filter
type FilterStatusResponse struct {
	FilterID          string     `json:"filterId"`
	Status            string     `json:"status"`
	FlinkStatementIDs []string   `json:"flinkStatementIds,omitempty"`
	DeployedAt        *time.Time `json:"deployedAt,omitempty"`
	DeploymentError   string     `json:"deploymentError,omitempty"`
	LastChecked       time.Time  `json:"lastChecked"`
}
