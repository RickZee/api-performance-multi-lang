use chrono::{DateTime, Utc};
use serde_json::Value;
use sqlx::{PgPool, Postgres, Transaction};

#[derive(Clone)]
pub struct EntityRepository {
    pool: PgPool,
    table_name: String,
}

impl EntityRepository {
    pub fn new(pool: PgPool, table_name: String) -> Self {
        Self { pool, table_name }
    }

    pub fn table_name(&self) -> &str {
        &self.table_name
    }

    pub async fn exists_by_entity_id(
        &self,
        entity_id: &str,
        tx: Option<&mut Transaction<'_, Postgres>>,
    ) -> Result<bool, sqlx::Error> {
        let query = format!(
            "SELECT EXISTS(SELECT 1 FROM {} WHERE entity_id = $1)",
            self.table_name
        );

        if let Some(t) = tx {
            let result: Option<bool> = sqlx::query_scalar(&query)
                .bind(entity_id)
                .fetch_optional(&mut **t)
                .await?;
            Ok(result.unwrap_or(false))
        } else {
            let result: Option<bool> = sqlx::query_scalar(&query)
                .bind(entity_id)
                .fetch_optional(&self.pool)
                .await?;
            Ok(result.unwrap_or(false))
        }
    }

    pub async fn create(
        &self,
        entity_id: &str,
        entity_type: &str,
        created_at: Option<DateTime<Utc>>,
        updated_at: Option<DateTime<Utc>>,
        entity_data: &Value,
        event_id: Option<&str>,
        tx: Option<&mut Transaction<'_, Postgres>>,
    ) -> Result<(), sqlx::Error> {
        let entity_data_json = serde_json::to_string(entity_data)
            .map_err(|e| sqlx::Error::Decode(Box::new(e)))?;

        let query = format!(
            "INSERT INTO {} (entity_id, entity_type, created_at, updated_at, entity_data, event_id) 
             VALUES ($1, $2, $3, $4, $5::jsonb, $6)",
            self.table_name
        );

        if let Some(t) = tx {
            sqlx::query(&query)
                .bind(entity_id)
                .bind(entity_type)
                .bind(created_at)
                .bind(updated_at)
                .bind(&entity_data_json)
                .bind(event_id)
                .execute(&mut **t)
                .await?;
        } else {
            sqlx::query(&query)
                .bind(entity_id)
                .bind(entity_type)
                .bind(created_at)
                .bind(updated_at)
                .bind(&entity_data_json)
                .bind(event_id)
                .execute(&self.pool)
                .await?;
        }

        Ok(())
    }

    pub async fn update(
        &self,
        entity_id: &str,
        updated_at: DateTime<Utc>,
        entity_data: &Value,
        event_id: Option<&str>,
        tx: Option<&mut Transaction<'_, Postgres>>,
    ) -> Result<(), sqlx::Error> {
        let entity_data_json = serde_json::to_string(entity_data)
            .map_err(|e| sqlx::Error::Decode(Box::new(e)))?;

        let query = format!(
            "UPDATE {} SET updated_at = $1, entity_data = $2::jsonb, event_id = $3 
             WHERE entity_id = $4",
            self.table_name
        );

        if let Some(t) = tx {
            sqlx::query(&query)
                .bind(updated_at)
                .bind(&entity_data_json)
                .bind(event_id)
                .bind(entity_id)
                .execute(&mut **t)
                .await?;
        } else {
            sqlx::query(&query)
                .bind(updated_at)
                .bind(&entity_data_json)
                .bind(event_id)
                .bind(entity_id)
                .execute(&self.pool)
                .await?;
        }

        Ok(())
    }
}
