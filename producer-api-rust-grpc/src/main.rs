mod config;
mod constants;
mod error;
mod models;
mod repository;
mod service;

use anyhow::Context;
use config::Config;
use constants::API_NAME;
use repository::BusinessEventRepository;
use service::event_service::create_service;
use sqlx::postgres::PgPoolOptions;
use std::net::SocketAddr;
use tonic::transport::Server;
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

    tracing::info!(
        "{} Starting Producer API Rust gRPC server on port {}",
        API_NAME,
        config.server_port
    );

    // Create database connection pool
    let pool = PgPoolOptions::new()
        .max_connections(10)
        .connect(&config.database_url)
        .await
        .context("Failed to connect to database")?;

    tracing::info!("{} Connected to database", API_NAME);

    // Initialize repository and service
    let business_event_repo = BusinessEventRepository::new(pool.clone());
    let event_service = create_service(business_event_repo, pool);

    // Start gRPC server
    let addr = SocketAddr::from(([0, 0, 0, 0], config.server_port));
    tracing::info!("{} gRPC server listening on {}", API_NAME, addr);

    Server::builder()
        .add_service(event_service)
        .serve(addr)
        .await?;

    Ok(())
}

