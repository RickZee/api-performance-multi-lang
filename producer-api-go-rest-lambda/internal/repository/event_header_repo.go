package repository

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// EventHeaderRepository handles database operations for event headers
type EventHeaderRepository struct {
	pool *pgxpool.Pool
}

// NewEventHeaderRepository creates a new EventHeaderRepository
func NewEventHeaderRepository(pool *pgxpool.Pool) *EventHeaderRepository {
	return &EventHeaderRepository{pool: pool}
}

// Create inserts a new event header into the database
// If conn is provided, uses that connection (for transactions), otherwise acquires from pool
// Returns DuplicateEventError if event ID already exists
func (r *EventHeaderRepository) Create(
	ctx context.Context,
	eventID string,
	eventName string,
	eventType *string,
	createdDate *time.Time,
	savedDate *time.Time,
	headerData map[string]interface{},
	conn pgx.Tx,
) error {
	// Serialize header data to JSON
	headerDataJSON, err := json.Marshal(headerData)
	if err != nil {
		return err
	}

	query := `
		INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data)
		VALUES ($1, $2, $3, $4, $5, $6)
	`

	var execErr error
	if conn != nil {
		// Use provided transaction connection
		_, execErr = conn.Exec(ctx, query, eventID, eventName, eventType, createdDate, savedDate, headerDataJSON)
	} else {
		// Acquire connection from pool
		_, execErr = r.pool.Exec(ctx, query, eventID, eventName, eventType, createdDate, savedDate, headerDataJSON)
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
