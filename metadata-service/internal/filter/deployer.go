package filter

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"go.uber.org/zap"
)

// Deployer handles deployment of Flink SQL statements to Confluent Cloud
type Deployer struct {
	apiKey        string
	apiSecret     string
	environmentID string
	clusterID     string
	computePoolID string
	apiEndpoint   string
	httpClient    *http.Client
	logger        *zap.Logger
}

// NewDeployer creates a new Confluent Cloud deployer
func NewDeployer(logger *zap.Logger) *Deployer {
	return &Deployer{
		apiKey:        os.Getenv("CONFLUENT_CLOUD_API_KEY"),
		apiSecret:     os.Getenv("CONFLUENT_CLOUD_API_SECRET"),
		environmentID: os.Getenv("CONFLUENT_ENVIRONMENT_ID"),
		clusterID:     os.Getenv("CONFLUENT_KAFKA_CLUSTER_ID"),
		computePoolID: os.Getenv("CONFLUENT_FLINK_COMPUTE_POOL_ID"),
		apiEndpoint:   os.Getenv("CONFLUENT_FLINK_API_ENDPOINT"),
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		logger: logger,
	}
}

// FlinkStatement represents a Flink SQL statement
type FlinkStatement struct {
	Name      string `json:"name"`
	Statement string `json:"statement"`
}

// FlinkStatementResponse represents the response from creating a statement
type FlinkStatementResponse struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Status string `json:"status"`
	Error  string `json:"error,omitempty"`
}

// DeployStatements deploys Flink SQL statements to Confluent Cloud
func (d *Deployer) DeployStatements(statements []string, statementNames []string) ([]string, error) {
	if d.apiKey == "" || d.apiSecret == "" {
		return nil, fmt.Errorf("Confluent Cloud API credentials not configured")
	}

	if d.computePoolID == "" {
		return nil, fmt.Errorf("Confluent Cloud compute pool ID not configured")
	}

	if len(statements) != len(statementNames) {
		return nil, fmt.Errorf("statements and statementNames must have the same length")
	}

	var statementIDs []string

	// Deploy each statement
	for i, sql := range statements {
		statementName := statementNames[i]
		if statementName == "" {
			statementName = fmt.Sprintf("statement-%d", i+1)
		}

		statementID, err := d.deployStatement(sql, statementName)
		if err != nil {
			return nil, fmt.Errorf("failed to deploy statement %s: %w", statementName, err)
		}

		statementIDs = append(statementIDs, statementID)
		d.logger.Info("Flink statement deployed",
			zap.String("statementName", statementName),
			zap.String("statementID", statementID))
	}

	return statementIDs, nil
}

// deployStatement deploys a single Flink SQL statement
func (d *Deployer) deployStatement(sql, statementName string) (string, error) {
	// Build API URL
	url := fmt.Sprintf("%s/v1/compute-pools/%s/statements", d.apiEndpoint, d.computePoolID)
	if d.apiEndpoint == "" {
		// Default endpoint if not specified
		url = fmt.Sprintf("https://api.confluent.cloud/flink/v1/compute-pools/%s/statements", d.computePoolID)
	}

	// Create request body
	reqBody := map[string]interface{}{
		"statement": sql,
		"name":      statementName,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	// Create HTTP request
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	// Set headers
	req.SetBasicAuth(d.apiKey, d.apiSecret)
	req.Header.Set("Content-Type", "application/json")

	// Execute request
	resp, err := d.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	// Read response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return "", fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	// Parse response
	var statementResp FlinkStatementResponse
	if err := json.Unmarshal(body, &statementResp); err != nil {
		// If response doesn't match expected format, try to extract ID from response
		var genericResp map[string]interface{}
		if err2 := json.Unmarshal(body, &genericResp); err2 == nil {
			if id, ok := genericResp["id"].(string); ok {
				return id, nil
			}
		}
		return "", fmt.Errorf("failed to parse response: %w, body: %s", err, string(body))
	}

	return statementResp.ID, nil
}

// GetStatementStatus retrieves the status of a Flink statement
func (d *Deployer) GetStatementStatus(statementID string) (string, error) {
	if d.apiKey == "" || d.apiSecret == "" {
		return "", fmt.Errorf("Confluent Cloud API credentials not configured")
	}

	url := fmt.Sprintf("%s/v1/compute-pools/%s/statements/%s", d.apiEndpoint, d.computePoolID, statementID)
	if d.apiEndpoint == "" {
		url = fmt.Sprintf("https://api.confluent.cloud/flink/v1/compute-pools/%s/statements/%s", d.computePoolID, statementID)
	}

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.SetBasicAuth(d.apiKey, d.apiSecret)
	req.Header.Set("Content-Type", "application/json")

	resp, err := d.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	var statementResp FlinkStatementResponse
	if err := json.Unmarshal(body, &statementResp); err != nil {
		// Try to extract status from generic response
		var genericResp map[string]interface{}
		if err2 := json.Unmarshal(body, &genericResp); err2 == nil {
			if status, ok := genericResp["status"].(string); ok {
				return status, nil
			}
		}
		return "", fmt.Errorf("failed to parse response: %w", err)
	}

	return statementResp.Status, nil
}

// DeleteStatement deletes a Flink statement
func (d *Deployer) DeleteStatement(statementID string) error {
	if d.apiKey == "" || d.apiSecret == "" {
		return fmt.Errorf("Confluent Cloud API credentials not configured")
	}

	url := fmt.Sprintf("%s/v1/compute-pools/%s/statements/%s", d.apiEndpoint, d.computePoolID, statementID)
	if d.apiEndpoint == "" {
		url = fmt.Sprintf("https://api.confluent.cloud/flink/v1/compute-pools/%s/statements/%s", d.computePoolID, statementID)
	}

	req, err := http.NewRequest("DELETE", url, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.SetBasicAuth(d.apiKey, d.apiSecret)

	resp, err := d.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	return nil
}

// ValidateConnection validates the connection to Confluent Cloud
func (d *Deployer) ValidateConnection() error {
	if d.apiKey == "" || d.apiSecret == "" {
		return fmt.Errorf("Confluent Cloud API credentials not configured")
	}

	if d.computePoolID == "" {
		return fmt.Errorf("Confluent Cloud compute pool ID not configured")
	}

	// Try to list statements as a connection test
	url := fmt.Sprintf("%s/v1/compute-pools/%s/statements", d.apiEndpoint, d.computePoolID)
	if d.apiEndpoint == "" {
		url = fmt.Sprintf("https://api.confluent.cloud/flink/v1/compute-pools/%s/statements", d.computePoolID)
	}

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.SetBasicAuth(d.apiKey, d.apiSecret)
	req.Header.Set("Content-Type", "application/json")

	resp, err := d.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to connect to Confluent Cloud: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("connection validation failed with status %d: %s", resp.StatusCode, string(body))
	}

	return nil
}

// ExtractStatementNames extracts statement names from SQL
func (d *Deployer) ExtractStatementNames(sql string) []string {
	var names []string
	lines := strings.Split(sql, "\n")

	for _, line := range lines {
		line = strings.TrimSpace(line)
		// Look for CREATE TABLE statements
		if strings.HasPrefix(strings.ToUpper(line), "CREATE TABLE") {
			// Extract table name
			parts := strings.Fields(line)
			for i, part := range parts {
				if strings.ToUpper(part) == "TABLE" && i+1 < len(parts) {
					tableName := strings.Trim(parts[i+1], "`")
					names = append(names, tableName+"-sink")
					break
				}
			}
		}
		// Look for INSERT statements
		if strings.HasPrefix(strings.ToUpper(line), "INSERT INTO") {
			parts := strings.Fields(line)
			for i, part := range parts {
				if strings.ToUpper(part) == "INTO" && i+1 < len(parts) {
					tableName := strings.Trim(parts[i+1], "`")
					names = append(names, tableName+"-insert")
					break
				}
			}
		}
	}

	return names
}
