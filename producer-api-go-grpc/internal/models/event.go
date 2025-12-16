package models

import (
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"producer-api-go-grpc/proto"
)

// Event represents the complete event structure (converted from protobuf)
type Event struct {
	EventHeader EventHeader
	Entities    []Entity
}

// EventHeader contains event metadata
type EventHeader struct {
	UUID        *string
	EventName   string
	CreatedDate *time.Time
	SavedDate   *time.Time
	EventType   *string
}

// EntityHeader contains entity metadata
type EntityHeader struct {
	EntityID   string
	EntityType string
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

// Entity represents a single entity with header and flat properties
// The entity-specific properties are stored as raw JSON to allow flexible structure
type Entity struct {
	EntityHeader EntityHeader
	// Additional entity-specific fields are stored as raw JSON
	// These will be unmarshaled separately when needed
	RawData json.RawMessage
}

// ConvertFromProto converts a protobuf EventRequest to internal Event model
func ConvertFromProto(req *proto.EventRequest) (*Event, error) {
	if req == nil {
		return nil, fmt.Errorf("request is nil")
	}

	event := &Event{}

	// Convert EventHeader
	if req.EventHeader != nil {
		event.EventHeader.EventName = req.EventHeader.EventName
		if req.EventHeader.Uuid != "" {
			event.EventHeader.UUID = &req.EventHeader.Uuid
		}
		if req.EventHeader.EventType != "" {
			event.EventHeader.EventType = &req.EventHeader.EventType
		}

		// Parse dates
		if req.EventHeader.CreatedDate != "" {
			if t, err := parseFlexibleDate(req.EventHeader.CreatedDate); err == nil {
				event.EventHeader.CreatedDate = t
			}
		}
		if req.EventHeader.SavedDate != "" {
			if t, err := parseFlexibleDate(req.EventHeader.SavedDate); err == nil {
				event.EventHeader.SavedDate = t
			}
		}
	}

	// Convert entities
	entities := make([]Entity, 0, len(req.Entities))
	for _, protoEntity := range req.Entities {
		if protoEntity.EntityHeader == nil {
			return nil, fmt.Errorf("entity missing entityHeader")
		}

		// Parse entityHeader dates
		createdAt, err := parseFlexibleDate(protoEntity.EntityHeader.CreatedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to parse createdAt: %w", err)
		}
		updatedAt, err := parseFlexibleDate(protoEntity.EntityHeader.UpdatedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to parse updatedAt: %w", err)
		}

		entityHeader := EntityHeader{
			EntityID:   protoEntity.EntityHeader.EntityId,
			EntityType: protoEntity.EntityHeader.EntityType,
			CreatedAt:  *createdAt,
			UpdatedAt:  *updatedAt,
		}

		// Convert properties_json to map
		var properties map[string]interface{}
		if protoEntity.PropertiesJson != "" {
			if err := json.Unmarshal([]byte(protoEntity.PropertiesJson), &properties); err != nil {
				return nil, fmt.Errorf("failed to parse properties_json: %w", err)
			}
		} else {
			properties = make(map[string]interface{})
		}

		entities = append(entities, Entity{
			EntityHeader: entityHeader,
			Properties:   properties,
		})
	}
	event.Entities = entities

	return event, nil
}

// parseFlexibleDate handles both ISO 8601 strings and Unix timestamps (milliseconds)
func parseFlexibleDate(v string) (*time.Time, error) {
	if v == "" {
		return nil, nil
	}

	// Try ISO 8601 formats first
	formats := []string{
		time.RFC3339,
		time.RFC3339Nano,
		"2006-01-02T15:04:05Z",
		"2006-01-02T15:04:05.000Z",
		"2006-01-02T15:04:05Z07:00",
	}
	for _, format := range formats {
		if t, err := time.Parse(format, v); err == nil {
			return &t, nil
		}
	}

	// Try parsing as numeric string (timestamp in milliseconds)
	if ms, err := strconv.ParseInt(v, 10, 64); err == nil {
		secs := ms / 1000
		nsecs := (ms % 1000) * 1000000
		t := time.Unix(secs, nsecs)
		return &t, nil
	}

	return nil, fmt.Errorf("unable to parse date string: %s", v)
}
