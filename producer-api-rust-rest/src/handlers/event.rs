use axum::{
    extract::State,
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use serde_json::json;
use validator::{Validate, ValidationError};

use crate::error::AppError;
use crate::models::Event;
use crate::service::EventProcessingService;

use crate::constants::API_NAME;

pub fn router() -> Router<EventProcessingService> {
    Router::new()
        .route("/", post(process_event))
        .route("/bulk", post(process_bulk_events))
}

async fn process_event(
    State(service): State<EventProcessingService>,
    Json(event): Json<Event>,
) -> Result<Json<serde_json::Value>, AppError> {
    // Validate event
    if event.event_header.event_name.is_empty() {
        return Err(AppError::Validation("Event header event_name is required".to_string()));
    }
    
    if event.event_body.entities.is_empty() {
        return Err(AppError::Validation("Event body must contain at least one entity".to_string()));
    }

    // Validate each entity
    for entity in &event.event_body.entities {
        if entity.entity_type.is_empty() {
            return Err(AppError::Validation("Entity type cannot be empty".to_string()));
        }
        if entity.entity_id.is_empty() {
            return Err(AppError::Validation("Entity ID cannot be empty".to_string()));
        }
    }

    tracing::info!("{} Received event: {}", API_NAME, event.event_header.event_name);

    service
        .process_event(event)
        .await
        .map_err(|e| AppError::Internal(e))?;

    Ok(Json(json!({
        "success": true,
        "message": "Event processed successfully"
    })))
}

async fn process_bulk_events(
    State(service): State<EventProcessingService>,
    Json(events): Json<Vec<Event>>,
) -> Result<Json<serde_json::Value>, AppError> {
    if events.is_empty() {
        return Err(AppError::Validation(
            "Invalid request: events list is null or empty".to_string(),
        ));
    }

    tracing::info!("{} Received bulk request with {} events", API_NAME, events.len());

    let mut processed_count = 0;
    let mut failed_count = 0;

    for event in events {
        if event.validate().is_ok() {
            if event.event_header.event_name.is_empty() {
                failed_count += 1;
                continue;
            }

            match service.process_event(event).await {
                Ok(_) => processed_count += 1,
                Err(e) => {
                    tracing::error!("{} Error processing event in bulk: {}", API_NAME, e);
                    failed_count += 1;
                }
            }
        } else {
            failed_count += 1;
        }
    }

    let success = failed_count == 0;
    let message = if success {
        "All events processed successfully".to_string()
    } else {
        format!("Processed {} events, {} failed", processed_count, failed_count)
    };

    Ok(Json(json!({
        "success": success,
        "message": message,
        "processedCount": processed_count,
        "failedCount": failed_count,
        "batchId": format!("batch-{}", chrono::Utc::now().timestamp_millis()),
        "processingTimeMs": 100
    })))
}

