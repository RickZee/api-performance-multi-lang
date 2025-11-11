mod config;
mod error;
mod repository;
mod service;

use anyhow::Context;
use config::Config;
use repository::CarEntityRepository;
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
        "Starting Producer API Rust gRPC server on port {}",
        config.server_port
    );

    // Create database connection pool
    let pool = PgPoolOptions::new()
        .max_connections(10)
        .connect(&config.database_url)
        .await
        .context("Failed to connect to database")?;

    tracing::info!("Connected to database");

    // Run migrations
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .context("Failed to run migrations")?;

    tracing::info!("Database migrations completed");

    // Initialize repository and service
    let repository = CarEntityRepository::new(pool);
    let event_service = create_service(repository);

    // Start gRPC server
    let addr = SocketAddr::from(([0, 0, 0, 0], config.server_port));
    tracing::info!("gRPC server listening on {}", addr);

    Server::builder()
        .add_service(event_service)
        .serve(addr)
        .await?;

    Ok(())
}

