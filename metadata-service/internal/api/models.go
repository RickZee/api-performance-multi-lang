package api

type ValidateEventRequest struct {
	Event   interface{} `json:"event"`
	Version string       `json:"version,omitempty"` // Optional: specific version to validate against
}

type ValidateBulkEventsRequest struct {
	Events  []interface{} `json:"events"`
	Version string         `json:"version,omitempty"`
}

type ValidationError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
}

type ValidateEventResponse struct {
	Valid   bool              `json:"valid"`
	Errors  []ValidationError  `json:"errors,omitempty"`
	Version string            `json:"version"`
}

type ValidateBulkEventsResponse struct {
	Results []ValidateEventResponse `json:"results"`
	Summary BulkSummary             `json:"summary"`
}

type BulkSummary struct {
	Total    int `json:"total"`
	Valid    int `json:"valid"`
	Invalid  int `json:"invalid"`
}

type VersionsResponse struct {
	Versions []string `json:"versions"`
	Default  string   `json:"default"`
}

type SchemaResponse struct {
	Version string                 `json:"version"`
	Schema  map[string]interface{} `json:"schema"`
}

type HealthResponse struct {
	Status  string `json:"status"`
	Version string `json:"version,omitempty"`
}

