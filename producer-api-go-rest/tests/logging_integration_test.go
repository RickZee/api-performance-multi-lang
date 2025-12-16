package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"producer-api-go/internal/constants"
	"producer-api-go/internal/handlers"
	"producer-api-go/internal/repository"
	"producer-api-go/internal/service"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

// LogCapture is a custom zap core that captures log messages
type LogCapture struct {
	zapcore.LevelEnabler
	mu       sync.Mutex
	messages []string
}

func NewLogCapture(level zapcore.Level) *LogCapture {
	return &LogCapture{
		LevelEnabler: level,
		messages:     make([]string, 0),
	}
}

func (lc *LogCapture) Enabled(level zapcore.Level) bool {
	return lc.LevelEnabler.Enabled(level)
}

func (lc *LogCapture) With(fields []zapcore.Field) zapcore.Core {
	return lc
}

func (lc *LogCapture) Check(entry zapcore.Entry, checked *zapcore.CheckedEntry) *zapcore.CheckedEntry {
	if lc.Enabled(entry.Level) {
		return checked.AddCore(entry, lc)
	}
	return checked
}

func (lc *LogCapture) Write(entry zapcore.Entry, fields []zapcore.Field) error {
	lc.mu.Lock()
	defer lc.mu.Unlock()

	var buf bytes.Buffer
	buf.WriteString(entry.Message)
	for _, field := range fields {
		buf.WriteString(" ")
		buf.WriteString(field.Key)
		buf.WriteString("=")
		buf.WriteString(fmt.Sprintf("%v", field.Interface))
	}
	lc.messages = append(lc.messages, buf.String())
	return nil
}

func (lc *LogCapture) Sync() error {
	return nil
}

func (lc *LogCapture) GetMessages() []string {
	lc.mu.Lock()
	defer lc.mu.Unlock()
	result := make([]string, len(lc.messages))
	copy(result, lc.messages)
	return result
}

func (lc *LogCapture) Contains(pattern string) bool {
	lc.mu.Lock()
	defer lc.mu.Unlock()
	for _, msg := range lc.messages {
		if strings.Contains(msg, pattern) {
			return true
		}
	}
	return false
}

func createTestServerWithLogCapture(t *testing.T, pool *pgxpool.Pool, logCapture *LogCapture) *gin.Engine {
	gin.SetMode(gin.TestMode)

	// Create logger with log capture
	core := zapcore.NewTee(
		logCapture,
		zapcore.NewCore(
			zapcore.NewConsoleEncoder(zap.NewDevelopmentEncoderConfig()),
			zapcore.AddSync(os.Stderr),
			zapcore.DebugLevel,
		),
	)
	logger := zap.New(core)

	repo := repository.NewCarEntityRepository(pool)
	eventService := service.NewEventProcessingService(repo, logger)

	eventHandler := handlers.NewEventHandler(eventService, logger)
	healthHandler := handlers.NewHealthHandler()

	router := gin.New()
	router.Use(gin.Recovery())

	api := router.Group("/api/v1/events")
	{
		api.POST("", eventHandler.ProcessEvent)
		api.POST("/bulk", eventHandler.ProcessBulkEvents)
		api.GET("/health", healthHandler.HealthCheck)
	}

	return router
}

func TestProcessEventShouldLogProcessingEventWithAPIName(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	logCapture := NewLogCapture(zapcore.InfoLevel)
	router := createTestServerWithLogCapture(t, pool, logCapture)

	event := createTestEvent()
	body, _ := json.Marshal(event)

	req := httptest.NewRequest("POST", "/api/v1/events", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("Expected status 200, got %d: %s", w.Code, w.Body.String())
	}

	// Small delay to ensure logs are captured
	time.Sleep(100 * time.Millisecond)

	// Verify logs contain API name and processing event message
	if !logCapture.Contains(constants.APIName()) {
		t.Error("Logs should contain API name")
	}
	if !logCapture.Contains("Processing event") {
		t.Error("Logs should contain 'Processing event' message")
	}
}

func TestProcessEventShouldLogSuccessfullyCreatedEntityWithAPIName(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	logCapture := NewLogCapture(zapcore.InfoLevel)
	router := createTestServerWithLogCapture(t, pool, logCapture)

	event := createTestEvent()
	body, _ := json.Marshal(event)

	req := httptest.NewRequest("POST", "/api/v1/events", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("Expected status 200, got %d: %s", w.Code, w.Body.String())
	}

	// Small delay to ensure logs are captured
	time.Sleep(100 * time.Millisecond)

	// Verify logs contain API name and success message
	if !logCapture.Contains(constants.APIName()) {
		t.Error("Logs should contain API name")
	}
	if !logCapture.Contains("Successfully created entity") {
		t.Error("Logs should contain 'Successfully created entity' message")
	}

	// Verify entity was created in database
	ctx := context.Background()
	repo := repository.NewCarEntityRepository(pool)
	entity, err := repo.FindByEntityTypeAndID(ctx, "Loan", "loan-12345")
	if err != nil {
		t.Fatalf("Failed to find entity: %v", err)
	}
	if entity == nil {
		t.Fatal("Entity should exist")
	}
}

func TestProcessMultipleEventsShouldLogPersistedEventsCountWithAPIName(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	logCapture := NewLogCapture(zapcore.InfoLevel)
	router := createTestServerWithLogCapture(t, pool, logCapture)

	// Process 12 events (should trigger count log at 10)
	for i := 1; i <= 12; i++ {
		event := map[string]interface{}{
			"eventHeader": map[string]interface{}{
				"uuid":        fmt.Sprintf("550e8400-e29b-41d4-a716-44665544000%d", i),
				"eventName":   "LoanPaymentSubmitted",
				"createdDate": "2024-01-15T10:30:00Z",
				"savedDate":   "2024-01-15T10:30:05Z",
				"eventType":   "LoanPaymentSubmitted",
			},
			"entities": []map[string]interface{}{
				{
					"entityHeader": map[string]interface{}{
						"entityId":   fmt.Sprintf("loan-log-bulk-%d", i),
						"entityType": "Loan",
						"createdAt":  "2024-01-15T10:30:00Z",
						"updatedAt":  "2024-01-15T10:30:00Z",
					},
					"balance": "24439.75",
				},
			},
		}

		body, _ := json.Marshal(event)
		req := httptest.NewRequest("POST", "/api/v1/events", bytes.NewBuffer(body))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		if w.Code != http.StatusOK {
			t.Fatalf("Expected status 200, got %d: %s", w.Code, w.Body.String())
		}
	}

	// Small delay to ensure all logs are captured
	time.Sleep(200 * time.Millisecond)

	// Verify logs contain API name and persisted events count
	if !logCapture.Contains(constants.APIName()) {
		t.Error("Logs should contain API name")
	}
	if !logCapture.Contains("Persisted events count") {
		t.Error("Logs should contain 'Persisted events count' message")
	}
	if !logCapture.Contains("count=10") {
		t.Error("Logs should contain persisted events count: 10")
	}
}

func TestProcessEventShouldLogAllRequiredPatternsWithAPIName(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	logCapture := NewLogCapture(zapcore.InfoLevel)
	router := createTestServerWithLogCapture(t, pool, logCapture)

	event := createTestEvent()
	body, _ := json.Marshal(event)

	req := httptest.NewRequest("POST", "/api/v1/events", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("Expected status 200, got %d: %s", w.Code, w.Body.String())
	}

	// Small delay to ensure logs are captured
	time.Sleep(100 * time.Millisecond)

	// Verify all required log patterns are present with API name
	messages := strings.Join(logCapture.GetMessages(), "\n")

	if !strings.Contains(messages, "[producer-api-go-rest]") {
		t.Error("Logs should contain API name [producer-api-go-rest]")
	}
	if !strings.Contains(messages, "Processing event") {
		t.Error("Logs should contain 'Processing event' message")
	}
	if !strings.Contains(messages, "Successfully created entity") {
		t.Error("Logs should contain 'Successfully created entity' message")
	}
}
