use chrono::{DateTime, Utc};
use sqlx::PgPool;

pub struct CarEntity {
    pub id: String,
    pub entity_type: String,
    pub created_at: Option<DateTime<Utc>>,
    pub updated_at: Option<DateTime<Utc>>,
    pub data: String,
}

impl CarEntity {
    pub fn new(id: String, entity_type: String, data: String) -> Self {
        let now = Utc::now();
        Self {
            id,
            entity_type,
            created_at: Some(now),
            updated_at: Some(now),
            data,
        }
    }
}

pub struct CarEntityRepository {
    pool: PgPool,
}

impl CarEntityRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    pub async fn find_by_entity_type_and_id(
        &self,
        entity_type: &str,
        id: &str,
    ) -> Result<Option<CarEntity>, sqlx::Error> {
        let row = sqlx::query_as::<_, (String, String, Option<DateTime<Utc>>, Option<DateTime<Utc>>, String)>(
            "SELECT id, entity_type, created_at, updated_at, data FROM car_entities WHERE entity_type = $1 AND id = $2"
        )
        .bind(entity_type)
        .bind(id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row.map(|(id, entity_type, created_at, updated_at, data)| CarEntity {
            id,
            entity_type,
            created_at,
            updated_at,
            data,
        }))
    }

    pub async fn exists_by_entity_type_and_id(
        &self,
        entity_type: &str,
        id: &str,
    ) -> Result<bool, sqlx::Error> {
        let result: Option<bool> = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM car_entities WHERE entity_type = $1 AND id = $2)"
        )
        .bind(entity_type)
        .bind(id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(result.unwrap_or(false))
    }

    pub async fn create(&self, entity: &CarEntity) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO car_entities (id, entity_type, created_at, updated_at, data) VALUES ($1, $2, $3, $4, $5)"
        )
        .bind(&entity.id)
        .bind(&entity.entity_type)
        .bind(&entity.created_at)
        .bind(&entity.updated_at)
        .bind(&entity.data)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn update(&self, entity: &CarEntity) -> Result<(), sqlx::Error> {
        sqlx::query(
            "UPDATE car_entities SET entity_type = $1, updated_at = $2, data = $3 WHERE id = $4"
        )
        .bind(&entity.entity_type)
        .bind(&entity.updated_at)
        .bind(&entity.data)
        .bind(&entity.id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }
}

