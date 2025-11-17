# Producer API - Rust REST

High-performance RESTful API built with Rust, Axum, and sqlx.

## Overview

| Property | Value |
|----------|-------|
| Protocol | REST |
| Port | 8081 |
| Language | Rust |
| Framework | Axum |
| Database Driver | sqlx |
| Bulk Processing | Supported |

## Key Features

- Native Rust performance
- Tokio async runtime
- Compile-time SQL checking with sqlx
- Structured error handling (thiserror/anyhow)
- Validator crate for input validation
- Bulk event processing support

## Build & Run

Configuration uses environment variables:

```bash
export DATABASE_URL="postgresql://postgres:password@localhost:5432/car_entities"
export SERVER_PORT=8081
export RUST_LOG=info
```

```bash
# Run database migrations (if using sqlx-cli)
sqlx migrate run

# Run application
cargo run

# Build release binary
cargo build --release
```

For Docker usage, see the main [README.md](../README.md).