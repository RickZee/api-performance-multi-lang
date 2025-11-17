# Producer API - Rust gRPC

High-performance gRPC API built with Rust, Tonic, and sqlx.

## Overview

| Property | Value |
|----------|-------|
| Protocol | gRPC |
| Port | 9090 |
| Language | Rust |
| Framework | Tonic |
| Database Driver | sqlx |
| Proto File | `proto/event_service.proto` |

## Key Features

- Protocol Buffers for efficient serialization
- HTTP/2 support
- Tokio async runtime
- Compile-time SQL checking with sqlx
- Structured error handling

## Build & Run

Configuration uses environment variables:

```bash
export DATABASE_URL="postgresql://postgres:password@localhost:5432/car_entities"
export GRPC_SERVER_PORT=9090
export RUST_LOG=info
```

```bash
# Run database migrations (if using sqlx-cli)
sqlx migrate run --source migrations

# Run application
cargo run

# Build release binary
cargo build --release
```

For Docker usage, see the main [README.md](../README.md).