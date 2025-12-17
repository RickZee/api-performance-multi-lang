mod config;
mod constants;
mod error;
mod handlers;
mod models;
mod repository;
mod service;

use anyhow::Context;
use axum::Router;
use config::Config;
use constants::API_NAME;
use handlers::{event, health};
use repository::BusinessEventRepository;
use service::EventProcessingService;
use sqlx::postgres::PgPoolOptions;
use std::net::SocketAddr;
use tower_http::cors::CorsLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load environment variables
    dotenvy::dotenv().ok();

    // Initialize configuration
    let config = Config::from_env()?;

    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| config.log_level.clone().into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("{} Starting Producer API Rust server on port {}", API_NAME, config.server_port);

    // Create database connection pool
    let pool = PgPoolOptions::new()
        .max_connections(10)
        .connect(&config.database_url)
        .await
        .context("Failed to connect to database")?;

    tracing::info!("{} Connected to database", API_NAME);

    // Initialize repository and service
    let business_event_repo = BusinessEventRepository::new(pool.clone());
    let service = EventProcessingService::new(business_event_repo, pool);

    // Build application router
    let app = Router::new()
        .nest("/api/v1/events", event::router())
        .nest("/api/v1/events", health::router())
        .layer(CorsLayer::permissive())
        .with_state(service);

    // Start server
    let addr = SocketAddr::from(([0, 0, 0, 0], config.server_port));
    tracing::info!("{} Server listening on {}", API_NAME, addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
