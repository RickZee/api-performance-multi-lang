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
	EventBody   EventBody
}

// EventHeader contains event metadata
type EventHeader struct {
	UUID        *string
	EventName   string
	CreatedDate *time.Time
	SavedDate   *time.Time
	EventType   *string
}

// EventBody contains the entity updates
type EventBody struct {
	Entities []EntityUpdate
}

// EntityUpdate represents a single entity update
type EntityUpdate struct {
	EntityType        string
	EntityID          string
	UpdatedAttributes json.RawMessage
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

	// Convert EventBody
	if req.EventBody != nil {
		entities := make([]EntityUpdate, 0, len(req.EventBody.Entities))
		for _, protoEntity := range req.EventBody.Entities {
			// Convert map[string]string to JSON
			updatedAttrsJSON, err := json.Marshal(protoEntity.UpdatedAttributes)
			if err != nil {
				return nil, fmt.Errorf("failed to marshal updated attributes: %w", err)
			}

			entities = append(entities, EntityUpdate{
				EntityType:        protoEntity.EntityType,
				EntityID:          protoEntity.EntityId,
				UpdatedAttributes: updatedAttrsJSON,
			})
		}
		event.EventBody.Entities = entities
	}

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

