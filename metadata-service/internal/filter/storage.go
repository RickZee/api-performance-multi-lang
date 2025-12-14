package filter

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"go.uber.org/zap"
)

// Storage handles filter persistence in git repository
type Storage struct {
	baseDir string
	mu      sync.RWMutex
	logger  *zap.Logger
}

// NewStorage creates a new filter storage instance
func NewStorage(baseDir string, logger *zap.Logger) *Storage {
	return &Storage{
		baseDir: baseDir,
		logger:  logger,
	}
}

// getFiltersDir returns the path to the filters directory
func (s *Storage) getFiltersDir(version string) string {
	// Check if baseDir contains a "schemas" subdirectory (git repo structure)
	schemasSubDir := filepath.Join(s.baseDir, "schemas")
	if _, err := os.Stat(schemasSubDir); err == nil {
		return filepath.Join(schemasSubDir, version, "filters")
	}
	return filepath.Join(s.baseDir, "schemas", version, "filters")
}

// ensureFiltersDir creates the filters directory if it doesn't exist
func (s *Storage) ensureFiltersDir(version string) error {
	filtersDir := s.getFiltersDir(version)
	if err := os.MkdirAll(filtersDir, 0755); err != nil {
		return fmt.Errorf("failed to create filters directory: %w", err)
	}
	return nil
}

// FilterRequest represents a request to create a filter
type FilterRequest struct {
	Name           string
	Description    string
	ConsumerID     string
	OutputTopic    string
	Conditions     []FilterCondition
	Enabled        bool
	ConditionLogic string
}

// Filter represents a filter configuration
type Filter struct {
	ID                string
	Name              string
	Description       string
	ConsumerID        string
	OutputTopic       string
	Conditions        []FilterCondition
	Enabled           bool
	ConditionLogic    string
	Status            string
	CreatedAt         *time.Time
	UpdatedAt         *time.Time
	ApprovedBy        string
	ApprovedAt        *time.Time
	DeployedAt        *time.Time
	DeploymentError   string
	FlinkStatementIDs []string
	Version           int
}

// FilterCondition represents a filter condition
type FilterCondition struct {
	Field           string
	Operator        string
	Value           interface{}
	Values          []interface{}
	Min             interface{}
	Max             interface{}
	ValueType       string
	LogicalOperator string
}

// Create creates a new filter
func (s *Storage) Create(version string, req *FilterRequest) (*Filter, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Generate filter ID from name if not provided
	filterID := generateFilterID(req.Name)

	// Check if filter already exists
	if _, err := s.Get(version, filterID); err == nil {
		return nil, fmt.Errorf("filter with ID %s already exists", filterID)
	}

	now := time.Now()
	filter := &Filter{
		ID:             filterID,
		Name:           req.Name,
		Description:    req.Description,
		ConsumerID:     req.ConsumerID,
		OutputTopic:    req.OutputTopic,
		Conditions:     req.Conditions,
		Enabled:        req.Enabled,
		ConditionLogic: req.ConditionLogic,
		Status:         "pending_approval",
		CreatedAt:      &now,
		UpdatedAt:      &now,
		Version:        1,
	}

	if filter.ConditionLogic == "" {
		filter.ConditionLogic = "AND"
	}

	if err := s.save(version, filter); err != nil {
		return nil, err
	}

	s.logger.Info("Filter created",
		zap.String("version", version),
		zap.String("filterId", filter.ID),
		zap.String("name", filter.Name))

	return filter, nil
}

// Get retrieves a filter by ID
func (s *Storage) Get(version, filterID string) (*Filter, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	filtersDir := s.getFiltersDir(version)
	filterPath := filepath.Join(filtersDir, filterID+".json")

	data, err := os.ReadFile(filterPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("filter %s not found", filterID)
		}
		return nil, fmt.Errorf("failed to read filter: %w", err)
	}

	var filter Filter
	if err := json.Unmarshal(data, &filter); err != nil {
		return nil, fmt.Errorf("failed to parse filter: %w", err)
	}

	return &filter, nil
}

// List retrieves all filters for a version
func (s *Storage) List(version string) ([]*Filter, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	filtersDir := s.getFiltersDir(version)

	// Check if directory exists
	if _, err := os.Stat(filtersDir); os.IsNotExist(err) {
		return []*Filter{}, nil
	}

	entries, err := os.ReadDir(filtersDir)
	if err != nil {
		return nil, fmt.Errorf("failed to read filters directory: %w", err)
	}

	var filters []*Filter
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}

		filterPath := filepath.Join(filtersDir, entry.Name())
		data, err := os.ReadFile(filterPath)
		if err != nil {
			s.logger.Warn("Failed to read filter file",
				zap.String("path", filterPath),
				zap.Error(err))
			continue
		}

		var filter Filter
		if err := json.Unmarshal(data, &filter); err != nil {
			s.logger.Warn("Failed to parse filter file",
				zap.String("path", filterPath),
				zap.Error(err))
			continue
		}

		filters = append(filters, &filter)
	}

	return filters, nil
}

// UpdateFilterRequest represents a request to update a filter
type UpdateFilterRequest struct {
	Name           string
	Description    string
	ConsumerID     string
	OutputTopic    string
	Conditions     []FilterCondition
	Enabled        *bool
	ConditionLogic string
}

// Update updates an existing filter
func (s *Storage) Update(version, filterID string, req *UpdateFilterRequest) (*Filter, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	filter, err := s.Get(version, filterID)
	if err != nil {
		return nil, err
	}

	// Update fields if provided
	if req.Name != "" {
		filter.Name = req.Name
	}
	if req.Description != "" {
		filter.Description = req.Description
	}
	if req.ConsumerID != "" {
		filter.ConsumerID = req.ConsumerID
	}
	if req.OutputTopic != "" {
		filter.OutputTopic = req.OutputTopic
	}
	if len(req.Conditions) > 0 {
		filter.Conditions = req.Conditions
	}
	if req.Enabled != nil {
		filter.Enabled = *req.Enabled
	}
	if req.ConditionLogic != "" {
		filter.ConditionLogic = req.ConditionLogic
	}

	now := time.Now()
	filter.UpdatedAt = &now
	filter.Version++

	if err := s.save(version, filter); err != nil {
		return nil, err
	}

	s.logger.Info("Filter updated",
		zap.String("version", version),
		zap.String("filterId", filter.ID))

	return filter, nil
}

// Delete deletes a filter
func (s *Storage) Delete(version, filterID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	filtersDir := s.getFiltersDir(version)
	filterPath := filepath.Join(filtersDir, filterID+".json")

	if err := os.Remove(filterPath); err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf("filter %s not found", filterID)
		}
		return fmt.Errorf("failed to delete filter: %w", err)
	}

	s.logger.Info("Filter deleted",
		zap.String("version", version),
		zap.String("filterId", filterID))

	return nil
}

// UpdateStatus updates the status of a filter
func (s *Storage) UpdateStatus(version, filterID, status string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	filter, err := s.Get(version, filterID)
	if err != nil {
		return err
	}

	filter.Status = status
	now := time.Now()
	filter.UpdatedAt = &now

	if err := s.save(version, filter); err != nil {
		return err
	}

	return nil
}

// Approve marks a filter as approved
func (s *Storage) Approve(version, filterID, approvedBy string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	filter, err := s.Get(version, filterID)
	if err != nil {
		return err
	}

	filter.Status = "approved"
	filter.ApprovedBy = approvedBy
	now := time.Now()
	filter.ApprovedAt = &now
	filter.UpdatedAt = &now

	if err := s.save(version, filter); err != nil {
		return err
	}

	s.logger.Info("Filter approved",
		zap.String("version", version),
		zap.String("filterId", filter.ID),
		zap.String("approvedBy", approvedBy))

	return nil
}

// UpdateDeployment updates deployment information for a filter
func (s *Storage) UpdateDeployment(version, filterID string, statementIDs []string, err error) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	filter, e := s.Get(version, filterID)
	if e != nil {
		return e
	}

	now := time.Now()
	filter.UpdatedAt = &now

	if err != nil {
		filter.Status = "failed"
		filter.DeploymentError = err.Error()
	} else {
		filter.Status = "deployed"
		filter.DeployedAt = &now
		filter.FlinkStatementIDs = statementIDs
		filter.DeploymentError = ""
	}

	if e := s.save(version, filter); e != nil {
		return e
	}

	return nil
}

// save writes a filter to disk
func (s *Storage) save(version string, filter *Filter) error {
	if err := s.ensureFiltersDir(version); err != nil {
		return err
	}

	filtersDir := s.getFiltersDir(version)
	filterPath := filepath.Join(filtersDir, filter.ID+".json")

	data, err := json.MarshalIndent(filter, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal filter: %w", err)
	}

	if err := os.WriteFile(filterPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write filter: %w", err)
	}

	return nil
}

// generateFilterID generates a filter ID from a name
func generateFilterID(name string) string {
	// Simple implementation: convert to lowercase, replace spaces with hyphens
	id := ""
	for _, r := range name {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			id += string(r)
		} else if r >= 'A' && r <= 'Z' {
			id += string(r + 32) // Convert to lowercase
		} else if r == ' ' || r == '_' {
			id += "-"
		}
	}
	// Remove consecutive hyphens
	result := ""
	prev := ' '
	for _, r := range id {
		if r != '-' || prev != '-' {
			result += string(r)
		}
		prev = r
	}
	// Remove leading/trailing hyphens
	if len(result) > 0 && result[0] == '-' {
		result = result[1:]
	}
	if len(result) > 0 && result[len(result)-1] == '-' {
		result = result[:len(result)-1]
	}
	return result
}
