use axum::{response::Json, routing::get, Router};
use serde_json::json;
use crate::service::EventProcessingService;

pub fn router() -> Router<EventProcessingService> {
    Router::new().route("/health", get(health_check))
}

async fn health_check() -> Json<serde_json::Value> {
    Json(json!({
        "status": "healthy",
        "message": "Producer API is healthy"
    }))
}

