# Producer API - Go gRPC

Go gRPC API using pgx.

## Overview

| Property | Value |
|----------|-------|
| Protocol | gRPC |
| Port | 9092 |
| Language | Go |
| Framework | gRPC |
| Database Driver | pgx |
| Proto File | `proto/event_service.proto` |

## Key Features

- Structured logging with zap
- Automatic migrations on startup
- Automatic proto generation in Docker builds

## Build & Run

Configuration uses environment variables.

```bash
export DATABASE_URL="postgresql://postgres:password@localhost:5432/car_entities"
export GRPC_SERVER_PORT=9092
```

```bash
# Generate proto files first (for local development)
chmod +x scripts/generate-proto.sh
./scripts/generate-proto.sh

go run cmd/server/main.go    # Run locally
go build -o producer-api-go-grpc ./cmd/server    # Build binary
```

## Proto Generation (Local Development)

1. Install protoc (Protocol Buffers compiler)
2. Install Go plugins:
   ```bash
   go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
   go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
   ```
3. Run: `./scripts/generate-proto.sh`

**Note:** Proto files are automatically generated during Docker builds, so this step is only needed for local development.

For Docker usage, see the main [README.md](../README.md).

## Lambda Version

A serverless Lambda version is also available: **[Producer API - Go gRPC Lambda](../producer-api-go-grpc-lambda/README.md)**