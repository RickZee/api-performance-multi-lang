use chrono::{DateTime, Utc};
use serde_json::Value;
use sqlx::{PgPool, Postgres, Transaction};

#[derive(Clone)]
pub struct EventHeaderRepository {
    pool: PgPool,
}

impl EventHeaderRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    pub async fn create(
        &self,
        event_id: &str,
        event_name: &str,
        event_type: Option<&str>,
        created_date: Option<DateTime<Utc>>,
        saved_date: Option<DateTime<Utc>>,
        header_data: &Value,
        tx: Option<&mut Transaction<'_, Postgres>>,
    ) -> Result<(), sqlx::Error> {
        let header_data_json = serde_json::to_string(header_data)
            .map_err(|e| sqlx::Error::Decode(Box::new(e)))?;

        let query = "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) 
                     VALUES ($1, $2, $3, $4, $5, $6::jsonb)";

        if let Some(t) = tx {
            sqlx::query(query)
                .bind(event_id)
                .bind(event_name)
                .bind(event_type)
                .bind(created_date)
                .bind(saved_date)
                .bind(&header_data_json)
                .execute(&mut **t)
                .await?;
        } else {
            sqlx::query(query)
                .bind(event_id)
                .bind(event_name)
                .bind(event_type)
                .bind(created_date)
                .bind(saved_date)
                .bind(&header_data_json)
                .execute(&self.pool)
                .await?;
        }

        Ok(())
    }

    pub fn check_duplicate_error(err: &sqlx::Error) -> Option<String> {
        if let sqlx::Error::Database(db_err) = err {
            // Check error code directly
            if db_err.code().as_deref() == Some("23505") {
                return Some(db_err.message().to_string());
            }
        }
        None
    }
}

