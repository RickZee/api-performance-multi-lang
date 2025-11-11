package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"producer-api-go/internal/config"
	"producer-api-go/internal/handlers"
	"producer-api-go/internal/models"
	"producer-api-go/internal/repository"
	"producer-api-go/internal/service"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

func setupTestDatabase(t *testing.T) *pgxpool.Pool {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		databaseURL = "postgresql://postgres:password@localhost:5432/car_entities"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		t.Fatalf("Failed to connect to test database: %v. Make sure the database is running.", err)
	}

	// Test connection
	if err := pool.Ping(ctx); err != nil {
		t.Fatalf("Failed to ping database: %v", err)
	}

	// Run migrations
	migrationSQL, err := os.ReadFile("../migrations/001_initial_schema.sql")
	if err != nil {
		t.Fatalf("Failed to read migration file: %v", err)
	}

	_, err = pool.Exec(ctx, string(migrationSQL))
	if err != nil {
		t.Fatalf("Failed to run migrations: %v", err)
	}

	// Clean up test data
	_, err = pool.Exec(ctx, "DELETE FROM car_entities")
	if err != nil {
		t.Fatalf("Failed to clean up test data: %v", err)
	}

	return pool
}

func createTestServer(t *testing.T, pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)

	logger, _ := zap.NewDevelopment()
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

func createTestEvent() map[string]interface{} {
	return map[string]interface{}{
		"eventHeader": map[string]interface{}{
			"uuid":        "550e8400-e29b-41d4-a716-446655440000",
			"eventName":   "LoanPaymentSubmitted",
			"createdDate": "2024-01-15T10:30:00Z",
			"savedDate":   "2024-01-15T10:30:05Z",
			"eventType":   "LoanPaymentSubmitted",
		},
		"eventBody": map[string]interface{}{
			"entities": []map[string]interface{}{
				{
					"entityType": "Loan",
					"entityId":   "loan-12345",
					"updatedAttributes": map[string]interface{}{
						"balance":     24439.75,
						"lastPaidDate": "2024-01-15T10:30:00Z",
					},
				},
			},
		},
	}
}

func TestProcessEventWithNewEntityShouldCreateEntityInDatabase(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	router := createTestServer(t, pool)

	event := createTestEvent()
	body, _ := json.Marshal(event)

	req := httptest.NewRequest("POST", "/api/v1/events", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("Expected status 200, got %d: %s", w.Code, w.Body.String())
	}

	var response map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to parse response: %v", err)
	}

	if response["success"] != true {
		t.Errorf("Expected success=true, got %v", response["success"])
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

	if entity.EntityType != "Loan" {
		t.Errorf("Expected entity_type=Loan, got %s", entity.EntityType)
	}
	if entity.ID != "loan-12345" {
		t.Errorf("Expected id=loan-12345, got %s", entity.ID)
	}
	if !bytes.Contains([]byte(entity.Data), []byte("24439.75")) {
		t.Errorf("Entity data should contain 24439.75, got %s", entity.Data)
	}
}

func TestProcessEventWithExistingEntityShouldUpdateEntity(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	ctx := context.Background()
	repo := repository.NewCarEntityRepository(pool)

	// Create existing entity
	existingEntity := models.NewCarEntity(
		"loan-12345",
		"Loan",
		`{"balance": 25000.00, "status": "active"}`,
	)
	if err := repo.Create(ctx, existingEntity); err != nil {
		t.Fatalf("Failed to create existing entity: %v", err)
	}

	router := createTestServer(t, pool)

	event := createTestEvent()
	body, _ := json.Marshal(event)

	req := httptest.NewRequest("POST", "/api/v1/events", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("Expected status 200, got %d: %s", w.Code, w.Body.String())
	}

	// Verify entity was updated
	updatedEntity, err := repo.FindByEntityTypeAndID(ctx, "Loan", "loan-12345")
	if err != nil {
		t.Fatalf("Failed to find entity: %v", err)
	}
	if updatedEntity == nil {
		t.Fatal("Entity should exist")
	}

	if !bytes.Contains([]byte(updatedEntity.Data), []byte("24439.75")) {
		t.Errorf("Entity data should contain 24439.75, got %s", updatedEntity.Data)
	}
	if updatedEntity.UpdatedAt == nil {
		t.Error("UpdatedAt should be set")
	}
}

func TestProcessEventWithMultipleEntitiesShouldProcessAllEntities(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	router := createTestServer(t, pool)

	event := map[string]interface{}{
		"eventHeader": map[string]interface{}{
			"uuid":        "550e8400-e29b-41d4-a716-446655440000",
			"eventName":   "LoanPaymentSubmitted",
			"createdDate": "2024-01-15T10:30:00Z",
			"savedDate":   "2024-01-15T10:30:05Z",
			"eventType":   "LoanPaymentSubmitted",
		},
		"eventBody": map[string]interface{}{
			"entities": []map[string]interface{}{
				{
					"entityType": "Loan",
					"entityId":   "loan-12345",
					"updatedAttributes": map[string]interface{}{
						"balance":     24439.75,
						"lastPaidDate": "2024-01-15T10:30:00Z",
					},
				},
				{
					"entityType": "LoanPayment",
					"entityId":   "payment-12345",
					"updatedAttributes": map[string]interface{}{
						"paymentAmount": 560.25,
						"paymentDate":   "2024-01-15T10:30:00Z",
						"paymentMethod": "ACH",
					},
				},
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

	// Verify both entities were created
	ctx := context.Background()
	repo := repository.NewCarEntityRepository(pool)

	loanEntity, err := repo.FindByEntityTypeAndID(ctx, "Loan", "loan-12345")
	if err != nil {
		t.Fatalf("Failed to find loan entity: %v", err)
	}
	if loanEntity == nil {
		t.Fatal("Loan entity should exist")
	}
	if loanEntity.ID != "loan-12345" {
		t.Errorf("Expected id=loan-12345, got %s", loanEntity.ID)
	}

	paymentEntity, err := repo.FindByEntityTypeAndID(ctx, "LoanPayment", "payment-12345")
	if err != nil {
		t.Fatalf("Failed to find payment entity: %v", err)
	}
	if paymentEntity == nil {
		t.Fatal("Payment entity should exist")
	}
	if paymentEntity.ID != "payment-12345" {
		t.Errorf("Expected id=payment-12345, got %s", paymentEntity.ID)
	}
}

func TestProcessEventWithInvalidEventShouldReturnError(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	router := createTestServer(t, pool)

	invalidEvent := map[string]interface{}{
		"eventHeader": nil,
		"eventBody":   nil,
	}

	body, _ := json.Marshal(invalidEvent)

	req := httptest.NewRequest("POST", "/api/v1/events", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422, got %d: %s", w.Code, w.Body.String())
	}
}

func TestHealthCheckShouldReturnOK(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	router := createTestServer(t, pool)

	req := httptest.NewRequest("GET", "/api/v1/events/health", nil)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("Expected status 200, got %d: %s", w.Code, w.Body.String())
	}

	var response map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to parse response: %v", err)
	}

	if response["status"] != "healthy" {
		t.Errorf("Expected status=healthy, got %v", response["status"])
	}
}

func TestProcessBulkEventsWithValidEventsShouldProcessAllEvents(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	router := createTestServer(t, pool)

	events := []map[string]interface{}{
		createTestEvent(),
		{
			"eventHeader": map[string]interface{}{
				"uuid":        "660e8400-e29b-41d4-a716-446655440001",
				"eventName":   "LoanPaymentSubmitted",
				"createdDate": "2024-01-15T10:30:00Z",
				"savedDate":   "2024-01-15T10:30:05Z",
				"eventType":   "LoanPaymentSubmitted",
			},
			"eventBody": map[string]interface{}{
				"entities": []map[string]interface{}{
					{
						"entityType": "LoanPayment",
						"entityId":   "payment-67890",
						"updatedAttributes": map[string]interface{}{
							"paymentAmount": 560.25,
							"paymentDate":   "2024-01-15T10:30:00Z",
						},
					},
				},
			},
		},
	}

	body, _ := json.Marshal(events)

	req := httptest.NewRequest("POST", "/api/v1/events/bulk", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("Expected status 200, got %d: %s", w.Code, w.Body.String())
	}

	var response map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatalf("Failed to parse response: %v", err)
	}

	if response["success"] != true {
		t.Errorf("Expected success=true, got %v", response["success"])
	}
	if fmt.Sprintf("%.0f", response["processedCount"]) != "2" {
		t.Errorf("Expected processedCount=2, got %v", response["processedCount"])
	}
	if fmt.Sprintf("%.0f", response["failedCount"]) != "0" {
		t.Errorf("Expected failedCount=0, got %v", response["failedCount"])
	}
}

func TestProcessBulkEventsWithEmptyListShouldReturnError(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	router := createTestServer(t, pool)

	events := []map[string]interface{}{}
	body, _ := json.Marshal(events)

	req := httptest.NewRequest("POST", "/api/v1/events/bulk", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422, got %d: %s", w.Code, w.Body.String())
	}
}

func TestProcessEventWithEmptyEntitiesListShouldReturnError(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	router := createTestServer(t, pool)

	event := map[string]interface{}{
		"eventHeader": map[string]interface{}{
			"uuid":        "550e8400-e29b-41d4-a716-446655440000",
			"eventName":   "LoanPaymentSubmitted",
			"createdDate": "2024-01-15T10:30:00Z",
			"savedDate":   "2024-01-15T10:30:05Z",
			"eventType":   "LoanPaymentSubmitted",
		},
		"eventBody": map[string]interface{}{
			"entities": []map[string]interface{}{},
		},
	}

	body, _ := json.Marshal(event)

	req := httptest.NewRequest("POST", "/api/v1/events", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422, got %d: %s", w.Code, w.Body.String())
	}
}

func TestProcessEventWithEmptyEventNameShouldReturnError(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	router := createTestServer(t, pool)

	event := map[string]interface{}{
		"eventHeader": map[string]interface{}{
			"uuid":        "550e8400-e29b-41d4-a716-446655440000",
			"eventName":   "",
			"createdDate": "2024-01-15T10:30:00Z",
			"savedDate":   "2024-01-15T10:30:05Z",
			"eventType":   "LoanPaymentSubmitted",
		},
		"eventBody": map[string]interface{}{
			"entities": []map[string]interface{}{
				{
					"entityType": "Loan",
					"entityId":   "loan-12345",
					"updatedAttributes": map[string]interface{}{
						"balance": 24439.75,
					},
				},
			},
		},
	}

	body, _ := json.Marshal(event)

	req := httptest.NewRequest("POST", "/api/v1/events", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("Expected status 422, got %d: %s", w.Code, w.Body.String())
	}
}

