package metadata

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"go.uber.org/zap"
)

type Client struct {
	baseURL    string
	httpClient *http.Client
	logger     *zap.Logger
	enabled    bool
}

type ValidateEventRequest struct {
	Event   interface{} `json:"event"`
	Version string      `json:"version,omitempty"`
}

type ValidateEventResponse struct {
	Valid   bool              `json:"valid"`
	Errors  []ValidationError `json:"errors,omitempty"`
	Version string            `json:"version"`
}

type ValidationError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
}

func NewClient(baseURL string, timeout time.Duration, logger *zap.Logger) *Client {
	enabled := baseURL != ""
	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: timeout,
		},
		logger:  logger,
		enabled: enabled,
	}
}

func (c *Client) IsEnabled() bool {
	return c.enabled
}

func (c *Client) ValidateEvent(event interface{}) (*ValidateEventResponse, error) {
	if !c.enabled {
		return &ValidateEventResponse{Valid: true}, nil
	}

	reqBody := ValidateEventRequest{
		Event: event,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	url := fmt.Sprintf("%s/api/v1/validate", c.baseURL)
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		c.logger.Warn("Metadata service unavailable, skipping validation", zap.Error(err))
		// Fail open: if service is unavailable, allow the event through
		return &ValidateEventResponse{Valid: true}, nil
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusUnprocessableEntity {
		c.logger.Warn("Metadata service returned unexpected status",
			zap.Int("status", resp.StatusCode))
		// Fail open on unexpected status
		return &ValidateEventResponse{Valid: true}, nil
	}

	var validationResp ValidateEventResponse
	if err := json.NewDecoder(resp.Body).Decode(&validationResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &validationResp, nil
}
