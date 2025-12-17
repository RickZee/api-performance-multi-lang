package repository

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// EntityRepository is a generic repository for entity database operations
// It supports all entity types: Car, Loan, LoanPayment, ServiceRecord
type EntityRepository struct {
	pool      *pgxpool.Pool
	tableName string
}

// NewEntityRepository creates a new EntityRepository for a specific table
func NewEntityRepository(pool *pgxpool.Pool, tableName string) *EntityRepository {
	return &EntityRepository{
		pool:      pool,
		tableName: tableName,
	}
}

// ExistsByEntityID checks if an entity exists by entity ID
// If conn is provided, uses that connection (for transactions), otherwise acquires from pool
func (r *EntityRepository) ExistsByEntityID(ctx context.Context, entityID string, conn pgx.Tx) (bool, error) {
	query := "SELECT EXISTS(SELECT 1 FROM " + r.tableName + " WHERE entity_id = $1)"

	var exists bool
	var err error
	if conn != nil {
		// Use provided transaction connection
		err = conn.QueryRow(ctx, query, entityID).Scan(&exists)
	} else {
		// Acquire connection from pool
		err = r.pool.QueryRow(ctx, query, entityID).Scan(&exists)
	}

	if err != nil {
		return false, err
	}

	return exists, nil
}

// Create inserts a new entity into the database
// If conn is provided, uses that connection (for transactions), otherwise acquires from pool
func (r *EntityRepository) Create(
	ctx context.Context,
	entityID string,
	entityType string,
	createdAt *time.Time,
	updatedAt *time.Time,
	entityData map[string]interface{},
	eventID *string,
	conn pgx.Tx,
) error {
	// Serialize entity data to JSON
	entityDataJSON, err := json.Marshal(entityData)
	if err != nil {
		return err
	}

	query := `
		INSERT INTO ` + r.tableName + ` (entity_id, entity_type, created_at, updated_at, entity_data, event_id)
		VALUES ($1, $2, $3, $4, $5, $6)
	`

	var execErr error
	if conn != nil {
		// Use provided transaction connection
		_, execErr = conn.Exec(ctx, query, entityID, entityType, createdAt, updatedAt, entityDataJSON, eventID)
	} else {
		// Acquire connection from pool
		_, execErr = r.pool.Exec(ctx, query, entityID, entityType, createdAt, updatedAt, entityDataJSON, eventID)
	}

	return execErr
}

// Update updates an existing entity in the database
// If conn is provided, uses that connection (for transactions), otherwise acquires from pool
func (r *EntityRepository) Update(
	ctx context.Context,
	entityID string,
	updatedAt time.Time,
	entityData map[string]interface{},
	eventID *string,
	conn pgx.Tx,
) error {
	// Serialize entity data to JSON
	entityDataJSON, err := json.Marshal(entityData)
	if err != nil {
		return err
	}

	query := `
		UPDATE ` + r.tableName + `
		SET updated_at = $1, entity_data = $2, event_id = $3
		WHERE entity_id = $4
	`

	var execErr error
	if conn != nil {
		// Use provided transaction connection
		_, execErr = conn.Exec(ctx, query, updatedAt, entityDataJSON, eventID, entityID)
	} else {
		// Acquire connection from pool
		_, execErr = r.pool.Exec(ctx, query, updatedAt, entityDataJSON, eventID, entityID)
	}

	return execErr
}
