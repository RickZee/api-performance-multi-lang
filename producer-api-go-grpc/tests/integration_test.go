package tests

import (
	"context"
	"os"
	"producer-api-go-grpc/internal/config"
	"producer-api-go-grpc/internal/repository"
	"producer-api-go-grpc/internal/service"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// Note: Integration tests require proto files to be generated first.
// Run: ./scripts/generate-proto.sh before running tests.

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

func createTestService(t *testing.T, pool *pgxpool.Pool) *service.EventProcessingService {
	logger, _ := zap.NewDevelopment()
	repo := repository.NewCarEntityRepository(pool)
	return service.NewEventProcessingService(repo, logger)
}

// TODO: Add gRPC integration tests once proto files are generated
// Example test structure:
//
// func TestProcessEventWithValidEventShouldProcessSuccessfully(t *testing.T) {
//     pool := setupTestDatabase(t)
//     defer pool.Close()
//
//     // Create gRPC server and client
//     // Test ProcessEvent
//     // Verify entity was created in database
// }

func TestEventProcessingService(t *testing.T) {
	pool := setupTestDatabase(t)
	defer pool.Close()

	eventService := createTestService(t, pool)
	ctx := context.Background()

	// Test creating a new entity
	attributes := map[string]string{
		"balance":      "24439.75",
		"lastPaidDate": "2024-01-15T10:30:00Z",
	}

	err := eventService.ProcessEntityUpdate(ctx, "Loan", "loan-12345", attributes)
	if err != nil {
		t.Fatalf("Failed to process entity update: %v", err)
	}

	// Verify entity was created
	repo := repository.NewCarEntityRepository(pool)
	entity, err := repo.FindByEntityTypeAndID(ctx, "Loan", "loan-12345")
	if err != nil {
		t.Fatalf("Failed to find entity: %v", err)
	}
	if entity == nil {
		t.Fatal("Entity should exist")
	}
	if entity.ID != "loan-12345" {
		t.Errorf("Expected id=loan-12345, got %s", entity.ID)
	}
}

