package models

import "time"

// CarEntity represents a car entity in the database
type CarEntity struct {
	ID         string     `json:"id"`
	EntityType string     `json:"entity_type"`
	CreatedAt  *time.Time `json:"created_at,omitempty"`
	UpdatedAt  *time.Time `json:"updated_at,omitempty"`
	Data       string     `json:"data"` // JSON string
}

// NewCarEntity creates a new CarEntity with current timestamps
func NewCarEntity(id, entityType, data string) *CarEntity {
	now := time.Now()
	return &CarEntity{
		ID:         id,
		EntityType: entityType,
		CreatedAt:  &now,
		UpdatedAt:  &now,
		Data:       data,
	}
}

