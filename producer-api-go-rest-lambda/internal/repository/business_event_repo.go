package repository

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// BusinessEventRepository handles database operations for business events
type BusinessEventRepository struct {
	pool *pgxpool.Pool
}

// NewBusinessEventRepository creates a new BusinessEventRepository
func NewBusinessEventRepository(pool *pgxpool.Pool) *BusinessEventRepository {
	return &BusinessEventRepository{pool: pool}
}

// Create inserts a new business event into the database
// If conn is provided, uses that connection (for transactions), otherwise acquires from pool
// Returns DuplicateEventError if event ID already exists
func (r *BusinessEventRepository) Create(
	ctx context.Context,
	eventID string,
	eventName string,
	eventType *string,
	createdDate *time.Time,
	savedDate *time.Time,
	eventData map[string]interface{},
	conn pgx.Tx,
) error {
	// Serialize event data to JSON
	eventDataJSON, err := json.Marshal(eventData)
	if err != nil {
		return err
	}

	query := `
		INSERT INTO business_events (id, event_name, event_type, created_date, saved_date, event_data)
		VALUES ($1, $2, $3, $4, $5, $6)
	`

	var execErr error
	if conn != nil {
		// Use provided transaction connection
		_, execErr = conn.Exec(ctx, query, eventID, eventName, eventType, createdDate, savedDate, eventDataJSON)
	} else {
		// Acquire connection from pool
		_, execErr = r.pool.Exec(ctx, query, eventID, eventName, eventType, createdDate, savedDate, eventDataJSON)
	}

	if execErr != nil {
		// Check if it's a unique violation (duplicate key)
		if pgErr, ok := execErr.(*pgx.PgError); ok && pgErr.Code == "23505" {
			return NewDuplicateEventError(eventID, "")
		}
		return execErr
	}

	return nil
}

