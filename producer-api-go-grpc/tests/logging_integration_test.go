package tests

import (
	"context"
	"fmt"
	"os"
	"producer-api-go-grpc/internal/constants"
	"producer-api-go-grpc/internal/repository"
	"producer-api-go-grpc/internal/service"
	"strings"
	"sync"
	"testing"
	"time"

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

	var buf strings.Builder
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

func createTestServiceWithLogCapture(t *testing.T, pool *pgxpool.Pool, logCapture *LogCapture) *service.EventProcessingService {
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
	return service.NewEventProcessingService(repo, logger)
}

func TestProcessEntityUpdateShouldLogProcessingEventWithAPIName(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	logCapture := NewLogCapture(zapcore.InfoLevel)
	eventService := createTestServiceWithLogCapture(t, pool, logCapture)

	ctx := context.Background()
	attributes := map[string]string{
		"balance":      "24439.75",
		"lastPaidDate": "2024-01-15T10:30:00Z",
	}

	err := eventService.ProcessEntityUpdate(ctx, "Loan", "loan-grpc-log-001", attributes)
	if err != nil {
		t.Fatalf("Failed to process entity update: %v", err)
	}

	// Small delay to ensure logs are captured
	time.Sleep(100 * time.Millisecond)

	// Verify logs contain API name and processing event message
	if !logCapture.Contains(constants.APIName()) {
		t.Error("Logs should contain API name")
	}
	if !logCapture.Contains("Processing entity creation") {
		t.Error("Logs should contain 'Processing entity creation' message")
	}
}

func TestProcessEntityUpdateShouldLogSuccessfullyCreatedEntityWithAPIName(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	logCapture := NewLogCapture(zapcore.InfoLevel)
	eventService := createTestServiceWithLogCapture(t, pool, logCapture)

	ctx := context.Background()
	attributes := map[string]string{
		"balance":      "24439.75",
		"lastPaidDate": "2024-01-15T10:30:00Z",
	}

	err := eventService.ProcessEntityUpdate(ctx, "Loan", "loan-grpc-log-002", attributes)
	if err != nil {
		t.Fatalf("Failed to process entity update: %v", err)
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
	repo := repository.NewCarEntityRepository(pool)
	entity, err := repo.FindByEntityTypeAndID(ctx, "Loan", "loan-grpc-log-002")
	if err != nil {
		t.Fatalf("Failed to find entity: %v", err)
	}
	if entity == nil {
		t.Fatal("Entity should exist")
	}
}

func TestProcessMultipleEntityUpdatesShouldLogPersistedEventsCountWithAPIName(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	logCapture := NewLogCapture(zapcore.InfoLevel)
	eventService := createTestServiceWithLogCapture(t, pool, logCapture)

	ctx := context.Background()

	// Process 12 events (should trigger count log at 10)
	for i := 1; i <= 12; i++ {
		attributes := map[string]string{
			"balance": "24439.75",
		}

		err := eventService.ProcessEntityUpdate(ctx, "Loan", fmt.Sprintf("loan-grpc-bulk-%d", i), attributes)
		if err != nil {
			t.Fatalf("Failed to process entity update: %v", err)
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

func TestProcessEntityUpdateShouldLogAllRequiredPatternsWithAPIName(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	logCapture := NewLogCapture(zapcore.InfoLevel)
	eventService := createTestServiceWithLogCapture(t, pool, logCapture)

	ctx := context.Background()
	attributes := map[string]string{
		"balance":      "24439.75",
		"lastPaidDate": "2024-01-15T10:30:00Z",
	}

	err := eventService.ProcessEntityUpdate(ctx, "Loan", "loan-grpc-complete-001", attributes)
	if err != nil {
		t.Fatalf("Failed to process entity update: %v", err)
	}

	// Small delay to ensure logs are captured
	time.Sleep(100 * time.Millisecond)

	// Verify all required log patterns are present with API name
	messages := strings.Join(logCapture.GetMessages(), "\n")

	if !strings.Contains(messages, "[producer-api-go-grpc]") {
		t.Error("Logs should contain API name [producer-api-go-grpc]")
	}
	if !strings.Contains(messages, "Processing entity creation") {
		t.Error("Logs should contain 'Processing entity creation' message")
	}
	if !strings.Contains(messages, "Successfully created entity") {
		t.Error("Logs should contain 'Successfully created entity' message")
	}
}

