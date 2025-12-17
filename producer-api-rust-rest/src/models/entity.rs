use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct CarEntity {
    pub id: String,
    #[sqlx(rename = "entity_type")]
    pub entity_type: String,
    #[sqlx(rename = "created_at")]
    pub created_at: Option<DateTime<Utc>>,
    #[sqlx(rename = "updated_at")]
    pub updated_at: Option<DateTime<Utc>>,
    pub data: String, // JSON string
}

impl CarEntity {
    pub fn new(
        id: String,
        entity_type: String,
        data: String,
    ) -> Self {
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
