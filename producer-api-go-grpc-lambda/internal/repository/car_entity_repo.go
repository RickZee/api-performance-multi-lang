package repository

import (
	"context"
	"producer-api-go-grpc-lambda/internal/models"

	"github.com/jackc/pgx/v5/pgxpool"
)

type CarEntityRepository struct {
	pool *pgxpool.Pool
}

func NewCarEntityRepository(pool *pgxpool.Pool) *CarEntityRepository {
	return &CarEntityRepository{pool: pool}
}

func (r *CarEntityRepository) FindByEntityTypeAndID(ctx context.Context, entityType, id string) (*models.CarEntity, error) {
	var entity models.CarEntity
	err := r.pool.QueryRow(
		ctx,
		"SELECT id, entity_type, created_at, updated_at, data FROM car_entities WHERE entity_type = $1 AND id = $2",
		entityType, id,
	).Scan(&entity.ID, &entity.EntityType, &entity.CreatedAt, &entity.UpdatedAt, &entity.Data)

	if err != nil {
		if err.Error() == "no rows in result set" {
			return nil, nil
		}
		return nil, err
	}

	return &entity, nil
}

func (r *CarEntityRepository) ExistsByEntityTypeAndID(ctx context.Context, entityType, id string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(
		ctx,
		"SELECT EXISTS(SELECT 1 FROM car_entities WHERE entity_type = $1 AND id = $2)",
		entityType, id,
	).Scan(&exists)

	if err != nil {
		return false, err
	}

	return exists, nil
}

func (r *CarEntityRepository) Create(ctx context.Context, entity *models.CarEntity) error {
	_, err := r.pool.Exec(
		ctx,
		"INSERT INTO car_entities (id, entity_type, created_at, updated_at, data) VALUES ($1, $2, $3, $4, $5)",
		entity.ID, entity.EntityType, entity.CreatedAt, entity.UpdatedAt, entity.Data,
	)
	return err
}

func (r *CarEntityRepository) Update(ctx context.Context, entity *models.CarEntity) error {
	_, err := r.pool.Exec(
		ctx,
		"UPDATE car_entities SET entity_type = $1, updated_at = $2, data = $3 WHERE id = $4",
		entity.EntityType, entity.UpdatedAt, entity.Data, entity.ID,
	)
	return err
}
