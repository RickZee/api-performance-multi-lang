use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("JSON serialization error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("Validation error: {0}")]
    Validation(String),

    #[error("Entity not found: {0}")]
    NotFound(String),

    #[error("Internal server error: {0}")]
    Internal(#[from] anyhow::Error),
}

impl From<AppError> for tonic::Status {
    fn from(err: AppError) -> Self {
        match err {
            AppError::Database(e) => {
                tracing::error!("Database error: {}", e);
                tonic::Status::internal(format!("Database error: {}", e))
            }
            AppError::Json(e) => {
                tracing::error!("JSON error: {}", e);
                tonic::Status::invalid_argument(format!("Invalid JSON: {}", e))
            }
            AppError::Validation(msg) => {
                tracing::warn!("Validation error: {}", msg);
                tonic::Status::invalid_argument(msg)
            }
            AppError::NotFound(msg) => {
                tracing::warn!("Not found: {}", msg);
                tonic::Status::not_found(msg)
            }
            AppError::Internal(e) => {
                tracing::error!("Internal error: {}", e);
                tonic::Status::internal(format!("Internal server error: {}", e))
            }
        }
    }
}

