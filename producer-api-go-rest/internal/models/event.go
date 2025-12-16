package models

import (
	"encoding/json"
	"fmt"
	"strconv"
	"time"
)

// Event represents the complete event structure
type Event struct {
	EventHeader EventHeader `json:"eventHeader"`
	Entities    []Entity    `json:"entities"`
}

// EventHeader contains event metadata
type EventHeader struct {
	UUID        *string    `json:"uuid,omitempty"`
	EventName   string     `json:"eventName"`
	CreatedDate *time.Time `json:"createdDate,omitempty"`
	SavedDate   *time.Time `json:"savedDate,omitempty"`
	EventType   *string    `json:"eventType,omitempty"`
}

// EntityHeader contains entity metadata
type EntityHeader struct {
	EntityID   string    `json:"entityId"`
	EntityType string    `json:"entityType"`
	CreatedAt  time.Time `json:"createdAt"`
	UpdatedAt  time.Time `json:"updatedAt"`
}

// UnmarshalJSON implements custom unmarshaling for EntityHeader to handle flexible date parsing
func (eh *EntityHeader) UnmarshalJSON(data []byte) error {
	type Alias EntityHeader
	aux := &struct {
		CreatedAt interface{} `json:"createdAt"`
		UpdatedAt interface{} `json:"updatedAt"`
		*Alias
	}{
		Alias: (*Alias)(eh),
	}

	if err := json.Unmarshal(data, &aux); err != nil {
		return err
	}

	// Parse CreatedAt
	if aux.CreatedAt != nil {
		createdAt, err := parseFlexibleDate(aux.CreatedAt)
		if err != nil {
			return fmt.Errorf("invalid createdAt: %w", err)
		}
		eh.CreatedAt = *createdAt
	}

	// Parse UpdatedAt
	if aux.UpdatedAt != nil {
		updatedAt, err := parseFlexibleDate(aux.UpdatedAt)
		if err != nil {
			return fmt.Errorf("invalid updatedAt: %w", err)
		}
		eh.UpdatedAt = *updatedAt
	}

	return nil
}

// Entity represents a single entity with header and flat properties
// Entity-specific properties are stored in a map for flexible structure
type Entity struct {
	EntityHeader EntityHeader           `json:"entityHeader"`
	Properties   map[string]interface{} `json:"-"`
}

// UnmarshalJSON implements custom unmarshaling to extract entityHeader and store other properties
func (e *Entity) UnmarshalJSON(data []byte) error {
	var raw map[string]interface{}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}

	// Extract entityHeader
	if headerData, ok := raw["entityHeader"]; ok {
		headerBytes, err := json.Marshal(headerData)
		if err != nil {
			return err
		}
		if err := json.Unmarshal(headerBytes, &e.EntityHeader); err != nil {
			return err
		}
		delete(raw, "entityHeader")
	}

	// Store remaining properties
	e.Properties = raw
	return nil
}

// MarshalJSON implements custom marshaling to include entityHeader and properties
func (e *Entity) MarshalJSON() ([]byte, error) {
	result := make(map[string]interface{})
	result["entityHeader"] = e.EntityHeader
	for k, v := range e.Properties {
		result[k] = v
	}
	return json.Marshal(result)
}

// UnmarshalJSON implements custom unmarshaling for EventHeader to handle flexible date parsing
func (eh *EventHeader) UnmarshalJSON(data []byte) error {
	type Alias EventHeader
	aux := &struct {
		CreatedDate interface{} `json:"createdDate,omitempty"`
		SavedDate   interface{} `json:"savedDate,omitempty"`
		*Alias
	}{
		Alias: (*Alias)(eh),
	}

	if err := json.Unmarshal(data, &aux); err != nil {
		return err
	}

	// Parse CreatedDate
	if aux.CreatedDate != nil {
		createdDate, err := parseFlexibleDate(aux.CreatedDate)
		if err != nil {
			return fmt.Errorf("invalid createdDate: %w", err)
		}
		eh.CreatedDate = createdDate
	}

	// Parse SavedDate
	if aux.SavedDate != nil {
		savedDate, err := parseFlexibleDate(aux.SavedDate)
		if err != nil {
			return fmt.Errorf("invalid savedDate: %w", err)
		}
		eh.SavedDate = savedDate
	}

	return nil
}

// parseFlexibleDate handles both ISO 8601 strings and Unix timestamps (milliseconds)
func parseFlexibleDate(v interface{}) (*time.Time, error) {
	switch val := v.(type) {
	case string:
		// Try ISO 8601 formats first
		formats := []string{
			time.RFC3339,
			time.RFC3339Nano,
			"2006-01-02T15:04:05Z",
			"2006-01-02T15:04:05.000Z",
		}
		for _, format := range formats {
			if t, err := time.Parse(format, val); err == nil {
				return &t, nil
			}
		}
		// Try parsing as numeric string (timestamp in milliseconds)
		if ms, err := strconv.ParseInt(val, 10, 64); err == nil {
			secs := ms / 1000
			nsecs := (ms % 1000) * 1000000
			t := time.Unix(secs, nsecs)
			return &t, nil
		}
		return nil, fmt.Errorf("unable to parse date string: %s", val)
	case float64:
		// JSON numbers are parsed as float64
		ms := int64(val)
		secs := ms / 1000
		nsecs := (ms % 1000) * 1000000
		t := time.Unix(secs, nsecs)
		return &t, nil
	case int64:
		ms := val
		secs := ms / 1000
		nsecs := (ms % 1000) * 1000000
		t := time.Unix(secs, nsecs)
		return &t, nil
	default:
		return nil, fmt.Errorf("unsupported date type: %T", v)
	}
}
