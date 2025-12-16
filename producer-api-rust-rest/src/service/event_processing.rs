use crate::models::{Entity, Event};
use crate::repository::{
    BusinessEventRepository, DuplicateEventError, EntityRepository, EventHeaderRepository,
};
use crate::constants::API_NAME;
use anyhow::Context;
use chrono::Utc;
use serde_json::Value;
use sqlx::{PgPool, Postgres, Transaction};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};

// Entity type to table name mapping
fn get_table_name(entity_type: &str) -> Option<&'static str> {
    match entity_type {
        "Car" => Some("car_entities"),
        "Loan" => Some("loan_entities"),
        "LoanPayment" => Some("loan_payment_entities"),
        "ServiceRecord" => Some("service_record_entities"),
        _ => None,
    }
}

#[derive(Clone)]
pub struct EventProcessingService {
    business_event_repo: BusinessEventRepository,
    event_header_repo: EventHeaderRepository,
    pool: PgPool,
    persisted_event_count: std::sync::Arc<AtomicU64>,
}

impl EventProcessingService {
    pub fn new(
        business_event_repo: BusinessEventRepository,
        pool: PgPool,
    ) -> Self {
        Self {
            business_event_repo,
            event_header_repo: EventHeaderRepository::new(pool.clone()),
            pool,
            persisted_event_count: std::sync::Arc::new(AtomicU64::new(0)),
        }
    }

    fn log_persisted_event_count(&self) {
        let count = self.persisted_event_count.fetch_add(1, Ordering::Relaxed) + 1;
        if count % 10 == 0 {
            tracing::info!("{} *** Persisted events count: {} ***", API_NAME, count);
        }
    }

    fn get_entity_repository(&self, entity_type: &str) -> Option<EntityRepository> {
        get_table_name(entity_type).map(|table_name| {
            EntityRepository::new(self.pool.clone(), table_name.to_string())
        })
    }

    // Process event within a transaction
    pub async fn process_event(&self, event: Event) -> anyhow::Result<()> {
        tracing::info!("{} Processing event: {}", API_NAME, event.event_header.event_name);

        // Generate event ID if not provided
        let event_id = event.event_header.uuid
            .as_ref()
            .filter(|s| !s.is_empty())
            .map(|s| s.clone())
            .unwrap_or_else(|| format!("event-{}", Utc::now().to_rfc3339()));

        // Begin transaction
        let mut tx = self.pool.begin().await
            .context("Failed to begin transaction")?;

        // Process all operations in transaction
        // Use a helper to avoid move issues with Option<&mut Transaction>
        let result = async {
            // 1. Save entire event to business_events table
            self.save_business_event(&event, &event_id, Some(&mut tx)).await
                .context("Failed to save business event")?;

            // 2. Save event header to event_headers table
            self.save_event_header(&event, &event_id, Some(&mut tx)).await
                .context("Failed to save event header")?;

            // 3. Extract and save entities to their respective tables
            for entity in &event.entities {
                self.process_entity_update(entity_update, &event_id, Some(&mut tx)).await
                    .context("Failed to process entity update")?;
            }

            // Commit transaction
            tx.commit().await
                .context("Failed to commit transaction")?;

            Ok::<(), anyhow::Error>(())
        }.await;

        match result {
            Ok(_) => {
                self.log_persisted_event_count();
                tracing::info!("{} Successfully processed event in transaction: {}", API_NAME, event_id);
                Ok(())
            }
            Err(e) => {
                // Check if it's a duplicate event error
                if let Some(dup_err) = e.downcast_ref::<DuplicateEventError>() {
                    return Err(anyhow::anyhow!(DuplicateEventError::new(dup_err.event_id.clone())));
                }
                Err(e)
            }
        }
    }

    async fn save_business_event(
        &self,
        event: &Event,
        event_id: &str,
        tx: Option<&mut Transaction<'_, Postgres>>,
    ) -> anyhow::Result<()> {
        let event_name = &event.event_header.event_name;
        let event_type = event.event_header.event_type.as_deref();
        let created_date = event.event_header.created_date;
        let saved_date = event.event_header.saved_date;

        // Use current time if dates are not provided
        let now = Utc::now();
        let created_date = created_date.unwrap_or(now);
        let saved_date = saved_date.unwrap_or(now);

        // Convert event to JSON value for JSONB storage
        let event_data: Value = serde_json::to_value(event)
            .context("Failed to serialize event")?;

        self.business_event_repo
            .create(event_id, event_name, event_type, Some(created_date), Some(saved_date), &event_data, tx)
            .await
            .map_err(|e| {
                if let Some(_) = BusinessEventRepository::check_duplicate_error(&e) {
                    anyhow::anyhow!(DuplicateEventError::new(event_id.to_string()))
                } else {
                    anyhow::anyhow!(e)
                }
            })?;

        tracing::info!("{} Successfully saved business event: {}", API_NAME, event_id);
        Ok(())
    }

    async fn save_event_header(
        &self,
        event: &Event,
        event_id: &str,
        tx: Option<&mut Transaction<'_, Postgres>>,
    ) -> anyhow::Result<()> {
        let event_name = &event.event_header.event_name;
        let event_type = event.event_header.event_type.as_deref();
        let created_date = event.event_header.created_date;
        let saved_date = event.event_header.saved_date;

        // Use current time if dates are not provided
        let now = Utc::now();
        let created_date = created_date.unwrap_or(now);
        let saved_date = saved_date.unwrap_or(now);

        // Convert eventHeader to JSON value for JSONB storage
        let header_data: Value = serde_json::to_value(&event.event_header)
            .context("Failed to serialize event header")?;

        self.event_header_repo
            .create(event_id, event_name, event_type, Some(created_date), Some(saved_date), &header_data, tx)
            .await
            .map_err(|e| {
                if let Some(_) = EventHeaderRepository::check_duplicate_error(&e) {
                    anyhow::anyhow!(DuplicateEventError::new(event_id.to_string()))
                } else {
                    anyhow::anyhow!(e)
                }
            })?;

        tracing::info!("{} Successfully saved event header: {}", API_NAME, event_id);
        Ok(())
    }

    async fn process_entity_update(
        &self,
        entity: &Entity,
        event_id: &str,
        tx: Option<&mut Transaction<'_, Postgres>>,
    ) -> anyhow::Result<()> {
        tracing::info!(
            "{} Processing entity for type: {} and id: {}",
            API_NAME,
            entity.entity_header.entity_type,
            entity.entity_header.entity_id
        );

        let entity_repo = match self.get_entity_repository(&entity.entity_header.entity_type) {
            Some(repo) => repo,
            None => {
                tracing::warn!(
                    "{} Skipping entity with unknown type: {}",
                    API_NAME,
                    entity.entity_header.entity_type
                );
                return Ok(());
            }
        };

        // Check existence using the pool (read operation doesn't need transaction)
        // The actual INSERT/UPDATE will be in the transaction and handle conflicts
        let exists = entity_repo
            .exists_by_entity_id(&entity.entity_header.entity_id, None)
            .await
            .context("Failed to check if entity exists")?;

        if exists {
            tracing::warn!(
                "{} Entity already exists, updating: {}",
                API_NAME,
                entity.entity_header.entity_id
            );
            self.update_existing_entity(&entity_repo, entity, event_id, tx).await
        } else {
            tracing::info!(
                "{} Entity does not exist, creating new: {}",
                API_NAME,
                entity.entity_header.entity_id
            );
            self.create_new_entity(&entity_repo, entity, event_id, tx).await
        }
    }

    async fn create_new_entity(
        &self,
        entity_repo: &EntityRepository,
        entity: &Entity,
        event_id: &str,
        tx: Option<&mut Transaction<'_, Postgres>>,
    ) -> anyhow::Result<()> {
        let entity_id = &entity.entity_header.entity_id;
        let entity_type = &entity.entity_header.entity_type;
        let now = Utc::now();

        // Extract entity data from entity properties (excluding entityHeader)
        let mut entity_data = entity.properties.clone();

        // Use createdAt and updatedAt from entityHeader
        let created_at = entity.entity_header.created_at;
        let updated_at = entity.entity_header.updated_at;

        entity_repo
            .create(entity_id, entity_type, Some(created_at), Some(updated_at), &entity_data, Some(event_id), tx)
            .await
            .context("Failed to create entity")?;

        tracing::info!("{} Successfully created entity: {}", API_NAME, entity_id);
        Ok(())
    }

    async fn update_existing_entity(
        &self,
        entity_repo: &EntityRepository,
        entity: &Entity,
        event_id: &str,
        tx: Option<&mut Transaction<'_, Postgres>>,
    ) -> anyhow::Result<()> {
        let entity_id = &entity.entity_header.entity_id;
        let updated_at = Utc::now();

        // Extract entity data from entity properties (excluding entityHeader)
        let entity_data = entity.properties.clone();

        entity_repo
            .update(entity_id, updated_at, &entity_data, Some(event_id), tx)
            .await
            .context("Failed to update entity")?;

        tracing::info!("{} Successfully updated entity: {}", API_NAME, entity_id);
        Ok(())
    }
}

fn parse_datetime(dt_str: &str) -> Result<chrono::DateTime<Utc>, String> {
    // Try ISO 8601 formats
    if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(dt_str) {
        return Ok(dt.with_timezone(&Utc));
    }
    if let Ok(dt) = chrono::DateTime::parse_from_str(dt_str, "%Y-%m-%dT%H:%M:%S%.fZ") {
        return Ok(dt.with_timezone(&Utc));
    }

    // Try parsing as Unix timestamp (milliseconds)
    if let Ok(ms) = dt_str.parse::<i64>() {
        let secs = ms / 1000;
        let nsecs = ((ms % 1000) * 1_000_000) as u32;
        if let Some(dt) = chrono::DateTime::from_timestamp(secs, nsecs) {
            return Ok(dt);
        }
    }

    Err(format!("Unable to parse datetime string: {}", dt_str))
}
