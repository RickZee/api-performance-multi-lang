use crate::repository::{CarEntity, CarEntityRepository};
use anyhow::Context;
use chrono::Utc;
use serde_json::Value;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};

pub struct EventProcessingService {
    repository: CarEntityRepository,
    persisted_event_count: std::sync::Arc<AtomicU64>,
}

impl EventProcessingService {
    pub fn new(repository: CarEntityRepository) -> Self {
        Self {
            repository,
            persisted_event_count: std::sync::Arc::new(AtomicU64::new(0)),
        }
    }
    
    fn log_persisted_event_count(&self) {
        let count = self.persisted_event_count.fetch_add(1, Ordering::Relaxed) + 1;
        if count % 10 == 0 {
            tracing::info!("*** Persisted events count: {} ***", count);
        }
    }

    pub async fn process_event(
        &self,
        event_name: &str,
        entity_type: &str,
        entity_id: &str,
        updated_attributes: &HashMap<String, String>,
    ) -> anyhow::Result<()> {
        tracing::info!("Processing event: {}", event_name);

        self.process_entity_update(entity_type, entity_id, updated_attributes)
            .await
            .context("Failed to process entity update")?;

        Ok(())
    }

    async fn process_entity_update(
        &self,
        entity_type: &str,
        entity_id: &str,
        updated_attributes: &HashMap<String, String>,
    ) -> anyhow::Result<()> {
        let exists = self
            .repository
            .exists_by_entity_type_and_id(entity_type, entity_id)
            .await
            .context("Failed to check if entity exists")?;

        if exists {
            tracing::warn!("Entity already exists, updating: {}", entity_id);
            self.update_existing_entity(entity_type, entity_id, updated_attributes)
                .await
                .context("Failed to update existing entity")?;
            self.log_persisted_event_count();
        } else {
            tracing::info!("Entity does not exist, creating new: {}", entity_id);
            self.create_new_entity(entity_type, entity_id, updated_attributes)
                .await
                .context("Failed to create new entity")?;
            self.log_persisted_event_count();
        }

        Ok(())
    }

    async fn create_new_entity(
        &self,
        entity_type: &str,
        entity_id: &str,
        updated_attributes: &HashMap<String, String>,
    ) -> anyhow::Result<()> {
        let data_json = serde_json::to_string(updated_attributes)
            .context("Failed to serialize entity data")?;

        let entity = CarEntity::new(entity_id.to_string(), entity_type.to_string(), data_json);

        self.repository
            .create(&entity)
            .await
            .context("Failed to insert entity into database")?;

        tracing::info!("Successfully created entity: {}", entity.id);
        Ok(())
    }

    async fn update_existing_entity(
        &self,
        entity_type: &str,
        entity_id: &str,
        updated_attributes: &HashMap<String, String>,
    ) -> anyhow::Result<()> {
        let mut existing_entity = self
            .repository
            .find_by_entity_type_and_id(entity_type, entity_id)
            .await
            .context("Failed to find existing entity")?
            .ok_or_else(|| anyhow::anyhow!("Entity not found for update"))?;

        // Parse existing data
        let mut existing_data: Value = serde_json::from_str(&existing_entity.data)
            .context("Failed to parse existing entity data")?;

        // Merge with new attributes
        if let (Value::Object(ref mut existing_obj), _) = (&mut existing_data, updated_attributes) {
            for (key, value) in updated_attributes {
                existing_obj.insert(key.clone(), Value::String(value.clone()));
            }
        }

        // Update entity
        existing_entity.data = serde_json::to_string(&existing_data)
            .context("Failed to serialize updated entity data")?;
        existing_entity.updated_at = Some(Utc::now());

        self.repository
            .update(&existing_entity)
            .await
            .context("Failed to update entity in database")?;

        tracing::info!("Successfully updated entity: {}", existing_entity.id);
        Ok(())
    }
}

